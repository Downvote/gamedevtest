--!strict
-- The island's tiers (GAME_DESIGN 4; docs/ARCHITECTURE.md 5): each tier's name (the island card's title). Pure. The
-- island has no house any more: its heart is the Tree of Life (Data/Street). (The module keeps its old
-- name: it was the studio's office, then the lodge.) Since the request of 2026-11-21, "rename all the islands in the game
-- to fit the floating island theme rather than island in water", no name has a cay, a harbour, a bay, a cove, a port, an
-- atoll, a tide or a shore in it: they float in the sky.
local Street = require(script.Parent.Street)

export type Plan = { tier: number, name: string }

local Office = {}

local PLANS: { Plan } = {
	{ tier = 1, name = "Driftstone" },
	{ tier = 2, name = "Breezy Isle" },
	{ tier = 3, name = "Grand Isle" },
	{ tier = 4, name = "Kite Town" },
	{ tier = 5, name = "Cumulus City" },
	{ tier = 6, name = "Sunspire Capital" },
	{ tier = 7, name = "Moonlit Heights" },
	{ tier = 8, name = "Evergreen Isle" },
	{ tier = 9, name = "Skyreach Isle" },
	{ tier = 10, name = "Driftling Haven" },
	{ tier = 11, name = "Lantern Loft" },
	{ tier = 12, name = "Highwind Reach" },
	{ tier = 13, name = "Mistwood Isle" },
	{ tier = 14, name = "Pearlstone Perch" },
	{ tier = 15, name = "Cloudberry Isle" },
	{ tier = 16, name = "Amberfield" },
	{ tier = 17, name = "Starfall Peak" },
	{ tier = 18, name = "Cloudcrown" },
	{ tier = 19, name = "Farsky" },
	{ tier = 20, name = "Everdrift" },
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
