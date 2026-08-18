--!strict
-- Guest stream generator (G-1). Spawns guests at the day-1 arrival rate
-- (§2 inflow formula) and walks them into the shortest visible stand queue.
-- Guests are lightweight server agents (§1): anchored grey-box rigs moved by
-- PivotTo gliding, no Humanoid physics. Beyond the visible front of each
-- queue, arrivals become an abstract counter, not characters.
-- Stand processing (approve/deny) is G-2; patience/walkaway is G-4.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GuestIdentity = require(ReplicatedStorage.Shared.GuestIdentity)

local rigTemplate = ServerStorage:WaitForChild("Assets"):WaitForChild("GuestRig") :: Model

local CURRENT_DAY = 1 -- placeholder until DayCycle lands (G-5)

type Guest = {
	model: Model,
	identity: GuestIdentity.Identity,
	pivotHeight: number,
	target: Vector3?, -- nil = settled in place
	facing: Vector3, -- direction to face once settled
}

type Stand = {
	part: BasePart,
	queue: { Guest },
	capacity: number,
}

local stands: { [Instance]: Stand } = {}
local guests: { Guest } = {}
local overflowCount = 0

local function getPart(model: Model, name: string): BasePart
	local child = model:FindFirstChild(name)
	assert(child and child:IsA("BasePart"), ("GuestRig is missing part %q"):format(name))
	return child
end

-- Queue extends along the stand's LookVector, slot 1 nearest the counter
local function queueSlot(stand: Stand, index: number): Vector3
	local cf = stand.part.CFrame
	local distance = GameConfig.QueueStartOffset + (index - 1) * GameConfig.QueueSpacing
	local slot = cf.Position + cf.LookVector * distance
	return Vector3.new(slot.X, 0, slot.Z)
end

local function spawnPosition(): Vector3
	local marker = CollectionService:GetTagged("GuestSpawn")[1]
	if marker and marker:IsA("BasePart") then
		return Vector3.new(marker.Position.X, 0, marker.Position.Z)
	end
	return Vector3.zero
end

local function pickShortestQueue(): Stand?
	local best: Stand? = nil
	for _, stand in stands do
		if #stand.queue < stand.capacity and (not best or #stand.queue < #best.queue) then
			best = stand
		end
	end
	return best
end

local function spawnGuest()
	if next(stands) == nil then
		return
	end

	local stand = pickShortestQueue()
	if not stand then
		-- §1: arrivals beyond the visible queue front are counters, not characters
		overflowCount += 1
		print(
			("[GuestSpawner] visible queues full — %d arrivals waiting abstractly"):format(
				overflowCount
			)
		)
		return
	end

	local identity = GuestIdentity.generate(CURRENT_DAY)
	local appearance = identity.appearance

	local model = rigTemplate:Clone()
	model.Name = identity.name
	getPart(model, "Body").Color = appearance.bodyColor
	getPart(model, "Head").Color = appearance.headColor
	getPart(model, "LeftArm").Color = appearance.headColor
	getPart(model, "RightArm").Color = appearance.headColor
	model:ScaleTo(appearance.scale)

	local guest: Guest = {
		model = model,
		identity = identity,
		pivotHeight = GameConfig.GuestPivotHeight * appearance.scale,
		target = nil,
		facing = -stand.part.CFrame.LookVector,
	}
	table.insert(stand.queue, guest)
	guest.target = queueSlot(stand, #stand.queue)

	local origin = spawnPosition() + Vector3.new(0, guest.pivotHeight, 0)
	model:PivotTo(CFrame.new(origin))
	model.Parent = workspace
	table.insert(guests, guest)
end

Component.bind("EntryStand", {
	onAttached = function(instance)
		if not instance:IsA("BasePart") then
			warn("[GuestSpawner] EntryStand tag on non-part instance: " .. instance:GetFullName())
			return
		end
		local capacityAttribute = instance:GetAttribute("QueueCapacity")
		local capacity = if typeof(capacityAttribute) == "number"
			then capacityAttribute
			else GameConfig.DefaultQueueCapacity
		stands[instance] = {
			part = instance,
			queue = {},
			capacity = math.min(capacity, GameConfig.VisibleQueuePerStand),
		}
		print(("[GuestSpawner] stand registered: %s"):format(instance:GetFullName()))
	end,
	onDetached = function(instance)
		local stand = stands[instance]
		if not stand then
			return
		end
		stands[instance] = nil
		for _, guest in stand.queue do
			local index = table.find(guests, guest)
			if index then
				table.remove(guests, index)
			end
			guest.model:Destroy()
		end
	end,
})

-- Glide guests toward their targets; settle facing the stand on arrival
RunService.Heartbeat:Connect(function(deltaTime)
	for _, guest in guests do
		local target = guest.target
		if not target then
			continue
		end
		local lift = Vector3.new(0, guest.pivotHeight, 0)
		local pivot = guest.model:GetPivot().Position
		local flat = Vector3.new(pivot.X, 0, pivot.Z)
		local delta = target - flat
		if delta.Magnitude <= 0.15 then
			guest.model:PivotTo(CFrame.lookAt(target + lift, target + lift + guest.facing))
			guest.target = nil
		else
			local step = math.min(GameConfig.GuestWalkSpeed * deltaTime, delta.Magnitude)
			local nextPosition = flat + delta.Unit * step + lift
			guest.model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + delta.Unit))
		end
	end
end)

local arrivalsPerMinute = GameConfig.arrivalsPerMinute(GameConfig.Day1AttractionIndex)
print(("[GuestSpawner] day-1 stream: %.1f arrivals/min"):format(arrivalsPerMinute))

task.spawn(function()
	while true do
		task.wait(60 / arrivalsPerMinute)
		spawnGuest()
	end
end)
