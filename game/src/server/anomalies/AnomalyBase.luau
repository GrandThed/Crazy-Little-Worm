--!strict
-- Server-only anomaly registry (G-6). Which guest is an anomaly NEVER
-- replicates (architecture rule) — clients only ever see the cosmetic tells
-- each anomaly applies to its guest model. Lifecycle per §4:
-- Infiltrate → Dormant → Activate → Incident → Contained | Escalates.

local AnomalyBase = {}

local byGuestId: { [string]: string } = {}

function AnomalyBase.mark(guestId: string, anomalyName: string)
	byGuestId[guestId] = anomalyName
end

function AnomalyBase.get(guestId: string): string?
	return byGuestId[guestId]
end

function AnomalyBase.clear(guestId: string)
	byGuestId[guestId] = nil
end

function AnomalyBase.clearAll()
	table.clear(byGuestId)
end

return AnomalyBase
