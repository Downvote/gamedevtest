--!strict
-- The island's tiers (GAME_DESIGN 4; docs/ARCHITECTURE.md 5): each tier's name (the island card's title). Pure. The
-- island has no house any more: its heart is the plaza round the campfire (Data/Street). (The module keeps its old
-- name: it was the studio's office, then the lodge.)
local Street = require(script.Parent.Street)

export type Plan = { tier: number, name: string }

local Office = {}

local PLANS: { Plan } = {
	{ tier = 1, name = "Castaway Cay" },
	{ tier = 2, name = "Palm Isle" },
	{ tier = 3, name = "Grand Isle" },
	{ tier = 4, name = "Harbor Town" },
	{ tier = 5, name = "Coral City" },
	{ tier = 6, name = "Sunspire Capital" },
	{ tier = 7, name = "Moonlit Bay" },
	{ tier = 8, name = "Evergreen Isle" },
	{ tier = 9, name = "Skyreach Isle" },
	{ tier = 10, name = "Driftling Haven" },
}
Office.plans = PLANS

function Office.plan(tier: number): Plan
	return PLANS[math.clamp(math.floor(tier), 1, #PLANS)]
end

-- The plot's origin in world studs (Data/Street: plots in a row along X, centred on x = 0).
function Office.origin(plot: number): (number, number)
	return Street.origin(plot)
end

return Office
