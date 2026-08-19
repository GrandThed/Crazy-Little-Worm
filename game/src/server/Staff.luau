--!strict
-- Staff NPCs (P-6 mechanic, P-7 clerk) — player substitutes per §6, worse at
-- every role than a human. Hired instantly from the Prep menu (no fee; the
-- wage IS the cost, §9), wages settle at Summary via Staff.settleWages —
-- unpayable wages make that staff member quit (§7 / P-9).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GuestIdentity = require(ReplicatedStorage.Shared.GuestIdentity)
local AnomalyBase = require(script.Parent.anomalies.AnomalyBase)
local Attractions = require(script.Parent.Attractions)
local EconomyStore = require(script.Parent.EconomyStore)
local Guests = require(script.Parent.Guests)
local IndexStore = require(script.Parent.IndexStore)
local TicketRules = require(script.Parent.TicketRules)

local assets = ServerStorage:WaitForChild("Assets")
local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

-- Staff names replicate for the shapeshifter ticket tell (A-6): the player
-- must be able to recognize "wait, that's OUR clerk's name" on a ticket
local staffState = Instance.new("Folder")
staffState.Name = "StaffState"
staffState:SetAttribute("Roster", "")
staffState.Parent = ReplicatedStorage

export type StaffKind = "Clerk" | "Mechanic"

export type StaffMember = {
	kind: StaffKind,
	tier: number,
	wage: number,
	name: string, -- person name (A-6: the shapeshifter forges these)
	model: Model,
	pivotHeight: number,
	target: Vector3?,
	restPivot: CFrame?, -- settled position; idle bob oscillates around it
	mimic: boolean, -- A-6: replaced by a shapeshifter — does NOTHING well
	standPart: BasePart?, -- clerk assignment
	repairTarget: Model?, -- mechanic assignment
	workTimer: number,
}

local roster: { StaffMember } = {}

local function refreshRosterState()
	local lines = {}
	for _, member in roster do
		table.insert(lines, ("%s — %s T%d"):format(member.name, member.kind, member.tier))
	end
	staffState:SetAttribute("Roster", table.concat(lines, "\n"))
end

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

local function spawnNpcModel(kind: StaffKind, tier: number, name: string): Model?
	local template = assets:FindFirstChild("GuestRig")
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	model.Name = name
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.Color = UNIFORByKind[kind]
	end
	local legs = model:FindFirstChild("Legs")
	if legs and legs:IsA("BasePart") then
		legs.Color = Color3.fromRGB(35, 35, 45)
	end
	-- Nameplate (A-6): staff names are load-bearing — the ticket tell
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Nameplate"
		billboard.Size = UDim2.fromOffset(140, 34)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Color3.fromRGB(240, 242, 250)
		label.TextStrokeTransparency = 0.4
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 12
		label.Text = ("%s\n%s T%d"):format(name, kind, tier)
		label.Parent = billboard
		billboard.Parent = head
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
		local name = GuestIdentity.generate(1).name
		local model = spawnNpcModel(kind, tier, name)
		if not model then
			return nil, "no rig template"
		end
		local member: StaffMember = {
			kind = kind,
			tier = tier,
			wage = GameConfig.ClerkWages[tier],
			name = name,
			model = model,
			pivotHeight = GameConfig.GuestPivotHeight,
			target = counterSide(assigned :: BasePart),
			restPivot = nil,
			mimic = false,
			standPart = assigned,
			repairTarget = nil,
			workTimer = GameConfig.ClerkSecondsPerGuest,
		}
		model:PivotTo(CFrame.new(MECHANIC_HOME + Vector3.new(0, member.pivotHeight, 0)))
		table.insert(roster, member)
		refreshRosterState()
		print(("[Staff] hired %s (clerk) for stand %s"):format(name, tostring(assigned)))
		return member, nil
	end

	local name = GuestIdentity.generate(1).name
	local model = spawnNpcModel(kind, 1, name)
	if not model then
		return nil, "no rig template"
	end
	local member: StaffMember = {
		kind = "Mechanic",
		tier = 1,
		wage = GameConfig.MechanicWage,
		name = name,
		model = model,
		pivotHeight = GameConfig.GuestPivotHeight,
		target = MECHANIC_HOME,
		restPivot = nil,
		mimic = false,
		standPart = nil,
		repairTarget = nil,
		workTimer = 0,
	}
	model:PivotTo(CFrame.new(MECHANIC_HOME + Vector3.new(0, member.pivotHeight, 0)))
	table.insert(roster, member)
	refreshRosterState()
	print(("[Staff] hired %s (mechanic)"):format(name))
	return member, nil
