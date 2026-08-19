--!strict
-- Corporate spy (A-3), per §4: the quiet economic bleed. Gate tells: suit +
-- briefcase (innocent businessmen exist — §3 ambiguity) and a wrong ticket
-- date. Inside: blends, then walks to the highest-appeal ride and tampers for
-- 15s → condition −40 (below 30 = breakdown, severity 6 per ride broken), up
-- to 3 rides, then slips away. Counters: a security camera covering the ride
-- pings and reveals the tamper; the capture net catches a spy in the act or
-- while revealed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local NetTargets = require(script.Parent.NetTargets)
local Attractions = require(script.Parent.Parent.Attractions)
local Buildings = require(script.Parent.Parent.Buildings)
local Guests = require(script.Parent.Parent.Guests)
local IndexStore = require(script.Parent.Parent.IndexStore)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

local SUIT_COLOR = Color3.fromRGB(52, 68, 130) -- matches the innocent suits

type Stage = "Blending" | "Moving" | "Tampering" | "Done"

type Case = {
	guest: Guests.Guest,
	stage: Stage,
	timer: number, -- simulated seconds to the next stage
	targetRide: Model?,
	hitRides: { [Model]: boolean },
	ridesHit: number,
	revealTimer: number, -- >0 while a camera ping has them highlighted
	highlight: Highlight?,
	sparks: ParticleEmitter?,
}

local cases: { [string]: Case } = {}

local Spy = {}

local function getPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	return if child and child:IsA("BasePart") then child else nil
end

local function guestStillActive(guest: Guests.Guest): boolean
	return table.find(Guests.getActive(), guest) ~= nil
end

local function guestPosition(guest: Guests.Guest): Vector3
	local pivot = guest.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function rideGroundPosition(model: Model): Vector3
	local pivot = model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function attributeNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

-- Gate-time marker (§4 Infiltrate): suit, briefcase, wrong-date ticket
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Spy")
	local body = getPart(guest.model, "Body")
	if body then
		body.Color = SUIT_COLOR
	end
	Guests.attachBriefcase(guest.model)

	local day = dayState:GetAttribute("Day") :: number
	local wrongDay = math.max(1, day + (if rng:NextNumber() < 0.5 then -1 else 1))
	if wrongDay == day then
		wrongDay = day + 1
	end
	local wrongDate = ("Day %d"):format(wrongDay)
	guest.identity.ticket.date = wrongDate
	guest.model:SetAttribute("TicketDate", wrongDate)

	cases[guest.id] = {
		guest = guest,
		stage = "Blending",
		timer = math.huge, -- armed on admission
		targetRide = nil,
		hitRides = {},
		ridesHit = 0,
		revealTimer = 0,
		highlight = nil,
		sparks = nil,
	}
	print("[Anomaly] a corporate spy has joined the queue")
end

-- §2 appeal formula, minus satisfaction: the spy hits where it hurts most
local function pickTarget(case: Case): Model?
	local best: Model? = nil
	local bestAppeal = 0
	for _, model in Attractions.getRideModels() do
		if model:GetAttribute("Broken") == true or case.hitRides[model] then
			continue
		end
		local appeal = attributeNumber(model, "BaseAppeal", 0)
			* (1 + 0.25 * (attributeNumber(model, "Tier", 1) - 1))
			* (attributeNumber(model, "Condition", 100) / 100)
		if appeal > bestAppeal then
			bestAppeal = appeal
			best = model
		end
	end
	return best
end

local function clearReveal(case: Case)
	case.revealTimer = 0
	local highlight = case.highlight
	if highlight then
		highlight:Destroy()
		case.highlight = nil
	end
end

local function reveal(case: Case)
	case.revealTimer = GameConfig.SpyRevealSeconds
	if not case.highlight then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 70, 60)
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = Color3.fromRGB(255, 70, 60)
		highlight.Parent = case.guest.model
		case.highlight = highlight
	end
end

local function clearSparks(case: Case)
	local sparks = case.sparks
	if sparks then
		sparks:Destroy()
		case.sparks = nil
	end
end

