--!strict
-- The cult (A-5a infiltration + A-5b ritual), per §4: attacks gate
-- PATTERN-recognition — the tell spans guests, not one ticket. On a cult day
-- 4–6 members trickle in spread across the whole day wearing matching
-- amulets; their serials share a letter and count up consecutively on the
-- same date. Individually harmless — but at ≥4 admitted they converge on a
-- bathroom, kidnap its occupants, and channel for 180s (+60s if the bathroom
-- is locked, §9) under candles and a plume visible from across the park. On
-- completion the kidnapped DISAPPEAR — a police-bribe fine per guest lands on
-- the Summary. Counter: thrown salt evaporates cultists; below 4 the ritual
-- collapses and the rescued thumbs-up and carry on (§4 tone rule).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local NetTargets = require(script.Parent.NetTargets)
local Attractions = require(script.Parent.Parent.Attractions)
local Guests = require(script.Parent.Parent.Guests)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

local AMULET_COLOR = Color3.fromRGB(235, 190, 60) -- matching gold amulets

type Case = {
	guest: Guests.Guest,
	admitted: boolean,
	inRitual: boolean, -- A-5b: currently converging/channeling
}

local cases: { [string]: Case } = {}
local pendingSerials: { string } = {} -- queued for the next marked arrivals

local Cult = {}

local function attachAmulet(model: Model)
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local amulet = Instance.new("Part")
	amulet.Name = "Amulet"
	amulet.Anchored = true
	amulet.CanCollide = false
	amulet.Shape = Enum.PartType.Cylinder
	amulet.Size = Vector3.new(0.15, 0.5, 0.5) * model:GetScale()
	amulet.Color = AMULET_COLOR
	amulet.Material = Enum.Material.SmoothPlastic
	amulet.CFrame = body.CFrame
		* CFrame.new(0, body.Size.Y * 0.25, -(body.Size.Z / 2 + 0.1))
		* CFrame.Angles(0, math.rad(90), 0)
	amulet.Parent = model
end

-- Gate-time marker (§4 Infiltrate): amulet + the next serial in the sequence
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Cultist")
	attachAmulet(guest.model)
	local serial = table.remove(pendingSerials, 1)
	if serial then
		guest.identity.ticket.serial = serial
		guest.model:SetAttribute("TicketSerial", serial)
	end
	cases[guest.id] = { guest = guest, admitted = false, inRitual = false }
	print("[Anomaly] a devotee has joined the queue")
end

local function spawnMember(serial: string)
	table.insert(pendingSerials, serial)
	Guests.spawnArrival({ anomaly = "Cultist" })
end

-- §4/§8: cult slots trickle members across the WHOLE day (Scheduler calls
-- this once at Open with trickle = true)
function Cult.beginDay()
	local count = rng:NextInteger(GameConfig.CultMemberCount[1], GameConfig.CultMemberCount[2])
	local letter = string.char(rng:NextInteger(65, 90))
	local startNumber = rng:NextInteger(1000, 9000)
	print(("[Anomaly] a cult of %d is coming — watch the serials"):format(count))
	for index = 1, count do
		local serial = ("%s%04d"):format(letter, startNumber + index - 1)
		-- spread across ~the whole open day, in serial order
		local spawnAt = (0.03 + 0.85 * (index - 1 + rng:NextNumber(0, 0.8)) / count)
			* GameConfig.OpenDurationSeconds
		task.spawn(function()
			local elapsed = 0
			while dayState:GetAttribute("Phase") == "Open" do
				local waited = task.wait(0.25)
				elapsed += waited * GameConfig.timeScale()
				if elapsed >= spawnAt then
					spawnMember(serial)
					return
				end
			end
		end)
	end
end

-- Debug (F-5): a whole coven at the gate right now, serials consecutive
function Cult.debugBatch()
	local letter = string.char(rng:NextInteger(65, 90))
	local startNumber = rng:NextInteger(1000, 9000)
	for index = 1, GameConfig.CultMinMembers do
		spawnMember(("%s%04d"):format(letter, startNumber + index - 1))
	end
end

Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case then
		case.admitted = true
	end
end)

Guests.registerAnomalyMarker("Cultist", mark)

-- ============================== the ritual (A-5b) ==============================

type Ritual = {
	bathroom: Model,
	stage: "Converging" | "Channeling",
	timer: number,
	kidnapped: { Guests.Guest },
	effects: { Instance },
}

local ritual: Ritual? = nil

local function guestStillActive(guest: Guests.Guest): boolean
	return table.find(Guests.getActive(), guest) ~= nil
