--!strict
-- Guest lifecycle module (G-2 refactor of the G-1 spawner internals).
-- Owns stands, queues, counter promotion/resolution, and glide movement.
-- Driven by two thin scripts: GuestSpawner (arrivals) and GateService
-- (decisions). Server-only; clients see guest models + replicated ticket
-- attributes, never lifecycle state.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GuestIdentity = require(ReplicatedStorage.Shared.GuestIdentity)
local Buildings = require(script.Parent.Buildings)
local EconomyStore = require(script.Parent.EconomyStore)
local TicketRules = require(script.Parent.TicketRules)

local rigTemplate = ServerStorage:WaitForChild("Assets"):WaitForChild("GuestRig") :: Model
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

export type Verdict = "Approve" | "Deny"
export type GuestState =
	"Queueing"
	| "AtCounter"
	| "Admitted"
	| "Denied"
	| "WalkedAway"
	| "Leaving" -- dwell expired, heading home content
	| "Fleeing" -- §1: Fear > 70, scared exit
	| "Converting" -- §4: tagged by a zombie, timer running (Infected owns the timer)
	| "Zombie"
	| "OnMission" -- §4: anomaly-driven movement (spy/alien/cult); needs AI hands off

export type Needs = { Fun: number, Hunger: number, Bladder: number, Fear: number }

export type Guest = {
	id: string,
	model: Model,
	identity: GuestIdentity.Identity,
	pivotHeight: number,
	state: GuestState,
	target: Vector3?, -- nil = settled
	facing: Vector3,
	patience: number, -- §3: decays while Queueing; 0 = walkaway
	emoteLabel: TextLabel,
	speed: number, -- studs/s; zombies run faster than guests
	dwell: number, -- simulated seconds left in the park once Admitted
	needs: Needs, -- §1 needs system (GuestNeeds drives decay/decisions)
	busy: boolean, -- riding/using a facility; ignored by zombies + decisions
	wasAdmitted: boolean,
	wobble: boolean?, -- §4 aliens: tipsy sway applied by the glide loop (A-4)
}

export type SpawnOptions = {
	countArrival: boolean?, -- false when materializing an already-counted overflow
	anomaly: string?, -- registered marker name; truth stays server-only
}

type Stand = {
	part: BasePart,
	queue: { Guest }, -- waiting line; the counter guest is NOT in here
	counterGuest: Guest?,
	capacity: number,
}

local Guests = {}

-- (standPart: BasePart, guestModel: Model?) — fired on promote and on clear
Guests.counterChanged = Instance.new("BindableEvent")

local stands: { [BasePart]: Stand } = {}
local active: { Guest } = {}
local overflowCount = 0

-- Extension points for the anomaly layer (plain callbacks — BindableEvents
-- would deep-copy the guest table and break identity)
export type ExitReason = "left" | "fled" | "walkaway"

local anomalyMarkers: { [string]: (Guest) -> () } = {}
local admittedCallbacks: { (Guest) -> () } = {}
local drainedCallbacks: { () -> () } = {}
local exitCallbacks: { (Guest, ExitReason) -> () } = {}
local spawnedCallbacks: { (Guest) -> () } = {}

-- Fired when a guest exits the park on their own feet (satisfaction input,
-- §1 exit happiness). Zombified/captured guests never "exit".
function Guests.onExit(callback: (Guest, ExitReason) -> ())
	table.insert(exitCallbacks, callback)
end

local function reportExit(guest: Guest, reason: ExitReason)
	for _, callback in exitCallbacks do
		callback(guest, reason)
	end
end

function Guests.registerAnomalyMarker(name: string, marker: (Guest) -> ())
	anomalyMarkers[name] = marker
end

function Guests.onAdmitted(callback: (Guest) -> ())
	table.insert(admittedCallbacks, callback)
end

-- Fired once per fresh arrival, after the model is in workspace (A-8:
-- the infirmary escort prompt hangs off this)
function Guests.onSpawned(callback: (Guest) -> ())
	table.insert(spawnedCallbacks, callback)
end

function Guests.onDrained(callback: () -> ())
	table.insert(drainedCallbacks, callback)
end

-- Live list — callers iterate, never mutate
function Guests.getActive(): { Guest }
	return active
end

