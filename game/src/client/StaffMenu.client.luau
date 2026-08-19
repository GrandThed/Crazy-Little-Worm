--!strict
-- Staff hire menu (P-6/P-7). Prep-only panel: hire clerks (tiered) and
-- mechanics. No hire fee — wages are the cost, settled at Summary (§9).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local dayState = ReplicatedStorage:WaitForChild("DayState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hireRemote = remotes:WaitForChild("HireStaff") :: RemoteEvent
local hireAckRemote = remotes:WaitForChild("HireAck") :: RemoteEvent

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StaffMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Position = UDim2.fromOffset(160, 60)
toggleButton.Size = UDim2.fromOffset(120, 36)
toggleButton.BackgroundColor3 = Color3.fromRGB(140, 96, 175)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 16
toggleButton.Text = "Staff (Prep)"
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(160, 102)
panel.Size = UDim2.fromOffset(220, 210)
panel.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 22)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(200, 205, 220)
status.Font = Enum.Font.Gotham
status.TextSize = 13
status.Text = "wages paid at Summary"
status.LayoutOrder = 99
status.Parent = panel

-- A-6: know your staff by NAME — the shapeshifter forges these on tickets
local staffState = ReplicatedStorage:WaitForChild("StaffState")
local rosterLabel = Instance.new("TextLabel")
rosterLabel.Size = UDim2.fromScale(1, 0)
rosterLabel.AutomaticSize = Enum.AutomaticSize.Y
rosterLabel.BackgroundTransparency = 1
rosterLabel.TextColor3 = Color3.fromRGB(170, 180, 210)
rosterLabel.Font = Enum.Font.Code
rosterLabel.TextSize = 12
rosterLabel.TextXAlignment = Enum.TextXAlignment.Left
rosterLabel.TextWrapped = true
rosterLabel.Text = ""
rosterLabel.LayoutOrder = 100
rosterLabel.Parent = panel

local function refreshRoster()
	local roster = staffState:GetAttribute("Roster") :: string
	rosterLabel.Text = if roster == "" then "(no staff yet)" else roster
end
staffState:GetAttributeChangedSignal("Roster"):Connect(refreshRoster)
refreshRoster()

local function hireButton(text: string, kind: string, tier: number, order: number)
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 30)
	button.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
	button.TextColor3 = Color3.fromRGB(235, 238, 248)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 13
	button.Text = text
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	button.Activated:Connect(function()
		hireRemote:FireServer(kind, tier)
	end)
end

hireButton("Hire Clerk T1 — $100/day", "Clerk", 1, 1)
hireButton("Hire Clerk T2 — $150/day", "Clerk", 2, 2)
hireButton("Hire Clerk T3 — $220/day", "Clerk", 3, 3)
hireButton("Hire Mechanic — $120/day", "Mechanic", 1, 4)

hireAckRemote.OnClientEvent:Connect(
	function(ack: { accepted: boolean, reason: string?, count: number })
		status.Text = if ack.accepted
			then ("hired! staff: %d"):format(ack.count)
			else (ack.reason or "rejected")
	end
)

toggleButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

dayState:GetAttributeChangedSignal("Phase"):Connect(function()
	local isPrep = dayState:GetAttribute("Phase") == "Prep"
	toggleButton.Visible = isPrep
	if not isPrep then
		panel.Visible = false
	end
end)
toggleButton.Visible = dayState:GetAttribute("Phase") == "Prep"
