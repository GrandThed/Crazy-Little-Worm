--!strict
-- Tool rack + capture net (G-7). Racks are tagged ToolRack with a Tool
-- attribute naming the template in ServerStorage.Assets; a proximity prompt
-- hands the tool out. The net swing is resolved server-side: Tool.Activated
-- → nearest zombie/tagged guest within NetRange of the swinger.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local NetTargets = require(script.Parent.anomalies.NetTargets)

local assets = ServerStorage:WaitForChild("Assets")

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

local function onSwing(player: Player)
	local now = os.clock()
	if now - (swingCooldowns[player] or 0) < GameConfig.NetCooldownSeconds then
		return
	end
	swingCooldowns[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = Vector3.new(root.Position.X, 0, root.Position.Z)
	-- Generic catch (§9): nearest target across every registered anomaly
	local result = NetTargets.swing(position, GameConfig.NetRange)
	if result == "cured" then
		playSoundAt(root, "rbxasset://sounds/electronicpingshort.wav", 1.2)
	elseif result ~= nil then
		playSoundAt(root, "rbxasset://sounds/snap.mp3", 0.6)
	end
end

local function giveNet(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	if not backpack then
		return
	end
	if
		backpack:FindFirstChild("Capture Net")
		or (character and character:FindFirstChild("Capture Net"))
	then
		return -- one net each
	end
	local template = assets:FindFirstChild("CaptureNet")
	if not (template and template:IsA("Tool")) then
		warn("[ToolRack] CaptureNet template missing from ServerStorage.Assets")
		return
	end
	local tool = template:Clone()
	tool.Name = "Capture Net"
	-- JSON models can't express welds; bind the head to the handle here
	local handle = tool:FindFirstChild("Handle")
	local head = tool:FindFirstChild("NetHead")
	if handle and handle:IsA("BasePart") and head and head:IsA("BasePart") then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = head
		weld.Parent = handle
	end
	tool.Activated:Connect(function()
		onSwing(player)
	end)
	tool.Parent = backpack
	print(("[ToolRack] gave a capture net to %s"):format(player.Name))
end

Component.bind("ToolRack", {
	onAttached = function(instance)
		if not instance:IsA("BasePart") then
			return nil
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TakeToolPrompt"
		prompt.ActionText = "Take Capture Net"
		prompt.ObjectText = "Tool Rack"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = instance
		prompt.Triggered:Connect(giveNet)
		return prompt
	end,
	onDetached = function(_instance, prompt: ProximityPrompt?)
		if prompt then
			prompt:Destroy()
		end
	end,
})
