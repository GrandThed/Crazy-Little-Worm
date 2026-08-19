--!strict
-- Shapeshifter (A-6), per §4: attacks staff/trust — "can you trust your own
-- systems". Gate: an ordinary guest whose ticket NAME matches a rostered
-- staff member (nameplates + StaffMenu roster make that checkable). Inside:
-- 120s after admission it walks to an isolated staff NPC and replaces them —
-- the mimic keeps the name and post but does NOTHING: the clerk-mimic
-- approves everyone (infiltration floodgate), the mechanic-mimic never
-- repairs, and it never does the idle bob (the physical tell). Counter: the
-- manager clipboard reveals it (severity 10, staff lost, nettable while it
-- runs for the exit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local NetTargets = require(script.Parent.NetTargets)
local Guests = require(script.Parent.Parent.Guests)
local Staff = require(script.Parent.Parent.Staff)

local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

local REVEALED_COLOR = Color3.fromRGB(150, 150, 165) -- grey putty, mid-shift

type Stage = "Blending" | "Hunting"

type Case = {
	guest: Guests.Guest,
	stage: Stage,
	timer: number,
	targetMember: Staff.StaffMember?,
}

type Escapee = {
	model: Model,
	target: Vector3,
}

local cases: { [string]: Case } = {}
local escapees: { Escapee } = {}

local Shapeshifter = {}

local function guestStillActive(guest: Guests.Guest): boolean
	return table.find(Guests.getActive(), guest) ~= nil
end

local function guestPosition(guest: Guests.Guest): Vector3
	local pivot = guest.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function memberPosition(member: Staff.StaffMember): Vector3
	local pivot = member.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function realStaff(): { Staff.StaffMember }
	local list = {}
	for _, member in Staff.getRoster() do
		if not member.mimic then
			table.insert(list, member)
		end
	end
	return list
end

-- Scheduler gate: no staff, no one worth impersonating
function Shapeshifter.canSpawn(): boolean
	return #realStaff() > 0
end

-- Gate-time marker (§4 Infiltrate): perfectly ordinary… except the name
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Shapeshifter")
	local staff = realStaff()
	if #staff > 0 then
		local forged = staff[rng:NextInteger(1, #staff)].name
		guest.identity.ticket.name = forged
		guest.model:SetAttribute("TicketName", forged)
		guest.model.Name = forged
	end
	cases[guest.id] = { guest = guest, stage = "Blending", timer = math.huge, targetMember = nil }
	print("[Anomaly] someone with a very familiar name has joined the queue")
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

-- §4: "replaces an ISOLATED staff NPC" — nearest one with no player watching
local function pickIsolatedStaff(from: Vector3): Staff.StaffMember?
	local best: Staff.StaffMember? = nil
	local bestDistance = math.huge
	for _, member in realStaff() do
		local position = memberPosition(member)
		if playerNear(position, GameConfig.ShapeshifterIsolationRadius) then
			continue
		end
		local distance = (position - from).Magnitude
		if distance < bestDistance then
			best = member
			bestDistance = distance
		end
	end
	return best
end

local function shimmerAt(position: Vector3)
	NetTargets.puffAt(position, Color3.fromRGB(190, 190, 210))
end

local function replaceStaff(case: Case, member: Staff.StaffMember)
	local guest = case.guest
	cases[guest.id] = nil
	AnomalyBase.clear(guest.id)
	member.mimic = true
	shimmerAt(memberPosition(member))
	Guests.despawn(guest)
	print(
		("[Anomaly] …did %s just blink sideways? (a staff member was replaced)"):format(
			member.name
		)
	)
end

local TICK = 0.5
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()

		for id, case in cases do
			local guest = case.guest
			if not guestStillActive(guest) then
				cases[id] = nil
				AnomalyBase.clear(id)
				continue
			end

			if case.stage == "Blending" then
				case.timer -= simDt
				if case.timer <= 0 then
					local member = pickIsolatedStaff(guestPosition(guest))
					if member then
						case.stage = "Hunting"
						case.targetMember = member
						guest.state = "OnMission"
					else
						case.timer = 10 -- everyone's being watched; lurk
					end
				end
			elseif case.stage == "Hunting" then
				local member = case.targetMember
				if not member or member.mimic or table.find(Staff.getRoster(), member) == nil then
					case.stage = "Blending"
					case.timer = 5
					continue
				end
				local staffPosition = memberPosition(member)
				if playerNear(staffPosition, GameConfig.ShapeshifterIsolationRadius) then
					-- a player wandered over; break off and blend again
					case.stage = "Blending"
					case.timer = 10
					guest.state = "Admitted"
					guest.target = nil
					continue
				end
				if (guestPosition(guest) - staffPosition).Magnitude <= 3 then
					replaceStaff(case, member)
				else
					guest.target = staffPosition
				end
			end
		end

		-- revealed mimics sprint for the exit (nettable until they make it)
		for index = #escapees, 1, -1 do
			local escapee = escapees[index]
			if not escapee.model.Parent then
				table.remove(escapees, index)
				continue
			end
			local pivot = escapee.model:GetPivot().Position
			local flat = Vector3.new(pivot.X, 0, pivot.Z)
			local delta = escapee.target - flat
			if delta.Magnitude <= 1 then
				print("[Anomaly] the shapeshifter escaped into the parking lot")
				escapee.model:Destroy()
				table.remove(escapees, index)
			else
				local step = math.min(GameConfig.GuestWalkSpeed * 1.4 * TICK, delta.Magnitude)
				local nextPosition = flat
					+ delta.Unit * step
					+ Vector3.new(0, GameConfig.GuestPivotHeight, 0)
				escapee.model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + delta.Unit))
			end
		end
	end
end)

