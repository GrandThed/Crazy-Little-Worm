--!strict
-- Day cycle state machine (G-5). Phases per design doc §5:
--   Prep (untimed, waits for Open Gates) → Open (12 min) → Closing (2 min)
--   → Summary (waits for continue) → next day.
--
-- Replication (server-architecture skill): phase/day/deadline live as
-- attributes on ReplicatedStorage.DayState — server writes, clients only
-- render. Per-day counters live on ServerStorage.DayStats (server-only;
-- gameplay systems increment them) and reach clients exactly once, inside
-- the summary payload. v0: any player may advance phases — host-gating
-- arrives with rooms (Epic R).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local dayState = Instance.new("Folder")
dayState.Name = "DayState"
dayState:SetAttribute("Day", 1)
dayState:SetAttribute("Phase", "Prep")
dayState:SetAttribute("PhaseEndsAt", 0) -- workspace:GetServerTimeNow() deadline; 0 = untimed
dayState.Parent = ReplicatedStorage

local dayStats = Instance.new("Folder")
dayStats.Name = "DayStats"
dayStats:SetAttribute("Arrivals", 0)
dayStats:SetAttribute("Admissions", 0)
dayStats:SetAttribute("Income", 0)
dayStats.Parent = ServerStorage

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local openGatesRemote = Instance.new("RemoteEvent")
openGatesRemote.Name = "OpenGates"
openGatesRemote.Parent = remotes
local nextDayRemote = Instance.new("RemoteEvent")
nextDayRemote.Name = "NextDay"
nextDayRemote.Parent = remotes
local daySummaryRemote = Instance.new("RemoteEvent")
daySummaryRemote.Name = "DaySummary"
daySummaryRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local currentDay = 1

-- Studio-only fast-forward: set a DaySpeedMultiplier attribute on Workspace
-- (e.g. 20) in the command bar to compress the 12-minute day for testing
local function scaled(seconds: number): number
	local multiplier = workspace:GetAttribute("DaySpeedMultiplier")
	if RunService:IsStudio() and typeof(multiplier) == "number" and multiplier > 0 then
		return seconds / multiplier
	end
	return seconds
end

local function setPhase(phase: string, duration: number?)
	dayState:SetAttribute("Phase", phase)
	dayState:SetAttribute(
		"PhaseEndsAt",
		if duration then workspace:GetServerTimeNow() + duration else 0
	)
	print(("[DayCycle] day %d — %s"):format(currentDay, phase))
end

local function resetStats()
	dayStats:SetAttribute("Arrivals", 0)
	dayStats:SetAttribute("Admissions", 0)
	dayStats:SetAttribute("Income", 0)
end

task.spawn(function()
	while true do
		resetStats()
		setPhase("Prep")
		openGatesRemote.OnServerEvent:Wait()

		local openDuration = scaled(GameConfig.OpenDurationSeconds)
		setPhase("Open", openDuration)
		task.wait(openDuration)

		local closingDuration = scaled(GameConfig.ClosingDurationSeconds)
		setPhase("Closing", closingDuration)
		task.wait(closingDuration)

		setPhase("Summary")
		daySummaryRemote:FireAllClients({
			day = currentDay,
			arrivals = dayStats:GetAttribute("Arrivals"),
			admissions = dayStats:GetAttribute("Admissions"),
			income = dayStats:GetAttribute("Income"),
		})
		nextDayRemote.OnServerEvent:Wait()

		currentDay += 1
		dayState:SetAttribute("Day", currentDay)
	end
end)
