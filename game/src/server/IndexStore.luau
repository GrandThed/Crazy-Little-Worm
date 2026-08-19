--!strict
-- Attraction index (P-5), the coupling variable between all systems (§2).
-- Server computes; Index/Satisfaction replicate as IndexState attributes for
-- HUD/menu rendering. Floor of 50 is the anti-soft-lock guarantee (§2/§7).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local state = Instance.new("Folder")
state.Name = "IndexState"
state.Parent = ReplicatedStorage

local satisfaction = 0.6 -- §8 seed
local incidentP = 0

local IndexStore = {}

local function attributeNumber(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function compute(): number
	-- RideAppeal_r = BaseAppeal × (1 + 0.25·(tier−1)) × condition (broken = 0)
	local appealSum = 0
	for _, model in CollectionService:GetTagged("Ride") do
		if not model:IsA("Model") then
			continue
		end
		local conditionFactor = if model:GetAttribute("Broken") == true
			then 0
			else attributeNumber(model, "Condition", 100) / 100
		local tier = attributeNumber(model, "Tier", 1)
		appealSum += attributeNumber(model, "BaseAppeal", 0) * (1 + 0.25 * (tier - 1)) * conditionFactor
	end
	local parkAppeal = 6 * appealSum ^ 0.9 -- diminishing returns
	local index = math.clamp(parkAppeal * (0.5 + 0.5 * satisfaction) - incidentP, 50, 1000)
	state:SetAttribute("Index", index)
	state:SetAttribute("Satisfaction", satisfaction)
	return index
end

function IndexStore.getIndex(): number
	local value = state:GetAttribute("Index")
	return if typeof(value) == "number" then value else compute()
end

function IndexStore.getSatisfaction(): number
	return satisfaction
end

-- §2: Satisfaction = EMA of exit happiness (0–100 in), α = 0.1 per exit
function IndexStore.reportExitHappiness(happiness: number)
	satisfaction += 0.1 * (math.clamp(happiness, 0, 100) / 100 - satisfaction)
	compute()
end

function IndexStore.addIncident(severity: number)
	incidentP += severity
	compute()
	print(("[Index] incident +%d (pressure now %d)"):format(severity, incidentP))
end

-- §2: IncidentP decays ×0.5 per day
local dayState = ReplicatedStorage:WaitForChild("DayState")
dayState:GetAttributeChangedSignal("Day"):Connect(function()
	incidentP *= 0.5
	compute()
end)

task.spawn(function()
	while true do
		compute()
		task.wait(5)
	end
end)

return IndexStore
