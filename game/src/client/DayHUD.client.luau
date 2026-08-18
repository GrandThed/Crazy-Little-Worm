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

type SummaryPayload = { day: number, arrivals: number, admissions: number, income: number }

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

-- Summary panel (hidden until the DaySummary payload arrives)
local summaryPanel = Instance.new("Frame")
summaryPanel.Name = "SummaryPanel"
summaryPanel.AnchorPoint = Vector2.new(0.5, 0.5)
summaryPanel.Position = UDim2.fromScale(0.5, 0.5)
summaryPanel.Size = UDim2.fromOffset(320, 240)
summaryPanel.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
summaryPanel.Visible = false
summaryPanel.Parent = screenGui
local summaryCorner = Instance.new("UICorner")
summaryCorner.CornerRadius = UDim.new(0, 12)
summaryCorner.Parent = summaryPanel

local summaryTitle = Instance.new("TextLabel")
summaryTitle.BackgroundTransparency = 1
summaryTitle.Position = UDim2.fromOffset(0, 16)
summaryTitle.Size = UDim2.new(1, 0, 0, 28)
summaryTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
summaryTitle.Font = Enum.Font.GothamBold
summaryTitle.TextSize = 22
summaryTitle.Text = "Day 1 Summary"
summaryTitle.Parent = summaryPanel

local summaryBody = Instance.new("TextLabel")
summaryBody.BackgroundTransparency = 1
summaryBody.Position = UDim2.fromOffset(24, 56)
summaryBody.Size = UDim2.new(1, -48, 0, 110)
summaryBody.TextColor3 = Color3.fromRGB(220, 224, 235)
summaryBody.Font = Enum.Font.Gotham
summaryBody.TextSize = 17
summaryBody.TextXAlignment = Enum.TextXAlignment.Left
summaryBody.TextYAlignment = Enum.TextYAlignment.Top
summaryBody.Text = ""
summaryBody.Parent = summaryPanel

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
	if phase ~= "Summary" then
		summaryPanel.Visible = false
	end
end

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
	summaryBody.Text = ("Admissions:  %d\nArrivals:  %d\nIncome:  $%d"):format(
		payload.admissions,
		payload.arrivals,
		payload.income
	)
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
