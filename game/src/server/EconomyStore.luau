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
state:SetAttribute("LoanBalance", 0)
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

-- §7 anti-soft-lock loan (P-9): +2000 cash, one loan at a time
function EconomyStore.getLoanBalance(): number
	return state:GetAttribute("LoanBalance") :: number
end

function EconomyStore.takeLoan(): boolean
	if EconomyStore.getLoanBalance() > 0 then
		return false
	end
	state:SetAttribute("LoanBalance", 2000)
	EconomyStore.add(2000)
	print("[Economy] loan taken: +$2000 (auto-repays 10%/day)")
	return true
end

-- Called at Summary: auto-repay 10% of the balance, limited by cash on hand
-- (cash never goes negative). Returns what was actually repaid.
function EconomyStore.repayLoanDaily(): number
	local balance = EconomyStore.getLoanBalance()
	if balance <= 0 then
		return 0
	end
	local due = math.ceil(balance * 0.1)
	local payment = math.min(due, EconomyStore.getCash())
	if payment > 0 then
		state:SetAttribute("Cash", EconomyStore.getCash() - payment)
		state:SetAttribute("LoanBalance", balance - payment)
	end
	return payment
end

-- Loan remote (deferred: Remotes folder is created by DayCycle)
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local loanRemote = Instance.new("RemoteEvent")
	loanRemote.Name = "TakeLoan"
	loanRemote.Parent = remotes
	loanRemote.OnServerEvent:Connect(function(player)
		if EconomyStore.takeLoan() then
			print(("[Economy] %s took the loan"):format(player.Name))
		end
	end)
end)

return EconomyStore
