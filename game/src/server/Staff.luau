--!strict
-- Staff NPCs (P-6 mechanic, P-7 clerk) — player substitutes per §6, worse at
-- every role than a human. Hired instantly from the Prep menu (no fee; the
-- wage IS the cost, §9), wages settle at Summary via Staff.settleWages —
-- unpayable wages make that staff member quit (§7 / P-9).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.anomalies.AnomalyBase)
local Attractions = require(script.Parent.Attractions)
local EconomyStore = require(script.Parent.EconomyStore)
local Guests = require(script.Parent.Guests)

local assets = ServerStorage:WaitForChild("Assets")
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

export type StaffKind = "Clerk" | "Mechanic"

export type StaffMember = {
	kind: StaffKind,
	tier: number,
	wage: number,
	model: Model,
	pivotHeight: number,
	target: Vector3?,
	standPart: BasePart?, -- clerk assignment
	repairTarget: Model?, -- mechanic assignment
	workTimer: number,
}

local roster: { StaffMember } = {}

local Staff = {}

local quitCallbacks: { (StaffMember) -> () } = {}

function Staff.onQuit(callback: (StaffMember) -> ())
	table.insert(quitCallbacks, callback)
end

function Staff.getRoster(): { StaffMember }
	return roster
end

local UNIFORByKind: { [string]: Color3 } = {
	Clerk = Color3.fromRGB(40, 60, 110), -- navy uniform variant
	Mechanic = Color3.fromRGB(210, 120, 40), -- hi-vis orange
}

local MECHANIC_HOME = Vector3.new(4, 0, -4)

local function spawnNpcModel(kind: StaffKind, tier: number): Model?
	local template = assets:FindFirstChild("GuestRig")
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	model.Name = ("%s (T%d)"):format(kind, tier)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.Color = UNIFORByKind[kind]
	end
	local legs = model:FindFirstChild("Legs")
	if legs and legs:IsA("BasePart") then
		legs.Color = Color3.fromRGB(35, 35, 45)
	end
	model.Parent = workspace
	return model
end

local function counterSide(standPart: BasePart): Vector3
	local position = standPart.Position - standPart.CFrame.LookVector * 2.5
	return Vector3.new(position.X, 0, position.Z)
end

local function playerNear(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
			if (flat - position).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

-- Returns the new member or nil + reason
function Staff.hire(kind: StaffKind, tier: number): (StaffMember?, string?)
	if kind == "Clerk" then
		tier = math.clamp(tier, 1, 3)
		-- assign the first stand without a clerk
		local assigned: BasePart? = nil
		for _, stand in Guests.getStands() do
			local taken = false
			for _, member in roster do
				if member.standPart == stand.part then
					taken = true
					break
				end
			end
			if not taken then
				assigned = stand.part
				break
			end
		end
		if not assigned then
			return nil, "every stand already has a clerk"
		end
		local model = spawnNpcModel(kind, tier)
		if not model then
			return nil, "no rig template"
		end
		local member: StaffMember = {
			kind = kind,
			tier = tier,
			wage = GameConfig.ClerkWages[tier],
			model = model,
			pivotHeight = GameConfig.GuestPivotHeight,
			target = counterSide(assigned :: BasePart),
			standPart = assigned,
			repairTarget = nil,
			workTimer = GameConfig.ClerkSecondsPerGuest,
		}
		model:PivotTo(CFrame.new(MECHANIC_HOME + Vector3.new(0, member.pivotHeight, 0)))
		table.insert(roster, member)
		print(("[Staff] hired %s for stand %s"):format(model.Name, tostring(assigned)))
		return member, nil
	end

	local model = spawnNpcModel(kind, 1)
	if not model then
		return nil, "no rig template"
	end
	local member: StaffMember = {
		kind = "Mechanic",
		tier = 1,
		wage = GameConfig.MechanicWage,
		model = model,
		pivotHeight = GameConfig.GuestPivotHeight,
		target = MECHANIC_HOME,
		standPart = nil,
		repairTarget = nil,
		workTimer = 0,
	}
	model:PivotTo(CFrame.new(MECHANIC_HOME + Vector3.new(0, member.pivotHeight, 0)))
	table.insert(roster, member)
	print("[Staff] hired a mechanic")
	return member, nil
end

local function dismiss(member: StaffMember, reason: string)
	local index = table.find(roster, member)
	if index then
		table.remove(roster, index)
	end
	member.model:Destroy()
	print(("[Staff] %s %s"):format(member.model.Name, reason))
	for _, callback in quitCallbacks do
		callback(member)
	end
end

-- Summary-time wage settlement (§9). Cash can't go negative: whoever can't
-- be paid quits on the spot (§7 anti-soft-lock). Returns total paid.
function Staff.settleWages(): number
	local paid = 0
	for _, member in table.clone(roster) do
		if EconomyStore.trySpend(member.wage) then
			paid += member.wage
		else
			dismiss(member, "quit — wages went unpaid")
		end
	end
	dayStats:SetAttribute("Wages", paid)
	return paid
end

-- ============================== behavior loops ==============================

local TICK = 0.5

-- NPC glide movement (same grey-box locomotion as guests)
task.spawn(function()
	while true do
		local deltaTime = task.wait(TICK)
		for _, member in roster do
			local target = member.target
			if not target then
				continue
			end
			local lift = Vector3.new(0, member.pivotHeight, 0)
			local pivot = member.model:GetPivot().Position
			local flat = Vector3.new(pivot.X, 0, pivot.Z)
			local delta = target - flat
			if delta.Magnitude <= 0.3 then
				member.target = nil
			else
				local step = math.min(GameConfig.GuestWalkSpeed * deltaTime, delta.Magnitude)
				local nextPosition = flat + delta.Unit * step + lift
				member.model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + delta.Unit))
			end
		end
	end
