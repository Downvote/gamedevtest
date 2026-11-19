--!strict
-- What makes one driftling unlike another (GAME_DESIGN 6: "make each creature have a different passive ability. some
-- can have different mutations which allow them to do different things better ... mutations also have tiers, so a
-- rarer mutation gives better benefits"; since 2026-11-12 "creatures work faster based on their rarity and can also
-- have mutations like before"). Pure.
--   Effects (`Fx`): at work, a share added to its help (work: every workplace alike since the request of 2026-11-19,
--   "remove work building types. They all now fall in the same category of work ... Passives and mutations that have
--   different work building types now are just one"); sell (its price when sold); charm (charm it adds to the island,
--   whole points); and while it lives in a hut, for the whole island: luck (its eggs that much luckier), cost (its eggs
--   cost that much less: below 0 cheaper), hatch (the Hatcheries' eggs that much sooner; several multiply, so each
--   more counts for less: Logic/Island.isle), boost (the boost buildings' boost that much stronger) and charmPct (the
--   island's charm that much more, as a share). 0.1 = +10%. (A `tree` share, the next eggs sooner, went on 2026-11-14:
--   "remove anything that decreases the tree of life refresh, keep it at 10 minutes throughout the whole game unless a
--   gamepass is bought". Each passive's became that much luck.)
--   The wondrous mutations (tier 5, the request of 2026-11-19: "add a higher, rarer tier of mutations which provide
--   strong and unique buffs"): each its own family, one tier, with an effect nothing else gives, for the whole island
--   while it lives in a hut: all (every shell the island makes), aura (every driftling at work), eggs (more eggs in
--   each of the tree's lots), skip (an egg hatching a rarity higher more often) and away (offline earnings).
--   Logic/Island.isle adds the island's up, each to its cap (Tuning.IsleCap).
--   Each species has a passive of its own (Data/Creatures `passive`); each driftling may carry up to MAX mutations
--   (Pal.muts: ids "<family><tier>", tier 1 .. 4, a wondrous one's "<family>5", or a flaw's id), rolled when it hatches.
--   Rarity (Data/Creatures `rarity`): 1 common .. 7 celestial (RMAX): the tree lays rarer eggs less often, they cost
--   more, and what hatches works faster (Tuning.RarityWork), sells for more and rolls better mutations.
export type Fx = { [string]: number }

export type Mutation = { id: string, family: string, tier: number, name: string, blurb: string, fx: Fx }
export type Rarity = { name: string, color: string, weight: number }

local Traits = {}

Traits.MAX = 4 -- mutations a driftling carries at most
Traits.TOP = 5 -- the highest tier (the wondrous ones)
-- every effect, in the order the panels list them
Traits.KEYS = { "work", "aura", "all", "hatch", "boost", "charmPct", "charm", "luck", "skip", "eggs", "away", "cost", "sell" }
-- the effects a driftling gives the whole island while it lives in a hut (Logic/Island.isle)
Traits.ISLE = { "luck", "cost", "hatch", "boost", "charmPct", "all", "aura", "eggs", "skip", "away" }

-- The rarities: their names, colours (UIKit / Palette keys) and how often the tree lays each (weights, before luck).
Traits.RARITY = {
	{ name = "Common", color = "text_dim", weight = 100 },
	{ name = "Uncommon", color = "good", weight = 45 },
	{ name = "Rare", color = "button", weight = 16 },
	{ name = "Epic", color = "purple", weight = 5 },
	{ name = "Legendary", color = "accent", weight = 1.2 },
	{ name = "Mythic", color = "mythic", weight = 0.02 },
	{ name = "Celestial", color = "celestial", weight = 0.002 },
} :: { Rarity }
Traits.RMAX = #Traits.RARITY -- the rarest (every table by rarity has this many entries)

-- A mutation's tier: its name's colour (UIKit) and how often a roll lands on it (flaws are tier 0).
Traits.TIER_COLOR = { [0] = "bad", [1] = "text", [2] = "good", [3] = "button", [4] = "accent", [5] = "mythic" } :: { [number]: string }
Traits.TIER_NAME = { [0] = "Flaw", [1] = "Tier 1", [2] = "Tier 2", [3] = "Tier 3", [4] = "Tier 4", [5] = "Wondrous" } :: { [number]: string }

-- The families: what each tier is called and gives (rarer tiers give much more). The family ids are the saves' (they
-- date from the fights, gone 2026-11-12: each family that gave a fighting stat gives something on the island now).
-- The three that helped at one kind of work (grower farms, chopper wood, trader shops) give the request of
-- 2026-11-19's new effects since then, keeping their ids so a saved driftling keeps its tier: "make mutations that
-- decrease hatchery time, with diminishing returns if stacked. Make mutations ... to boost boost buildings. Make
-- mutations ... to give a percentage boost to charm".
local FAMILIES: { { family: string, key: string, names: { string }, values: { number } } } = {
	{ family = "sturdy", key = "cost", names = { "Thrifty", "Frugal", "Modest", "Selfless" }, values = { -0.15, -0.3, -0.5, -0.8 } },
	{ family = "fierce", key = "sell", names = { "Shiny", "Glossy", "Golden", "Radiant" }, values = { 0.3, 0.7, 1.5, 3 } },
	{ family = "armor", key = "charm", names = { "Cute", "Sweet", "Adorable", "Beloved" }, values = { 1, 2, 3, 5 } },
	{ family = "bright", key = "luck", names = { "Lucky", "Blessed", "Fortunate", "Starborn" }, values = { 0.05, 0.1, 0.18, 0.3 } },
	{ family = "busy", key = "work", names = { "Busy", "Diligent", "Tireless", "Workaholic" }, values = { 0.12, 0.24, 0.4, 0.65 } },
	{ family = "grower", key = "hatch", names = { "Cozy", "Broody", "Nesting", "Egg Keeper" }, values = { 0.06, 0.12, 0.2, 0.3 } },
	{ family = "chopper", key = "boost", names = { "Handy", "Tinkerer", "Foreman", "Master Builder" }, values = { 0.06, 0.12, 0.2, 0.32 } },
	{ family = "trader", key = "charmPct", names = { "Charming", "Darling", "Dazzling", "Enchanting" }, values = { 0.04, 0.08, 0.14, 0.22 } },
}
-- The weather's families (GAME_DESIGN 13: "also, make weather and seasons, and eggs spawns are affected by these with
-- different mutations"): an egg the Tree of Life laid in a weather may be touched by it (Logic/Weather.touch) and
-- hatches with that weather's mutation. They never come from a plain roll (`roll` keeps to FAMILIES), only from the
-- weather (a Hatchery passes one on and tiers it up like any other). Rain's, haze's and the falling leaves' helped at
-- one kind of work till 2026-11-19 (farms, shops, wood): they shorten the Hatcheries' eggs, raise charm and the boost
-- buildings since.
local WEATHER_FAMILIES: { { family: string, key: string, names: { string }, values: { number }, weather: string } } = {
	{ family = "rainy", weather = "rain", key = "hatch", names = { "Drizzly", "Rainkissed", "Downpour", "Monsoon" }, values = { 0.05, 0.1, 0.17, 0.26 } },
	-- (snow's helped at fishing until 2026-11-14: fishing went into the farms, so it helps a little at any work)
	{ family = "frosty", weather = "snow", key = "work", names = { "Chilly", "Frosty", "Snowbound", "Glacial" }, values = { 0.08, 0.16, 0.27, 0.42 } },
	{ family = "sunny", weather = "haze", key = "charmPct", names = { "Warm", "Sunbaked", "Sunkissed", "Midsummer" }, values = { 0.04, 0.08, 0.14, 0.22 } },
	{ family = "bloomy", weather = "blossom", key = "charm", names = { "Budding", "Petalled", "Flowering", "Springborn" }, values = { 1, 2, 3, 5 } },
	{ family = "autumn", weather = "leaves", key = "boost", names = { "Russet", "Amber", "Copper", "Goldleaf" }, values = { 0.05, 0.1, 0.17, 0.27 } },
	-- (fog's brought the tree's eggs sooner until 2026-11-14: the tree keeps its time now, so it helps the price)
	{ family = "misty", weather = "fog", key = "sell", names = { "Misty", "Foggy", "Veiled", "Phantom" }, values = { 0.2, 0.45, 0.9, 1.8 } },
	{ family = "stormy", weather = "storm", key = "luck", names = { "Gusty", "Stormborn", "Thunderous", "Tempest" }, values = { 0.06, 0.12, 0.2, 0.32 } },
}
-- The wondrous mutations (tier 5): rolled very seldom (TIER_W's last weight, a little more for a rarer egg), never a
-- flaw, never from the weather. A Hatchery passes one on first, being the highest tier.
local WONDERS: { { family: string, name: string, fx: Fx } } = {
	{ family = "golden", name = "Goldtouched", fx = { all = 0.15 } },
	{ family = "maestro", name = "Maestro", fx = { aura = 0.1 } },
	{ family = "twin", name = "Twinborn", fx = { eggs = 1 } },
	{ family = "prism", name = "Prismatic", fx = { skip = 0.06 } },
	{ family = "dream", name = "Dreamer", fx = { away = 0.5 } },
	{ family = "heart", name = "Heartsong", fx = { charmPct = 0.3, charm = 8 } },
}

-- The flaws (tier 0): a driftling can be born a little worse at something. A flaw belongs to the family of the same
-- effect (a driftling is Lazy or Diligent, never both; a Hatchery turns a flaw both parents carry into its family's
-- first tier).
local FLAWS: { { id: string, family: string, name: string, key: string, value: number } } = {
	{ id = "frail", family = "sturdy", name = "Greedy", key = "cost", value = 0.25 },
	{ id = "timid", family = "fierce", name = "Dull", key = "sell", value = -0.2 },
	{ id = "clumsy", family = "armor", name = "Grumpy", key = "charm", value = -1 },
	{ id = "sluggish", family = "busy", name = "Sluggish", key = "work", value = -0.08 },
	{ id = "lazy", family = "busy", name = "Lazy", key = "work", value = -0.15 },
}

local LIST: { Mutation } = {}
local BY_ID: { [string]: Mutation } = {}
for _, f in FAMILIES do
	for tier = 1, 4 do
		local m: Mutation = {
			id = f.family .. tier,
			family = f.family,
			tier = tier,
			name = f.names[tier],
			blurb = "", -- (its effect's words: below)
			fx = { [f.key] = f.values[tier] },
		}
		table.insert(LIST, m)
		BY_ID[m.id] = m
	end
end
for _, f in WEATHER_FAMILIES do
	for tier = 1, 4 do
		local m: Mutation = { id = f.family .. tier, family = f.family, tier = tier, name = f.names[tier], blurb = "", fx = { [f.key] = f.values[tier] } }
		table.insert(LIST, m)
		BY_ID[m.id] = m
	end
end
for _, f in WONDERS do
	local m: Mutation = { id = f.family .. "5", family = f.family, tier = 5, name = f.name, blurb = "", fx = f.fx }
	table.insert(LIST, m)
	BY_ID[m.id] = m
end
for _, f in FLAWS do
	local m: Mutation = { id = f.id, family = f.family, tier = 0, name = f.name, blurb = "", fx = { [f.key] = f.value } }
	table.insert(LIST, m)
	BY_ID[m.id] = m
end
Traits.list = LIST
Traits.byId = BY_ID
Traits.families = FAMILIES
Traits.weather = WEATHER_FAMILIES -- (the weather's families: Data/Weather, Logic/Weather)
Traits.wonders = WONDERS

-- A family's mutation at a tier ("sturdy", 3 -> "sturdy3"), clamped to 1 .. 4 (a wondrous family's is always its own,
-- tier 5).
function Traits.at(family: string, tier: number): string
	local w = BY_ID[family .. "5"]
	if w then
		return w.id
	end
	return family .. math.clamp(math.floor(tier), 1, 4)
end

-- How many mutations a new driftling rolls and how good they are: weights by count (0 .. 3) and by tier (flaw, 1 .. 4,
-- wondrous); a rarer species rolls a little better (WONDER_UP more of the wondrous tier a rarity step).
local COUNT_W = { 34, 36, 22, 8 }
local TIER_W = { 16, 46, 25, 10, 3, 0.25 }
local WONDER_UP = 0.15

local FAMILY_IDS: { string } = {}
for _, f in FAMILIES do
	table.insert(FAMILY_IDS, f.family)
end

-- (the island's lean on a new mutation's family, from its kinds of work building, went with the kinds on 2026-11-19)

-- Mutations for a new driftling of a rarity (1 .. 5; a bigger island may roll it as a rarer one), no family twice.
function Traits.roll(rng: any, rarity: number): { string }
	local r = math.clamp(rarity or 1, 1, Traits.RMAX)
	local function pickW(ws: { number }): number
		local total = 0
		for _, w in ws do
			total += w
		end
		local x = rng:next() * total
		for i, w in ws do
			x -= w
			if x <= 0 then
				return i
			end
		end
		return #ws
	end
	local count = pickW(COUNT_W) - 1
	local tw = table.clone(TIER_W)
	-- a rarer species: fewer flaws, more of the top tiers
	tw[1] = math.max(4, tw[1] - (r - 1) * 3)
	tw[4] += (r - 1) * 2
	tw[5] += (r - 1) * 1.2
	tw[6] += (r - 1) * WONDER_UP
	local out: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, count do
		local t = pickW(tw) - 1
		local id: string
		if t == 0 then
			id = FLAWS[rng:int(1, #FLAWS)].id
		elseif t == 5 then
			id = WONDERS[rng:int(1, #WONDERS)].family .. "5"
		else
			id = FAMILY_IDS[rng:int(1, #FAMILY_IDS)] .. t
		end
		local m = BY_ID[id]
		if m and not used[m.family] then
			used[m.family] = true
			table.insert(out, id)
		end
	end
	return out
end

-- The effects of a passive and a list of mutations together (each key summed).
function Traits.sum(passive: Fx?, muts: { string }?): Fx
	local out: Fx = {}
	if passive then
		for k, v in passive do
			out[k] = (out[k] or 0) + v
		end
	end
	local list: { string } = muts or {}
	for _, id in list do
		local m = BY_ID[id]
		if m then
			for k, v in m.fx do
				out[k] = (out[k] or 0) + v
			end
		end
	end
	return out
end

-- What a driftling adds at work (its work share), never below -50%.
function Traits.work(fx: Fx): number
	return math.max(-0.5, fx.work or 0)
end

-- Families that went, and the family a saved one of theirs becomes (the Angler family helped at fishing: since
-- 2026-11-19 every workplace is one kind of work, so an Angler is Busy of the same tier; the Leafy family brought the
-- tree's eggs sooner: since 2026-11-14 the tree keeps its time, so a Leafy one is Lucky of the same tier).
local RENAMED: { [string]: string } = { angler = "busy", swift = "bright" }
local function renamed(id: string): string
	local fam, tier = string.match(id, "^(%a+)(%d)$")
	local to = if fam then RENAMED[fam] else nil
	return if to and tier then to .. tier else id
end
Traits.renamed = renamed

-- Keep only known mutations, no family twice, at most MAX (a save's or a payload's list; a renamed family's id becomes
-- its new family's).
function Traits.clean(muts: any): { string }
	local out: { string } = {}
	local used: { [string]: boolean } = {}
	if type(muts) ~= "table" then
		return out
	end
	for _, id in muts do
		local m = if type(id) == "string" then BY_ID[renamed(id)] else nil
		if m and not used[m.family] and #out < Traits.MAX then
			used[m.family] = true
			table.insert(out, m.id)
		end
	end
	return out
end

-- An effect's words for the panels ("+24% work", "eggs cost 30% less", "+2 charm", "Hatchery 12% faster").
local WORDS: { [string]: string } = {
	work = "work",
	aura = "work for all",
	all = "all shells",
	boost = "boost buildings",
	charmPct = "charm",
	sell = "sell price",
	luck = "egg luck",
	skip = "rarer hatch chance",
	away = "offline shells",
}
local function pct(v: number): string
	local x = math.abs(v) * 100
	return if math.abs(x - math.round(x)) < 0.05 then tostring(math.round(x)) else string.format("%.1f", x)
end
function Traits.describe(fx: Fx): string
	local parts: { string } = {}
	for _, k in Traits.KEYS do
		local v = fx[k]
		if v and math.abs(v) > 1e-6 then
			if k == "cost" then
				table.insert(parts, string.format("eggs cost %s%% %s", pct(v), if v < 0 then "less" else "more"))
			elseif k == "charm" then
				table.insert(parts, string.format("%s%d charm", if v > 0 then "+" else "", math.round(v)))
			elseif k == "hatch" then
				table.insert(parts, string.format("Hatchery %s%% %s", pct(v), if v > 0 then "faster" else "slower"))
			elseif k == "eggs" then
				table.insert(parts, string.format("%s%d egg%s per lot", if v > 0 then "+" else "", math.round(v), if math.abs(math.round(v)) == 1 then "" else "s"))
			else
				table.insert(parts, string.format("%s%s%% %s", if v > 0 then "+" else "-", pct(v), WORDS[k] or k))
			end
		end
	end
	return table.concat(parts, ", ")
end
for _, m in LIST do
	m.blurb = Traits.describe(m.fx)
end

return table.freeze(Traits)
