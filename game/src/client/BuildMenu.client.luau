--!strict
-- Build menu (P-2). Prep-phase panel: pick a catalog item, pick a free plot,
-- server validates and builds. Occupancy/locks render from replicated truth
-- (plot attributes + IndexState); the request uses the optimistic-ack pattern.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buildRemote = remotes:WaitForChild("Build") :: RemoteEvent
local buildAckRemote = remotes:WaitForChild("BuildAck") :: RemoteEvent
local buyUpgradeRemote = remotes:WaitForChild("BuyUpgrade") :: RemoteEvent
local upgradeAckRemote = remotes:WaitForChild("UpgradeAck") :: RemoteEvent

-- §9 gate upgrades (A-8): server auto-picks the first eligible stand/bathroom
local UPGRADES: { { kind: string, label: string } } = {
	{ kind = "Scanner", label = "Ticket Scanner" },
	{ kind = "Arch", label = "Heartbeat Arch" },
	{ kind = "BathroomLock", label = "Bathroom Lock" },
}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuildMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Position = UDim2.fromOffset(12, 60)
toggleButton.Size = UDim2.fromOffset(140, 36)
toggleButton.BackgroundColor3 = Color3.fromRGB(76, 132, 175)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 16
toggleButton.Text = "Build (Prep)"
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(12, 102)
panel.Size = UDim2.fromOffset(300, 340)
panel.BackgroundColor3 = Color3.fromRGB(35, 38, 52)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local itemList = Instance.new("ScrollingFrame")
itemList.Position = UDim2.fromOffset(8, 8)
itemList.Size = UDim2.new(0.5, -12, 1, -16)
itemList.BackgroundTransparency = 1
itemList.ScrollBarThickness = 4
itemList.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemList.CanvasSize = UDim2.new()
itemList.Parent = panel
local itemLayout = Instance.new("UIListLayout")
itemLayout.Padding = UDim.new(0, 4)
itemLayout.Parent = itemList

local plotList = Instance.new("Frame")
plotList.Position = UDim2.new(0.5, 4, 0, 8)
plotList.Size = UDim2.new(0.5, -12, 1, -16)
plotList.BackgroundTransparency = 1
plotList.Parent = panel
local plotLayout = Instance.new("UIListLayout")
plotLayout.Padding = UDim.new(0, 4)
plotLayout.Parent = plotList

local selectedEntry: Catalog.Entry? = nil
local selectedUpgrade: string? = nil
local pendingRequests: { [string]: boolean } = {}

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

local function makeRowButton(parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 34)
	button.BackgroundColor3 = Color3.fromRGB(58, 64, 88)
	button.TextColor3 = Color3.fromRGB(235, 238, 248)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 13
	button.TextWrapped = true
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

local refreshPlots -- forward

local function refreshItems()
	for _, child in itemList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local index = currentIndex()
	for _, entry in Catalog.entries do
		local locked = index < entry.unlockIndex
		local label = ("%s\n$%d"):format(entry.name, entry.cost)
		if locked then
			label = ("%s\n🔒 idx %d"):format(entry.name, entry.unlockIndex)
		end
		local button = makeRowButton(itemList, label)
		if locked then
			button.BackgroundColor3 = Color3.fromRGB(44, 47, 60)
			button.TextColor3 = Color3.fromRGB(140, 145, 160)
		elseif selectedEntry and (selectedEntry :: Catalog.Entry).id == entry.id then
			button.BackgroundColor3 = Color3.fromRGB(76, 132, 175)
		end
		button.Activated:Connect(function()
			if not locked then
				selectedEntry = entry
				selectedUpgrade = nil
				refreshItems()
				refreshPlots()
			end
		end)
	end

	-- Gate upgrades (A-8) below the plot buildables
	for _, upgrade in UPGRADES do
		local cost = GameConfig.UpgradeCosts[upgrade.kind]
		local unlockIndex = GameConfig.UpgradeUnlockIndex[upgrade.kind]
		local locked = index < unlockIndex
		local label = if locked
			then ("%s\n🔒 idx %d"):format(upgrade.label, unlockIndex)
			else ("%s\n$%d"):format(upgrade.label, cost)
		local button = makeRowButton(itemList, label)
		if locked then
			button.BackgroundColor3 = Color3.fromRGB(44, 47, 60)
			button.TextColor3 = Color3.fromRGB(140, 145, 160)
		elseif selectedUpgrade == upgrade.kind then
			button.BackgroundColor3 = Color3.fromRGB(76, 132, 175)
		end
		button.Activated:Connect(function()
			if not locked then
				selectedUpgrade = upgrade.kind
				selectedEntry = nil
				refreshItems()
				refreshPlots()
			end
		end)
	end
end

function refreshPlots()
	for _, child in plotList:GetChildren() do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local upgradeKind = selectedUpgrade
	if upgradeKind then
		-- server auto-picks the first stand/bathroom without this upgrade
		local button = makeRowButton(
			plotList,
			("Install (auto-picks target)\n$%d"):format(GameConfig.UpgradeCosts[upgradeKind])
		)
		button.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
		button.Activated:Connect(function()
			local requestId = HttpService:GenerateGUID(false)
			pendingRequests[requestId] = true
			buyUpgradeRemote:FireServer({ requestId = requestId, kind = upgradeKind })
			button.Text = "…"
		end)
		return
	end
	local entry = selectedEntry
	if not entry then
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, 0, 0, 60)
		hint.BackgroundTransparency = 1
		hint.TextColor3 = Color3.fromRGB(170, 175, 190)
		hint.Font = Enum.Font.Gotham
		hint.TextSize = 13
		hint.TextWrapped = true
		hint.Text = "← pick something to build"
		hint.Parent = plotList
		return
	end
	for _, plotPart in CollectionService:GetTagged("Plot") do
		if not plotPart:IsA("BasePart") then
			continue
		end
		if not Catalog.plotAccepts(plotPart:GetAttribute("PlotKind"), entry) then
			continue
		end
		if plotPart:GetAttribute("OccupiedBy") ~= nil then
			continue
		end
		local plotId = tostring(plotPart:GetAttribute("PlotId"))
		local button = makeRowButton(plotList, ("Build on plot %s"):format(plotId))
		button.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
		button.Activated:Connect(function()
			local requestId = HttpService:GenerateGUID(false)
			pendingRequests[requestId] = true
			buildRemote:FireServer({
				requestId = requestId,
				plotPart = plotPart,
				catalogId = entry.id,
			})
			button.Text = "…"
		end)
	end
end

local function onAck(ack: { requestId: string, accepted: boolean, reason: string? })
	if not pendingRequests[ack.requestId] then
		return
	end
	pendingRequests[ack.requestId] = nil
	if not ack.accepted then
		toggleButton.Text = ack.reason or "rejected"
		task.delay(1.2, function()
			toggleButton.Text = "Build (Prep)"
		end)
	end
	refreshItems()
	refreshPlots()
end

buildAckRemote.OnClientEvent:Connect(onAck)
upgradeAckRemote.OnClientEvent:Connect(onAck)

toggleButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		refreshItems()
		refreshPlots()
	end
end)

-- Only meaningful during Prep (§5); hide the panel when the day starts
dayState:GetAttributeChangedSignal("Phase"):Connect(function()
	local isPrep = dayState:GetAttribute("Phase") == "Prep"
	toggleButton.Visible = isPrep
	if not isPrep then
		panel.Visible = false
	end
end)
toggleButton.Visible = dayState:GetAttribute("Phase") == "Prep"
