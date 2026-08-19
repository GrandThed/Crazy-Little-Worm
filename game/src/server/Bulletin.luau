--!strict
-- Daily bulletin (A-2), per §5/§8: Papers-Please-style morning read during
-- Prep — rule delta (A-7 plugs in via setRuleProvider), turnout forecast, and
-- themed first-appearance warnings the morning an anomaly type debuts. Only
-- the composed text replicates (BulletinState attributes); which slots are
-- actually filled stays server-only — a warning means "this type exists now",
-- never "an attack is scheduled today".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Scheduler = require(script.Parent.anomalies.Scheduler)

local state = Instance.new("Folder")
state.Name = "BulletinState"
state:SetAttribute("Day", 0)
state:SetAttribute("Text", "")
state.Parent = ReplicatedStorage

-- §8 first-appearance hints: themed, deliberately vague about timing
local DEBUT_WARNINGS: { [string]: string } = {
	Infected = "HEALTH NOTICE: infection outbreak reported nearby. Mind the coughers.",
	Aliens = "ODD SKIES: strange lights over the county. Keep an eye on ride speeds.",
	Spy = "BUSINESS DESK: a rival park is hiring 'consultants'. Double-check ticket dates.",
	Cult = "LOCAL: matching amulets spotted around town. Watch for patterns across tickets.",
	Shapeshifter = "CLASSIFIEDS: do you REALLY know your staff? Report anyone standing too still.",
}

local ruleProvider: (() -> string?)? = nil

local Bulletin = {}

-- A-7 ticket-rule days register their daily rule line here
function Bulletin.setRuleProvider(provider: () -> string?)
	ruleProvider = provider
end

local function currentIndex(): number
	local indexState = ReplicatedStorage:FindFirstChild("IndexState")
	local value = indexState and indexState:GetAttribute("Index")
	return if typeof(value) == "number" then value else GameConfig.Day1AttractionIndex
end

function Bulletin.publish(plan: Scheduler.Plan)
	local lines = {}

	if plan.day == 1 then
		table.insert(lines, "GRAND OPENING TODAY! Check every ticket: name, serial, type, date.")
	end

	local provider = ruleProvider
	local rule = if provider then provider() else nil
	if rule then
		table.insert(lines, ("TODAY'S RULE: %s"):format(rule))
	end

	for _, name in plan.debuts do
		local warning = DEBUT_WARNINGS[name]
		if warning then
			table.insert(lines, warning)
		end
	end

	local expected = GameConfig.arrivalsPerMinute(currentIndex())
		* (GameConfig.OpenDurationSeconds / 60)
	table.insert(lines, ("FORECAST: sunny. Expected turnout ~%d guests."):format(expected))

	state:SetAttribute("Day", plan.day)
	state:SetAttribute("Text", table.concat(lines, "\n\n"))
end

Scheduler.onPlanRolled(Bulletin.publish)

-- The boot-time day-1 roll happens while THIS module is still requiring
-- Scheduler — publish it retroactively if we missed it
local bootPlan = Scheduler.getPlan()
if bootPlan and (state:GetAttribute("Day") :: number) < bootPlan.day then
	Bulletin.publish(bootPlan)
end

return Bulletin
