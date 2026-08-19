--!strict
-- Rides + facilities as tagged components (P-3 / P-4), plus the provider API
-- the needs AI queries (P-1). Data-driven per the component rule: behavior
-- binds to any model tagged Ride/Facility with the right attributes — swap
-- the grey-box for final art, keep the tag, zero code change.
-- Breakdown/repair state (P-6) also lives here: condition decays per cycle,
-- low condition risks a breakdown, Broken rides stop and show sparks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EconomyStore = require(script.Parent.EconomyStore)
local Guests = require(script.Parent.Guests)

local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

export type Need = "Fun" | "Hunger" | "Bladder"

type Ride = {
	model: Model,
	seatSpots: { Vector3 },
	riders: { Guests.Guest },
	incoming: { Guests.Guest }, -- reserved, walking over or waiting to board
	running: boolean,
	loadTimer: number, -- simulated seconds until the cycle starts anyway
	runTimer: number,
}

type Facility = {
	model: Model,
	refillNeed: Need,
	occupants: { [Guests.Guest]: number }, -- guest → simulated seconds left
	incoming: { Guests.Guest },
}

local rides: { [Model]: Ride } = {}
local facilities: { [Model]: Facility } = {}

local breakdownCallbacks: { (Model) -> () } = {}

local Attractions = {}

function Attractions.onBreakdown(callback: (Model) -> ())
	table.insert(breakdownCallbacks, callback)
end

local function modelGroundPosition(model: Model): Vector3
	local pivot = model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function attributeNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

-- Seat spots: parts named Seat*/Car* if the model has them, else a ring
local function collectSeatSpots(model: Model, capacity: number): { Vector3 }
	local spots = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name:match("^Seat") or child.Name:match("^Car")) then
			table.insert(spots, Vector3.new(child.Position.X, 0, child.Position.Z))
		end
	end
	local center = modelGroundPosition(model)
	local index = #spots
	while #spots < capacity do
		index += 1
		local angle = (index / capacity) * math.pi * 2
		table.insert(spots, center + Vector3.new(math.cos(angle) * 3.5, 0, math.sin(angle) * 3.5))
	end
	return spots
end

local function isBroken(model: Model): boolean
	return model:GetAttribute("Broken") == true
end

-- ============================== provider API ==============================

export type Provider = {
	kind: "Ride" | "Facility",
	model: Model,
	approach: Vector3, -- where the guest should walk to
}

-- Nearest provider that can take one more guest for this need, or nil
function Attractions.findProvider(need: Need, fromPosition: Vector3): Provider?
	local best: Provider? = nil
	local bestDistance = math.huge
	if need == "Fun" then
		for model, ride in rides do
			if isBroken(model) then
				continue
			end
			local capacity = attributeNumber(model, "Capacity", 4)
			if #ride.riders + #ride.incoming >= capacity then
				continue
			end
			local position = modelGroundPosition(model)
			local distance = (position - fromPosition).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = { kind = "Ride", model = model, approach = position }
			end
		end
	else
		for model, facility in facilities do
			if facility.refillNeed ~= need then
				continue
			end
			local occupantCount = 0
			for _ in facility.occupants do
				occupantCount += 1
			end
			if occupantCount + #facility.incoming >= GameConfig.FacilityCapacity then
				continue
			end
			local position = modelGroundPosition(model) + Vector3.new(0, 0, 4)
			local distance = (position - fromPosition).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = { kind = "Facility", model = model, approach = position }
			end
		end
	end
	return best
end

function Attractions.reserve(provider: Provider, guest: Guests.Guest)
	local ride = rides[provider.model]
	if ride then
		table.insert(ride.incoming, guest)
		return
	end
	local facility = facilities[provider.model]
	if facility then
		table.insert(facility.incoming, guest)
	end
end

local function unreserve(list: { Guests.Guest }, guest: Guests.Guest)
	local index = table.find(list, guest)
	if index then
		table.remove(list, index)
	end
end

