--!strict
-- Cash HUD v0 (G-8): renders the replicated park cash pool, flashes green on
-- income. Pure rendering — the server owns the number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local economyState = ReplicatedStorage:WaitForChild("EconomyState")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CashHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local cashLabel = Instance.new("TextLabel")
cashLabel.Name = "Cash"
cashLabel.Position = UDim2.fromOffset(12, 12)
cashLabel.Size = UDim2.fromOffset(140, 36)
cashLabel.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
cashLabel.BackgroundTransparency = 0.25
cashLabel.TextColor3 = Color3.fromRGB(140, 220, 140)
cashLabel.Font = Enum.Font.GothamBold
cashLabel.TextSize = 20
cashLabel.Parent = screenGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = cashLabel

local flashTween: Tween? = nil

local function render()
	cashLabel.Text = ("$ %d"):format(economyState:GetAttribute("Cash") :: number)
end

economyState:GetAttributeChangedSignal("Cash"):Connect(function()
	render()
	cashLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	if flashTween then
		flashTween:Cancel()
	end
	flashTween = TweenService:Create(
		cashLabel,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = Color3.fromRGB(140, 220, 140) }
	);
	(flashTween :: Tween):Play()
end)
render()
