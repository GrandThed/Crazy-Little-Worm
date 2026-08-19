--!strict
-- Infirmary escort (A-8), per §9: walk a suspicious coughing guest to the
-- infirmary — cured if infected (dormant/incubating), thumbs-up if not (§4
-- tone rule: no punishment for a wrong hunch). Every admitted guest carries
-- an escort prompt that lights up once an infirmary exists; the exam result
-- never leaks the anomaly flag — both outcomes look identical to clients
-- except for the cure's puff of green.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Infected = require(script.Parent.anomalies.Infected)
local Buildings = require(script.Parent.Buildings)
local Guests = require(script.Parent.Guests)

local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

type Escort = {
	stage: "Walking" | "Exam",
	timer: number,
}

local prompts: { [Guests.Guest]: ProximityPrompt } = {}
local escorts: { [Guests.Guest]: Escort } = {}

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

local function thumbsUp(guest: Guests.Guest)
	guest.emoteLabel.Text = "👍"
	(guest.emoteLabel.Parent :: BillboardGui).Enabled = true
	task.delay(1.5, function()
		if guest.emoteLabel.Parent then
			guest.emoteLabel.Text = ""
			(guest.emoteLabel.Parent :: BillboardGui).Enabled = false
		end
	end)
end

local function beginEscort(guest: Guests.Guest)
	if escorts[guest] or guest.state ~= "Admitted" or guest.busy then
		return
	end
	local pivot = guest.model:GetPivot().Position
	local infirmary, spot = Buildings.nearestInfirmary(Vector3.new(pivot.X, 0, pivot.Z))
	if not (infirmary and spot) then
		return
	end
	guest.state = "OnMission"
	guest.target = spot
	escorts[guest] = { stage = "Walking", timer = GameConfig.InfirmaryExamSeconds }
	print(("[Infirmary] %s is being walked to a check-up"):format(guest.model.Name))
end

Guests.onSpawned(function(guest)
	local body = guest.model:FindFirstChild("Body")
	if not body then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EscortPrompt"
	prompt.ActionText = "Infirmary check-up"
	prompt.ObjectText = guest.model.Name
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 6
	prompt.UIOffset = Vector2.new(0, 40) -- clear of the emote billboard
	prompt.Enabled = false
	prompt.Parent = body
	prompt.Triggered:Connect(function()
		beginEscort(guest)
	end)
	prompts[guest] = prompt
end)

local TICK = 0.5
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()
		local hasInfirmary = Buildings.hasInfirmary()

		for guest, prompt in prompts do
			if not guestStillActive(guest) then
				prompts[guest] = nil -- prompt died with the model
				continue
			end
			prompt.Enabled = hasInfirmary
				and guest.state == "Admitted"
				and not guest.busy
				and escorts[guest] == nil
		end

		for guest, escort in escorts do
			if not guestStillActive(guest) or guest.state ~= "OnMission" then
				escorts[guest] = nil
				continue
			end
			if escort.stage == "Walking" then
				if not guest.target then
					escort.stage = "Exam"
				end
			else
				escort.timer -= simDt
				if escort.timer <= 0 then
					escorts[guest] = nil
					if Infected.cure(guest.id) then
						dayStats:SetAttribute(
							"Cured",
							(dayStats:GetAttribute("Cured") :: number? or 0) + 1
						)
						print(("[Infirmary] %s was infected — cured!"):format(guest.model.Name))
					else
						print(
							("[Infirmary] %s got a clean bill of health"):format(guest.model.Name)
						)
					end
					thumbsUp(guest) -- either way: thumbs-up, carry on (§4)
					guest.state = "Admitted"
					guest.dwell = math.max(guest.dwell, 60)
					guest.target = randomParkPoint()
				end
			end
		end
	end
end)
