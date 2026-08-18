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

local arrivalsPerMinute = GameConfig.arrivalsPerMinute(GameConfig.Day1AttractionIndex)
print(("[GuestSpawner] day-1 stream: %.1f arrivals/min"):format(arrivalsPerMinute))

task.spawn(function()
	while true do
		task.wait(60 / arrivalsPerMinute)
		-- §5: guests only arrive while the gates are open
		if dayState:GetAttribute("Phase") == "Open" then
			Guests.spawnArrival()
		end
	end
end)
