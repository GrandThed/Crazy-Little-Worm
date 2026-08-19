--!strict
-- Debug panel (F-5), client side. Studio-only: never constructed in production,
-- and every command it sends is re-gated server-side in DebugService.
-- Debuggability rule: new features add a button/readout here + a command there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local dayState = ReplicatedStorage:WaitForChild("DayState")
local debugState = ReplicatedStorage:WaitForChild("DebugState")
local economyState = ReplicatedStorage:WaitForChild("EconomyState")
local indexState = ReplicatedStorage:WaitForChild("IndexState")
local debugCommand =
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DebugCommand") :: RemoteEvent

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DebugPanel"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -8, 0.5, 0)
panel.Size = UDim2.fromOffset(170, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BackgroundTransparency = 0.15
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function makeLabel(text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = nextOrder()
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextColor3 = Color3.fromRGB(200, 205, 220)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = panel
	return label
end

local function makeButton(text: string, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = nextOrder()
	button.Size = UDim2.new(1, 0, 0, 28)
	button.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
	button.TextColor3 = Color3.fromRGB(235, 238, 248)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 14
	button.Text = text
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	button.Activated:Connect(onClick)
	return button
end

local title = makeLabel("⚙ DEBUG (Studio)")
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(255, 200, 80)

local statsLabel = makeLabel("…")

-- A-1: today's rolled anomaly plan (server truth, Studio mirror only)
local planLabel = makeLabel("plan …")
planLabel.TextWrapped = true
planLabel.TextColor3 = Color3.fromRGB(235, 160, 120)

makeButton("Skip phase ⏭", function()
	debugCommand:FireServer("AdvancePhase")
end)

for _, speed in { 1, 5, 20 } do
	makeButton(("Day speed ×%d"):format(speed), function()
		debugCommand:FireServer("SetDaySpeed", speed)
	end)
end

makeButton("Spawn guest +1", function()
	debugCommand:FireServer("SpawnGuest")
end)

makeButton("Drain park", function()
	debugCommand:FireServer("DrainPark")
end)

makeButton("Approve front ✅", function()
	debugCommand:FireServer("ApproveFront")
end)

makeButton("Deny front ⛔", function()
	debugCommand:FireServer("DenyFront")
end)

makeButton("Sap patience 😠", function()
	debugCommand:FireServer("SapPatience")
end)

makeButton("Give $500", function()
	debugCommand:FireServer("GiveCash", 500)
end)

-- Cycles 0 → +200 → +400 → +600 → 0: reach idx-gated unlocks in one sitting
makeButton("Index boost cycle 📈", function()
	local current = workspace:GetAttribute("DebugIndexBoost")
	local boost = if typeof(current) == "number" then current else 0
	boost += 200
	if boost > 600 then
		boost = 0
	end
	debugCommand:FireServer("BoostIndex", boost)
end)

makeButton("Spawn infected 🧟", function()
	debugCommand:FireServer("SpawnInfected")
end)

makeButton("Spawn spy 🕵️", function()
	debugCommand:FireServer("SpawnSpy")
end)

makeButton("Spawn aliens 👽", function()
	debugCommand:FireServer("SpawnAlien")
end)

makeButton("Spawn cultists 🕯", function()
	debugCommand:FireServer("SpawnCultists")
end)

makeButton("Spawn shapeshifter 🎭", function()
	debugCommand:FireServer("SpawnShapeshifter")
end)

makeButton("Force rule day 📜", function()
	debugCommand:FireServer("ForceRuleDay")
end)

task.spawn(function()
	while true do
		local lines = {
			("day     %s"):format(tostring(dayState:GetAttribute("Day"))),
			("phase   %s"):format(tostring(dayState:GetAttribute("Phase"))),
			("speed   ×%s"):format(tostring(debugState:GetAttribute("DaySpeed") or 1)),
			("guests  %s"):format(tostring(debugState:GetAttribute("GuestsOnMap") or 0)),
			("queue+  %s"):format(tostring(debugState:GetAttribute("Overflow") or 0)),
			("arrived %s"):format(tostring(debugState:GetAttribute("Arrivals") or 0)),
			("walkout %s"):format(tostring(debugState:GetAttribute("Walkaways") or 0)),
			("zombies %s"):format(tostring(debugState:GetAttribute("Zombies") or 0)),
			("netted  %s"):format(tostring(debugState:GetAttribute("Captured") or 0)),
			("admits  %s"):format(tostring(debugState:GetAttribute("Admissions") or 0)),
			("income  $%s"):format(tostring(debugState:GetAttribute("Income") or 0)),
			("cash    $%s"):format(tostring(economyState:GetAttribute("Cash") or 0)),
			("index   %d"):format(tonumber(indexState:GetAttribute("Index")) or 0),
			("satisf  %.2f"):format(tonumber(indexState:GetAttribute("Satisfaction")) or 0),
		}
		statsLabel.Text = table.concat(lines, "\n")
		planLabel.Text = ("plan    %s"):format(
			tostring(debugState:GetAttribute("AnomalyPlan") or "…")
		)
		task.wait(0.25)
	end
end)
