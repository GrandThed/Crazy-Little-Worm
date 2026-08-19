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
local Spy = require(script.Parent.anomalies.Spy)
local TicketRules = require(script.Parent.TicketRules)

local Bulletin = require(script.Parent.Bulletin) -- composes the morning edition on plan roll (A-2)
Bulletin.setRuleProvider(TicketRules.ruleTextForDay) -- rule delta line (A-7)

-- §4 pool (tier gates in GameConfig.AnomalyMinIndex); later cards append here
Scheduler.register({
	name = "Infected",
	minIndex = GameConfig.AnomalyMinIndex.Infected,
	spawn = Infected.spawnOne,
})
Scheduler.register({
	name = "Spy",
	minIndex = GameConfig.AnomalyMinIndex.Spy,
	spawn = Spy.spawnOne,
})

-- Debug hooks (F-5): force an arrival of each type / force a rule day now
task.spawn(function()
	local debugActions = ServerStorage:WaitForChild("DebugActions")
	local spawnInfected = debugActions:WaitForChild("SpawnInfected") :: BindableEvent
	spawnInfected.Event:Connect(Infected.spawnOne)
	local spawnSpy = debugActions:WaitForChild("SpawnSpy") :: BindableEvent
	spawnSpy.Event:Connect(Spy.spawnOne)

	local dayState = ReplicatedStorage:WaitForChild("DayState")
	local forceRule = debugActions:WaitForChild("ForceRuleDay") :: BindableEvent
	forceRule.Event:Connect(function()
		TicketRules.forceRule(dayState:GetAttribute("Day") :: number)
		local plan = Scheduler.getPlan()
		if plan then
			Bulletin.publish(plan) -- refresh the edition so the rule line shows
		end
	end)
end)
