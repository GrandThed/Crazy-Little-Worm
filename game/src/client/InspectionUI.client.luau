--!strict
-- Ticket inspection UI (G-2). Opened via the stand's "Man the stand" prompt.
-- Shows the counter guest's ticket card (fields replicate as model
-- attributes). Approve/Deny is optimistic: the card resolves instantly under
-- a client request id; the server ack either confirms (next guest arrives via
-- CounterChanged) or rejects (card flashes and resyncs). Placeholder styling —
-- juice lands in G-3, final art later.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local decideRemote = remotes:WaitForChild("Decide") :: RemoteEvent
local decideAckRemote = remotes:WaitForChild("DecideAck") :: RemoteEvent
local counterChangedRemote = remotes:WaitForChild("CounterChanged") :: RemoteEvent

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local focusedStand: BasePart? = nil -- stand we're manning; nil = UI closed
local counterGuests: { [BasePart]: Model? } = {} -- latest server truth per stand
local currentGuestModel: Model? = nil -- guest the card is showing
local pendingRequests: { [string]: boolean } = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InspectionUI"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "TicketCard"
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -24)
card.Size = UDim2.fromOffset(300, 210)
card.BackgroundColor3 = Color3.fromRGB(247, 241, 227)
card.Parent = screenGui
local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 10)
cardCorner.Parent = card

local header = Instance.new("TextLabel")
header.BackgroundColor3 = Color3.fromRGB(224, 87, 79)
header.Size = UDim2.new(1, 0, 0, 34)
header.TextColor3 = Color3.fromRGB(255, 255, 255)
header.Font = Enum.Font.GothamBold
header.TextSize = 16
header.Text = "PARK TICKET"
header.Parent = card
local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

local body = Instance.new("TextLabel")
body.Name = "Fields"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(18, 44)
body.Size = UDim2.new(1, -36, 0, 108)
body.TextColor3 = Color3.fromRGB(45, 41, 38)
body.Font = Enum.Font.Code
body.TextSize = 16
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = ""
body.Parent = card

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -4, 0, 4)
closeButton.Size = UDim2.fromOffset(26, 26)
closeButton.BackgroundColor3 = Color3.fromRGB(139, 45, 40)
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Text = "X"
closeButton.ZIndex = 3
closeButton.Parent = card
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = closeButton

local function makeVerdictButton(text: string, color: Color3, xScale: number): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(xScale, 0, 1, -12)
	button.Size = UDim2.fromOffset(124, 40)
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = text
	button.Parent = card
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local approveButton = makeVerdictButton("APPROVE", Color3.fromRGB(76, 175, 80), 0.27)
local denyButton = makeVerdictButton("DENY", Color3.fromRGB(211, 76, 60), 0.73)

local function renderGuest(guestModel: Model?)
	currentGuestModel = guestModel
	if not guestModel then
		body.Text = "\n   waiting for the\n   next guest…"
		approveButton.Visible = false
		denyButton.Visible = false
		return
	end
	body.Text = ("NAME    %s\nSERIAL  %s\nTYPE    %s\nDATE    %s"):format(
		tostring(guestModel:GetAttribute("TicketName")),
		tostring(guestModel:GetAttribute("TicketSerial")),
		tostring(guestModel:GetAttribute("TicketType")),
		tostring(guestModel:GetAttribute("TicketDate"))
	)
	approveButton.Visible = true
	denyButton.Visible = true
end

local function refreshFromServerTruth()
	local stand = focusedStand
	renderGuest(if stand then counterGuests[stand] else nil)
end

local function setFocusedStand(stand: BasePart?)
	focusedStand = stand
	screenGui.Enabled = stand ~= nil
	refreshFromServerTruth()
end

local function sendVerdict(verdict: "Approve" | "Deny")
	local stand = focusedStand
	local guestModel = currentGuestModel
	if not (stand and guestModel) then
		return
	end
	local requestId = HttpService:GenerateGUID(false)
	pendingRequests[requestId] = true
	decideRemote:FireServer({
		requestId = requestId,
		standPart = stand,
		guestId = guestModel:GetAttribute("GuestId"),
		verdict = verdict,
	})
	-- Optimistic: resolve the card now; CounterChanged brings the next guest
	renderGuest(nil)
end

approveButton.Activated:Connect(function()
	sendVerdict("Approve")
end)
denyButton.Activated:Connect(function()
	sendVerdict("Deny")
end)
closeButton.Activated:Connect(function()
	setFocusedStand(nil)
end)

-- Escape is reserved by the core menu, so X is the keyboard close
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.X and focusedStand then
		setFocusedStand(nil)
	end
end)

decideAckRemote.OnClientEvent:Connect(function(ack: { requestId: string, accepted: boolean })
	if not pendingRequests[ack.requestId] then
		return
	end
	pendingRequests[ack.requestId] = nil
	if not ack.accepted then
		-- Rollback: flash and resync to whatever the server says is at the counter
		header.Text = "OUT OF SYNC — RETRY"
		task.delay(0.8, function()
			header.Text = "PARK TICKET"
		end)
		refreshFromServerTruth()
	end
end)

counterChangedRemote.OnClientEvent:Connect(function(standPart: BasePart, guestModel: Model?)
	counterGuests[standPart] = guestModel
	if focusedStand == standPart then
		refreshFromServerTruth()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local parent = prompt.Parent
	if
		prompt.Name == "ManStandPrompt"
		and parent
		and parent:IsA("BasePart")
		and CollectionService:HasTag(parent, "EntryStand")
	then
		setFocusedStand(parent)
	end
end)
