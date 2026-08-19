--!strict
-- Build catalog (P-2). All prices/appeal/unlocks from design doc §9 —
-- placeholders scaled to the income curve. Rides drop onto Ride plots,
-- facilities onto Facility plots. `template` names a model in
-- ServerStorage.Assets; rides without bespoke grey-boxes yet use GenericRide
-- (recolored) until their asset card lands.

export type Kind = "Ride" | "Facility"

export type Entry = {
	id: string,
	name: string,
	kind: Kind,
	cost: number,
	unlockIndex: number, -- AttractionIdx required in shop (0 = from start)
	template: string,
	color: Color3?, -- recolor applied to GenericRide templates
	-- Ride fields
	baseAppeal: number?,
	speed: ("low" | "mid" | "high")?, -- drives alien targeting (A-4)
	capacity: number?,
	rideSeconds: number?,
	-- Facility fields
	refillNeed: ("Hunger" | "Bladder")?,
	serviceSeconds: number?,
	revenue: number?, -- paid by the guest on use (food)
}

local Catalog: { Entry } = {
	-- §9 rides (tier upgrades: +25% appeal per tier, upgrade cost 50% of base — P-later)
	{
		id = "Carousel",
		name = "Carousel",
		kind = "Ride",
		cost = 600,
		unlockIndex = 0,
		template = "Carousel",
		baseAppeal = 40,
		speed = "low",
		capacity = 4,
		rideSeconds = 12,
	},
	{
		id = "BumperCars",
		name = "Bumper Cars",
		kind = "Ride",
		cost = 900,
		unlockIndex = 0,
		template = "BumperCars",
		baseAppeal = 55,
		speed = "low",
		capacity = 6,
		rideSeconds = 14,
	},
	{
		id = "FerrisWheel",
		name = "Ferris Wheel",
		kind = "Ride",
		cost = 1400,
		unlockIndex = 150,
		template = "GenericRide",
		color = Color3.fromRGB(240, 200, 80),
		baseAppeal = 70,
		speed = "low",
		capacity = 8,
		rideSeconds = 18,
	},
	{
		id = "HauntedHouse",
		name = "Haunted House",
		kind = "Ride",
		cost = 2200,
		unlockIndex = 300,
		template = "GenericRide",
		color = Color3.fromRGB(120, 80, 160),
		baseAppeal = 85,
		speed = "mid",
		capacity = 6,
		rideSeconds = 20,
	},
	{
		id = "DropTower",
		name = "Drop Tower",
		kind = "Ride",
		cost = 3500,
		unlockIndex = 450,
		template = "GenericRide",
		color = Color3.fromRGB(220, 90, 90),
		baseAppeal = 100,
		speed = "high",
		capacity = 8,
		rideSeconds = 10,
	},
	{
		id = "RollerCoaster",
		name = "Roller Coaster",
		kind = "Ride",
		cost = 5000,
		unlockIndex = 600,
		template = "GenericRide",
		color = Color3.fromRGB(80, 170, 220),
		baseAppeal = 120,
		speed = "high",
		capacity = 12,
		rideSeconds = 25,
	},
	-- §9 facilities
	{
		id = "SnackCart",
		name = "Snack Cart",
		kind = "Facility",
		cost = 300,
		unlockIndex = 0,
		template = "SnackCart",
		refillNeed = "Hunger",
		serviceSeconds = 5,
		revenue = 5,
	},
	{
		id = "FoodCourt",
		name = "Food Court",
		kind = "Facility",
		cost = 1200,
		unlockIndex = 250,
		template = "SnackCart",
		color = Color3.fromRGB(240, 150, 60),
		refillNeed = "Hunger",
		serviceSeconds = 3,
		revenue = 9,
	},
	{
		id = "Bathroom",
		name = "Bathroom",
		kind = "Facility",
		cost = 400,
		unlockIndex = 0,
		template = "Bathroom",
		refillNeed = "Bladder",
		serviceSeconds = 6,
	},
}

local byId: { [string]: Entry } = {}
for _, entry in Catalog do
	byId[entry.id] = entry
end

return {
	entries = Catalog,
	byId = byId,
}
