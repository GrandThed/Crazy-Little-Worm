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
dayStats:SetAttribute("Walkaways", 0)
dayStats:SetAttribute("Zombies", 0)
dayStats:SetAttribute("Captured", 0)
dayStats:SetAttribute("FoodIncome", 0)
dayStats:SetAttribute("Breakdowns", 0)
dayStats:SetAttribute("Wages", 0)
dayStats:SetAttribute("Fled", 0)
dayStats:SetAttribute("CounterfeitAdmits", 0)
dayStats:SetAttribute("Fines", 0)
dayStats:SetAttribute("Disappeared", 0)
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

-- Required AFTER the folders above exist (their init waits on DayStats/Remotes)
local ReviewTemplates = require(ReplicatedStorage.Shared.ReviewTemplates)
local EconomyStore = require(script.Parent.EconomyStore)
local IndexStore = require(script.Parent.IndexStore)
local Staff = require(script.Parent.Staff)

local staffQuitToday = 0
Staff.onQuit(function()
	staffQuitToday += 1
end)

local currentDay = 1
local currentPhase = "Prep"
local advanceRequested = false
local phaseDeadline: number? = nil -- real-time deadline of the current timed phase
local lastTimeScale = GameConfig.timeScale()

-- gameDuration is in design-time seconds; the debug time scale (F-5)
-- compresses it to real time. duration nil = untimed phase.
local function setPhase(phase: string, gameDuration: number?)
	currentPhase = phase
	phaseDeadline = if gameDuration
		then workspace:GetServerTimeNow() + gameDuration / GameConfig.timeScale()
		else nil
	dayState:SetAttribute("Phase", phase)
	dayState:SetAttribute("PhaseEndsAt", phaseDeadline or 0)
	print(("[DayCycle] day %d — %s"):format(currentDay, phase))
end

-- Speed changes apply immediately: rescale the remaining time of the current
-- phase so the countdown jumps to the new pace
workspace:GetAttributeChangedSignal("DaySpeedMultiplier"):Connect(function()
	if not RunService:IsStudio() then
		return
	end
	local newScale = GameConfig.timeScale()
	local deadline = phaseDeadline
	if deadline then
		local now = workspace:GetServerTimeNow()
		local remaining = math.max(0, deadline - now)
		phaseDeadline = now + remaining * lastTimeScale / newScale
		dayState:SetAttribute("PhaseEndsAt", phaseDeadline)
	end
	lastTimeScale = newScale
end)

-- Blocks until the phase deadline passes (untimed phases have none) or
-- something requests an advance: the phase-appropriate player remote, or the
-- debug skip (F-5)
local function waitForAdvance()
	advanceRequested = false
	while not advanceRequested do
		local deadline = phaseDeadline
		if deadline and workspace:GetServerTimeNow() >= deadline then
			return
		end
		task.wait(0.1)
	end
end

local function resetStats()
	dayStats:SetAttribute("Arrivals", 0)
	dayStats:SetAttribute("Admissions", 0)
	dayStats:SetAttribute("Income", 0)
	dayStats:SetAttribute("Walkaways", 0)
	dayStats:SetAttribute("Zombies", 0)
	dayStats:SetAttribute("Captured", 0)
	dayStats:SetAttribute("FoodIncome", 0)
	dayStats:SetAttribute("Breakdowns", 0)
	dayStats:SetAttribute("Wages", 0)
	dayStats:SetAttribute("Fled", 0)
	dayStats:SetAttribute("CounterfeitAdmits", 0)
	dayStats:SetAttribute("Fines", 0)
	dayStats:SetAttribute("Disappeared", 0)
	staffQuitToday = 0
end

local function statNumber(name: string): number
	local value = dayStats:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

openGatesRemote.OnServerEvent:Connect(function()
	if currentPhase == "Prep" then
		advanceRequested = true
	end
end)
nextDayRemote.OnServerEvent:Connect(function()
	if currentPhase == "Summary" then
		advanceRequested = true
	end
end)

-- Debug skip (F-5): DebugService owns the DebugActions folder
task.spawn(function()
	local advanceAction = ServerStorage:WaitForChild("DebugActions"):WaitForChild("AdvancePhase");
	(advanceAction :: BindableEvent).Event:Connect(function()
		advanceRequested = true
	end)
end)

task.spawn(function()
	while true do
		resetStats()
		setPhase("Prep")
		waitForAdvance()

		setPhase("Open", GameConfig.OpenDurationSeconds)
		waitForAdvance()

		setPhase("Closing", GameConfig.ClosingDurationSeconds)
		waitForAdvance()

		setPhase("Summary")
		-- Summary v1 (P-8): settle wages + loan first so the numbers are final
		local wagesPaid = Staff.settleWages()
		local loanRepaid = EconomyStore.repayLoanDaily()
		-- A-7 counterfeit fines (A-5b police bribes add to the same pot);
		-- collected up to cash on hand — the floor rule holds (§7)
		local finesDue = statNumber("CounterfeitAdmits") * GameConfig.CounterfeitFine
			+ statNumber("Disappeared") * GameConfig.CultFinePerGuest
		local finesPaid = EconomyStore.deductUpTo(finesDue)
		dayStats:SetAttribute("Fines", finesPaid)
		local satisfaction = IndexStore.getSatisfaction()
		local stars = math.clamp(math.floor(1 + 4 * satisfaction + 0.5), 1, 5)
		local reviews = ReviewTemplates.pick({
			zombies = statNumber("Zombies"),
			captured = statNumber("Captured"),
			breakdowns = statNumber("Breakdowns"),
			walkaways = statNumber("Walkaways"),
			fled = statNumber("Fled"),
			staffQuit = staffQuitToday,
			loanBalance = EconomyStore.getLoanBalance(),
			stars = stars,
			counterfeits = statNumber("CounterfeitAdmits"),
			tampered = statNumber("Tampered"),
			launched = statNumber("Launched"),
			disappeared = statNumber("Disappeared"),
			salted = statNumber("Salted"),
		}, 3)
		daySummaryRemote:FireAllClients({
			day = currentDay,
			arrivals = statNumber("Arrivals"),
			admissions = statNumber("Admissions"),
			walkaways = statNumber("Walkaways"),
			income = statNumber("Income"),
			foodIncome = statNumber("FoodIncome"),
			wages = wagesPaid,
			loanRepaid = loanRepaid,
			fines = finesPaid,
			counterfeits = statNumber("CounterfeitAdmits"),
			disappeared = statNumber("Disappeared"),
			zombies = statNumber("Zombies"),
			captured = statNumber("Captured"),
			breakdowns = statNumber("Breakdowns"),
			stars = stars,
			reviews = reviews,
		})
		waitForAdvance()

		currentDay += 1
		dayState:SetAttribute("Day", currentDay)
	end
end)
