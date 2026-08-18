--!strict
-- Anomaly driver (G-6). Boots anomaly modules and runs the interim spawn
-- rule from §8: day 1 is guaranteed safe; from day 2, one slot fills with
-- p≈0.7 at a random time within Open. The real scheduler (slots by
-- AttractionIdx, pool gating) replaces this in A-1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Infected = require(script.Parent.anomalies.Infected)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local rng = Random.new()

-- Debug hook (F-5): force an infected arrival right now
task.spawn(function()
	local debugActions = ServerStorage:WaitForChild("DebugActions")
	local spawnInfected = debugActions:WaitForChild("SpawnInfected") :: BindableEvent
	spawnInfected.Event:Connect(Infected.spawnOne)
end)

-- One filled-or-empty slot per day (interim A-1 stand-in), timed by
-- accumulating simulated seconds so the debug time scale is honored
dayState:GetAttributeChangedSignal("Phase"):Connect(function()
	if dayState:GetAttribute("Phase") ~= "Open" then
		return
	end
	local day = dayState:GetAttribute("Day") :: number
	if day < 2 then
		return -- §8: day 1 is the only guaranteed-safe day
	end
	if rng:NextNumber() >= GameConfig.AnomalyFillChance then
		print("[Anomaly] quiet day — the slot stayed empty")
		return
	end
	local spawnAt = rng:NextNumber(0.1, 0.8) * GameConfig.OpenDurationSeconds
	task.spawn(function()
		local elapsed = 0
		while dayState:GetAttribute("Phase") == "Open" do
			local waited = task.wait(0.25)
			elapsed += waited * GameConfig.timeScale()
			if elapsed >= spawnAt then
				Infected.spawnOne()
				return
			end
		end
	end)
end)
