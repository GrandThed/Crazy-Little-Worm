--!strict
-- Day cycle HUD v0 (G-5): phase/day bar with countdown, Open Gates button
-- during Prep, and the Summary panel (admissions + income). Pure rendering —
-- all state comes from ReplicatedStorage.DayState attributes and the
-- DaySummary payload; buttons just fire remotes and the server decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local dayState = ReplicatedStorage:WaitForChild("DayState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openGatesRemote = remotes:WaitForChild("OpenGates") :: RemoteEvent
local nextDayRemote = remotes:WaitForChild("NextDay") :: RemoteEvent
local daySummaryRemote = remotes:WaitForChild("DaySummary") :: RemoteEvent

type Review = { stars: number, text: string }
type SummaryPayload = {
	day: number,
	arrivals: number,
	admissions: number,
	walkaways: number,
	income: number,
	foodIncome: number,
	wages: number,
	loanRepaid: number,
	fines: number,
	counterfeits: number,
	disappeared: number,
	zombies: number,
	captured: number,
	breakdowns: number,
	stars: number,
	reviews: { Review },
}

local economyState = ReplicatedStorage:WaitForChild("EconomyState")
local takeLoanRemote = remotes:WaitForChild("TakeLoan") :: RemoteEvent

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DayHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Top-center phase bar
local phaseBar = Instance.new("TextLabel")
phaseBar.Name = "PhaseBar"
phaseBar.AnchorPoint = Vector2.new(0.5, 0)
phaseBar.Position = UDim2.fromScale(0.5, 0.02)
phaseBar.Size = UDim2.fromOffset(260, 36)
phaseBar.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
phaseBar.BackgroundTransparency = 0.25
phaseBar.TextColor3 = Color3.fromRGB(255, 255, 255)
phaseBar.Font = Enum.Font.GothamBold
phaseBar.TextSize = 18
phaseBar.Text = "Day 1 · Prep"
phaseBar.Parent = screenGui
local phaseBarCorner = Instance.new("UICorner")
phaseBarCorner.CornerRadius = UDim.new(0, 8)
phaseBarCorner.Parent = phaseBar

-- Prep: Open the Gates button
local openButton = Instance.new("TextButton")
openButton.Name = "OpenGates"
openButton.AnchorPoint = Vector2.new(0.5, 1)
openButton.Position = UDim2.fromScale(0.5, 0.9)
openButton.Size = UDim2.fromOffset(220, 52)
openButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.Font = Enum.Font.GothamBold
openButton.TextSize = 20
openButton.Text = "Open the Gates"
openButton.Parent = screenGui
local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(0, 10)
openButtonCorner.Parent = openButton

-- Prep loan button (P-9): visible while no loan is outstanding
local loanButton = Instance.new("TextButton")
loanButton.Name = "TakeLoan"
loanButton.Position = UDim2.fromOffset(12, 440)
loanButton.Size = UDim2.fromOffset(180, 32)
loanButton.BackgroundColor3 = Color3.fromRGB(175, 132, 40)
loanButton.TextColor3 = Color3.fromRGB(255, 255, 255)
loanButton.Font = Enum.Font.GothamBold
loanButton.TextSize = 14
loanButton.Text = "Take loan +$2000"
loanButton.Visible = false
loanButton.Parent = screenGui
local loanCorner = Instance.new("UICorner")
loanCorner.CornerRadius = UDim.new(0, 8)
loanCorner.Parent = loanButton

-- Summary panel v1 (P-8): statistics page + review page
local summaryPanel = Instance.new("Frame")
summaryPanel.Name = "SummaryPanel"
summaryPanel.AnchorPoint = Vector2.new(0.5, 0.5)
summaryPanel.Position = UDim2.fromScale(0.5, 0.5)
summaryPanel.Size = UDim2.fromOffset(380, 330)
summaryPanel.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
summaryPanel.Visible = false
summaryPanel.Parent = screenGui
local summaryCorner = Instance.new("UICorner")
summaryCorner.CornerRadius = UDim.new(0, 12)
summaryCorner.Parent = summaryPanel

local summaryTitle = Instance.new("TextLabel")
summaryTitle.BackgroundTransparency = 1
summaryTitle.Position = UDim2.fromOffset(0, 12)
summaryTitle.Size = UDim2.new(1, 0, 0, 28)
summaryTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
summaryTitle.Font = Enum.Font.GothamBold
summaryTitle.TextSize = 22
summaryTitle.Text = "Day 1 Summary"
summaryTitle.Parent = summaryPanel

local starsLabel = Instance.new("TextLabel")
starsLabel.BackgroundTransparency = 1
starsLabel.Position = UDim2.fromOffset(0, 40)
starsLabel.Size = UDim2.new(1, 0, 0, 22)
starsLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
starsLabel.Font = Enum.Font.GothamBold
starsLabel.TextSize = 18
starsLabel.Text = ""
starsLabel.Parent = summaryPanel

local function makeTab(text: string, xScale: number): TextButton
	local tab = Instance.new("TextButton")
	tab.AnchorPoint = Vector2.new(0.5, 0)
	tab.Position = UDim2.new(xScale, 0, 0, 66)
	tab.Size = UDim2.fromOffset(120, 26)
	tab.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
	tab.TextColor3 = Color3.fromRGB(235, 238, 248)
	tab.Font = Enum.Font.GothamMedium
	tab.TextSize = 14
	tab.Text = text
	tab.Parent = summaryPanel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tab
	return tab
end

local statsTab = makeTab("Statistics", 0.28)
local reviewsTab = makeTab("Reviews", 0.72)

local summaryBody = Instance.new("TextLabel")
summaryBody.BackgroundTransparency = 1
summaryBody.Position = UDim2.fromOffset(28, 100)
summaryBody.Size = UDim2.new(1, -56, 0, 160)
summaryBody.TextColor3 = Color3.fromRGB(220, 224, 235)
summaryBody.Font = Enum.Font.Code
summaryBody.TextSize = 14
summaryBody.TextXAlignment = Enum.TextXAlignment.Left
summaryBody.TextYAlignment = Enum.TextYAlignment.Top
summaryBody.TextWrapped = true
summaryBody.Text = ""
summaryBody.Parent = summaryPanel

local statsText = ""
local reviewsText = ""

local function showStats()
	summaryBody.Text = statsText
	statsTab.BackgroundColor3 = Color3.fromRGB(76, 132, 175)
	reviewsTab.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
end

local function showReviews()
	summaryBody.Text = reviewsText
	reviewsTab.BackgroundColor3 = Color3.fromRGB(76, 132, 175)
	statsTab.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
end

statsTab.Activated:Connect(showStats)
reviewsTab.Activated:Connect(showReviews)

local continueButton = Instance.new("TextButton")
continueButton.AnchorPoint = Vector2.new(0.5, 1)
continueButton.Position = UDim2.new(0.5, 0, 1, -16)
continueButton.Size = UDim2.fromOffset(200, 44)
continueButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
continueButton.TextColor3 = Color3.fromRGB(255, 255, 255)
continueButton.Font = Enum.Font.GothamBold
continueButton.TextSize = 18
continueButton.Text = "Start Day 2"
continueButton.Parent = summaryPanel
local continueCorner = Instance.new("UICorner")
continueCorner.CornerRadius = UDim.new(0, 10)
continueCorner.Parent = continueButton

local function refreshPhaseUI()
	local phase = dayState:GetAttribute("Phase") :: string
	openButton.Visible = phase == "Prep"
	loanButton.Visible = phase == "Prep"
		and (economyState:GetAttribute("LoanBalance") :: number? or 0) <= 0
	if phase ~= "Summary" then
		summaryPanel.Visible = false
	end
end

economyState:GetAttributeChangedSignal("LoanBalance"):Connect(refreshPhaseUI)
loanButton.Activated:Connect(function()
	takeLoanRemote:FireServer()
end)

dayState:GetAttributeChangedSignal("Phase"):Connect(refreshPhaseUI)
refreshPhaseUI()

openButton.Activated:Connect(function()
	openGatesRemote:FireServer()
end)

continueButton.Activated:Connect(function()
	nextDayRemote:FireServer()
end)

daySummaryRemote.OnClientEvent:Connect(function(payload: SummaryPayload)
	summaryTitle.Text = ("Day %d Summary"):format(payload.day)
	starsLabel.Text = string.rep("★", payload.stars) .. string.rep("☆", 5 - payload.stars)

	statsText = table.concat({
		("admissions   %d   (arrivals %d)"):format(payload.admissions, payload.arrivals),
		("walkaways    %d"):format(payload.walkaways),
		("entry fees   $%d"):format(payload.income - payload.foodIncome),
		("food sales   $%d"):format(payload.foodIncome),
		("wages        -$%d"):format(payload.wages),
		("loan repaid  -$%d"):format(payload.loanRepaid),
		("fines        -$%d%s"):format(
			payload.fines,
			if payload.counterfeits > 0 or payload.disappeared > 0
				then (" (%d fakes, %d missing)"):format(payload.counterfeits, payload.disappeared)
				else ""
		),
		("net          $%d"):format(
			payload.income - payload.wages - payload.loanRepaid - payload.fines
		),
		"",
		("zombies %d · netted %d · breakdowns %d"):format(
			payload.zombies,
			payload.captured,
			payload.breakdowns
		),
	}, "\n")

	local reviewLines = {}
	for _, review in payload.reviews do
		table.insert(
			reviewLines,
			('%s%s\n"%s"\n'):format(
				string.rep("★", review.stars),
				string.rep("☆", 5 - review.stars),
				review.text
			)
		)
	end
	reviewsText = if #reviewLines > 0
		then table.concat(reviewLines, "\n")
		else "(no reviews today — nobody had feelings)"

	showStats()
	continueButton.Text = ("Start Day %d"):format(payload.day + 1)
	summaryPanel.Visible = true
end)

-- Phase bar text + countdown
task.spawn(function()
	while true do
		local phase = dayState:GetAttribute("Phase") :: string
		local day = dayState:GetAttribute("Day") :: number
		local endsAt = dayState:GetAttribute("PhaseEndsAt") :: number
		local text = ("Day %d · %s"):format(day, phase)
		if endsAt > 0 then
			local remaining = math.max(0, endsAt - workspace:GetServerTimeNow())
			text ..= (" — %d:%02d"):format(remaining // 60, remaining % 60 // 1)
		end
		phaseBar.Text = text
		task.wait(0.2)
	end
end)
