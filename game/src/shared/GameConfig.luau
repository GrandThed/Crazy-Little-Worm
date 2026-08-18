--!strict
-- Tunable constants. Numbers come from docs/game-design.md — section noted per value.
-- Change knobs here, never inline in feature code.

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

	-- §5 day cycle: Prep (untimed) → Open → Closing → Summary (waits for continue)
	OpenDurationSeconds = 12 * 60,
	ClosingDurationSeconds = 2 * 60,

	-- §8: fixed entry fee (charged on admission — wired up in G-8)
	EntryFee = 10,
}

-- §2 inflow: arrivalsPerMinute = 2 + AttractionIdx / 50
function GameConfig.arrivalsPerMinute(attractionIndex: number): number
	return 2 + attractionIndex / 50
end

return GameConfig
