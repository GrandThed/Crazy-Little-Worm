--!strict
-- Anomaly driver. Composition root for the anomaly layer: registers every
-- anomaly type with the Scheduler (A-1) and wires the per-type debug spawn
-- hooks (F-5). Scheduling itself — slots by AttractionIdx, pool tier gating,
-- fill rolls, spawn times — lives in anomalies/Scheduler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Infected = require(script.Parent.anomalies.Infected)
local Scheduler = require(script.Parent.anomalies.Scheduler)

require(script.Parent.Bulletin) -- composes the morning edition on plan roll (A-2)

-- §4 pool (tier gates in GameConfig.AnomalyMinIndex); later cards append here
Scheduler.register({
	name = "Infected",
	minIndex = GameConfig.AnomalyMinIndex.Infected,
	spawn = Infected.spawnOne,
})

-- Debug hooks (F-5): force an arrival of each type right now
task.spawn(function()
	local debugActions = ServerStorage:WaitForChild("DebugActions")
	local spawnInfected = debugActions:WaitForChild("SpawnInfected") :: BindableEvent
	spawnInfected.Event:Connect(Infected.spawnOne)
end)
