--!strict
-- Gate-infrastructure upgrades (A-8), per §9: Ticket Scanner and Heartbeat
-- Arch install per stand, Bathroom Lock per bathroom. These aren't plot
-- builds — the server auto-picks the first eligible target, sets the
-- attribute the behavior code reads, and drops a grey-box visual part.
-- Same Prep-only + funds + unlock-index validation as PlotService.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EconomyStore = require(script.Parent.EconomyStore)

local dayState = ReplicatedStorage:WaitForChild("DayState")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyUpgradeRemote = Instance.new("RemoteEvent")
buyUpgradeRemote.Name = "BuyUpgrade"
buyUpgradeRemote.Parent = remotes
local upgradeAckRemote = Instance.new("RemoteEvent")
upgradeAckRemote.Name = "UpgradeAck"
upgradeAckRemote.Parent = remotes

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

local function greyBoxPart(name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = cframe
	return part
end

-- Each upgrade: find the first eligible target, apply attribute + visual.
-- Returns applied target name, or nil + reason.
local APPLIERS: { [string]: () -> (string?, string?) } = {
	Scanner = function()
		for _, stand in CollectionService:GetTagged("EntryStand") do
			if stand:IsA("BasePart") and stand:GetAttribute("HasScanner") ~= true then
				stand:SetAttribute("HasScanner", true)
				local box = greyBoxPart(
					"ScannerBox",
					Vector3.new(1, 0.8, 1),
					Color3.fromRGB(60, 180, 170),
					stand.CFrame * CFrame.new(stand.Size.X / 2 - 0.6, stand.Size.Y / 2 + 0.4, 0)
				)
				box.Parent = stand
				return stand.Name, nil
			end
		end
		return nil, "every stand has a scanner"
	end,
	Arch = function()
		for _, stand in CollectionService:GetTagged("EntryStand") do
			if stand:IsA("BasePart") and stand:GetAttribute("HasArch") ~= true then
				stand:SetAttribute("HasArch", true)
				-- crossbar over the counter spot; grey-box for the arch model
				local spot = stand.Position + stand.CFrame.LookVector * 2
				local arch = greyBoxPart(
					"HeartbeatArch",
					Vector3.new(4, 0.5, 0.5),
					Color3.fromRGB(200, 70, 100),
					CFrame.new(Vector3.new(spot.X, 4.4, spot.Z))
				)
				arch.Parent = stand
				return stand.Name, nil
			end
		end
		return nil, "every stand has an arch"
	end,
	BathroomLock = function()
		for _, model in CollectionService:GetTagged("Facility") do
			if
				model:IsA("Model")
				and model:GetAttribute("RefillNeed") == "Bladder"
				and model:GetAttribute("Locked") ~= true
			then
				model:SetAttribute("Locked", true)
				local pivot = model:GetPivot().Position
				local padlock = greyBoxPart(
					"Padlock",
					Vector3.new(0.6, 0.8, 0.3),
					Color3.fromRGB(220, 180, 60),
					CFrame.new(Vector3.new(pivot.X, 2, pivot.Z + 2.2))
				)
				padlock.Parent = model
				return model.Name, nil
			end
		end
		return nil, "every bathroom is locked"
	end,
}

buyUpgradeRemote.OnServerEvent:Connect(function(player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local requestId = data.requestId
	local kind = data.kind
	if typeof(requestId) ~= "string" or typeof(kind) ~= "string" then
		return
	end

	local function ack(accepted: boolean, reason: string?)
		upgradeAckRemote:FireClient(player, {
			requestId = requestId,
			accepted = accepted,
			reason = reason,
		})
	end

	local applier = APPLIERS[kind]
	local cost = GameConfig.UpgradeCosts[kind]
	local unlockIndex = GameConfig.UpgradeUnlockIndex[kind]
	if not (applier and cost and unlockIndex) then
		return ack(false, "unknown upgrade")
	end
	if dayState:GetAttribute("Phase") ~= "Prep" then
		return ack(false, "install during Prep")
	end
	if currentIndex() < unlockIndex then
		return ack(false, ("unlocks at index %d"):format(unlockIndex))
	end
	if not EconomyStore.trySpend(cost) then
		return ack(false, "not enough cash")
	end

	local target, reason = applier()
	if not target then
		EconomyStore.add(cost) -- refund: nothing eligible
		return ack(false, reason)
	end
	print(("[Upgrade] %s installed %s on %s ($%d)"):format(player.Name, kind, target, cost))
	ack(true)
end)