function Guests.exitPosition(): Vector3
	local marker = CollectionService:GetTagged("GuestSpawn")[1]
	if marker and marker:IsA("BasePart") then
		return Vector3.new(marker.Position.X, 0, marker.Position.Z)
	end
	return Vector3.zero
end

local function getPart(model: Model, name: string): BasePart
	local child = model:FindFirstChild(name)
	assert(child and child:IsA("BasePart"), ("GuestRig is missing part %q"):format(name))
	return child
end

local function queueSlot(stand: Stand, index: number): Vector3
	local cf = stand.part.CFrame
	local distance = GameConfig.QueueStartOffset + (index - 1) * GameConfig.QueueSpacing
	local slot = cf.Position + cf.LookVector * distance
	return Vector3.new(slot.X, 0, slot.Z)
end

local function counterSpot(stand: Stand): Vector3
	local cf = stand.part.CFrame
	local spot = cf.Position + cf.LookVector * (GameConfig.QueueStartOffset - 2)
	return Vector3.new(spot.X, 0, spot.Z)
end

local function spawnPosition(): Vector3
	local marker = CollectionService:GetTagged("GuestSpawn")[1]
	if marker and marker:IsA("BasePart") then
		return Vector3.new(marker.Position.X, 0, marker.Position.Z)
	end
	return Vector3.zero
end

local function randomParkPoint(): Vector3
	local bounds = GameConfig.ParkBounds
	return Vector3.new(
		rng:NextNumber(bounds.minX, bounds.maxX),
		0,
		rng:NextNumber(bounds.minZ, bounds.maxZ)
	)
end

