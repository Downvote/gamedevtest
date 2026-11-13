--!strict
-- What makes one driftling unlike another (GAME_DESIGN 6: "make each creature have a different passive ability. some
-- can have different mutations which allow them to do different things better ... mutations also have tiers, so a
-- rarer mutation gives better benefits"; since 2026-11-12 "creatures work faster based on their rarity and can also
-- have mutations like before"). Pure.
--   Effects (`Fx`): at work, shares added to its help: work (any building), farm, fish, wood, shop (the buildings of
--   that knack); sell (its price when sold); charm (charm it adds to the island, whole points); and while it lives in
--   a hut, for the whole island: tree (the Tree of Life lays its next eggs that much sooner), luck (its eggs that much
--   luckier) and cost (its eggs cost that much less: below 0 cheaper). 0.1 = +10%.
--   Each species has a passive of its own (Data/Creatures `passive`); each driftling may carry up to MAX mutations
--   (Pal.muts: ids "<family><tier>", tier 1 .. 4, or a flaw's id), rolled when it hatches.
--   Rarity (Data/Creatures `rarity`): 1 common .. 5 legendary: the tree lays rarer eggs less often, they cost more,
--   and what hatches works faster (Tuning.RarityWork), sells for more and rolls better mutations.
export type Fx = { [string]: number }

export type Mutation = { id: string, family: string, tier: number, name: string, blurb: string, fx: Fx }
export type Rarity = { name: string, color: string, weight: number }

local Traits = {}

Traits.MAX = 4 -- mutations a driftling carries at most
Traits.KEYS = { "work", "farm", "fish", "wood", "shop", "cost", "sell", "charm", "tree", "luck" }

-- The rarities: their names, colours (UIKit / Palette keys) and how often the tree lays each (weights, before luck).
Traits.RARITY = {
	{ name = "Common", color = "text_dim", weight = 100 },
	{ name = "Uncommon", color = "good", weight = 45 },
	{ name = "Rare", color = "button", weight = 16 },
	{ name = "Epic", color = "purple", weight = 5 },
	{ name = "Legendary", color = "accent", weight = 1.2 },
} :: { Rarity }

-- A mutation's tier: its name's colour (UIKit) and how often a roll lands on it (flaws are tier 0).
Traits.TIER_COLOR = { [0] = "bad", [1] = "text", [2] = "good", [3] = "button", [4] = "accent" } :: { [number]: string }
Traits.TIER_STARS = { [0] = "", [1] = "*", [2] = "**", [3] = "***", [4] = "****" } :: { [number]: string }

-- The families: what each tier is called and gives (rarer tiers give much more). The family ids are the saves' (they
-- date from the fights, gone 2026-11-12: each family that gave a fighting stat gives something on the island now).
local FAMILIES: { { family: string, key: string, names: { string }, values: { number } } } = {
	{ family = "sturdy", key = "cost", names = { "Thrifty", "Frugal", "Modest", "Selfless" }, values = { -0.15, -0.3, -0.5, -0.8 } },
	{ family = "fierce", key = "sell", names = { "Shiny", "Glossy", "Golden", "Radiant" }, values = { 0.3, 0.7, 1.5, 3 } },
	{ family = "armor", key = "charm", names = { "Cute", "Sweet", "Adorable", "Beloved" }, values = { 1, 2, 3, 5 } },
	{ family = "swift", key = "tree", names = { "Leafy", "Blooming", "Lush", "Evergreen" }, values = { 0.04, 0.08, 0.14, 0.22 } },
	{ family = "bright", key = "luck", names = { "Lucky", "Blessed", "Fortunate", "Starborn" }, values = { 0.05, 0.1, 0.18, 0.3 } },
	{ family = "busy", key = "work", names = { "Busy", "Diligent", "Tireless", "Workaholic" }, values = { 0.08, 0.15, 0.25, 0.4 } },
	{ family = "grower", key = "farm", names = { "Green Thumb", "Grower", "Harvester", "Bountiful" }, values = { 0.12, 0.24, 0.4, 0.65 } },
	{ family = "angler", key = "fish", names = { "Angler", "Netcaster", "Tidecaller", "Sea Sage" }, values = { 0.12, 0.24, 0.4, 0.65 } },
	{ family = "chopper", key = "wood", names = { "Chopper", "Woodsy", "Timberwise", "Forest Heart" }, values = { 0.12, 0.24, 0.4, 0.65 } },
	{ family = "trader", key = "shop", names = { "Chatty", "Smooth Talker", "Haggler", "Tycoon" }, values = { 0.12, 0.24, 0.4, 0.65 } },
}
-- The flaws (tier 0): a driftling can be born a little worse at something. A flaw belongs to the family of the same
-- effect (a driftling is Lazy or Diligent, never both; a Hatchery tier-up turns a flaw into its family's first tier).
local FLAWS: { { id: string, family: string, name: string, key: string, value: number } } = {
	{ id = "frail", family = "sturdy", name = "Greedy", key = "cost", value = 0.25 },
	{ id = "timid", family = "fierce", name = "Dull", key = "sell", value = -0.2 },
	{ id = "clumsy", family = "armor", name = "Grumpy", key = "charm", value = -1 },
	{ id = "sluggish", family = "swift", name = "Sluggish", key = "work", value = -0.08 },
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
for _, f in FLAWS do
	local m: Mutation = { id = f.id, family = f.family, tier = 0, name = f.name, blurb = "", fx = { [f.key] = f.value } }
	table.insert(LIST, m)
	BY_ID[m.id] = m
end
Traits.list = LIST
Traits.byId = BY_ID
Traits.families = FAMILIES

-- A family's mutation at a tier ("sturdy", 3 -> "sturdy3"), clamped to 1 .. 4.
function Traits.at(family: string, tier: number): string
	return family .. math.clamp(math.floor(tier), 1, 4)
end

-- How many mutations a new driftling rolls and how good they are: weights by count (0 .. 3) and by tier (flaw, 1 .. 4);
-- a rarer species rolls a little better.
local COUNT_W = { 34, 36, 22, 8 }
local TIER_W = { 16, 46, 25, 10, 3 }

-- Mutations for a new driftling of a rarity (1 .. 5; a bigger island may roll it as a rarer one), no family twice.
function Traits.roll(rng: any, rarity: number): { string }
	local r = math.clamp(rarity or 1, 1, 5)
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
	local out: { string } = {}
	local used: { [string]: boolean } = {}
	for _ = 1, count do
		local t = pickW(tw) - 1
		local id: string
		if t == 0 then
			id = FLAWS[rng:int(1, #FLAWS)].id
		else
			id = FAMILIES[rng:int(1, #FAMILIES)].family .. t
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

-- What a driftling adds at a building of a knack (work + that knack's share), never below -50%.
function Traits.workAt(fx: Fx, knack: string): number
	return math.max(-0.5, (fx.work or 0) + (fx[knack] or 0))
end

-- Keep only known mutations, no family twice, at most MAX (a save's or a payload's list).
function Traits.clean(muts: any): { string }
	local out: { string } = {}
	local used: { [string]: boolean } = {}
	if type(muts) ~= "table" then
		return out
	end
	for _, id in muts do
		local m = if type(id) == "string" then BY_ID[id] else nil
		if m and not used[m.family] and #out < Traits.MAX then
			used[m.family] = true
			table.insert(out, id)
		end
	end
	return out
end

-- An effect's words for the panels ("+24% at farms", "eggs cost 30% less", "eggs 8% sooner", "+2 charm").
local WORDS: { [string]: string } = {
	work = "work",
	farm = "at farms",
	fish = "at fishing",
	wood = "at wood",
	shop = "at shops",
	sell = "sell price",
	luck = "egg luck",
}
function Traits.describe(fx: Fx): string
	local parts: { string } = {}
	for _, k in Traits.KEYS do
		local v = fx[k]
		if v and math.abs(v) > 1e-6 then
			if k == "cost" then
				table.insert(parts, string.format("eggs cost %d%% %s", math.round(math.abs(v) * 100), if v < 0 then "less" else "more"))
			elseif k == "tree" then
				table.insert(parts, string.format("eggs %d%% %s", math.round(math.abs(v) * 100), if v > 0 then "sooner" else "later"))
			elseif k == "charm" then
				table.insert(parts, string.format("%s%d charm", if v > 0 then "+" else "", math.round(v)))
			else
				table.insert(parts, string.format("%s%d%% %s", if v > 0 then "+" else "", math.round(v * 100), WORDS[k]))
			end
		end
	end
	return table.concat(parts, ", ")
end
for _, m in LIST do
	m.blurb = Traits.describe(m.fx)
end

return table.freeze(Traits)
