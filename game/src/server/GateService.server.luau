--!strict
-- Gate decisions (G-2). Promotes the front queued guest to each stand's
-- counter and resolves player verdicts through the optimistic ack protocol
-- (server-architecture skill): client sends Decide{requestId, standPart,
-- guestId, verdict} and renders optimistically; server validates and answers
-- DecideAck{requestId, accepted}. A stale guestId (double-click, race with a
-- co-op partner) is rejected and the client resyncs from CounterChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Component = require(ReplicatedStorage.Shared.Component)
local Guests = require(script.Parent.Guests)

local dayState = ReplicatedStorage:WaitForChild("DayState")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local decideRemote = Instance.new("RemoteEvent")
decideRemote.Name = "Decide"
decideRemote.Parent = remotes
local decideAckRemote = Instance.new("RemoteEvent")
decideAckRemote.Name = "DecideAck"
decideAckRemote.Parent = remotes
local counterChangedRemote = Instance.new("RemoteEvent")
counterChangedRemote.Name = "CounterChanged"
counterChangedRemote.Parent = remotes

local MAX_DECIDE_DISTANCE = 16 -- studs from stand; cheap remote-spam guard

-- Relay counter changes (promote/resolve/drain) to all clients
Guests.counterChanged.Event:Connect(function(standPart: BasePart, guestModel: Model?)
	counterChangedRemote:FireAllClients(standPart, guestModel)
end)

-- "Man the stand" prompt so the inspection UI has a diegetic entry point
Component.bind("EntryStand", {
	onAttached = function(instance)
		if not instance:IsA("BasePart") then
			return nil
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ManStandPrompt"
		prompt.ActionText = "Man the stand"
		prompt.ObjectText = "Ticket Stand"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Parent = instance
		return prompt
	end,
	onDetached = function(_instance, prompt: ProximityPrompt?)
		if prompt then
			prompt:Destroy()
		end
	end,
})

local function playerNearStand(player: Player, standPart: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - standPart.Position).Magnitude <= MAX_DECIDE_DISTANCE
end

decideRemote.OnServerEvent:Connect(function(player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local requestId = data.requestId
	local standPart = data.standPart
	local guestId = data.guestId
	local verdict = data.verdict
	if typeof(requestId) ~= "string" or typeof(guestId) ~= "string" then
		return
	end
	if verdict ~= "Approve" and verdict ~= "Deny" then
		return
	end
	if typeof(standPart) ~= "Instance" or not standPart:IsA("BasePart") then
		return
	end

	local accepted = playerNearStand(player, standPart)
		and Guests.resolveCounter(standPart, guestId, verdict :: Guests.Verdict)

	if accepted then
		print(("[Gate] %s %sd guest %s"):format(player.Name, verdict :: string, guestId))
	end
	decideAckRemote:FireClient(player, { requestId = requestId, accepted = accepted })
end)

-- Debug hooks (F-5): resolve the first occupied counter without the UI
task.spawn(function()
	local debugActions = ServerStorage:WaitForChild("DebugActions")
	local function resolveFirst(verdict: Guests.Verdict)
		for _, stand in Guests.getStands() do
			local guest = stand.counterGuest
			if guest then
				Guests.resolveCounter(stand.part, guest.id, verdict)
				return
			end
		end
	end
	local approveAction = debugActions:WaitForChild("ApproveFront") :: BindableEvent
	local denyAction = debugActions:WaitForChild("DenyFront") :: BindableEvent
	approveAction.Event:Connect(function()
		resolveFirst("Approve")
	end)
	denyAction.Event:Connect(function()
		resolveFirst("Deny")
	end)
end)

-- Promotion loop: keep counters fed while the park is processing guests
task.spawn(function()
	while true do
		local phase = dayState:GetAttribute("Phase")
		if phase == "Open" or phase == "Closing" then
			for _, stand in Guests.getStands() do
				if not stand.counterGuest then
					Guests.promoteFront(stand.part)
				end
			end
		end
		task.wait(0.25)
	end
end)
