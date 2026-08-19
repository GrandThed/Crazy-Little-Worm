--!strict
-- Tunable constants. Numbers come from docs/game-design.md — section noted per value.
-- Change knobs here, never inline in feature code.

local RunService = game:GetService("RunService")

local GameConfig = {
	-- §2 / §8: day-1 seed values (real AttractionIndex calc lands in P-5)
	Day1AttractionIndex = 130,

	-- §1: front ~8 queued guests per stand are real characters; the rest are
	-- abstract counters, not models
	VisibleQueuePerStand = 8,

	-- §3: stand defaults (also settable per-stand via Attributes)
	DefaultQueueCapacity = 8,

	-- Grey-box locomotion (visual dressing, not physics — guests glide via PivotTo)
	GuestWalkSpeed = 8, -- studs/s
	QueueSpacing = 2.5, -- studs between queued guests
	QueueStartOffset = 4, -- studs from stand front to first queue slot
	GuestPivotHeight = 2.3, -- rig bounding-box center above ground, at scale 1

	-- §3 queue patience: 100 at arrival, −1/s while waiting, walkaway at 0
	PatienceMax = 100,
	PatienceDecayPerSecond = 1,
	-- Emote thresholds (patience ≤ value shows the face)
	PatienceAnnoyedAt = 60,
	PatienceAngryAt = 30,
	PatienceFuriousAt = 10,

	-- §5 day cycle: Prep (untimed) → Open → Closing → Summary (waits for continue)
	OpenDurationSeconds = 12 * 60,
	ClosingDurationSeconds = 2 * 60,

	-- §8: fixed entry fee (charged on admission) and day-1 kit cash
	EntryFee = 10,
	StartingCash = 500,

	-- §4 Infected: incubates after admission, zombie tag-converts on contact
	InfectedIncubationSeconds = 90,
	InfectedConversionSeconds = 20,
	ZombieSpeedMultiplier = 1.3, -- zombies outrun guests so the cascade lands
	ZombieTagRadius = 2.2, -- studs; contact distance for a conversion tag
	ZombieScareRadius = 9, -- studs; admitted guests flee zombies inside this
	-- §8: day 1 is the only guaranteed-safe day; slots fill with p≈0.7
	AnomalyFillChance = 0.7,

	-- §4 counter-item: capture net (G-7)
	NetRange = 7, -- studs; nearest zombie/tagged guest within this gets hit
	NetCooldownSeconds = 1,

	-- §1 needs system: decay per simulated second (Fear decays TOWARD zero)
	NeedDecay = { Fun = 0.2, Hunger = 0.1, Bladder = 0.08 },
	FearDecayPerSecond = 0.5,
	FleeFearThreshold = 70, -- §1: Fear > 70 → Fleeing → scared exit
	ZombieFearHit = 25, -- Fear added when a zombie scares a nearby guest
	NeedWeights = { Fun = 1.0, Hunger = 0.9, Bladder = 1.1 },
	NeedSeekThreshold = 30, -- urgency below this = keep wandering
	DecisionIntervalSeconds = 5, -- §1: decision rule every ~5 s
	GuestCap = 120, -- §1 performance cap on simulated guests

	-- Ride operation (P-3): cycle waits this long for more riders before running
	RideLoadWaitSeconds = 8,
	RideConditionPerCycle = 2, -- condition lost per operating cycle (P-6)
	FacilityCapacity = 2,

	-- v0 dwell (G-9 finding): admitted guests wander the park this long before
	-- heading home — must exceed infected incubation or outbreaks can't happen.
	-- P-1 needs AI replaces this with real behavior-driven dwell.
	GuestDwellSecondsMin = 180,
	GuestDwellSecondsMax = 300,

	-- Grey-box park interior where admitted guests wander/flee (studs)
	ParkBounds = { minX = -30, maxX = 30, minZ = -35, maxZ = 25 },
}

-- §2 inflow: arrivalsPerMinute = 2 + AttractionIdx / 50
function GameConfig.arrivalsPerMinute(attractionIndex: number): number
	return 2 + attractionIndex / 50
end

-- Studio-only debug time scale (F-5 panel): compresses simulation time —
-- phase durations, arrival rate, patience decay. Always 1 in production.
-- Visual glide speed is intentionally NOT scaled.
function GameConfig.timeScale(): number
	if not RunService:IsStudio() then
		return 1
	end
	local multiplier = workspace:GetAttribute("DaySpeedMultiplier")
	return if typeof(multiplier) == "number" and multiplier > 0 then multiplier else 1
end

return GameConfig
