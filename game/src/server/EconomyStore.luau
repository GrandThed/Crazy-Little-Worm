--!strict
-- Economy store v0 (G-8). One authoritative cash pool for the park (shared
-- 6-player economy). Server-only writes; the Cash attribute on
-- ReplicatedStorage.EconomyState replicates for HUD rendering. Persistence
-- arrives with ProfileStore in S-1; concurrent-spend conflict resolution
-- (arrival order, loser rolls back) matters once the build menu lands in P-2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local state = Instance.new("Folder")
state.Name = "EconomyState"
state:SetAttribute("Cash", GameConfig.StartingCash)
state.Parent = ReplicatedStorage

local EconomyStore = {}

function EconomyStore.getCash(): number
	return state:GetAttribute("Cash") :: number
end

function EconomyStore.add(amount: number)
	assert(amount >= 0, "use trySpend for deductions")
	state:SetAttribute("Cash", EconomyStore.getCash() + amount)
end

-- Server-side gate for purchases: false = insufficient funds, nothing changes.
-- Cash can never go negative (anti-soft-lock floor, §7).
function EconomyStore.trySpend(amount: number): boolean
	assert(amount >= 0, "spend amounts are positive")
	local cash = EconomyStore.getCash()
	if cash < amount then
		return false
	end
	state:SetAttribute("Cash", cash - amount)
	return true
end

return EconomyStore
