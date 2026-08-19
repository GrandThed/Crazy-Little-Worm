--!strict
-- Aliens in a coat (A-4), per §4: attacks a single ride. Gate tells:
-- double-height wobbly walker holding a CHILD ticket. Inside: heads to the
-- fastest ride and overclocks it for 60s — speed visibly ramps (vibration,
-- rising hum, particles) — then the whole ride launches into space: ride
-- destroyed (plot freed), big Fear spike, severity 12. Counter: the ride's
-- e-stop panel resets the overclock and exposes them (coat drops — nettable);
-- the net also works mid-tamper.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local AnomalyBase = require(script.Parent.AnomalyBase)
local NetTargets = require(script.Parent.NetTargets)
local Attractions = require(script.Parent.Parent.Attractions)
local IndexStore = require(script.Parent.Parent.IndexStore)
local Guests = require(script.Parent.Parent.Guests)

local dayStats = ServerStorage:WaitForChild("DayStats")
local rng = Random.new()

local COAT_COLOR = Color3.fromRGB(196, 168, 124) -- trench-coat beige
local ALIEN_COLOR = Color3.fromRGB(110, 220, 120) -- what's under the coat

type Stage = "Blending" | "Moving" | "Overclocking" | "Exposed"

type Overclock = {
	ride: Model,
	originalPivot: CFrame,
	emitter: ParticleEmitter?,
	hum: Sound?,
	progress: number, -- 0..1 through the channel
}

type Case = {
	guest: Guests.Guest,
	stage: Stage,
	timer: number,
	overclock: Overclock?,
}

local cases: { [string]: Case } = {}

local Aliens = {}

local function getPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	return if child and child:IsA("BasePart") then child else nil
end

local function guestStillActive(guest: Guests.Guest): boolean
	return table.find(Guests.getActive(), guest) ~= nil
end

local function guestPosition(guest: Guests.Guest): Vector3
	local pivot = guest.model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

local function rideGroundPosition(model: Model): Vector3
	local pivot = model:GetPivot().Position
	return Vector3.new(pivot.X, 0, pivot.Z)
end

-- Gate-time marker (§4 Infiltrate): 9ft of trench coat with a Child ticket
local function mark(guest: Guests.Guest)
	AnomalyBase.mark(guest.id, "Aliens")
	local scale = guest.identity.appearance.scale * GameConfig.AlienScaleMultiplier
	guest.model:ScaleTo(scale)
	guest.pivotHeight = GameConfig.GuestPivotHeight * scale
	guest.wobble = true
	for _, name in { "Body", "LeftArm", "RightArm" } do
		local part = getPart(guest.model, name)
		if part then
			part.Color = COAT_COLOR
		end
	end
	guest.identity.ticket.ticketType = "Child"
	guest.model:SetAttribute("TicketType", "Child")

	cases[guest.id] = {
		guest = guest,
		stage = "Blending",
		timer = math.huge, -- armed on admission
		overclock = nil,
	}
	print("[Anomaly] something tall and wobbly has joined the queue")
end

-- §4: "goes to fastest ride" — Speed attribute rank, appeal breaks ties
local function pickFastestRide(): Model?
	local best: Model? = nil
	local bestScore = -1
	for _, model in Attractions.getRideModels() do
		if model:GetAttribute("Broken") == true or model:GetAttribute("Overclocked") == true then
			continue
		end
		local speed = model:GetAttribute("Speed")
		local rank = GameConfig.AlienSpeedRank[if typeof(speed) == "string" then speed else "low"]
			or 1
		local appeal = model:GetAttribute("BaseAppeal")
		local score = rank * 1000 + (if typeof(appeal) == "number" then appeal else 0)
		if score > bestScore then
			bestScore = score
			best = model
		end
	end
	return best
end

local function stopOverclockVisuals(overclock: Overclock, restorePivot: boolean)
	local emitter = overclock.emitter
	if emitter then
		emitter:Destroy()
	end
	local hum = overclock.hum
	if hum then
		hum:Destroy()
	end
	if restorePivot and overclock.ride.Parent then
		overclock.ride:PivotTo(overclock.originalPivot)
	end
end

local function cancelOverclock(case: Case, restorePivot: boolean)
	local overclock = case.overclock
	if overclock then
		stopOverclockVisuals(overclock, restorePivot)
		if overclock.ride.Parent then
			overclock.ride:SetAttribute("Overclocked", nil)
		end
		case.overclock = nil
	end
end

