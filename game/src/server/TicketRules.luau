--!strict
-- Ticket-rule days (A-7), per §5/§8: the content treadmill — a daily
-- Papers-Please rule delta that refreshes the inspection minigame with data,
-- not new systems. From day 3, ~40% of days carry a rule; violating tickets
-- appear in the normal guest stream and the correct play is Deny. Admitting a
-- violator lands a counterfeit fine at Summary (§3's deny-cost stays: denied
-- guests simply pay nothing).
--
-- The day's rule rolls LAZILY on first query for that day (the bulletin's
-- rule line during Prep), so there's no listener-ordering race with the
-- anomaly plan roll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GuestIdentity = require(ReplicatedStorage.Shared.GuestIdentity)

local rng = Random.new()

type Rule = {
	text: string,
	violates: (GuestIdentity.Ticket) -> boolean,
	-- Reshape a fresh valid ticket: violators at ~RuleViolatorChance, everyone
	-- else guaranteed clean (no accidental counterfeits from the generator)
	apply: (GuestIdentity.Ticket) -> (),
}

local rolledDay = 0
local currentRule: Rule? = nil

local function lastDigit(serial: string): number
	return tonumber(serial:sub(-1)) :: number
end

local RULE_MAKERS: { () -> Rule } = {
	-- counterfeit serial letter
	function(): Rule
		local letter = string.char(rng:NextInteger(65, 90))
		return {
			text = ("Serials starting with %s are counterfeit — deny them."):format(letter),
			violates = function(ticket)
				return ticket.serial:sub(1, 1) == letter
			end,
			apply = function(ticket)
				if rng:NextNumber() < GameConfig.RuleViolatorChance then
					ticket.serial = letter .. ticket.serial:sub(2)
				else
					while ticket.serial:sub(1, 1) == letter do
						ticket.serial = string.char(rng:NextInteger(65, 90)) .. ticket.serial:sub(2)
					end
				end
			end,
		}
	end,
	-- VIP ban (natural ~10% VIP rate is the violator rate)
	function(): Rule
		return {
			text = "No VIP passes accepted today — deny every VIP.",
			violates = function(ticket)
				return ticket.ticketType == "VIP"
			end,
			apply = function() end,
		}
	end,
	-- odd serials counterfeit (generator reweights so odds stay rare)
	function(): Rule
		return {
			text = "Printing error upstream: odd serial numbers are counterfeit — deny them.",
			violates = function(ticket)
				return lastDigit(ticket.serial) % 2 == 1
			end,
			apply = function(ticket)
				local wantOdd = rng:NextNumber() < GameConfig.RuleViolatorChance
				local digit = lastDigit(ticket.serial)
				if (digit % 2 == 1) ~= wantOdd then
					ticket.serial = ticket.serial:sub(1, -2) .. tostring((digit + 1) % 10)
				end
			end,
		}
	end,
}

local TicketRules = {}

local function rollFor(day: number)
	if day == rolledDay then
		return
	end
	rolledDay = day
	currentRule = nil
	if day >= GameConfig.RuleDayStartsDay and rng:NextNumber() < GameConfig.RuleDayChance then
		currentRule = RULE_MAKERS[rng:NextInteger(1, #RULE_MAKERS)]()
		print(("[Rules] day %d rule: %s"):format(day, (currentRule :: Rule).text))
	end
end

-- Bulletin rule provider (A-2): rolls the day on first ask
function TicketRules.ruleTextForDay(day: number): string?
	rollFor(day)
	local rule = currentRule
	return if rule then rule.text else nil
end

-- Debug (F-5): force a rule onto the CURRENT day regardless of the roll
function TicketRules.forceRule(day: number): string
	rolledDay = day
	currentRule = RULE_MAKERS[rng:NextInteger(1, #RULE_MAKERS)]()
	local rule = currentRule :: Rule
	print(("[Rules] day %d rule FORCED: %s"):format(day, rule.text))
	return rule.text
end

-- Called by Guests on every fresh ticket
function TicketRules.applyToTicket(ticket: GuestIdentity.Ticket)
	local rule = currentRule
	if rule then
		rule.apply(ticket)
	end
end

-- The clerk's (and the fine counter's) truth: valid unless today's rule says no
function TicketRules.isValid(ticket: GuestIdentity.Ticket): boolean
	local rule = currentRule
	return not (rule and rule.violates(ticket))
end

return TicketRules