-- Admission arms the §4 replacement clock (120s)
Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case and case.stage == "Blending" then
		case.timer = GameConfig.ShapeshifterReplaceSeconds
	end
end)

-- Clipboard reveal (severity already charged by Staff): the staffer is lost,
-- the imposter drops the uniform and legs it
Staff.setMimicRevealHandler(function(member: Staff.StaffMember)
	local model = Staff.removeRevealedMimic(member)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Color = REVEALED_COLOR
		end
	end
	shimmerAt(memberPosition(member))
	table.insert(escapees, { model = model, target = Guests.exitPosition() })
	print(("[Anomaly] CLIPBOARD REVEAL: %s was a shapeshifter! Staff lost."):format(member.name))
end)

-- Net catch (§9): revealed shapeshifters mid-escape
NetTargets.register(function(position: Vector3): NetTargets.Hit?
	local bestIndex: number? = nil
	local bestDistance = math.huge
	for index, escapee in escapees do
		if escapee.model.Parent then
			local pivot = escapee.model:GetPivot().Position
			local distance = (Vector3.new(pivot.X, 0, pivot.Z) - position).Magnitude
			if distance < bestDistance then
				bestIndex = index
				bestDistance = distance
			end
		end
	end
	if not bestIndex then
		return nil
	end
	local index = bestIndex :: number
	return {
		distance = bestDistance,
		resolve = function(): string
			local escapee = escapees[index]
			table.remove(escapees, index)
			local pivot = escapee.model:GetPivot().Position
			shimmerAt(Vector3.new(pivot.X, 0, pivot.Z))
			escapee.model:Destroy()
			dayStats:SetAttribute(
				"Captured",
				(dayStats:GetAttribute("Captured") :: number? or 0) + 1
			)
			print("[Anomaly] netted the shapeshifter — it evaporated into grey mist")
			return "shapeshifter"
		end,
	}
end)

Guests.onDrained(function()
	table.clear(cases)
	-- escapees are not guests; let any mid-escape run finish naturally
end)

Guests.registerAnomalyMarker("Shapeshifter", mark)

function Shapeshifter.spawnOne()
	Guests.spawnArrival({ anomaly = "Shapeshifter" })
end

return Shapeshifter