end)

-- Clerk (§3): ~6 guests/min, detection accuracy by tier, ~5% false positives.
-- Defers whenever a player is close enough to man the stand themselves.
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()
		for _, member in roster do
			if member.kind ~= "Clerk" or member.target then
				continue
			end
			local standPart = member.standPart
			if not standPart then
				continue
			end
			member.workTimer -= simDt
			if member.workTimer > 0 then
				continue
			end
			member.workTimer = GameConfig.ClerkSecondsPerGuest

			local standPosition = Vector3.new(standPart.Position.X, 0, standPart.Position.Z)
			if playerNear(standPosition, 12) then
				continue -- the player is handling this stand
			end
			for _, stand in Guests.getStands() do
				if stand.part ~= standPart then
					continue
				end
				local guest = stand.counterGuest
				if not guest then
					break
				end
				local isAnomaly = AnomalyBase.get(guest.id) ~= nil
				local verdict: Guests.Verdict
				if isAnomaly then
					verdict = if rng:NextNumber() < GameConfig.ClerkAccuracy[member.tier]
						then "Deny"
						else "Approve"
				else
					verdict = if rng:NextNumber() < GameConfig.ClerkFalsePositiveChance
						then "Deny"
						else "Approve"
				end
				if Guests.resolveCounter(standPart, guest.id, verdict) then
					print(("[Staff] clerk %sd %s"):format(verdict, guest.model.Name))
				end
				break
			end
		end
	end
end)

-- Mechanic (P-6): walk to the nearest broken ride, repair over time, go home
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()
		for _, member in roster do
			if member.kind ~= "Mechanic" then
				continue
			end
			local repairTarget = member.repairTarget
			if repairTarget then
				if not repairTarget.Parent then
					member.repairTarget = nil
					member.target = MECHANIC_HOME
					continue
				end
				if member.target then
					continue -- still walking over
				end
				if
					Attractions.repairTick(repairTarget, GameConfig.MechanicRepairPerSecond * simDt)
				then
					member.repairTarget = nil
					member.target = MECHANIC_HOME
				end
			else
				local broken = Attractions.getBrokenRides()[1]
				if broken then
					member.repairTarget = broken
					local pivot = broken:GetPivot().Position
					member.target = Vector3.new(pivot.X + 4, 0, pivot.Z + 4)
					print(("[Staff] mechanic heading to %s"):format(broken.Name))
				end
			end
		end
	end
end)

-- Hire remote (client Staff menu). Deferred: the Remotes folder is created by
-- DayCycle, which may require this module first — a synchronous wait here
-- would deadlock the require chain.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local hireRemote = Instance.new("RemoteEvent")
	hireRemote.Name = "HireStaff"
	hireRemote.Parent = remotes
	local hireAckRemote = Instance.new("RemoteEvent")
	hireAckRemote.Name = "HireAck"
	hireAckRemote.Parent = remotes

	hireRemote.OnServerEvent:Connect(function(player, kind: unknown, tier: unknown)
		if kind ~= "Clerk" and kind ~= "Mechanic" then
			return
		end
		local tierNumber = if typeof(tier) == "number" then math.clamp(tier, 1, 3) else 1
		local member, reason = Staff.hire(kind :: StaffKind, tierNumber)
		hireAckRemote:FireClient(player, {
			accepted = member ~= nil,
			reason = reason,
			count = #roster,
		})
	end)
end)

return Staff