-- Anger emote above the head (G-4 grey-box asset: emoji billboard; final art
-- may swap in icon images — same label, no code change needed elsewhere)
local function makeEmoteBillboard(head: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AngerEmote"
	billboard.Size = UDim2.fromOffset(44, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = ""
	label.Parent = billboard
	billboard.Parent = head
	return label
end

local function updateEmote(guest: Guest)
	local billboard = guest.emoteLabel.Parent :: BillboardGui
	local patience = guest.patience
	if patience <= GameConfig.PatienceFuriousAt then
		guest.emoteLabel.Text = "🤬"
	elseif patience <= GameConfig.PatienceAngryAt then
		guest.emoteLabel.Text = "😠"
	elseif patience <= GameConfig.PatienceAnnoyedAt then
		guest.emoteLabel.Text = "😐"
	else
		guest.emoteLabel.Text = ""
	end
	billboard.Enabled = guest.emoteLabel.Text ~= ""
end

local function hideEmote(guest: Guest)
	guest.emoteLabel.Text = ""
	(guest.emoteLabel.Parent :: BillboardGui).Enabled = false
end

local function removeGuest(guest: Guest)
	local index = table.find(active, guest)
	if index then
		table.remove(active, index)
	end
	guest.model:Destroy()
	dayStats:SetAttribute("GuestsOnMap", #active)
end

-- External removal (anomaly capture etc.)
function Guests.despawn(guest: Guest)
	removeGuest(guest)
end

-- Grey-box briefcase prop (A-3): worn by the spy AND by innocent businessmen
-- (§3: every tell has an innocent lookalike). PivotTo moves all model parts,
-- so a plain anchored child part rides along.
function Guests.attachBriefcase(model: Model)
	if model:FindFirstChild("Briefcase") then
		return
	end
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local case = Instance.new("Part")
	case.Name = "Briefcase"
	case.Anchored = true
	case.CanCollide = false
	case.Size = Vector3.new(0.9, 0.7, 0.3) * model:GetScale()
	case.Color = Color3.fromRGB(96, 62, 32)
	case.Material = Enum.Material.SmoothPlastic
	case.CFrame = body.CFrame * CFrame.new(body.Size.X / 2 + 0.35, -body.Size.Y / 2, 0)
	case.Parent = model
end

local function retargetQueue(stand: Stand)
	for index, guest in stand.queue do
		guest.target = queueSlot(stand, index)
	end
end

-- Convert one abstract overflow arrival into a real character at the queue back
local function materializeOverflow(stand: Stand)
	if overflowCount <= 0 or #stand.queue >= stand.capacity then
		return
	end
	overflowCount -= 1
	dayStats:SetAttribute("Overflow", overflowCount)
	Guests.spawnArrival({ countArrival = false })
end

function Guests.getStands(): { Stand }
	local list = {}
	for _, stand in stands do
		table.insert(list, stand)
	end
	return list
end

function Guests.hasStands(): boolean
	return next(stands) ~= nil
end

function Guests.spawnArrival(options: SpawnOptions?)
	local opts: SpawnOptions = options or {}
	if not Guests.hasStands() then
		return
	end
	if #active >= GameConfig.GuestCap then
		return -- §1 performance cap on simulated guests
	end
	if opts.countArrival ~= false then
		dayStats:SetAttribute("Arrivals", (dayStats:GetAttribute("Arrivals") :: number) + 1)
	end

	local best: Stand? = nil
	for _, stand in stands do
		if #stand.queue < stand.capacity and (not best or #stand.queue < #best.queue) then
			best = stand
		end
	end
	if not best then
		overflowCount += 1
		dayStats:SetAttribute("Overflow", overflowCount)
		return
	end
	local stand = best :: Stand

	local dayState = ReplicatedStorage:FindFirstChild("DayState")
	local day = if dayState then dayState:GetAttribute("Day") :: number else 1
	local identity = GuestIdentity.generate(day)
	TicketRules.applyToTicket(identity.ticket) -- §5 rule days (A-7) reshape fresh tickets
	local appearance = identity.appearance

	local model = rigTemplate:Clone()
	model.Name = identity.name
	getPart(model, "Body").Color = appearance.bodyColor
	getPart(model, "Head").Color = appearance.headColor
	getPart(model, "LeftArm").Color = appearance.headColor
	getPart(model, "RightArm").Color = appearance.headColor
	model:ScaleTo(appearance.scale)
	if appearance.briefcase then
		Guests.attachBriefcase(model) -- §3 ambiguity: legit businessmen exist (A-3)
	end

	local id = HttpService:GenerateGUID(false)
	-- Ticket fields replicate with the model so InspectionUI reads them directly.
	-- Only cosmetic/inspectable data goes here — anomaly truth stays server-only.
	model:SetAttribute("GuestId", id)
	model:SetAttribute("TicketName", identity.ticket.name)
	model:SetAttribute("TicketSerial", identity.ticket.serial)
	model:SetAttribute("TicketType", identity.ticket.ticketType)
	model:SetAttribute("TicketDate", identity.ticket.date)

	local guest: Guest = {
		id = id,
		model = model,
		identity = identity,
		pivotHeight = GameConfig.GuestPivotHeight * appearance.scale,
		state = "Queueing",
		target = nil,
		facing = -stand.part.CFrame.LookVector,
		patience = GameConfig.PatienceMax,
		emoteLabel = makeEmoteBillboard(getPart(model, "Head")),
		speed = GameConfig.GuestWalkSpeed,
		dwell = 0,
		needs = {
			Fun = rng:NextNumber(40, 70), -- they came here for fun
			Hunger = rng:NextNumber(60, 90),
			Bladder = rng:NextNumber(70, 100),
			Fear = 0,
		},
		busy = false,
		wasAdmitted = false,
	}
	table.insert(stand.queue, guest)
	guest.target = queueSlot(stand, #stand.queue)

	if opts.anomaly then
		local marker = anomalyMarkers[opts.anomaly]
		if marker then
			marker(guest)
		else
			warn(("[Guests] no anomaly marker registered for %q"):format(opts.anomaly))
		end
	end

	local origin = spawnPosition() + Vector3.new(0, guest.pivotHeight, 0)
	model:PivotTo(CFrame.new(origin))
	model.Parent = workspace
	table.insert(active, guest)
	dayStats:SetAttribute("GuestsOnMap", #active)
	for _, callback in spawnedCallbacks do
		callback(guest)
	end
end

-- Move the front queued guest up to the counter. Returns it, or nil.
function Guests.promoteFront(standPart: BasePart): Guest?
	local stand = stands[standPart]
	if not stand or stand.counterGuest or #stand.queue == 0 then
		return nil
	end
	local guest = table.remove(stand.queue, 1) :: Guest
	stand.counterGuest = guest
	guest.state = "AtCounter"
	guest.target = counterSpot(stand)
	guest.facing = -standPart.CFrame.LookVector
	retargetQueue(stand)
	materializeOverflow(stand)
	Guests.counterChanged:Fire(standPart, guest.model)
	return guest
end

-- Authoritative verdict on the guest currently at this stand's counter.
-- Returns false when guestId is stale/mismatched (client resyncs via
-- counterChanged) — that's the reject path of the optimistic protocol.
function Guests.resolveCounter(standPart: BasePart, guestId: string, verdict: Verdict): boolean
	local stand = stands[standPart]
	if not stand then
		return false
	end
	local guest = stand.counterGuest
	if not guest or guest.id ~= guestId then
		return false
	end
	stand.counterGuest = nil

	hideEmote(guest)
	if verdict == "Approve" then
		guest.state = "Admitted"
		if not TicketRules.isValid(guest.identity.ticket) then
			-- A-7: an admitted rule-violator becomes a counterfeit fine at Summary
			dayStats:SetAttribute(
				"CounterfeitAdmits",
				(dayStats:GetAttribute("CounterfeitAdmits") :: number? or 0) + 1
			)
		end
		dayStats:SetAttribute("Admissions", (dayStats:GetAttribute("Admissions") :: number) + 1)
		dayStats:SetAttribute(
			"Income",
			(dayStats:GetAttribute("Income") :: number) + GameConfig.EntryFee
		)
		EconomyStore.add(GameConfig.EntryFee)
		guest.wasAdmitted = true
		-- dwell floor (must outlast infected incubation — G-9 finding);
		-- the needs AI (P-1) drives what they do inside
		guest.dwell =
			rng:NextNumber(GameConfig.GuestDwellSecondsMin, GameConfig.GuestDwellSecondsMax)
		guest.target = randomParkPoint()
		for _, callback in admittedCallbacks do
			callback(guest)
		end
	else
		guest.state = "Denied"
		guest.target = spawnPosition()
	end

	Guests.counterChanged:Fire(standPart, nil)
	return true
end

-- §3 walkaway: lost revenue now, satisfaction penalty when the index lands (P-5)
local function abandonVisit(guest: Guest)
	guest.state = "WalkedAway"
	guest.target = spawnPosition()
	dayStats:SetAttribute("Walkaways", (dayStats:GetAttribute("Walkaways") :: number? or 0) + 1)
	print(("[Guests] %s ran out of patience and left"):format(guest.model.Name))
end

local function walkAwayFromQueue(stand: Stand, queueIndex: number)
	local guest = table.remove(stand.queue, queueIndex) :: Guest
	abandonVisit(guest)
	retargetQueue(stand)
	materializeOverflow(stand)
end

local function walkAwayFromCounter(stand: Stand)
	local guest = stand.counterGuest :: Guest
	stand.counterGuest = nil
	abandonVisit(guest)
	Guests.counterChanged:Fire(stand.part, nil)
end

-- Debug hook (F-5): drop everyone waiting (queue + counter) to near-zero patience
function Guests.sapPatience()
	for _, stand in stands do
		for _, guest in stand.queue do
			guest.patience = math.min(guest.patience, GameConfig.PatienceFuriousAt + 2)
			updateEmote(guest)
		end
		local counterGuest = stand.counterGuest
		if counterGuest then
			counterGuest.patience =
				math.min(counterGuest.patience, GameConfig.PatienceFuriousAt + 2)
			updateEmote(counterGuest)
		end
	end
end

-- Patience decay (§3): everyone still waiting loses patience — the queue AND
-- the counter guest (an unmanned stand keeps nobody happy; it also soft-caps
-- how long a player can dither over one ticket)
task.spawn(function()
	while true do
		task.wait(1)
		-- decay in simulated seconds so the debug time scale compresses waits too
		local decay = GameConfig.PatienceDecayPerSecond * GameConfig.timeScale()

		-- Admitted guests: burn dwell, wander between random spots, then head
		-- home content (Leaving guests despawn at the gate). Busy guests are
		-- mid-ride/mid-refill: their dwell clock pauses and they must never be
		-- retargeted out of a seat (A-3 guard).
		for _, guest in table.clone(active) do
			if guest.state == "Admitted" and not guest.busy then
				guest.dwell -= GameConfig.timeScale()
				if guest.dwell <= 0 then
					guest.state = "Leaving"
					guest.target = spawnPosition()
				elseif not guest.target and rng:NextNumber() < 0.3 then
					guest.target = randomParkPoint()
				end
			end
		end

		for _, stand in stands do
			-- §9 queue busker (A-8): halves patience decay in its radius
			local standPosition = Vector3.new(stand.part.Position.X, 0, stand.part.Position.Z)
			local standDecay = if Buildings.buskerCovers(standPosition)
				then decay * GameConfig.BuskerPatienceMultiplier
				else decay
			local counterGuest = stand.counterGuest
			if counterGuest then
				counterGuest.patience -= standDecay
				if counterGuest.patience <= 0 then
					walkAwayFromCounter(stand)
				else
					updateEmote(counterGuest)
				end
			end
			for index = #stand.queue, 1, -1 do
				local guest = stand.queue[index]
				guest.patience -= standDecay
				if guest.patience <= 0 then
					walkAwayFromQueue(stand, index)
				else
					updateEmote(guest)
				end
			end
		end
	end
end)

function Guests.drainPark()
	for _, stand in stands do
		table.clear(stand.queue)
		stand.counterGuest = nil
		Guests.counterChanged:Fire(stand.part, nil)
	end
	for _, guest in active do
		guest.model:Destroy()
	end
	table.clear(active)
	overflowCount = 0
	dayStats:SetAttribute("GuestsOnMap", 0)
	dayStats:SetAttribute("Overflow", 0)
	for _, callback in drainedCallbacks do
		callback()
	end
	print("[Guests] park drained")
end

Component.bind("EntryStand", {
	onAttached = function(instance)
		if not instance:IsA("BasePart") then
			warn("[Guests] EntryStand tag on non-part instance: " .. instance:GetFullName())
			return
		end
		local capacityAttribute = instance:GetAttribute("QueueCapacity")
		local capacity = if typeof(capacityAttribute) == "number"
			then capacityAttribute
			else GameConfig.DefaultQueueCapacity
		stands[instance] = {
			part = instance,
			queue = {},
			counterGuest = nil,
			capacity = math.min(capacity, GameConfig.VisibleQueuePerStand),
		}
		print(("[Guests] stand registered: %s"):format(instance:GetFullName()))
	end,
	onDetached = function(instance)
		local stand = stands[instance :: BasePart]
		if not stand then
			return
		end
		stands[instance :: BasePart] = nil
		local affected = table.clone(stand.queue)
		if stand.counterGuest then
			table.insert(affected, stand.counterGuest)
		end
		for _, guest in affected do
			removeGuest(guest)
		end
	end,
})

-- Glide movement + arrival handling
RunService.Heartbeat:Connect(function(deltaTime)
	for _, guest in table.clone(active) do
		local target = guest.target
		if not target then
			continue
		end
		local lift = Vector3.new(0, guest.pivotHeight, 0)
		local pivot = guest.model:GetPivot().Position
		local flat = Vector3.new(pivot.X, 0, pivot.Z)
		local delta = target - flat
		if delta.Magnitude <= 0.15 then
			guest.model:PivotTo(CFrame.lookAt(target + lift, target + lift + guest.facing))
			guest.target = nil
			if guest.state == "Denied" then
				removeGuest(guest)
			elseif guest.state == "WalkedAway" then
				reportExit(guest, "walkaway") -- §3: counts as an unhappy exit
				removeGuest(guest)
			elseif guest.state == "Leaving" then
				reportExit(guest, "left")
				removeGuest(guest)
			elseif guest.state == "Fleeing" then
				dayStats:SetAttribute("Fled", (dayStats:GetAttribute("Fled") :: number? or 0) + 1)
				reportExit(guest, "fled")
				removeGuest(guest)
			end
		else
			local step = math.min(guest.speed * deltaTime, delta.Magnitude)
			local nextPosition = flat + delta.Unit * step + lift
			local cf = CFrame.lookAt(nextPosition, nextPosition + delta.Unit)
			if guest.wobble then
				-- §4 aliens gate tell: three people in a coat walk like this
				cf *= CFrame.Angles(0, 0, math.sin(os.clock() * 7) * 0.16)
			end
			guest.model:PivotTo(cf)
		end
	end
end)

return Guests