local function beginOverclock(case: Case, ride: Model)
	case.stage = "Overclocking"
	case.timer = GameConfig.AlienChannelSeconds
	ride:SetAttribute("Overclocked", true)

	local base = ride:FindFirstChildWhichIsA("BasePart")
	local emitter: ParticleEmitter? = nil
	local hum: Sound? = nil
	if base then
		emitter = Instance.new("ParticleEmitter")
		local e = emitter :: ParticleEmitter
		e.Name = "OverclockStreaks"
		e.Color = ColorSequence.new(Color3.fromRGB(150, 240, 170))
		e.Size = NumberSequence.new(0.5)
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 8
		e.Parent = base
		hum = Instance.new("Sound")
		local h = hum :: Sound
		h.SoundId = "rbxasset://sounds/bass.wav"
		h.Looped = true
		h.Volume = 0.5
		h.PlaybackSpeed = 0.5
		h.Parent = base
		h:Play()
	end
	case.overclock = {
		ride = ride,
		originalPivot = ride:GetPivot(),
		emitter = emitter,
		hum = hum,
		progress = 0,
	}
	print(("[Anomaly] %s is speeding up… someone should check the panel"):format(ride.Name))
end

-- §4 Fear AoE around the launch site — nearby guests scatter
local function fearSpike(center: Vector3)
	for _, guest in Guests.getActive() do
		if guest.state == "Admitted" and not guest.busy then
			if (guestPosition(guest) - center).Magnitude <= GameConfig.AlienFearRadius then
				guest.needs.Fear = math.min(100, guest.needs.Fear + GameConfig.AlienFearSpike)
			end
		end
	end
end

-- The streamable moment: ride (aliens aboard) accelerates into the sky
local function launch(case: Case)
	local overclock = case.overclock :: Overclock
	local ride = overclock.ride
	local guest = case.guest
	cases[guest.id] = nil
	AnomalyBase.clear(guest.id)
	stopOverclockVisuals(overclock, false)

	dayStats:SetAttribute("Launched", (dayStats:GetAttribute("Launched") :: number? or 0) + 1)
	IndexStore.addIncident(GameConfig.AlienSeverity)
	local center = rideGroundPosition(ride)
	fearSpike(center)

	-- Aliens board for takeoff; the guest model rides the ascent then despawns
	local startPivot = ride:GetPivot()
	guest.target = nil
	guest.state = "OnMission"

	local base = ride:FindFirstChildWhichIsA("BasePart")
	if base then
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "LaunchFlame"
		flame.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60))
		flame.Size = NumberSequence.new(1.6)
		flame.Lifetime = NumberRange.new(0.4, 0.8)
		flame.Speed = NumberRange.new(15, 25)
		flame.SpreadAngle = Vector2.new(30, 30)
		flame.Rate = 60
		flame.Parent = base
	end

	print(("[Anomaly] %s HAS ACHIEVED LIFTOFF"):format(ride.Name))
	task.spawn(function()
		-- real-time visual (like glide speed, deliberately not sim-scaled)
		local elapsed = 0
		while elapsed < 2.4 and ride.Parent do
			local dt = task.wait()
			elapsed += dt
			local height = 90 * elapsed * elapsed
			local spin = elapsed * 3
			ride:PivotTo(
				CFrame.new(startPivot.Position + Vector3.new(0, height, 0))
					* CFrame.Angles(0, spin, 0)
			)
			guest.model:PivotTo(ride:GetPivot() * CFrame.new(0, 4, 0))
		end
		NetTargets.puffAt(center + Vector3.new(0, 4, 0), Color3.fromRGB(255, 200, 120))
		if guestStillActive(guest) then
			Guests.despawn(guest)
		end
		if ride.Parent then
			ride:Destroy() -- Ride component detaches; PlotService frees the pad
		end
	end)
end

local function expose(case: Case)
	cancelOverclock(case, true)
	case.stage = "Exposed"
	local guest = case.guest
	for _, name in { "Body", "LeftArm", "RightArm" } do
		local part = getPart(guest.model, name)
		if part then
			part.Color = ALIEN_COLOR
		end
	end
	local head = getPart(guest.model, "Head")
	if head then
		head.Color = ALIEN_COLOR
	end
	guest.state = "Leaving"
	guest.speed = GameConfig.GuestWalkSpeed * 1.3
	guest.target = Guests.exitPosition()
	print("[Anomaly] the coat came off — THREE ALIENS?! They're making a run for it")
end

-- E-stop interact (§4 counter): reset + expose, or a harmless clunk
function Aliens.eStop(ride: Model): boolean
	for _, case in cases do
		local overclock = case.overclock
		if case.stage == "Overclocking" and overclock and overclock.ride == ride then
			expose(case)
			return true
		end
	end
	return false
end

