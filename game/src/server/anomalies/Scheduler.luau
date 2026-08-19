--!strict
-- Anomaly scheduler (A-1), per §2/§4/§8. Replaces the interim day-2 roll:
-- daily slots = 1 + floor(AttractionIdx/250) capped at 5 AND by the unlocked
-- pool; each slot fills with p≈0.7; each filled slot draws a type from the
-- index-gated pool at a random time within Open. Day 1 is the only
-- guaranteed-safe day. The plan is rolled at Prep entry so the bulletin (A-2)
-- can carry first-appearance hints the morning a type debuts (§8) — first
-- draw EVER in this park marks the type "seen" (save-slot state in S-1).
--
-- The plan never replicates (anomaly truth is server-only); the debug readout
-- goes through the Studio-only DebugState mirror.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

export type PoolEntry = {
	name: string,
	minIndex: number, -- §4 tier gate
	spawn: () -> (), -- insert one instance (or one batch) into the day
	trickle: boolean?, -- cult: fires at Open and owns its own all-day timing
	canSpawn: (() -> boolean)?, -- extra gate (e.g. shapeshifter needs staff)
}

type FilledSlot = { name: string, spawnAt: number } -- sim-seconds into Open

export type Plan = {
	day: number,
	slots: number,
	filled: { FilledSlot },
	debuts: { string }, -- types drawn for the first time ever (bulletin hints)
}

local pool: { PoolEntry } = {}
local seenTypes: { [string]: boolean } = {}
local plan: Plan? = nil
local planRolledCallbacks: { (Plan) -> () } = {}

local Scheduler = {}

function Scheduler.register(entry: PoolEntry)
	table.insert(pool, entry)
end

function Scheduler.onPlanRolled(callback: (Plan) -> ())
	table.insert(planRolledCallbacks, callback)
end

function Scheduler.getPlan(): Plan?
	return plan
end

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

local function formatPlan(rolled: Plan): string
	if rolled.slots == 0 then
		return "day 1: safe"
	end
	local parts = {}
	for _, slot in rolled.filled do
		table.insert(
			parts,
			("%s@%dm%02ds"):format(slot.name, slot.spawnAt // 60, slot.spawnAt % 60)
		)
	end
	for _ = #rolled.filled + 1, rolled.slots do
		table.insert(parts, "—")
	end
	return ("%d slots: %s"):format(rolled.slots, table.concat(parts, " · "))
end

-- Rolled once per day, at Prep entry (§8: the bulletin needs the plan before
-- gates open; the index a few Prep-purchases later is close enough)
function Scheduler.rollPlan(day: number): Plan
	local existing = plan
	if existing and existing.day == day then
		return existing -- already rolled (boot race guard)
	end

	local rolled: Plan = { day = day, slots = 0, filled = {}, debuts = {} }
	if day >= 2 then
		local index = currentIndex()
		local unlocked: { PoolEntry } = {}
		for _, entry in pool do
			if
				index >= entry.minIndex
				and (not entry.canSpawn or (entry.canSpawn :: () -> boolean)())
			then
				table.insert(unlocked, entry)
			end
		end
		-- §2: 1 + floor(idx/250), capped at 5 and by the unlocked pool (card A-1)
		rolled.slots = math.min(
			1 + currentIndex() // GameConfig.AnomalySlotsPer,
			GameConfig.AnomalySlotCap,
			#unlocked
		)
		local window = GameConfig.AnomalySpawnWindow
		for _ = 1, rolled.slots do
			if rng:NextNumber() < GameConfig.AnomalyFillChance then
				local entry = unlocked[rng:NextInteger(1, #unlocked)]
				table.insert(rolled.filled, {
					name = entry.name,
					spawnAt = rng:NextNumber(window[1], window[2]) * GameConfig.OpenDurationSeconds,
				})
				if not seenTypes[entry.name] then
					seenTypes[entry.name] = true
					table.insert(rolled.debuts, entry.name)
				end
			end
		end
	end

	plan = rolled
	dayStats:SetAttribute("AnomalyPlan", formatPlan(rolled))
	print(("[Anomaly] day %d plan — %s"):format(day, formatPlan(rolled)))
	for _, callback in planRolledCallbacks do
		callback(rolled)
	end
	return rolled
end

local function poolEntry(name: string): PoolEntry?
	for _, entry in pool do
		if entry.name == name then
			return entry
		end
	end
	return nil
end

-- Execute the plan while Open: trickle types fire immediately and own their
-- timing; everything else waits out its rolled spawn time in simulated
-- seconds (the debug time scale compresses the wait)
local function executePlan()
	local current = plan
	if not current or #current.filled == 0 then
		if current and current.slots > 0 then
			print("[Anomaly] quiet day — every slot stayed empty")
		end
		return
	end
	for _, slot in current.filled do
		local entry = poolEntry(slot.name)
		if not entry then
			continue
		end
		if entry.trickle then
			entry.spawn()
			continue
		end
		task.spawn(function()
			local elapsed = 0
			while dayState:GetAttribute("Phase") == "Open" do
				local waited = task.wait(0.25)
				elapsed += waited * GameConfig.timeScale()
				if elapsed >= slot.spawnAt then
					entry.spawn()
					return
				end
			end
		end)
	end
end

dayState:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = dayState:GetAttribute("Phase")
	if phase == "Prep" then
		Scheduler.rollPlan(dayState:GetAttribute("Day") :: number)
	elseif phase == "Open" then
		executePlan()
	end
end)

-- Boot: DayCycle may already sit in Prep before this module loads
if dayState:GetAttribute("Phase") == "Prep" then
	Scheduler.rollPlan(dayState:GetAttribute("Day") :: number)
end

return Scheduler
