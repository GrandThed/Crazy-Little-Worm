--!strict
-- Arrival driver (G-1, thinned in G-2 — lifecycle lives in Guests.luau).
-- Spawns at the §2 inflow rate while gates are Open; drains at Summary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Guests = require(script.Parent.Guests)

local dayState = ReplicatedStorage:WaitForChild("DayState")

dayState:GetAttributeChangedSignal("Phase"):Connect(function()
	if dayState:GetAttribute("Phase") == "Summary" then
		Guests.drainPark()
	end
end)

-- Debug hooks (F-5): force one arrival (ignores phase + rate) / drain now
task.spawn(function()
	local debugActions = ServerStorage:WaitForChild("DebugActions")
	local spawnAction = debugActions:WaitForChild("SpawnGuest") :: BindableEvent
	local drainAction = debugActions:WaitForChild("DrainPark") :: BindableEvent
	local sapAction = debugActions:WaitForChild("SapPatience") :: BindableEvent
	spawnAction.Event:Connect(function()
		Guests.spawnArrival()
	end)
	drainAction.Event:Connect(Guests.drainPark)
	sapAction.Event:Connect(Guests.sapPatience)
end)

-- §2 inflow wired to the LIVE attraction index (P-5): the interval re-derives
-- every tick, so park growth immediately raises the arrival stream.
-- Accumulates simulated time so the debug time scale applies instantly;
-- §5: guests only arrive while the gates are open.
task.spawn(function()
	local indexState = ReplicatedStorage:WaitForChild("IndexState")
	local accumulated = 0
	while true do
		local elapsed = task.wait(0.25)
		if dayState:GetAttribute("Phase") == "Open" then
			local index = indexState:GetAttribute("Index")
			local perMinute = GameConfig.arrivalsPerMinute(
				if typeof(index) == "number" then index else GameConfig.Day1AttractionIndex
			)
			accumulated += elapsed * GameConfig.timeScale()
			local interval = 60 / perMinute
			if accumulated >= interval then
				accumulated -= interval
				Guests.spawnArrival()
			end
		else
			accumulated = 0
		end
	end
end)
