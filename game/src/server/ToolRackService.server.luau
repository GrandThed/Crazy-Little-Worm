--!strict
-- Tool racks (G-7, generalized in A-8). §9: handheld tools live on wall racks
-- (DOORS-style proximity grab), never in persistent inventories. A rack part
-- is tagged ToolRack with a Tool attribute naming the entry below. Each tool
-- is bought ONCE for the park (shop-with-legs: the rack IS the shop) — after
-- that anyone grabs freely. Unlocks follow §9: net day 2, salt with the cult
-- tier, clipboard with the shapeshifter tier.
--
-- Swings resolve server-side through NetTargets channels: the net catches any
-- humanoid anomaly; salt only evaporates cultists; the clipboard routes to
-- Staff.clipboardInspect (A-6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local NetTargets = require(script.Parent.anomalies.NetTargets)
local EconomyStore = require(script.Parent.EconomyStore)

local assets = ServerStorage:WaitForChild("Assets")
local dayState = ReplicatedStorage:WaitForChild("DayState")

-- Park-wide "which tools are bought" state (save-slot state later, S-1)
local shopState = Instance.new("Folder")
shopState.Name = "ToolShopState"
shopState.Parent = ReplicatedStorage

type ToolDef = {
	display: string,
	template: string,
	cost: number,
	unlockDay: number?, -- available from this day…
	unlockIndex: number?, -- …or from this AttractionIdx (§9)
	swingChannel: string?, -- NetTargets channel to swing on Activated…
	swingRange: number?,
	onActivated: ((player: Player) -> ())?, -- …or a custom handler (clipboard)
	sounds: { [string]: { id: string, pitch: number } }?, -- result tag → SFX
}

local TOOLS: { [string]: ToolDef } = {
	CaptureNet = {
		display = "Capture Net",
		template = "CaptureNet",
		cost = 500,
		unlockDay = 2,
		swingChannel = "net",
		swingRange = GameConfig.NetRange,
		sounds = {
			cured = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.2 },
		},
	},
	SaltBucket = {
		display = "Salt Bucket",
		template = "SaltBucket",
		cost = 350,
		unlockIndex = 400,
		swingChannel = "salt",
		swingRange = GameConfig.SaltRange,
	},
}

local racks: { [BasePart]: ProximityPrompt } = {}
local swingCooldowns: { [Player]: number } = {}

local function playSoundAt(parent: Instance, soundId: string, pitch: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.PlaybackSpeed = pitch
	sound.Volume = 0.6
	sound.Parent = parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

local function toolUnlocked(def: ToolDef): boolean
	if def.unlockDay and (dayState:GetAttribute("Day") :: number) >= def.unlockDay then
		return true
	end
	if def.unlockIndex and currentIndex() >= def.unlockIndex then
		return true
	end
	return def.unlockDay == nil and def.unlockIndex == nil
end

local function toolOwned(name: string): boolean
	return shopState:GetAttribute(name .. "Owned") == true
end

local function rackToolName(rack: BasePart): string
	local value = rack:GetAttribute("Tool")
	return if typeof(value) == "string" then value else "CaptureNet"
end

local function onSwing(player: Player, toolName: string)
	local def = TOOLS[toolName]
	if not def then
		return
	end
	local now = os.clock()
	if now - (swingCooldowns[player] or 0) < GameConfig.NetCooldownSeconds then
		return
	end
	swingCooldowns[player] = now

	if def.onActivated then
		(def.onActivated :: (Player) -> ())(player)
		return
	end
	if not def.swingChannel then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = Vector3.new(root.Position.X, 0, root.Position.Z)
	local result =
		NetTargets.swing(position, def.swingRange or GameConfig.NetRange, def.swingChannel)
	if result == nil then
		return
	end
	local special = def.sounds
		and (def.sounds :: { [string]: { id: string, pitch: number } })[result]
	if special then
		playSoundAt(root, special.id, special.pitch)
	else
		playSoundAt(root, "rbxasset://sounds/snap.mp3", 0.6)
	end
end

local function giveTool(player: Player, toolName: string, def: ToolDef)
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	if not backpack then
		return
	end
	if
		backpack:FindFirstChild(def.display)
		or (character and character:FindFirstChild(def.display))
	then
		return -- one of each per player
	end
	local template = assets:FindFirstChild(def.template)
	if not (template and template:IsA("Tool")) then
		warn(("[ToolRack] %s template missing from ServerStorage.Assets"):format(def.template))
		return
	end
	local tool = template:Clone()
	tool.Name = def.display
	-- JSON models can't express welds; bind every part to the handle here
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		for _, part in tool:GetChildren() do
			if part:IsA("BasePart") and part ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = handle
			end
		end
	end
	tool.Activated:Connect(function()
		onSwing(player, toolName)
	end)
	tool.Parent = backpack
	print(("[ToolRack] gave a %s to %s"):format(def.display:lower(), player.Name))
end

local function onRackTriggered(player: Player, rack: BasePart)
	local toolName = rackToolName(rack)
	local def = TOOLS[toolName]
	if not def or not toolUnlocked(def) then
		return
	end
	if not toolOwned(toolName) then
		-- §9 buy-once: the first grab pays the catalog price for the whole park
		if not EconomyStore.trySpend(def.cost) then
			print(("[ToolRack] not enough cash for the %s"):format(def.display:lower()))
			return
		end
		shopState:SetAttribute(toolName .. "Owned", true)
		print(("[ToolRack] %s bought the %s for $%d"):format(player.Name, def.display, def.cost))
	end
	giveTool(player, toolName, def)
end

-- Prompt text tracks unlock/purchase state (cheap polling; racks are few)
task.spawn(function()
	while true do
		for rack, prompt in racks do
			local toolName = rackToolName(rack)
			local def = TOOLS[toolName]
			if not def then
				prompt.Enabled = false
				prompt.ObjectText = "Tool Rack (?)"
				continue
			end
			if not toolUnlocked(def) then
				prompt.Enabled = false
				prompt.ObjectText = if def.unlockIndex
					then ("%s — unlocks at index %d"):format(def.display, def.unlockIndex)
					else ("%s — unlocks day %d"):format(def.display, def.unlockDay or 1)
			else
				prompt.Enabled = true
				prompt.ObjectText = "Tool Rack"
				prompt.ActionText = if toolOwned(toolName)
					then ("Take %s"):format(def.display)
					else ("Buy %s ($%d)"):format(def.display, def.cost)
			end
		end
		task.wait(1)
	end
end)

Component.bind("ToolRack", {
	onAttached = function(instance)
		if not instance:IsA("BasePart") then
			return nil
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TakeToolPrompt"
		prompt.ActionText = "Take Tool"
		prompt.ObjectText = "Tool Rack"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = instance
		prompt.Triggered:Connect(function(player)
			onRackTriggered(player, instance)
		end)
		racks[instance] = prompt
		return prompt
	end,
	onDetached = function(instance, prompt: ProximityPrompt?)
		racks[instance :: BasePart] = nil
		if prompt then
			prompt:Destroy()
		end
	end,
})