-- Guest reached the provider (GuestNeeds detects arrival and calls this)
function Attractions.guestArrived(provider: Provider, guest: Guests.Guest)
	local ride = rides[provider.model]
	if ride then
		unreserve(ride.incoming, guest)
		if isBroken(provider.model) then
			return -- broke while they walked over; decision loop re-plans
		end
		table.insert(ride.riders, guest)
		guest.busy = true
		local spot = ride.seatSpots[math.min(#ride.riders, #ride.seatSpots)]
		guest.model:PivotTo(CFrame.new(spot + Vector3.new(0, guest.pivotHeight + 0.8, 0)))
		guest.target = nil
		return
	end
	local facility = facilities[provider.model]
	if facility then
		unreserve(facility.incoming, guest)
		local serviceSeconds = attributeNumber(provider.model, "ServiceSeconds", 5)
		facility.occupants[guest] = serviceSeconds
		guest.busy = true
		guest.target = nil
	end
end

-- Reservation abandoned (guest fled/converted/left before arriving)
function Attractions.cancel(provider: Provider, guest: Guests.Guest)
	local ride = rides[provider.model]
	if ride then
		unreserve(ride.incoming, guest)
	end
	local facility = facilities[provider.model]
	if facility then
		unreserve(facility.incoming, guest)
	end
end

-- ============================== components ==============================

Component.bind("Ride", {
	onAttached = function(instance)
		if not instance:IsA("Model") then
			return
		end
		rides[instance] = {
			model = instance,
			seatSpots = collectSeatSpots(instance, attributeNumber(instance, "Capacity", 4)),
			riders = {},
			incoming = {},
			running = false,
			loadTimer = GameConfig.RideLoadWaitSeconds,
			runTimer = 0,
		}
		print(("[Attractions] ride online: %s"):format(instance.Name))
	end,
	onDetached = function(instance)
		local ride = rides[instance :: Model]
		if ride then
			for _, rider in ride.riders do
				rider.busy = false
			end
			rides[instance :: Model] = nil
		end
	end,
})

Component.bind("Facility", {
	onAttached = function(instance)
		if not instance:IsA("Model") then
			return
		end
		local refillNeed = instance:GetAttribute("RefillNeed")
		if refillNeed ~= "Hunger" and refillNeed ~= "Bladder" then
			warn("[Attractions] Facility without a valid RefillNeed: " .. instance.Name)
			return
		end
		facilities[instance] = {
			model = instance,
			refillNeed = refillNeed :: Need,
			occupants = {},
			incoming = {},
		}
		print(("[Attractions] facility online: %s"):format(instance.Name))
	end,
	onDetached = function(instance)
		local facility = facilities[instance :: Model]
		if facility then
			for occupant in facility.occupants do
				occupant.busy = false
			end
			facilities[instance :: Model] = nil
		end
	end,
})

-- ============================== breakdowns (P-6) ==============================

local function sparkEffect(model: Model): ParticleEmitter?
	local base = model:FindFirstChildWhichIsA("BasePart")
	if not base then
		return nil
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BreakdownSparks"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
	emitter.Size = NumberSequence.new(0.4)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 12
	emitter.Parent = base
	return emitter
end

local function breakDown(ride: Ride)
	local model = ride.model
	model:SetAttribute("Broken", true)
	sparkEffect(model)
	-- dump riders unhappy-ish: cycle aborts, no Fun refill
	for _, rider in ride.riders do
		rider.busy = false
		rider.target = nil
	end
	table.clear(ride.riders)
	ride.running = false
	dayStats:SetAttribute("Breakdowns", (dayStats:GetAttribute("Breakdowns") :: number? or 0) + 1)
	print(("[Attractions] %s BROKE DOWN"):format(model.Name))
	for _, callback in breakdownCallbacks do
		callback(model)
	end
end

-- Repair tick used by the Mechanic (P-6): returns true when fully repaired
function Attractions.repairTick(model: Model, amount: number): boolean
	local condition = math.min(100, attributeNumber(model, "Condition", 100) + amount)
	model:SetAttribute("Condition", condition)
	if condition >= 100 and isBroken(model) then
		model:SetAttribute("Broken", false)
		local base = model:FindFirstChildWhichIsA("BasePart")
		local sparks = base and base:FindFirstChild("BreakdownSparks")
		if sparks then
			sparks:Destroy()
		end
		print(("[Attractions] %s repaired"):format(model.Name))
		return true
	end
	return condition >= 100
end

-- Spy sabotage (A-3), per §4: condition −40; below the threshold the ride
-- breaks on the spot. Severity is charged by the caller. Returns broke.
function Attractions.sabotage(model: Model, amount: number): boolean
	local ride = rides[model]
	if not ride or isBroken(model) then
		return false
	end
	local condition = math.max(0, attributeNumber(model, "Condition", 100) - amount)
	model:SetAttribute("Condition", condition)
	print(("[Attractions] %s condition sabotaged to %d%%"):format(model.Name, condition))
	if condition < GameConfig.SpyBreakThreshold then
		breakDown(ride)
		return true
	end
	return false
end

-- Live ride models (anomaly targeting: spy picks by appeal, aliens by speed)
function Attractions.getRideModels(): { Model }
	local list = {}
	for model in rides do
		table.insert(list, model)
	end
	return list
end

function Attractions.getBrokenRides(): { Model }
	local broken = {}
	for model in rides do
		if isBroken(model) then
			table.insert(broken, model)
		end
	end
	return broken
end

-- Scripted day-2 carousel breakdown setup (§8 teaching beat): weaken it so
-- the first cycles of the day push it over the edge
function Attractions.weakenStarterRide()
	for model in rides do
		if model:GetAttribute("CatalogId") == "Carousel" then
			model:SetAttribute("Condition", 12)
			print("[Attractions] the carousel sounds... funny today")
			return
		end
	end
end

-- ============================== operation loop ==============================

local TICK = 0.5
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()

		for model, ride in rides do
			if isBroken(model) then
				continue
			end
			if ride.running then
				ride.runTimer -= simDt
				if ride.runTimer <= 0 then
					-- cycle complete: §1 riding refills Fun
					for _, rider in ride.riders do
						rider.needs.Fun = 100
						rider.busy = false
						rider.target = nil -- decision loop picks the next stop
					end
					table.clear(ride.riders)
					ride.running = false
					ride.loadTimer = GameConfig.RideLoadWaitSeconds

					local condition = attributeNumber(model, "Condition", 100)
						- GameConfig.RideConditionPerCycle
					model:SetAttribute("Condition", math.max(0, condition))
					if condition <= 0 or (condition <= 30 and rng:NextNumber() < 0.12) then
						breakDown(ride)
					end
				end
			elseif #ride.riders > 0 then
				local capacity = attributeNumber(model, "Capacity", 4)
				ride.loadTimer -= simDt
				if #ride.riders >= capacity or ride.loadTimer <= 0 then
					ride.running = true
					ride.runTimer = attributeNumber(model, "RideSeconds", 12)
				end
			end
		end

		for model, facility in facilities do
			for occupant, remaining in facility.occupants do
				local left = remaining - simDt
				if left <= 0 then
					facility.occupants[occupant] = nil
					occupant.needs[facility.refillNeed] = 100
					occupant.busy = false
					occupant.target = nil
					local revenue = attributeNumber(model, "Revenue", 0)
					if revenue > 0 then
						EconomyStore.add(revenue)
						dayStats:SetAttribute(
							"Income",
							(dayStats:GetAttribute("Income") :: number) + revenue
						)
						dayStats:SetAttribute(
							"FoodIncome",
							(dayStats:GetAttribute("FoodIncome") :: number? or 0) + revenue
						)
					end
				else
					facility.occupants[occupant] = left
				end
			end
		end
	end
end)

Guests.onDrained(function()
	for _, ride in rides do
		table.clear(ride.riders)
		table.clear(ride.incoming)
		ride.running = false
	end
	for _, facility in facilities do
		table.clear(facility.occupants)
		table.clear(facility.incoming)
	end
end)

-- §8 teaching beat: scripted carousel breakdown on day 2 (P-6)
task.spawn(function()
	local dayState = ReplicatedStorage:WaitForChild("DayState")
	local done = false
	dayState:GetAttributeChangedSignal("Phase"):Connect(function()
		if
			not done
			and dayState:GetAttribute("Phase") == "Open"
			and dayState:GetAttribute("Day") == 2
		then
			done = true
			Attractions.weakenStarterRide()
		end
	end)
end)

return Attractions
