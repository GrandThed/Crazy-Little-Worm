--!strict
-- Review page seed templates (P-8), Google-reviews pastiche per §5: flavor
-- text picked from templates keyed to the day's actual event log. Cheap to
-- author, high charm. ~15 seeds; Q-6 grows this to ~40.

export type Review = { stars: number, text: string }

export type DayEvents = {
	zombies: number,
	captured: number,
	breakdowns: number,
	walkaways: number,
	fled: number,
	staffQuit: number,
	loanBalance: number,
	stars: number, -- park star rating for generic picks
}

type Template = { stars: number, text: string, when: (DayEvents) -> boolean }

local TEMPLATES: { Template } = {
	-- outbreak
	{
		stars = 1,
		text = "waited in line and then my husband turned green and bit a man",
		when = function(e)
			return e.zombies >= 3
		end,
	},
	{
		stars = 2,
		text = "the zombie petting zoo was NOT on the park map",
		when = function(e)
			return e.zombies >= 1
		end,
	},
	-- containment
	{
		stars = 5,
		text = "watched staff net a zombie like a butterfly. incredible scenes",
		when = function(e)
			return e.captured >= 1
		end,
	},
	{
		stars = 4,
		text = "swift outbreak response, barely anyone got bitten at all",
		when = function(e)
			return e.captured >= 2 and e.zombies <= 3
		end,
	},
	-- breakdowns
	{
		stars = 2,
		text = "the carousel made a noise like a dying whale and then stopped",
		when = function(e)
			return e.breakdowns >= 1
		end,
	},
	{
		stars = 3,
		text = "ride broke down but a nice orange man hit it until it worked",
		when = function(e)
			return e.breakdowns >= 1
		end,
	},
	-- queues
	{
		stars = 1,
		text = "queue so long I aged out of my own ticket",
		when = function(e)
			return e.walkaways >= 8
		end,
	},
	{
		stars = 2,
		text = "waited 40 minutes, never even got in. the emoji faces were accurate",
		when = function(e)
			return e.walkaways >= 4
		end,
	},
	-- panic
	{
		stars = 1,
		text = "everyone was RUNNING. why was everyone running. i also ran",
		when = function(e)
			return e.fled >= 3
		end,
	},
	-- staff
	{
		stars = 1,
		text = "the clerk just took off his little hat and walked out mid-shift",
		when = function(e)
			return e.staffQuit >= 1
		end,
	},
	-- finances
	{
		stars = 3,
		text = "park seems… financially stressed? where ferris wheel",
		when = function(e)
			return e.loanBalance > 0
		end,
	},
	-- generic by rating
	{
		stars = 5,
		text = "lovely sunny day, kids loved the carousel, mustard was adequate",
		when = function(e)
			return e.stars >= 4
		end,
	},
	{
		stars = 4,
		text = "clean park, short lines, nobody bit anybody. would return",
		when = function(e)
			return e.stars >= 4
		end,
	},
	{
		stars = 3,
		text = "it's a park. the rides were rides. the mustard was warm",
		when = function(e)
			return e.stars == 3
		end,
	},
	{
		stars = 2,
		text = "it's giving 'abandoned fairground', but the ticket lady was nice",
		when = function(e)
			return e.stars <= 2
		end,
	},
}

local ReviewTemplates = {}

-- Up to `count` reviews whose conditions match today's events, event-keyed
-- picks first (they're the charm), generics fill the rest
function ReviewTemplates.pick(events: DayEvents, count: number, seed: number?): { Review }
	local rng = if seed then Random.new(seed) else Random.new()
	local matching: { Template } = {}
	for _, template in TEMPLATES do
		if template.when(events) then
			table.insert(matching, template)
		end
	end
	-- shuffle
	for index = #matching, 2, -1 do
		local swap = rng:NextInteger(1, index)
		matching[index], matching[swap] = matching[swap], matching[index]
	end
	local picked: { Review } = {}
	for _, template in matching do
		if #picked >= count then
			break
		end
		table.insert(picked, { stars = template.stars, text = template.text })
	end
	return picked
end

return ReviewTemplates
