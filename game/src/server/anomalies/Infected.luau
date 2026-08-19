--!strict
-- Infected anomaly (G-6), per design doc §4.
-- Gate tells (cosmetic, replicated): pale/green head tint, cough billboard,
-- stained ticket attribute. Inside: incubates 90s after admission → zombie;
-- chases guests, a tag converts the victim 20s later — exponential cascade.
-- All timers run in simulated seconds (debug time scale compresses them).
-- Containment (capture net) is G-7; Fear AoE waits for the needs AI (P-1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local NetTargets = require(script.Parent.NetTargets)
local Guests = require(script.Parent.Parent.Guests)
local IndexStore = require(script.Parent.Parent.IndexStore)

local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

-- Tell colors: pale sickly tint while dormant (plausible against warm skin
-- tones — that's the inspection challenge), unmistakable green once turned.
-- Art rule: the head is the display surface for this tell.
local DORMANT_HEAD_COLOR = Color3.fromRGB(196, 214, 176)
local ZOMBIE_HEAD_COLOR = Color3.fromRGB(96, 178, 74)
local ZOMBIE_BODY_COLOR = Color3.fromRGB(72, 122, 62)

type Stage = "Dormant" | "Incubating" | "Converting" | "Zombie"

type Case = {
	guest: Guests.Guest,
	stage: Stage,
	timer: number, -- simulated seconds until next stage
	nextCough: number,
	coughLabel: TextLabel?,
}

local cases: { [string]: Case } = {}

local Infected = {}

local function getPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	return if child and child:IsA("BasePart") then child else nil
end

local function makeCoughBillboard(head: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CoughTell"
	billboard.Size = UDim2.fromOffset(90, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextColor3 = Color3.fromRGB(120, 130, 110)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.Text = "*cough*"
	label.Parent = billboard
	billboard.Parent = head
	return label
end

-- Gate-time marker: registered with Guests, applied at spawn (§4 Infiltrate)
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Infected")
	local head = getPart(guest.model, "Head")
	if head then
		head.Color = DORMANT_HEAD_COLOR
	end
	guest.model:SetAttribute("TicketStained", true) -- ticket tell (§4)
	cases[guest.id] = {
		guest = guest,
		stage = "Dormant",
		timer = 0,
		nextCough = rng:NextNumber(3, 8),
		coughLabel = if head then makeCoughBillboard(head) else nil,
	}
	print("[Anomaly] an infected guest has joined the queue")
end

local function zombify(case: Case)
	local guest = case.guest
	case.stage = "Zombie"
	guest.state = "Zombie"
	guest.speed = GameConfig.GuestWalkSpeed * GameConfig.ZombieSpeedMultiplier
	AnomalyBase.mark(guest.id, "Infected")
	local head = getPart(guest.model, "Head")
	if head then
		head.Color = ZOMBIE_HEAD_COLOR
	end
	local body = getPart(guest.model, "Body")
	if body then
		body.Color = ZOMBIE_BODY_COLOR
	end
	local coughLabel = case.coughLabel
	if coughLabel then
		(coughLabel.Parent :: BillboardGui):Destroy()
		case.coughLabel = nil
	end
	-- §4 severity: 8 for the outbreak, +2 per further conversion
	local zombiesToday = dayStats:GetAttribute("Zombies") :: number? or 0
	IndexStore.addIncident(if zombiesToday == 0 then 8 else 2)
	dayStats:SetAttribute("Zombies", zombiesToday + 1)
	print(("[Anomaly] %s turned!"):format(guest.model.Name))
end

-- A zombie tag starts the victim's own conversion timer (§4 cascade)
local function tagVictim(victim: Guests.Guest)
	victim.state = "Converting"
	cases[victim.id] = {
		guest = victim,
		stage = "Converting",
		timer = GameConfig.InfectedConversionSeconds,
		nextCough = math.huge,
		coughLabel = nil,
	}
	print(("[Anomaly] %s was tagged by a zombie"):format(victim.model.Name))
end

local function guestStillActive(guest: Guests.Guest): boolean
	return table.find(Guests.getActive(), guest) ~= nil
end

local function randomParkPoint(): Vector3
	local bounds = GameConfig.ParkBounds
	return Vector3.new(
		rng:NextNumber(bounds.minX, bounds.maxX),
		0,
		rng:NextNumber(bounds.minZ, bounds.maxZ)
	)
end

local function guestPosition(guest: Guests.Guest): Vector3
	local pivot = guest.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

-- Single simulation tick: coughs, incubation, conversion, chase, flee
local TICK = 0.25
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()

		for id, case in cases do
			local guest = case.guest
			if not guestStillActive(guest) then
				cases[id] = nil
				AnomalyBase.clear(id)
				continue
			end

			if case.stage == "Dormant" then
				-- §4 dormant tell: cough loop while blending in
				case.nextCough -= simDt
				if case.nextCough <= 0 and case.coughLabel then
					case.nextCough = rng:NextNumber(4, 9)
					local billboard = case.coughLabel.Parent :: BillboardGui
					billboard.Enabled = true
					task.delay(0.9, function()
						if billboard.Parent then
							billboard.Enabled = false
						end
					end)
				end
				-- admission starts incubation (set via onAdmitted below)
			elseif case.stage == "Incubating" or case.stage == "Converting" then
				case.timer -= simDt
				if case.timer <= 0 then
					zombify(case)
				end
			elseif case.stage == "Zombie" then
				-- chase the nearest healthy admitted guest
				local zombiePosition = guestPosition(guest)
				local nearest: Guests.Guest? = nil
				local nearestDistance = math.huge
				for _, other in Guests.getActive() do
					if other.state == "Admitted" and not other.busy then
						local distance = (guestPosition(other) - zombiePosition).Magnitude
						if distance < nearestDistance then
							nearest = other
							nearestDistance = distance
						end
					end
				end
				if nearest then
					guest.target = guestPosition(nearest)
					if nearestDistance <= GameConfig.ZombieTagRadius then
						tagVictim(nearest)
					end
				elseif not guest.target then
					guest.target = randomParkPoint() -- shamble around
				end
			end
		end

		-- Flee pass: healthy admitted guests run from nearby zombies, and the
		-- scare raises Fear (§1) — enough seconds near a zombie triggers Fleeing
		for _, guest in Guests.getActive() do
			if guest.state ~= "Admitted" or guest.busy then
				continue
			end
			local position = guestPosition(guest)
			for _, case in cases do
				if case.stage == "Zombie" and guestStillActive(case.guest) then
					local zombiePosition = guestPosition(case.guest)
					local offset = position - zombiePosition
					if offset.Magnitude < GameConfig.ZombieScareRadius then
						guest.needs.Fear =
							math.min(100, guest.needs.Fear + GameConfig.ZombieFearHit * simDt)
						local direction = if offset.Magnitude > 0.1
							then offset.Unit
							else Vector3.new(1, 0, 0)
						local bounds = GameConfig.ParkBounds
						local fleeTo = position + direction * 12
						guest.target = Vector3.new(
							math.clamp(fleeTo.X, bounds.minX, bounds.maxX),
							0,
							math.clamp(fleeTo.Z, bounds.minZ, bounds.maxZ)
						)
						break
					end
				end
			end
		end
	end
end)

-- Admission flips a dormant case to incubating (§4: incubates 90s → zombie)
Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case and case.stage == "Dormant" then
		case.stage = "Incubating"
		case.timer = GameConfig.InfectedIncubationSeconds
	end
end)

Guests.onDrained(function()
	table.clear(cases)
	AnomalyBase.clearAll()
end)

Guests.registerAnomalyMarker("Infected", mark)

function Infected.spawnOne()
	Guests.spawnArrival({ anomaly = "Infected" })
end

-- Net probe (G-7, moved onto the A-3 registry). Nearest zombie evaporates in
-- a puff; a tagged (Converting) guest is cured — thumbs-up, carries on as if
-- nothing happened (tone rule).
NetTargets.register(function(position: Vector3): NetTargets.Hit?
	local bestId: string? = nil
	local bestCase: Case? = nil
	local bestDistance = math.huge
	for id, case in cases do
		if case.stage == "Zombie" or case.stage == "Converting" then
			if guestStillActive(case.guest) then
				local distance = (guestPosition(case.guest) - position).Magnitude
				if distance < bestDistance then
					bestId = id
					bestCase = case
					bestDistance = distance
				end
			end
		end
	end
	if not (bestId and bestCase) then
		return nil
	end
	local id = bestId :: string
	local case = bestCase :: Case

	return {
		distance = bestDistance,
		resolve = function(): string
			local guest = case.guest
			cases[id] = nil
			AnomalyBase.clear(id)

			if case.stage == "Zombie" then
				NetTargets.puffAt(guestPosition(guest))
				Guests.despawn(guest)
				dayStats:SetAttribute(
					"Captured",
					(dayStats:GetAttribute("Captured") :: number? or 0) + 1
				)
				print(("[Anomaly] %s was netted and evaporated in a puff"):format(guest.model.Name))
				return "zombie"
			end

			-- Cured mid-conversion: thumbs-up and resume the day (§4 tone rule)
			guest.state = "Admitted"
			guest.dwell = math.max(guest.dwell, 60) -- stick around a while after the rescue
			guest.emoteLabel.Text = "👍"
			(guest.emoteLabel.Parent :: BillboardGui).Enabled = true
			task.delay(1.5, function()
				if guest.emoteLabel.Parent then
					guest.emoteLabel.Text = ""
					(guest.emoteLabel.Parent :: BillboardGui).Enabled = false
				end
			end)
			guest.target = randomParkPoint()
			print(("[Anomaly] %s was cured by the net — thumbs up"):format(guest.model.Name))
			return "cured"
		end,
	}
end)

-- Infirmary check-up (A-8): a dormant/incubating case is quietly cured
function Infected.cure(guestId: string): boolean
	local case = cases[guestId]
	if not case or (case.stage ~= "Dormant" and case.stage ~= "Incubating") then
		return false
	end
	local coughLabel = case.coughLabel
	if coughLabel then
		(coughLabel.Parent :: BillboardGui):Destroy()
	end
	local head = getPart(case.guest.model, "Head")
	if head then
		head.Color = Color3.fromRGB(245, 205, 165) -- healthy again
	end
	case.guest.model:SetAttribute("TicketStained", nil)
	cases[guestId] = nil
	AnomalyBase.clear(guestId)
	return true
end

return Infected
