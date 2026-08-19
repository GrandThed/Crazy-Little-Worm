--!strict
-- Anomaly-building components (§9): Security Camera (A-3), Infirmary and
-- Queue Busker (A-8). Same data-driven rule as rides: behavior binds to
-- tagged models with attributes; PlotService drops them onto pads. This
-- module never requires Guests (Guests queries the busker aura — keep the
-- dependency one-way).

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

-- ============================== infirmary (A-8) ==============================

local infirmaries: { [Model]: boolean } = {}

Component.bind("Infirmary", {
	onAttached = function(instance)
		if instance:IsA("Model") then
			infirmaries[instance] = true
			print(("[Buildings] infirmary open: %s"):format(instance.Name))
		end
	end,
	onDetached = function(instance)
		infirmaries[instance :: Model] = nil
	end,
})

function Buildings.hasInfirmary(): boolean
	return next(infirmaries) ~= nil
end

-- Nearest infirmary door spot for an escorted guest to walk to
function Buildings.nearestInfirmary(position: Vector3): (Model?, Vector3?)
	local best: Model? = nil
	local bestSpot: Vector3? = nil
	local bestDistance = math.huge
	for infirmary in infirmaries do
		local spot = modelGroundPosition(infirmary) + Vector3.new(0, 0, 4)
		local distance = (spot - position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = infirmary
			bestSpot = spot
		end
	end
	return best, bestSpot
end

-- ============================== queue busker (A-8) ==============================

local buskers: { [Model]: boolean } = {}

Component.bind("QueueBusker", {
	onAttached = function(instance): BillboardGui?
		if not instance:IsA("Model") then
			return nil
		end
		buskers[instance] = true
		print(("[Buildings] busker performing: %s"):format(instance.Name))
		local base = instance:FindFirstChildWhichIsA("BasePart")
		if not base then
			return nil
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(40, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Text = "🎵"
		label.Parent = billboard
		billboard.Parent = base
		return billboard
	end,
	onDetached = function(instance, billboard: BillboardGui?)
		buskers[instance :: Model] = nil
		if billboard then
			billboard:Destroy()
		end
	end,
})

-- §9: patience decay ×0.5 for queues inside a busker's radius
function Buildings.buskerCovers(position: Vector3): boolean
	for busker in buskers do
		local radius = attributeNumber(busker, "Radius", GameConfig.BuskerDefaultRadius)
		if (modelGroundPosition(busker) - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

return Buildings
