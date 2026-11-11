--!strict
-- The wild places on the island (GAME_DESIGN 7: "caves and tall grass and volcanoes and other areas will spawn on the
-- island when it is first created, with an area for each island we are removing"). Pure. One kind of place for each
-- kind of island the sea chart had (Data/Islets: its driftlings, its stage on an expedition). A new island has a few;
-- every expansion brings more, each higher in level (SPAWN). A place stands on the island as a piece (Logic/Plot):
-- "wild_<id>" while wild (nothing may be built within Tuning.SiteRadius studs of it, it can't be moved or cleared
-- away; a tap explores it), "done_<id>" once its guardian is beaten (an ordinary piece after that: moved, or cleared
-- away for nothing; a tap still explores it again). The piece's `lvl` is the place's level.
--   islet: its Data/Islets kind (its driftlings, its stage); w x d: its footprint (whole studs, facing south)
export type SiteDef = { id: string, islet: number, name: string, plural: string, w: number, d: number, blurb: string }

-- stylua: ignore start
local LIST: { SiteDef } = {
	{ id = "tidepool", islet = 1, name = "Tide Pool", plural = "Tide Pools", w = 4, d = 4, blurb = "Rock pools full of grumpy crabs." },
	{ id = "tallgrass", islet = 2, name = "Tall Grass", plural = "Tall Grass", w = 4, d = 4, blurb = "Grass taller than you. Something rustles in it." },
	{ id = "bog", islet = 6, name = "Bog", plural = "Bogs", w = 4, d = 4, blurb = "Tangled roots over warm brown water." },
	{ id = "volcano", islet = 3, name = "Volcano", plural = "Volcanoes", w = 5, d = 5, blurb = "A small volcano that never quite goes out." },
	{ id = "cave", islet = 7, name = "Cave", plural = "Caves", w = 5, d = 4, blurb = "Glowing crystals down in the dark." },
	{ id = "frostpeak", islet = 4, name = "Frost Peak", plural = "Frost Peaks", w = 5, d = 5, blurb = "A heap of rock that stays frozen in the sun." },
	{ id = "bluff", islet = 8, name = "Windy Bluff", plural = "Windy Bluffs", w = 5, d = 4, blurb = "A rocky crag the wind never leaves alone." },
	{ id = "coralpool", islet = 5, name = "Coral Pool", plural = "Coral Pools", w = 4, d = 4, blurb = "A deep blue pool with coral at the bottom." },
	{ id = "ruins", islet = 9, name = "Old Ruins", plural = "Old Ruins", w = 5, d = 5, blurb = "Broken stones from before anyone lived here." },
}
-- stylua: ignore end

local byId: { [string]: SiteDef } = {}
local byIslet: { [number]: SiteDef } = {}
for _, d in LIST do
	byId[d.id] = d
	byIslet[d.islet] = d
end

-- What comes up on the island at each tier (its kind and level): tier 1 when the island is new, each later one when
-- the island grows to it ("Expanding your island will cause more of these caves to spawn, with higher level per
-- expansion"). Every kind turns up by the fifth tier.
local SPAWN: { { { any } } } = {
	{ { "tidepool", 1 }, { "tallgrass", 3 } },
	{ { "bog", 6 }, { "tidepool", 8 }, { "volcano", 10 } },
	{ { "cave", 13 }, { "tallgrass", 15 }, { "frostpeak", 17 } },
	{ { "bluff", 20 }, { "coralpool", 23 }, { "volcano", 26 } },
	{ { "ruins", 29 }, { "cave", 32 }, { "frostpeak", 35 } },
	{ { "coralpool", 38 }, { "bluff", 41 }, { "ruins", 45 } },
}

local Sites = {}
Sites.list = LIST
Sites.byId = byId
Sites.byIslet = byIslet
Sites.SPAWN = SPAWN

-- The piece ids of a place: wild, and cleared.
function Sites.wildId(id: string): string
	return "wild_" .. id
end
function Sites.doneId(id: string): string
	return "done_" .. id
end

-- The place a piece id is (or nil), and whether it is still wild.
function Sites.of(pieceId: string): (SiteDef?, boolean)
	local pre, key = string.match(pieceId, "^(%a+)_(%a+)$")
	if pre == "wild" or pre == "done" then
		local d = byId[key :: string]
		if d then
			return d, pre == "wild"
		end
	end
	return nil, false
end

-- What spawns at a tier (none past the last).
function Sites.spawnAt(tier: number): { { id: string, lvl: number } }
	local out: { { id: string, lvl: number } } = {}
	local row: { { any } } = SPAWN[tier] or {}
	for _, e in row do
		table.insert(out, { id = e[1] :: string, lvl = e[2] :: number })
	end
	return out
end

return Sites