local TICK = 0.25
task.spawn(function()
	while true do
		task.wait(TICK)
		local simDt = TICK * GameConfig.timeScale()

		for id, case in cases do
			local guest = case.guest
			if not guestStillActive(guest) then
				cancelOverclock(case, true)
				cases[id] = nil
				AnomalyBase.clear(id)
				continue
			end

			if case.stage == "Blending" then
				case.timer -= simDt
				if case.timer <= 0 then
					local ride = pickFastestRide()
					if ride then
						case.stage = "Moving"
						guest.state = "OnMission"
						local around = rideGroundPosition(ride)
						guest.target = around + Vector3.new(rng:NextNumber(-2, 2), 0, 3)
						case.overclock = {
							ride = ride,
							originalPivot = ride:GetPivot(),
							emitter = nil,
							hum = nil,
							progress = 0,
						}
					else
						case.timer = 20 -- no rides up; sulk and retry
					end
				end
			elseif case.stage == "Moving" then
				local pending = case.overclock
				local ride = if pending then pending.ride else nil
				if not (ride and ride.Parent) or ride:GetAttribute("Broken") == true then
					case.overclock = nil
					case.stage = "Blending"
					case.timer = 5
				elseif not guest.target then
					beginOverclock(case, ride :: Model)
				end
			elseif case.stage == "Overclocking" then
				local overclock = case.overclock :: Overclock
				local ride = overclock.ride
				if not ride.Parent or ride:GetAttribute("Broken") == true then
					cancelOverclock(case, true)
					case.stage = "Blending"
					case.timer = 5
					continue
				end
				case.timer -= simDt
				overclock.progress = 1 - case.timer / GameConfig.AlienChannelSeconds
				-- the ramp: shake grows, hum pitch rises with progress
				local intensity = overclock.progress * 0.35
				ride:PivotTo(
					overclock.originalPivot
						* CFrame.new(
							rng:NextNumber(-intensity, intensity),
							0,
							rng:NextNumber(-intensity, intensity)
						)
				)
				local hum = overclock.hum
				if hum then
					hum.PlaybackSpeed = 0.5 + overclock.progress * 1.3
				end
				local emitter = overclock.emitter
				if emitter then
					emitter.Rate = 8 + overclock.progress * 60
				end
				if case.timer <= 0 then
					launch(case)
				end
			end
		end
	end
end)

-- Admission arms the activation clock
Guests.onAdmitted(function(guest)
	local case = cases[guest.id]
	if case and case.stage == "Blending" then
		local delay = GameConfig.AlienActivationDelay
		case.timer = rng:NextNumber(delay[1], delay[2])
	end
end)

-- Net catch (§9): mid-tamper or exposed
NetTargets.register(function(position: Vector3): NetTargets.Hit?
	local bestCase: Case? = nil
	local bestDistance = math.huge
	for _, case in cases do
		if case.stage == "Overclocking" or case.stage == "Exposed" then
			if guestStillActive(case.guest) then
				local distance = (guestPosition(case.guest) - position).Magnitude
				if distance < bestDistance then
					bestCase = case
					bestDistance = distance
				end
			end
		end
	end
	if not bestCase then
		return nil
	end
	local case = bestCase :: Case
	return {
		distance = bestDistance,
		resolve = function(): string
			local guest = case.guest
			cancelOverclock(case, true)
			cases[guest.id] = nil
			AnomalyBase.clear(guest.id)
			NetTargets.puffAt(guestPosition(guest), Color3.fromRGB(150, 240, 170))
			Guests.despawn(guest)
			dayStats:SetAttribute(
				"Captured",
				(dayStats:GetAttribute("Captured") :: number? or 0) + 1
			)
			print("[Anomaly] netted the coat — three very small aliens evaporated")
			return "aliens"
		end,
	}
end)

Guests.onDrained(function()
	for _, case in cases do
		cancelOverclock(case, true)
	end
	table.clear(cases)
end)

Guests.registerAnomalyMarker("Aliens", mark)

function Aliens.spawnOne()
	Guests.spawnArrival({ anomaly = "Aliens" })
end

-- E-stop panel per ride (A-4 wire-up): a second binder on the Ride tag adds
-- the grey-box panel + prompt; final art replaces the part, same prompt
Component.bind("Ride", {
	onAttached = function(instance): { Part | ProximityPrompt }?
		if not instance:IsA("Model") then
			return nil
		end
		local pivot = instance:GetPivot().Position
		local panel = Instance.new("Part")
		panel.Name = "EStopPanel"
		panel.Anchored = true
		panel.Size = Vector3.new(1, 1.4, 0.6)
		panel.Position = Vector3.new(pivot.X + 3.5, 0.9, pivot.Z + 3.5)
		panel.Color = Color3.fromRGB(180, 40, 36)
		panel.Material = Enum.Material.SmoothPlastic
		panel.Parent = instance
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EStopPrompt"
		prompt.ActionText = "E-Stop"
		prompt.ObjectText = instance.Name
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.Parent = panel
		prompt.Triggered:Connect(function()
			if not Aliens.eStop(instance) then
				print(("[Anomaly] e-stop clunked: %s is running normally"):format(instance.Name))
			end
		end)
		return { panel, prompt }
	end,
	onDetached = function(_instance, state)
		if state then
			for _, object in state do
				object:Destroy()
			end
		end
	end,
})

return Aliens
