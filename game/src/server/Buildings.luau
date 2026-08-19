--!strict
-- Anomaly-building components (§9): Security Camera (A-3), extended by A-8
-- with Infirmary and Queue Busker. Same data-driven rule as rides: behavior
-- binds to tagged models with attributes; PlotService drops them onto pads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Buildings = {}

local function attributeNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function modelGroundPosition(model: Model): Vector3
	local pivot = model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

-- ============================== security cameras (A-3) ==============================

local cameras: { [Model]: boolean } = {}

Component.bind("SecurityCamera", {
	onAttached = function(instance)
		if instance:IsA("Model") then
			cameras[instance] = true
			print(("[Buildings] camera online: %s"):format(instance.Name))
		end
	end,
	onDetached = function(instance)
		cameras[instance :: Model] = nil
	end,
})

-- First camera whose radius covers the position, or nil
function Buildings.cameraCovering(position: Vector3): Model?
	for camera in cameras do
		local radius = attributeNumber(camera, "Radius", GameConfig.CameraDefaultRadius)
		if (modelGroundPosition(camera) - position).Magnitude <= radius then
			return camera
		end
	end
	return nil
end

-- §4/§9 alert ping: red "!" flash + chirp at the camera
function Buildings.cameraAlert(camera: Model)
	local base = camera:FindFirstChildWhichIsA("BasePart")
	if not base then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(50, 50)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 60, 50)
	label.Font = Enum.Font.GothamBlack
	label.Text = "❗"
	label.Parent = billboard
	billboard.Parent = base
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.PlaybackSpeed = 0.7
	sound.Volume = 0.8
	sound.Parent = base
	sound:Play()
	task.delay(3, function()
		billboard:Destroy()
		sound:Destroy()
	end)
end

return Buildings
