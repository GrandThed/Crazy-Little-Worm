--!strict
-- The cult (A-5a: infiltration), per §4: attacks gate PATTERN-recognition —
-- the tell spans guests, not one ticket. On a cult day 4–6 members trickle in
-- spread across the whole day wearing matching amulets; their serials share a
-- letter and count up consecutively on the same date. Individually they're
-- harmless model citizens. The ritual half (convergence, kidnap, salt, fine)
-- is A-5b.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local Guests = require(script.Parent.Parent.Guests)

local dayState = ReplicatedStorage:WaitForChild("DayState")
local rng = Random.new()

local AMULET_COLOR = Color3.fromRGB(235, 190, 60) -- matching gold amulets

type Case = {
	guest: Guests.Guest,
	admitted: boolean,
	inRitual: boolean, -- A-5b: currently converging/channeling
}

local cases: { [string]: Case } = {}
local pendingSerials: { string } = {} -- queued for the next marked arrivals

local Cult = {}

local function attachAmulet(model: Model)
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local amulet = Instance.new("Part")
	amulet.Name = "Amulet"
	amulet.Anchored = true
	amulet.CanCollide = false
	amulet.Shape = Enum.PartType.Cylinder
	amulet.Size = Vector3.new(0.15, 0.5, 0.5) * model:GetScale()
	amulet.Color = AMULET_COLOR
	amulet.Material = Enum.Material.SmoothPlastic
	amulet.CFrame = body.CFrame
		* CFrame.new(0, body.Size.Y * 0.25, -(body.Size.Z / 2 + 0.1))
		* CFrame.Angles(0, math.rad(90), 0)
	amulet.Parent = model
end

-- Gate-time marker (§4 Infiltrate): amulet + the next serial in the sequence
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Cultist")
	attachAmulet(guest.model)
	local serial = table.remove(pendingSerials, 1)
	if serial then
		guest.identity.ticket.serial = serial
		guest.model:SetAttribute("TicketSerial", serial)
	end
	cases[guest.id] = { guest = guest, admitted = false, inRitual = false }
	print("[Anomaly] a devotee has joined the queue")
end

local function spawnMember(serial: string)
	table.insert(pendingSerials, serial)
	Guests.spawnArrival({ anomaly = "Cultist" })
end

-- §4/§8: cult slots trickle members across the WHOLE day (Scheduler calls
-- this once at Open with trickle = true)
function Cult.beginDay()
	local count = rng:NextInteger(GameConfig.CultMemberCount[1], GameConfig.CultMemberCount[2])
	local letter = string.char(rng:NextInteger(65, 90))
	local startNumber = rng:NextInteger(1000, 9000)
	print(("[Anomaly] a cult of %d is coming — watch the serials"):format(count))
	for index = 1, count do
		local serial = ("%s%04d"):format(letter, startNumber + index - 1)
		-- spread across ~the whole open day, in serial order
		local spawnAt = (0.03 + 0.85 * (index - 1 + rng:NextNumber(0, 0.8)) / count)
			* GameConfig.OpenDurationSeconds
		task.spawn(function()
			local elapsed = 0
			while dayState:GetAttribute("Phase") == "Open" do
				local waited = task.wait(0.25)
				elapsed += waited * GameConfig.timeScale()
				if elapsed >= spawnAt then
					spawnMember(serial)
					return
				end
			end
		end)
	end
end

-- Debug (F-5): a whole coven at the gate right now, serials consecutive
function Cult.debugBatch()
	local letter = string.char(rng:NextInteger(65, 90))
	local startNumber = rng:NextInteger(1000, 9000)
	for index = 1, GameConfig.CultMinMembers do
		spawnMember(("%s%04d"):format(letter, startNumber + index - 1))
	end
end

Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case then
		case.admitted = true
	end
end)

Guests.onDrained(function()
	table.clear(cases)
	table.clear(pendingSerials)
end)

Guests.registerAnomalyMarker("Cultist", mark)

-- A-5b hooks in here: ritual loop reads these
function Cult.getCases(): { [string]: Case }
	return cases
end

export type CultCase = Case

return Cult
