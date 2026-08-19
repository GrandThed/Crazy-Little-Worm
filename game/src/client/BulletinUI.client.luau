--!strict
-- Daily bulletin panel (A-2). Newspaper-style Prep read, pure rendering from
-- BulletinState attributes (server composes the text). Auto-opens when a new
-- day's edition lands during Prep; a 📰 button reopens it. Placeholder
-- styling — final art later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local bulletinState = ReplicatedStorage:WaitForChild("BulletinState")
local dayState = ReplicatedStorage:WaitForChild("DayState")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BulletinUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local reopenButton = Instance.new("TextButton")
reopenButton.Position = UDim2.fromOffset(292, 60)
reopenButton.Size = UDim2.fromOffset(120, 36)
reopenButton.BackgroundColor3 = Color3.fromRGB(175, 148, 96)
reopenButton.TextColor3 = Color3.fromRGB(255, 255, 255)
reopenButton.Font = Enum.Font.GothamBold
reopenButton.TextSize = 16
reopenButton.Text = "📰 Bulletin"
reopenButton.Parent = screenGui
local reopenCorner = Instance.new("UICorner")
reopenCorner.CornerRadius = UDim.new(0, 8)
reopenCorner.Parent = reopenButton

local paper = Instance.new("Frame")
paper.Name = "Paper"
paper.AnchorPoint = Vector2.new(0.5, 0.5)
paper.Position = UDim2.fromScale(0.5, 0.46)
paper.Size = UDim2.fromOffset(380, 330)
paper.BackgroundColor3 = Color3.fromRGB(238, 230, 210)
paper.Visible = false
paper.Parent = screenGui
local paperCorner = Instance.new("UICorner")
paperCorner.CornerRadius = UDim.new(0, 6)
paperCorner.Parent = paper

local masthead = Instance.new("TextLabel")
masthead.BackgroundTransparency = 1
masthead.Position = UDim2.fromOffset(0, 14)
masthead.Size = UDim2.new(1, 0, 0, 34)
masthead.TextColor3 = Color3.fromRGB(40, 34, 28)
masthead.Font = Enum.Font.Antique
masthead.TextSize = 32
masthead.Text = "THE WORM DAILY"
masthead.Parent = paper

local dateline = Instance.new("TextLabel")
dateline.BackgroundTransparency = 1
dateline.Position = UDim2.fromOffset(0, 50)
dateline.Size = UDim2.new(1, 0, 0, 18)
dateline.TextColor3 = Color3.fromRGB(110, 98, 82)
dateline.Font = Enum.Font.Code
dateline.TextSize = 13
dateline.Text = "— Day 1 —"
dateline.Parent = paper

local divider = Instance.new("Frame")
divider.Position = UDim2.new(0, 24, 0, 74)
divider.Size = UDim2.new(1, -48, 0, 2)
divider.BackgroundColor3 = Color3.fromRGB(110, 98, 82)
divider.BorderSizePixel = 0
divider.Parent = paper

local bodyText = Instance.new("TextLabel")
bodyText.BackgroundTransparency = 1
bodyText.Position = UDim2.fromOffset(24, 86)
bodyText.Size = UDim2.new(1, -48, 1, -140)
bodyText.TextColor3 = Color3.fromRGB(50, 44, 36)
bodyText.Font = Enum.Font.Gotham
bodyText.TextSize = 14
bodyText.TextXAlignment = Enum.TextXAlignment.Left
bodyText.TextYAlignment = Enum.TextYAlignment.Top
bodyText.TextWrapped = true
bodyText.Text = ""
bodyText.Parent = paper

local dismissButton = Instance.new("TextButton")
dismissButton.AnchorPoint = Vector2.new(0.5, 1)
dismissButton.Position = UDim2.new(0.5, 0, 1, -14)
dismissButton.Size = UDim2.fromOffset(160, 36)
dismissButton.BackgroundColor3 = Color3.fromRGB(90, 78, 58)
dismissButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dismissButton.Font = Enum.Font.GothamBold
dismissButton.TextSize = 15
dismissButton.Text = "Got it"
dismissButton.Parent = paper
local dismissCorner = Instance.new("UICorner")
dismissCorner.CornerRadius = UDim.new(0, 8)
dismissCorner.Parent = dismissButton

local function render()
	local day = bulletinState:GetAttribute("Day") :: number
	dateline.Text = ("— Day %d —"):format(day)
	bodyText.Text = bulletinState:GetAttribute("Text") :: string
end

local function refreshVisibility()
	local isPrep = dayState:GetAttribute("Phase") == "Prep"
	reopenButton.Visible = isPrep
	if not isPrep then
		paper.Visible = false
	end
end

-- A new edition auto-opens during Prep (each morning); reopen at will
bulletinState:GetAttributeChangedSignal("Text"):Connect(function()
	render()
	if dayState:GetAttribute("Phase") == "Prep" then
		paper.Visible = true
	end
end)

dayState:GetAttributeChangedSignal("Phase"):Connect(refreshVisibility)

reopenButton.Activated:Connect(function()
	render()
	paper.Visible = not paper.Visible
end)

dismissButton.Activated:Connect(function()
	paper.Visible = false
end)

refreshVisibility()
if (bulletinState:GetAttribute("Text") :: string) ~= "" then
	render()
	if dayState:GetAttribute("Phase") == "Prep" then
		paper.Visible = true
	end
end
