--!strict
-- Guest identity generation (G-1): name, appearance, and ticket card.
-- Ticket fields per docs/game-design.md §3: Name · Serial (letter + 4 digits) ·
-- Type (Adult / Child / VIP) · Date. All tickets generated here are valid —
-- anomalies (G-6+) and rule days (A-7) introduce the invalid ones.

local rng = Random.new()

export type TicketType = "Adult" | "Child" | "VIP"

export type Ticket = {
	name: string,
	serial: string,
	ticketType: TicketType,
	date: string,
}

export type Appearance = {
	bodyColor: Color3,
	headColor: Color3,
	scale: number,
	briefcase: boolean, -- businessman look (§3: the spy's innocent lookalike)
}

export type Identity = {
	name: string,
	ticket: Ticket,
	appearance: Appearance,
}

local FIRST_NAMES = {
	"Benny",
	"Clara",
	"Dot",
	"Elmo",
	"Fern",
	"Gus",
	"Hazel",
	"Iggy",
	"June",
	"Kip",
	"Lola",
	"Milo",
	"Nell",
	"Ollie",
	"Pip",
	"Quinn",
	"Rosa",
	"Sam",
	"Tilly",
	"Umi",
	"Vera",
	"Wally",
	"Yuki",
	"Ziggy",
}

local LAST_NAMES = {
	"Applewhite",
	"Bumble",
	"Crank",
	"Dizzle",
	"Earwig",
	"Fizz",
	"Gumdrop",
	"Honk",
	"Inkwell",
	"Jolly",
	"Kettle",
	"Lemon",
	"Mustard",
	"Noodle",
	"Oats",
	"Pickle",
	"Quibble",
	"Rumple",
	"Sprocket",
	"Tumble",
	"Underfoot",
	"Vole",
	"Wobble",
	"Zest",
}

-- Art direction: saturated and cheerful, never desaturated (tell contrast rule).
-- Heads stay warm-toned — the Infected tell (pale/green) must read against these.
local BODY_COLORS = {
	Color3.fromRGB(224, 87, 79), -- cherry red
	Color3.fromRGB(246, 168, 33), -- marigold
	Color3.fromRGB(64, 156, 214), -- sky blue
	Color3.fromRGB(94, 187, 94), -- lawn green
	Color3.fromRGB(171, 103, 214), -- grape
	Color3.fromRGB(240, 122, 171), -- bubblegum
	Color3.fromRGB(84, 196, 179), -- teal
	Color3.fromRGB(238, 208, 66), -- lemon
}

local HEAD_COLORS = {
	Color3.fromRGB(245, 205, 165),
	Color3.fromRGB(224, 172, 122),
	Color3.fromRGB(188, 132, 87),
	Color3.fromRGB(139, 94, 60),
}

-- Businessman suits (A-3): rich, not desaturated — the spy hides among these
local SUIT_COLORS = {
	Color3.fromRGB(52, 68, 130), -- navy
	Color3.fromRGB(78, 60, 118), -- plum pinstripe (in spirit)
}
local BUSINESSMAN_CHANCE = 0.07 -- fraction of adult guests in a suit

local GuestIdentity = {}

local function rollTicketType(): TicketType
	local roll = rng:NextNumber()
	if roll < 0.7 then
		return "Adult"
	elseif roll < 0.9 then
		return "Child"
	else
		return "VIP"
	end
end

function GuestIdentity.generate(day: number): Identity
	local name = ("%s %s"):format(
		FIRST_NAMES[rng:NextInteger(1, #FIRST_NAMES)],
		LAST_NAMES[rng:NextInteger(1, #LAST_NAMES)]
	)
	local ticketType = rollTicketType()

	local scale
	if ticketType == "Child" then
		scale = rng:NextNumber(0.7, 0.85)
	else
		scale = rng:NextNumber(0.95, 1.15)
	end

	local businessman = ticketType ~= "Child" and rng:NextNumber() < BUSINESSMAN_CHANCE

	return {
		name = name,
		ticket = {
			name = name,
			serial = ("%s%04d"):format(
				string.char(rng:NextInteger(65, 90)),
				rng:NextInteger(0, 9999)
			),
			ticketType = ticketType,
			date = ("Day %d"):format(day),
		},
		appearance = {
			bodyColor = if businessman
				then SUIT_COLORS[rng:NextInteger(1, #SUIT_COLORS)]
				else BODY_COLORS[rng:NextInteger(1, #BODY_COLORS)],
			headColor = HEAD_COLORS[rng:NextInteger(1, #HEAD_COLORS)],
			scale = scale,
			briefcase = businessman,
		},
	}
end

return GuestIdentity
