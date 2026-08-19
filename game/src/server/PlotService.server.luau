--!strict
-- Plot system (P-2). Plots are tagged pads with PlotId/PlotKind attributes;
-- building = pick a free plot + a catalog entry (§8: no freeform placement —
-- keeps the nav graph static and build UX trivial). Server validates phase
-- (§5: build during Prep), plot kind/occupancy, unlock index, and funds.
-- Occupancy replicates as an OccupiedBy attribute on the plot part so the
-- client menu renders from live truth. Starter kit per §8: carousel +
-- bathroom pre-built (persistence arrives in S-3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Component = require(ReplicatedStorage.Shared.Component)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local EconomyStore = require(script.Parent.EconomyStore)

local assets = ServerStorage:WaitForChild("Assets")
local dayState = ReplicatedStorage:WaitForChild("DayState")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buildRemote = Instance.new("RemoteEvent")
buildRemote.Name = "Build"
buildRemote.Parent = remotes
local buildAckRemote = Instance.new("RemoteEvent")
buildAckRemote.Name = "BuildAck"
buildAckRemote.Parent = remotes

local plots: { [BasePart]: Model? } = {} -- plot part → built model (nil = free)

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

local function recolor(model: Model, color: Color3)
	for _, name in { "Body", "Cart" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function buildOn(plotPart: BasePart, entry: Catalog.Entry): Model?
	local template = assets:FindFirstChild(entry.template)
	if not (template and template:IsA("Model")) then
		warn(("[Plot] template %q missing"):format(entry.template))
		return nil
	end
	local model = template:Clone()
	model.Name = entry.name
	if entry.color then
		recolor(model, entry.color :: Color3)
	end

	model:SetAttribute("CatalogId", entry.id)
	model:SetAttribute("Tier", 1)
	model:SetAttribute("PlotId", plotPart:GetAttribute("PlotId"))
	if entry.kind == "Ride" then
		model:SetAttribute("Condition", 100)
		model:SetAttribute("Capacity", entry.capacity)
		model:SetAttribute("BaseAppeal", entry.baseAppeal)
		model:SetAttribute("RideSeconds", entry.rideSeconds)
		model:SetAttribute("Speed", entry.speed)
	elseif entry.kind == "Facility" then
		model:SetAttribute("RefillNeed", entry.refillNeed)
		model:SetAttribute("ServiceSeconds", entry.serviceSeconds)
		model:SetAttribute("Revenue", entry.revenue or 0)
	elseif entry.radius then
		model:SetAttribute("Radius", entry.radius)
	end

	-- Templates author their WorldPivot at ground level with identity rotation,
	-- so placement is pure translation onto the pad top (never re-orients —
	-- a rotated first part used to tip whole models sideways)
	model:PivotTo(CFrame.new(plotPart.Position.X, 0.4, plotPart.Position.Z))
	model.Parent = workspace
	model:AddTag(entry.tag or entry.kind) -- binds the matching component

	plots[plotPart] = model
	plotPart:SetAttribute("OccupiedBy", entry.id)
	-- A-4: a destroyed building (ride launched into space…) frees its plot
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and plots[plotPart] == model then
			plots[plotPart] = nil
			plotPart:SetAttribute("OccupiedBy", nil)
			print(
				("[Plot] plot %s is free again"):format(tostring(plotPart:GetAttribute("PlotId")))
			)
		end
	end)
	print(
		("[Plot] built %s on plot %s"):format(entry.name, tostring(plotPart:GetAttribute("PlotId")))
	)
	return model
end

Component.bind("Plot", {
	onAttached = function(instance)
		if instance:IsA("BasePart") then
			plots[instance] = nil
			instance:SetAttribute("OccupiedBy", nil)
		end
	end,
	onDetached = function(instance)
		plots[instance :: BasePart] = nil
	end,
})

buildRemote.OnServerEvent:Connect(function(player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local requestId = data.requestId
	local plotPart = data.plotPart
	local catalogId = data.catalogId
	if typeof(requestId) ~= "string" or typeof(catalogId) ~= "string" then
		return
	end

	local function ack(accepted: boolean, reason: string?)
		buildAckRemote:FireClient(player, {
			requestId = requestId,
			accepted = accepted,
			reason = reason,
		})
	end

	local entry = Catalog.byId[catalogId]
	if not entry then
		return ack(false, "unknown item")
	end
	if typeof(plotPart) ~= "Instance" or not plotPart:IsA("BasePart") or plots[plotPart] ~= nil then
		return ack(false, "plot is taken")
	end
	if not table.find(plotPart:GetTags(), "Plot") then
		return ack(false, "not a plot")
	end
	if dayState:GetAttribute("Phase") ~= "Prep" then
		return ack(false, "build during Prep")
	end
	if not Catalog.plotAccepts(plotPart:GetAttribute("PlotKind"), entry) then
		return ack(false, ("needs a %s plot"):format(entry.kind))
	end
	if currentIndex() < entry.unlockIndex then
		return ack(false, ("unlocks at index %d"):format(entry.unlockIndex))
	end
	if not EconomyStore.trySpend(entry.cost) then
		return ack(false, "not enough cash")
	end

	local model = buildOn(plotPart, entry)
	if not model then
		EconomyStore.add(entry.cost) -- refund on template failure
		return ack(false, "build failed")
	end
	print(("[Plot] %s bought %s for $%d"):format(player.Name, entry.name, entry.cost))
	ack(true)
end)

-- §8 day-1 kit: 1 carousel + 1 bathroom pre-built, free (until saves in S-3)
task.defer(function()
	task.wait(1) -- let plots bind
	local ridePlot: BasePart? = nil
	local facilityPlot: BasePart? = nil
	for plotPart in plots do
		local kind = plotPart:GetAttribute("PlotKind")
		if kind == "Ride" and not ridePlot then
			ridePlot = plotPart
		elseif kind == "Facility" and not facilityPlot then
			facilityPlot = plotPart
		end
	end
	if ridePlot and not plots[ridePlot :: BasePart] then
		buildOn(ridePlot :: BasePart, Catalog.byId.Carousel)
	end
	if facilityPlot and not plots[facilityPlot :: BasePart] then
		buildOn(facilityPlot :: BasePart, Catalog.byId.Bathroom)
	end
end)