end

local function guestPosition(guest: Guests.Guest): Vector3
	local pivot = guest.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function bathroomGround(model: Model): Vector3
	local pivot = model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function pickBathroom(): Model?
	local bathrooms = {}
	for _, model in CollectionService:GetTagged("Facility") do
		if
			model:IsA("Model")
			and model.Parent
			and model:GetAttribute("RefillNeed") == "Bladder"
		then
			table.insert(bathrooms, model)
		end
	end
	if #bathrooms == 0 then
		return nil
	end
	-- §9: more bathrooms = more rooms for the cult to pick
	return bathrooms[rng:NextInteger(1, #bathrooms)]
end

local function ritualParticipants(): { Case }
	local list = {}
	for _, case in cases do
		if case.inRitual and guestStillActive(case.guest) then
			table.insert(list, case)
		end
	end
	return list
end

local function showEmote(guest: Guests.Guest, emoji: string)
	local billboard = guest.emoteLabel.Parent :: BillboardGui
	guest.emoteLabel.Text = emoji
	billboard.Enabled = true
end

local function hideEmote(guest: Guests.Guest)
	local billboard = guest.emoteLabel.Parent :: BillboardGui
	guest.emoteLabel.Text = ""
	billboard.Enabled = false
end

local function spawnRitualEffects(current: Ritual)
	local center = bathroomGround(current.bathroom)
	-- candle ring (grey-box: small posts with fire)
	for index = 1, 5 do
		local angle = (index / 5) * math.pi * 2
		local candle = Instance.new("Part")
		candle.Name = "RitualCandle"
		candle.Anchored = true
		candle.CanCollide = false
		candle.Size = Vector3.new(0.4, 1.2, 0.4)
		candle.Color = Color3.fromRGB(240, 232, 200)
		candle.Material = Enum.Material.SmoothPlastic
		candle.Position = center + Vector3.new(math.cos(angle) * 5, 0.6, math.sin(angle) * 5)
		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 4
		fire.Parent = candle
		candle.Parent = workspace
		table.insert(current.effects, candle)
	end
	-- §4: plume visible from outside the bathroom, across the park
	local plume = Instance.new("Part")
	plume.Name = "RitualPlume"
	plume.Anchored = true
	plume.CanCollide = false
	plume.Size = Vector3.new(1.5, 40, 1.5)
	plume.Position = center + Vector3.new(0, 22, 0)
	plume.Color = Color3.fromRGB(150, 60, 200)
	plume.Material = Enum.Material.Neon
	plume.Transparency = 0.45
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(160, 80, 210))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(4, 8)
	smoke.Rate = 20
	smoke.Parent = plume
	plume.Parent = workspace
	table.insert(current.effects, plume)
end

local function clearRitual(rescueKidnapped: boolean)
	local current = ritual
	if not current then
		return
	end
	ritual = nil
	for _, effect in current.effects do
		effect:Destroy()
	end
	for _, guest in current.kidnapped do
		if not guestStillActive(guest) then
			continue
		end
		if rescueKidnapped then
			-- §4 tone rule: thumbs-up and resume the day as if nothing happened
			showEmote(guest, "👍")
			task.delay(1.5, function()
				if guest.emoteLabel.Parent then
					hideEmote(guest)
				end
			end)
			guest.state = "Admitted"
			guest.dwell = math.max(guest.dwell, 60)
			guest.target = guestPosition(guest) + Vector3.new(rng:NextNumber(-8, 8), 0, 6)
		end
	end
	for _, case in ritualParticipants() do
		case.inRitual = false
		case.admitted = false -- spent: never counts toward another ritual
		local guest = case.guest
		-- made or unmade, the cult files out
		guest.state = "Leaving"
		guest.target = Guests.exitPosition()
	end
end

local function beginRitual(bathroom: Model)
	print("[Anomaly] the cult is converging on a bathroom…")
	ritual = {
		bathroom = bathroom,
		stage = "Converging",
		timer = GameConfig.CultConvergeTimeoutSeconds,
		kidnapped = {},
		effects = {},
	}
	for _, case in cases do
		if case.admitted and guestStillActive(case.guest) then
			case.inRitual = true
		end
	end
end

local function beginChannel(current: Ritual)
	current.stage = "Channeling"
	local locked = current.bathroom:GetAttribute("Locked") == true
	current.timer = GameConfig.CultRitualSeconds
		+ (if locked then GameConfig.CultLockDelaySeconds else 0)
	if locked then
		print("[Anomaly] the bathroom lock is slowing them down (+60s)")
	end
	-- §4 kidnap: whoever was inside is held for the ritual
	for _, guest in Attractions.evictOccupants(current.bathroom) do
		if cases[guest.id] then
			continue -- a cultist using their own ritual site
		end
		guest.state = "OnMission"
		guest.target = bathroomGround(current.bathroom)
			+ Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		showEmote(guest, "😱")
		table.insert(current.kidnapped, guest)
	end
	spawnRitualEffects(current)
	print(
		("[Anomaly] ritual channeling — %d guest(s) kidnapped, %ds to stop it"):format(
			#current.kidnapped,
			current.timer // 1
		)
	)
end

local function completeRitual(current: Ritual)
	local center = bathroomGround(current.bathroom)
	local vanished = 0
	for _, guest in current.kidnapped do
		if guestStillActive(guest) then
			NetTargets.puffAt(guestPosition(guest), Color3.fromRGB(160, 80, 210))
			Guests.despawn(guest)
			vanished += 1
		end
	end
	dayStats:SetAttribute(
		"Disappeared",
		(dayStats:GetAttribute("Disappeared") :: number? or 0) + vanished
	)
	NetTargets.puffAt(center + Vector3.new(0, 3, 0), Color3.fromRGB(160, 80, 210))
	print(
		("[Anomaly] the ritual completed — %d guest(s) are just GONE. The police will hear about this."):format(
			vanished
		)
	)
	current.kidnapped = {}
	clearRitual(false)
end

local TICK = 0.5
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()

		-- prune despawned cultists
		for id, case in cases do
			if not guestStillActive(case.guest) then
				cases[id] = nil
				AnomalyBase.clear(id)
			end
		end

		local current = ritual
		if not current then
			-- §4 trigger: ≥4 admitted members inside → converge
			local admittedCount = 0
			for _, case in cases do
				if case.admitted then
					admittedCount += 1
				end
			end
			if admittedCount >= GameConfig.CultMinMembers then
				local bathroom = pickBathroom()
				if bathroom then
					beginRitual(bathroom)
				end
			end
			continue
		end

		if not current.bathroom.Parent then
			clearRitual(true) -- ritual site vanished (?!) — call it off
			continue
		end

		local participants = ritualParticipants()
		if #participants < GameConfig.CultMinMembers then
			-- §4 counter: salted below the threshold — collapse + rescue
			print("[Anomaly] too few cultists — the ritual collapses!")
			clearRitual(true)
			continue
		end

		if current.stage == "Converging" then
			local arrived = 0
			for index, case in participants do
				local guest = case.guest
				if guest.busy then
					continue -- finishing a ride; they'll head over after
				end
				if guest.state ~= "OnMission" then
					guest.state = "OnMission"
					local angle = (index / #participants) * math.pi * 2
					guest.target = bathroomGround(current.bathroom)
						+ Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)
				elseif not guest.target then
					arrived += 1
				end
			end
			current.timer -= simDt
			if arrived >= GameConfig.CultMinMembers or current.timer <= 0 then
				if arrived >= GameConfig.CultMinMembers then
					beginChannel(current)
				else
					print("[Anomaly] the cult couldn't get organized — they slink off")
					clearRitual(true)
				end
			end
		else
			current.timer -= simDt
			if current.timer <= 0 then
				completeRitual(current)
			end
		end
	end
end)

-- Salt channel (§4/§9): thrown salt evaporates the nearest cultist in a puff
NetTargets.register(function(position: Vector3): NetTargets.Hit?
	local bestCase: Case? = nil
	local bestDistance = math.huge
	for _, case in cases do
		if guestStillActive(case.guest) then
			local distance = (guestPosition(case.guest) - position).Magnitude
			if distance < bestDistance then
				bestCase = case
				bestDistance = distance
			end
		end
	end
	if not bestCase then
		return nil
	end
	local case = bestCase :: Case
	return {
		distance = bestDistance,
		resolve = function(): string
			local guest = case.guest
			cases[guest.id] = nil
			AnomalyBase.clear(guest.id)
			NetTargets.puffAt(guestPosition(guest), Color3.fromRGB(250, 250, 245))
			Guests.despawn(guest)
			dayStats:SetAttribute("Salted", (dayStats:GetAttribute("Salted") :: number? or 0) + 1)
			print("[Anomaly] a cultist met the salt and evaporated")
			return "cultist"
		end,
	}
end, "salt")

Guests.onDrained(function()
	clearRitual(false)
	table.clear(cases)
	table.clear(pendingSerials)
end)

export type CultCase = Case

return Cult