end

local function dismiss(member: StaffMember, reason: string)
	local index = table.find(roster, member)
	if index then
		table.remove(roster, index)
	end
	refreshRosterState()
	member.model:Destroy()
	print(("[Staff] %s %s"):format(member.name, reason))
	for _, callback in quitCallbacks do
		callback(member)
	end
end

-- A-6: a revealed mimic leaves the roster WITHOUT the quit ceremony — the
-- real staffer was gone the moment the swap happened (§4 "lost staff"). The
-- model is handed to the caller (Shapeshifter animates the escape).
function Staff.removeRevealedMimic(member: StaffMember): Model
	local index = table.find(roster, member)
	if index then
		table.remove(roster, index)
	end
	refreshRosterState()
	return member.model
end

-- Clipboard inspect (§6/§9, A-6): the shapeshifter check. Nearest staff in
-- reach — a mimic goes to the reveal handler (Shapeshifter registers it), a
-- real staffer gets a ✓ over the head. §4 severity 10 charges on reveal.
local mimicRevealHandler: ((StaffMember) -> ())? = nil

function Staff.setMimicRevealHandler(handler: (StaffMember) -> ())
	mimicRevealHandler = handler
end

function Staff.clipboardInspect(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = Vector3.new(root.Position.X, 0, root.Position.Z)
	local best: StaffMember? = nil
	local bestDistance = GameConfig.ClipboardRange
	for _, member in roster do
		local pivot = member.model:GetPivot().Position
		local distance = (Vector3.new(pivot.X, 0, pivot.Z) - position).Magnitude
		if distance <= bestDistance then
			best = member
			bestDistance = distance
		end
	end
	if not best then
		print("[Staff] clipboard: nobody close enough to inspect")
		return
	end
	local member = best :: StaffMember
	if member.mimic then
		IndexStore.addIncident(GameConfig.ShapeshifterSeverity)
		local handler = mimicRevealHandler
		if handler then
			handler(member)
		end
		return
	end
	local head = member.model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(44, 44)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(90, 220, 110)
		label.Text = "✓"
		label.Parent = billboard
		billboard.Parent = head
		task.delay(1.5, function()
			billboard:Destroy()
		end)
	end
	print(("[Staff] clipboard: %s checks out"):format(member.name))
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

-- NPC glide movement (same grey-box locomotion as guests). Idle staff do a
-- gentle bob — the A-6 tell: a mimic stands PERFECTLY still.
task.spawn(function()
	while true do
		local deltaTime = task.wait(TICK)
		for _, member in roster do
			local target = member.target
			if not target then
				local rest = member.restPivot
				if rest and not member.mimic then
					local bob = math.sin(os.clock() * 2.4) * 0.12
					member.model:PivotTo(rest * CFrame.new(0, bob, 0))
				end
				continue
			end
			local lift = Vector3.new(0, member.pivotHeight, 0)
			local pivot = member.model:GetPivot().Position
			local flat = Vector3.new(pivot.X, 0, pivot.Z)
			local delta = target - flat
			if delta.Magnitude <= 0.3 then
				member.target = nil
				member.restPivot = member.model:GetPivot()
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
				local verdict: Guests.Verdict
				if member.mimic then
					-- §4 shapeshifter floodgate (A-6): the clerk-mimic waves
					-- EVERYONE through — the gate filter silently dies
					verdict = "Approve"
				else
					-- §3: clerks apply the same accuracy roll to anomalies AND
					-- rule-day violators (A-7) — a bad ticket is a bad ticket
					local isAnomaly = AnomalyBase.get(guest.id) ~= nil
						or not TicketRules.isValid(guest.identity.ticket)
					if isAnomaly then
						verdict = if rng:NextNumber() < GameConfig.ClerkAccuracy[member.tier]
							then "Deny"
							else "Approve"
					else
						verdict = if rng:NextNumber() < GameConfig.ClerkFalsePositiveChance
							then "Deny"
							else "Approve"
					end
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
			if member.mimic then
				-- §4 (A-6): the mechanic-mimic never repairs anything
				member.repairTarget = nil
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
