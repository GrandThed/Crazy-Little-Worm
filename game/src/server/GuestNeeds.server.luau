--!strict
-- Guest needs AI driver (P-1), per §1: four needs decay over time; every ~5 s
-- an idle guest picks the target with the highest urgency = (100−need)×weight
-- and walks to the nearest provider. Fear > 70 → Fleeing → scared exit.
-- Exit happiness H = 0.4·Fun + 0.2·Hunger + 0.15·Bladder + 0.25·(100−Fear)
-- feeds the satisfaction EMA (IndexStore).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Attractions = require(script.Parent.Attractions)
local Guests = require(script.Parent.Guests)
local IndexStore = require(script.Parent.IndexStore)

local trips: { [Guests.Guest]: Attractions.Provider } = {}
local decisionTimers: { [Guests.Guest]: number } = {}

local NEED_NAMES: { "Fun" | "Hunger" | "Bladder" } = { "Fun", "Hunger", "Bladder" }

local function cancelTrip(guest: Guests.Guest)
	local trip = trips[guest]
	if trip then
		Attractions.cancel(trip, guest)
		trips[guest] = nil
	end
end

local function decide(guest: Guests.Guest)
	local bestNeed: ("Fun" | "Hunger" | "Bladder")? = nil
	local bestUrgency = GameConfig.NeedSeekThreshold
	for _, needName in NEED_NAMES do
		local urgency = (100 - guest.needs[needName]) * GameConfig.NeedWeights[needName]
		if urgency > bestUrgency then
			bestUrgency = urgency
			bestNeed = needName
		end
	end
	if not bestNeed then
		return -- content: idle wander (Guests module) covers it
	end
	local pivot = guest.model:GetPivot().Position
	local provider =
		Attractions.findProvider(bestNeed :: Attractions.Need, Vector3.new(pivot.X, 0, pivot.Z))
	if provider then
		Attractions.reserve(provider, guest)
		trips[guest] = provider
		guest.target = provider.approach
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		local scale = GameConfig.timeScale()
		local activeSet: { [Guests.Guest]: boolean } = {}
		for _, guest in Guests.getActive() do
			activeSet[guest] = true
		end

		-- drop trips/timers for guests that despawned or stopped being guests
		for guest in trips do
			if
				not activeSet[guest]
				or (guest.state ~= "Admitted" and guest.state ~= "Converting")
			then
				cancelTrip(guest)
			end
		end
		for guest in decisionTimers do
			if not activeSet[guest] then
				decisionTimers[guest] = nil
			end
		end

		for _, guest in Guests.getActive() do
			if guest.state ~= "Admitted" then
				continue
			end

			-- §1 decay (busy guests are mid-refill; their clock pauses)
			if not guest.busy then
				for needName, perSecond in GameConfig.NeedDecay do
					guest.needs[needName] = math.max(0, guest.needs[needName] - perSecond * scale)
				end
			end
			guest.needs.Fear = math.max(0, guest.needs.Fear - GameConfig.FearDecayPerSecond * scale)

			-- §1: Fear > 70 → scared exit
			if guest.needs.Fear > GameConfig.FleeFearThreshold and not guest.busy then
				cancelTrip(guest)
				guest.state = "Fleeing"
				guest.speed = GameConfig.GuestWalkSpeed * 1.15
				guest.target = Guests.exitPosition()
				continue
			end

			local trip = trips[guest]
			if trip then
				if guest.busy then
					trips[guest] = nil -- arrived and got seated/served
				elseif not guest.target then
					trips[guest] = nil
					Attractions.guestArrived(trip, guest)
				end
				continue
			end

			if guest.busy then
				continue
			end

			local timer = (decisionTimers[guest] or GameConfig.DecisionIntervalSeconds) - scale
			if timer <= 0 then
				decisionTimers[guest] = GameConfig.DecisionIntervalSeconds
				decide(guest)
			else
				decisionTimers[guest] = timer
			end
		end
	end
end)

-- Exit happiness → satisfaction EMA. Walkaways count as unhappy exits (§3).
Guests.onExit(function(guest, reason)
	if reason == "walkaway" then
		IndexStore.reportExitHappiness(25)
		return
	end
	local needs = guest.needs
	local happiness = 0.4 * needs.Fun
		+ 0.2 * needs.Hunger
		+ 0.15 * needs.Bladder
		+ 0.25 * (100 - needs.Fear)
	IndexStore.reportExitHappiness(happiness)
end)

Guests.onDrained(function()
	table.clear(trips)
	table.clear(decisionTimers)
end)
