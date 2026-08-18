--!strict
-- Debug tooling (F-5), server side. One DebugCommand remote is the only entry
-- point, HARD-GATED on RunService:IsStudio() — in production it exists but
-- ignores everything. Commands route to BindableEvents under
-- ServerStorage.DebugActions; gameplay systems connect their own hooks there
-- (debuggability rule: every feature adds its knobs here + a DebugPanel control).
--
-- Current commands:
--   SetDaySpeed (number 1–100)  — day-duration divisor, applies at next phase
--   AdvancePhase                — skip the current day phase
--   SpawnGuest                  — force one arrival, ignores phase/rate
--   DrainPark                   — despawn all guests

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local EconomyStore = require(script.Parent.EconomyStore)

local ACTION_NAMES = {
	"AdvancePhase",
	"SpawnGuest",
	"DrainPark",
	"ApproveFront",
	"DenyFront",
	"SapPatience",
	"SpawnInfected",
}

local debugActions = Instance.new("Folder")
debugActions.Name = "DebugActions"
local actions: { [string]: BindableEvent } = {}
for _, name in ACTION_NAMES do
	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = debugActions
	actions[name] = event
end
debugActions.Parent = ServerStorage

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local debugCommand = Instance.new("RemoteEvent")
debugCommand.Name = "DebugCommand"
debugCommand.Parent = remotes

debugCommand.OnServerEvent:Connect(function(player, command: unknown, value: unknown)
	if not RunService:IsStudio() then
		return
	end
	if command == "SetDaySpeed" then
		if typeof(value) == "number" and value >= 1 and value <= 100 then
			workspace:SetAttribute("DaySpeedMultiplier", value)
			print(("[Debug] %s set day speed ×%d"):format(player.Name, value))
		end
	elseif command == "GiveCash" then
		if typeof(value) == "number" and value >= 1 and value <= 100000 then
			EconomyStore.add(value)
			print(("[Debug] %s added $%d"):format(player.Name, value))
		end
	elseif typeof(command) == "string" and actions[command] then
		print(("[Debug] %s → %s"):format(player.Name, command))
		actions[command]:Fire()
	end
end)

-- Mirror server-only stats to a replicated folder so the panel can read them.
-- Studio-only loop; in production the folder sits empty.
local debugState = Instance.new("Folder")
debugState.Name = "DebugState"
debugState.Parent = ReplicatedStorage

if RunService:IsStudio() then
	local dayStats = ServerStorage:WaitForChild("DayStats")
	task.spawn(function()
		while true do
			for _, attribute in
				{
					"Arrivals",
					"Admissions",
					"Income",
					"GuestsOnMap",
					"Overflow",
					"Walkaways",
					"Zombies",
				}
			do
				debugState:SetAttribute(attribute, dayStats:GetAttribute(attribute) or 0)
			end
			debugState:SetAttribute("DaySpeed", workspace:GetAttribute("DaySpeedMultiplier") or 1)
			task.wait(0.5)
		end
	end)
end