local function leave(case: Case)
	clearSparks(case)
	clearReveal(case)
	local guest = case.guest
	cases[guest.id] = nil
	AnomalyBase.clear(guest.id)
	guest.state = "Leaving"
	guest.target = Guests.exitPosition()
	print(("[Anomaly] the spy slipped away after %d ride(s)"):format(case.ridesHit))
end

local function beginTamper(case: Case)
	local target = case.targetRide :: Model
	case.stage = "Tampering"
	case.timer = GameConfig.SpyTamperSeconds
	local body = getPart(case.guest.model, "Body")
	if body then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "TamperSparks"
		sparks.Color = ColorSequence.new(Color3.fromRGB(120, 130, 150))
		sparks.Size = NumberSequence.new(0.25)
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Speed = NumberRange.new(2, 4)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Rate = 10
		sparks.Parent = body
		case.sparks = sparks
	end
	-- §4 counter: a camera covering the ride pings and blows their cover
	local camera = Buildings.cameraCovering(rideGroundPosition(target))
	if camera then
		Buildings.cameraAlert(camera)
		reveal(case)
		print(("[Anomaly] camera caught tampering at %s!"):format(target.Name))
	end
end

local function moveToNextTarget(case: Case): boolean
	local target = pickTarget(case)
	if not target then
		leave(case)
		return false
	end
	case.targetRide = target
	case.stage = "Moving"
	case.guest.state = "OnMission"
	local around = rideGroundPosition(target)
	case.guest.target = around + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
	return true
end

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

			if case.revealTimer > 0 then
				case.revealTimer -= simDt
				if case.revealTimer <= 0 then
					clearReveal(case)
				end
			end

			if case.stage == "Blending" then
				case.timer -= simDt
				if case.timer <= 0 then
					moveToNextTarget(case)
				end
			elseif case.stage == "Moving" then
				local target = case.targetRide
				if not (target and target.Parent) or target:GetAttribute("Broken") == true then
					moveToNextTarget(case) -- broke/vanished while walking over
				elseif not guest.target then
					beginTamper(case)
				end
			elseif case.stage == "Tampering" then
				local target = case.targetRide
				if not (target and target.Parent) then
					clearSparks(case)
					moveToNextTarget(case)
					continue
				end
				case.timer -= simDt
				if case.timer <= 0 then
					clearSparks(case)
					dayStats:SetAttribute(
						"Tampered",
						(dayStats:GetAttribute("Tampered") :: number? or 0) + 1
					)
					local broke = Attractions.sabotage(target, GameConfig.SpyConditionDamage)
					if broke then
						IndexStore.addIncident(GameConfig.SpySeverityPerRide) -- §4 severity
					end
					case.hitRides[target] = true
					case.ridesHit += 1
					if case.ridesHit >= GameConfig.SpyMaxRides then
						leave(case)
					else
						moveToNextTarget(case)
					end
				end
			end
		end
	end
end)

-- Admission arms the activation clock (§4 Dormant → Activate)
Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case and case.stage == "Blending" then
		local delay = GameConfig.SpyActivationDelay
		case.timer = rng:NextNumber(delay[1], delay[2])
	end
end)

-- Net catch (§9): in the act, or while a camera ping has them revealed
NetTargets.register(function(position: Vector3): NetTargets.Hit?
	local bestCase: Case? = nil
	local bestDistance = math.huge
	for _, case in cases do
		if case.stage == "Tampering" or case.revealTimer > 0 then
			if guestStillActive(case.guest) then
				local distance = (guestPosition(case.guest) - position).Magnitude
				if distance < bestDistance then
					bestCase = case
					bestDistance = distance
				end
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
			clearSparks(case)
			clearReveal(case)
			cases[guest.id] = nil
			AnomalyBase.clear(guest.id)
			NetTargets.puffAt(guestPosition(guest), Color3.fromRGB(160, 175, 220))
			Guests.despawn(guest)
			dayStats:SetAttribute(
				"Captured",
				(dayStats:GetAttribute("Captured") :: number? or 0) + 1
			)
			print("[Anomaly] the spy was netted mid-tamper — briefcase and all")
			return "spy"
		end,
	}
end)

Guests.onDrained(function()
	table.clear(cases)
end)

Guests.registerAnomalyMarker("Spy", mark)

function Spy.spawnOne()
	Guests.spawnArrival({ anomaly = "Spy" })
end

return Spy
