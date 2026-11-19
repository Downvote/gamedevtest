--!strict
-- What can stand on an island (GAME_DESIGN 4): buildings that make shells, huts for the driftlings (who do all the
-- work: no villagers since 2026-11-12), and decor for charm. Pure. Each piece is paid for in shells when it is placed
-- (the request of 2026-11-14: "make shells the main currency, allowing you to buy decor and expansions with it. remove
-- wood as a currency": the prices that were wood are shells now, one for one), may be placed as often as the island's
-- piece limit allows (Logic/Plot), and is built by Models/DecorModels. w x d: its footprint in whole studs facing south (a quarter turn
-- swaps them).
--   kind:  "work" (a workplace: it makes shells with driftlings working there; farms, wood buildings and shops were
--          three kinds, the Work tab's three groups, till the request of 2026-11-19: "remove work building types.
--          They all now fall in the same category of work")
--          | "nest" (a driftlings' hut) | "breed" (the Hatchery: two driftlings make an egg, Logic/Breed) | "gen" (a
--          boost building: every workplace makes more) | "path" (a 2 x 2 tile of path or road: drawn, apart
--          from the piece limit with the water, Tuning.PathPieces) | "water" (a 2 x 2 tile of water: drawn, for rivers
--          and ponds; GAME_DESIGN 4: "add the ability to add water to make rivers") | "fence" (a 2-stud length of fence
--          along a grid line: drawn, apart, Tuning.FencePieces; w 2, d 0) | "decor" (nature, themed decor and the
--          things to do, seats and lights: Build mode's Nature, Decor, Fun and Water tabs) | "tree" (the Tree of Life:
--          every island's, never bought)
--   rate:  the shells it makes a turn with one common driftling working there (Logic/Island). The wood buildings made
--          wood until 2026-11-14; selling it, they make about what a farm of the same price makes (the Lumber Camp 36,
--          the Sawmill 130, Timber Works 240, the Bamboo Grove 440, the Grand Mill 880)
--   act:   how its workers look at work (Controllers/WorldView: "farm" tends and harvests, "wood" chops, "shop"
--          serves) and its icon in the work picker; nothing else tells workplaces apart
--   slots: the driftlings a hut houses (its room). Since the request of 2026-11-19 ("after an expansion, buff huts
--          and work buildings such that buying 2 huts and 2 work buildings of the highest tier is enough to fill the
--          cap, assuming you also maxxed out the caps before expanding") the newest hut an island has holds half of
--          what its tier adds to the housing limit (Tuning.HousingLimit), and its listed price grew with its room, so
--          a driftling's place in it costs what it did
--   jobs:  the driftlings a workplace takes: Tuning.WorkRoom at its tier (the request of 2026-11-18,
--          "increase the capacity of work buildings by alot": 2 everywhere before; since 2026-11-19 as many as the
--          newest hut holds, so two of the newest workplaces fill what a tier adds to the work cap); all of them
--          together stay within the island's work cap (Logic/Plot.workLimit, its driftling limit). The Grand Vineyard
--          opens at tier 20 since then (19 before), with the Driftling Citadel, so the last tier has a workplace too
--   charm: what it adds to the island's charm (more charm, more shells: Logic/Island.charmBonus). A decor piece's
--          is 0 here: on an island it is its footprint's tiles times Tuning.DecorCharm at the island's tier, the
--          same for every piece (`charmOf`; the requests of 2026-11-19: "make decor all give the same amount of
--          charm, scaling based on their size instead", "make it such that the charm they give scale off expansions
--          as well"), so every decor piece's charm grows when the island does
--   comfort: a hut's share added to its residents' work (Logic/Island.homes)
--   boostBy: a boost building's share, for every workplace (each kind of boost building gives its whole share, a
--          second of its kind Tuning.BoostStack of it, a third that of the second's: Logic/Island.boost). The ones for
--          one kind of work boost everything since the request of 2026-11-19 ("All boost buildings should also just
--          boost everything instead"), at a little over half their old share
--   tier:  the island tier it needs
--   tab / sub: where Build mode lists it (its tab, and the row of chips under it: a decor piece's theme, a nature
--          piece's kind); from its kind when not given
--   water: "" | "over" (may stand over water tiles too: bridges, a dock, a waterwheel) | "on" (only on water tiles:
--          lily pads, reeds, a rowboat)
--   feel:  how putting it down looks and sounds (Build mode's effects: "wood" "stone" "plant" "water" "metal" "magic"
--          "sand" "snow" "cloth" "fire")
local Tuning = require(script.Parent.Parent.Config.Tuning)

export type BuildingDef = {
	id: string,
	name: string,
	kind: string,
	shells: number, -- its price
	w: number,
	d: number,
	rate: number,
	act: string,
	slots: number,
	jobs: number,
	charm: number,
	comfort: number,
	boostBy: number,
	tier: number,
	blurb: string,
	tab: string,
	sub: string,
	water: string,
	feel: string,
}

-- A kind's tab, chip row and feel when a piece doesn't give its own.
local TAB: { [string]: string } = { work = "work", gen = "work", nest = "nest", breed = "nest", path = "path", water = "water", fence = "fence", decor = "decor", tree = "" }
local SUB: { [string]: string } = { work = "work", gen = "gen", water = "tiles" }
local FEEL: { [string]: string } = { path = "stone", water = "water", fence = "wood" }

-- A wood price in shells for a piece of a tier (Tuning.WoodShells for each wood, times WoodTierUp for each tier past the
-- second up to WoodTierTop), to two figures (1 at least; nothing stays nothing).
local function shellsFor(wood: number, tier: number): number
	if wood <= 0 then
		return 0
	end
	local w = wood * Tuning.WoodShells * Tuning.WoodTierUp ^ math.clamp(tier - 2, 0, Tuning.WoodTierTop - 2)
	local step = 10 ^ math.max(0, math.floor(math.log10(w)) - 1)
	return math.max(1, math.floor(w / step + 0.5) * step)
end

-- A piece's price in shells: its listed price (the wood it cost) in shells, a Work or Huts tab building's
-- Tuning.BuildingPrice of that, to two figures (5 at least).
local function priceOf(kind: string, listed: number, tier: number): number
	local tab = TAB[kind]
	if listed <= 0 or (tab ~= "work" and tab ~= "nest") then
		return shellsFor(listed, tier)
	end
	local w = listed * Tuning.BuildingPrice
	local step = 10 ^ math.max(0, math.floor(math.log10(w)) - 1)
	return shellsFor(math.max(5, math.floor(w / step + 0.5) * step), tier)
end

local function B(t: { [string]: any }): BuildingDef
	local works = t.kind == "work"
	local jobs = if works then Tuning.WorkRoom[math.clamp(t.tier or 1, 1, #Tuning.WorkRoom)] else 0
	return {
		id = t.id,
		name = t.name,
		kind = t.kind,
		-- (a workplace's listed price was for 2 places: times its places over 2, so a place at work costs what it did)
		shells = priceOf(t.kind, (t.shells or 0) * (if works then jobs / 2 else 1), t.tier or 1),
		w = t.w,
		d = t.d,
		rate = t.rate or 0,
		act = t.act or "",
		slots = t.slots or 0,
		jobs = jobs,
		-- (decor: none of its own, `charmOf`)
		charm = if t.kind == "decor" then 0 else t.charm or 0,
		comfort = t.comfort or 0,
		boostBy = t.boostBy or 0,
		tier = t.tier or 1,
		blurb = t.blurb or "",
		tab = t.tab or TAB[t.kind] or "decor",
		sub = t.sub or SUB[t.kind] or "",
		water = t.water or "",
		feel = t.feel or FEEL[t.kind] or (if t.act == "farm" then "plant" else "wood"),
	}
end

-- stylua: ignore start
local LIST: { BuildingDef } = {
	-- farms: they sell what they grow or catch (shells)
	B({ id = "patch", name = "Veggie Patch", kind = "work", act = "farm", shells = 40, w = 3, d = 3, rate = 36, charm = 1, blurb = "Veggies to sell." }),
	B({ id = "pier", name = "Fishing Pier", kind = "work", act = "farm", shells = 160, w = 3, d = 3, rate = 60, charm = 1, blurb = "Fresh fish off the line." }),
	B({ id = "orchard", name = "Fruit Orchard", kind = "work", act = "farm", shells = 460, w = 4, d = 4, rate = 102, charm = 3, tier = 2, blurb = "Trees heavy with fruit." }),
	B({ id = "greenhouse", name = "Greenhouse", kind = "work", act = "farm", shells = 2900, w = 4, d = 3, rate = 240, charm = 4, tier = 3, blurb = "Grows all year round." }),
	B({ id = "paddy", name = "Rice Terrace", kind = "work", act = "farm", shells = 9800, w = 4, d = 4, rate = 510, charm = 5, tier = 4, blurb = "Rice on flooded steps." }),
	B({ id = "kelpfarm", name = "Kelp Farm", kind = "work", act = "farm", shells = 28000, w = 4, d = 4, rate = 990, charm = 6, tier = 5, blurb = "Kelp in a sea pen." }),
	B({ id = "skygarden", name = "Sky Garden", kind = "work", act = "farm", shells = 76000, w = 5, d = 4, rate = 1800, charm = 12, tier = 6, blurb = "A glass tower of gardens." }),
	-- (the islands past Driftling Haven, the request of 2026-11-14: "allow expansion up to level 20 ... add decor, huts, work buildings")
	B({ id = "shroomcellar", name = "Mushroom Cellar", kind = "work", act = "farm", shells = 200000, w = 4, d = 4, rate = 3300, charm = 10, tier = 11, blurb = "Mushrooms in the dark." }),
	B({ id = "pearlbeds", name = "Pearl Beds", kind = "work", act = "farm", shells = 520000, w = 5, d = 4, rate = 5800, charm = 14, tier = 13, blurb = "Some oysters hold a pearl." }),
	B({ id = "honeyterrace", name = "Honey Terraces", kind = "work", act = "farm", shells = 1500000, w = 5, d = 5, rate = 10500, charm = 18, tier = 16, blurb = "Hives among the flowers." }),
	B({ id = "vineyard", name = "Grand Vineyard", kind = "work", act = "farm", shells = 4200000, w = 5, d = 5, rate = 19000, charm = 22, tier = 20, blurb = "Grapes by the barrel." }),
	-- wood
	B({ id = "lumber", name = "Lumber Camp", kind = "work", act = "wood", shells = 70, w = 4, d = 3, rate = 36, blurb = "Logs, chopped and sold." }),
	B({ id = "sawmill", name = "Sawmill", kind = "work", act = "wood", shells = 640, w = 4, d = 4, rate = 130, charm = 1, tier = 2, blurb = "Logs in, planks out." }),
	B({ id = "timber", name = "Timber Works", kind = "work", act = "wood", shells = 2900, w = 4, d = 4, rate = 240, charm = 2, tier = 3, blurb = "Planks stacked high." }),
	B({ id = "bamboo", name = "Bamboo Grove", kind = "work", act = "wood", shells = 8300, w = 4, d = 3, rate = 440, charm = 4, tier = 4, blurb = "Grows back by the day." }),
	B({ id = "grandmill", name = "Grand Mill", kind = "work", act = "wood", shells = 25000, w = 5, d = 4, rate = 880, charm = 6, tier = 5, blurb = "A waterwheel turns its saws." }),
	-- (the islands past Driftling Haven, the request of 2026-11-14: "allow expansion up to level 20 ... add decor, huts, work buildings")
	B({ id = "logflume", name = "Log Flume", kind = "work", act = "wood", shells = 260000, w = 5, d = 4, rate = 900, charm = 8, tier = 11, blurb = "Logs ride the chute down." }),
	B({ id = "ironwood", name = "Ironwood Yard", kind = "work", act = "wood", shells = 800000, w = 5, d = 5, rate = 1700, charm = 10, tier = 14, blurb = "Wood as hard as stone." }),
	B({ id = "canopymill", name = "Canopy Mill", kind = "work", act = "wood", shells = 2200000, w = 5, d = 5, rate = 3200, charm = 14, tier = 17, blurb = "Saws up in the treetops." }),
	-- shops: snacks, meals and rooms (shells)
	B({ id = "stall", name = "Snack Stall", kind = "work", act = "shop", shells = 100, w = 3, d = 2, rate = 36, charm = 2, blurb = "Snacks by the path." }),
	B({ id = "cafe", name = "Beach Cafe", kind = "work", act = "shop", shells = 990, w = 4, d = 3, rate = 120, charm = 5, tier = 2, blurb = "Iced drinks and a bite." }),
	B({ id = "inn", name = "Seaside Inn", kind = "work", act = "shop", shells = 5700, w = 5, d = 4, rate = 340, charm = 10, tier = 3, blurb = "Rooms with a sea view." }),
	B({ id = "bakery", name = "Bakery", kind = "work", act = "shop", shells = 15000, w = 4, d = 3, rate = 700, charm = 12, tier = 4, blurb = "Warm bread for the town." }),
	B({ id = "bazaar", name = "Grand Bazaar", kind = "work", act = "shop", shells = 44000, w = 5, d = 4, rate = 1500, charm = 20, tier = 5, blurb = "Stalls under striped awnings." }),
	B({ id = "hotel", name = "Grand Hotel", kind = "work", act = "shop", shells = 120000, w = 5, d = 5, rate = 3200, charm = 35, tier = 6, blurb = "Five floors over the bay." }),
	-- (the islands past Driftling Haven, the request of 2026-11-14: "allow expansion up to level 20 ... add decor, huts, work buildings")
	B({ id = "nightmarket", name = "Night Market", kind = "work", act = "shop", shells = 420000, w = 5, d = 4, rate = 6800, charm = 40, tier = 12, blurb = "Stalls open till late." }),
	B({ id = "theatre", name = "Seaside Theatre", kind = "work", act = "shop", shells = 1100000, w = 5, d = 5, rate = 12000, charm = 60, tier = 15, blurb = "A show every evening." }),
	B({ id = "skytram", name = "Sky Tram", kind = "work", act = "shop", shells = 3000000, w = 5, d = 5, rate = 21000, charm = 80, tier = 18, blurb = "Rides over the island." }),
	-- huts (kind "nest"): room for driftlings, and comfort
	B({ id = "nest", name = "Driftling Hut", kind = "nest", shells = 55, w = 2, d = 2, slots = 2, blurb = "Small and snug." }),
	B({ id = "burrow", name = "Cozy Burrow", kind = "nest", shells = 840, w = 3, d = 3, slots = 8, charm = 1, comfort = 0.05, tier = 2, blurb = "Dug under the turf." }),
	B({ id = "den", name = "Driftling Den", kind = "nest", shells = 4400, w = 3, d = 3, slots = 10, charm = 3, comfort = 0.08, tier = 3, blurb = "Moss and soft beds." }),
	B({ id = "roost", name = "Treetop Roost", kind = "nest", shells = 14200, w = 4, d = 4, slots = 12, charm = 5, comfort = 0.12, tier = 4, blurb = "Nests in a great tree." }),
	B({ id = "grotto", name = "Spring Grotto", kind = "nest", shells = 40000, w = 4, d = 4, slots = 16, charm = 8, comfort = 0.18, tier = 5, blurb = "A warm spring under a rock." }),
	B({ id = "palace", name = "Driftling Palace", kind = "nest", shells = 90000, w = 5, d = 5, slots = 18, charm = 14, comfort = 0.25, tier = 6, blurb = "Soft beds and gold trim." }),
	-- (the islands past Driftling Haven, the request of 2026-11-14: "allow expansion up to level 20 ... add decor, huts, work buildings")
	B({ id = "loft", name = "Lighthouse Loft", kind = "nest", shells = 280000, w = 5, d = 5, slots = 22, charm = 18, comfort = 0.3, tier = 11, blurb = "Bunks up a striped tower." }),
	B({ id = "coralmanor", name = "Coral Manor", kind = "nest", shells = 910000, w = 5, d = 5, slots = 26, charm = 24, comfort = 0.36, tier = 14, blurb = "Pink rooms round a warm pool." }),
	B({ id = "cloudkeep", name = "Cloud Keep", kind = "nest", shells = 2800000, w = 6, d = 5, slots = 30, charm = 32, comfort = 0.42, tier = 17, blurb = "Towers wrapped in cloud." }),
	B({ id = "citadel", name = "Driftling Citadel", kind = "nest", shells = 8500000, w = 6, d = 6, slots = 34, charm = 45, comfort = 0.5, tier = 20, blurb = "Halls for a whole crowd." }),
	-- the Hatchery (GAME_DESIGN 6.1): an egg at a time
	B({ id = "hatchery", name = "Hatchery", kind = "breed", shells = 3900, w = 4, d = 4, charm = 3, tier = 3, blurb = "Breed two driftlings for an egg." }),
	-- boosts: every workplace makes more (a second of a kind counts less: Tuning.BoostStack)
	B({ id = "toolshed", name = "Tool Shed", kind = "gen", shells = 1300, w = 2, d = 2, charm = 1, boostBy = 0.06, tier = 2, blurb = "Sharp tools. Everything +6%." }),
	B({ id = "windmill", name = "Windmill", kind = "gen", shells = 1600, w = 3, d = 3, charm = 4, boostBy = 0.06, tier = 2, blurb = "Grinds the harvest. Everything +6%." }),
	B({ id = "smokehouse", name = "Smokehouse", kind = "gen", shells = 1500, w = 3, d = 3, charm = 2, boostBy = 0.06, tier = 2, blurb = "Smoked fish for all. Everything +6%." }),
	B({ id = "market", name = "Market Hall", kind = "gen", shells = 5500, w = 4, d = 3, charm = 8, boostBy = 0.07, tier = 3, blurb = "Brings in buyers. Everything +7%." }),
	B({ id = "watertower", name = "Water Tower", kind = "gen", shells = 13000, w = 3, d = 3, charm = 6, boostBy = 0.06, tier = 4, blurb = "Fresh water. Everything +6%." }),
	B({ id = "townhall", name = "Town Hall", kind = "gen", shells = 39000, w = 5, d = 4, charm = 30, boostBy = 0.1, tier = 5, blurb = "Keeps things running. Everything +10%." }),
	B({ id = "beacon", name = "Sun Beacon", kind = "gen", shells = 97000, w = 3, d = 3, charm = 40, boostBy = 0.15, tier = 6, blurb = "Never goes dark. Everything +15%." }),
	-- (the islands past Driftling Haven, the request of 2026-11-14: "allow expansion up to level 20 ... add decor, huts, work buildings")
	B({ id = "seedvault", name = "Seed Vault", kind = "gen", shells = 350000, w = 3, d = 3, charm = 12, boostBy = 0.07, tier = 12, blurb = "Good seeds, kept cool. Everything +7%." }),
	B({ id = "guildhall", name = "Carpenters' Hall", kind = "gen", shells = 900000, w = 4, d = 3, charm = 20, boostBy = 0.07, tier = 15, blurb = "Old hands teach. Everything +7%." }),
	B({ id = "tradehall", name = "Trade Hall", kind = "gen", shells = 1600000, w = 4, d = 4, charm = 30, boostBy = 0.07, tier = 16, blurb = "New goods by ship. Everything +7%." }),
	B({ id = "tidebell", name = "Tide Bell", kind = "gen", shells = 3500000, w = 3, d = 3, charm = 60, boostBy = 0.1, tier = 19, blurb = "Rung at every shift. Everything +10%." }),
	-- paths: 2 x 2 tiles of path and road, drawn (apart from the piece limit, with the water: Tuning.PathPieces)
	B({ id = "dirtpath", name = "Dirt Path", kind = "path", shells = 5, w = 2, d = 2, feel = "sand", blurb = "Trodden earth." }),
	B({ id = "sandtrail", name = "Sand Trail", kind = "path", shells = 4, w = 2, d = 2, feel = "sand", blurb = "Packed sand." }),
	B({ id = "gravel", name = "Gravel Path", kind = "path", shells = 8, w = 2, d = 2, blurb = "Crunchy grey grit." }),
	B({ id = "shellpath", name = "Shell Path", kind = "path", shells = 10, w = 2, d = 2, charm = 0.25, feel = "sand", blurb = "Crushed pale shells." }),
	B({ id = "plankwalk", name = "Plank Walk", kind = "path", shells = 12, w = 2, d = 2, charm = 0.25, feel = "wood", blurb = "Boards side by side." }),
	B({ id = "stonepath", name = "Stone Path", kind = "path", shells = 15, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Flat stones set in sand." }),
	B({ id = "flagstone", name = "Flagstones", kind = "path", shells = 18, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Big stones, grass between." }),
	B({ id = "cobble", name = "Cobblestones", kind = "path", shells = 22, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Worn round stones." }),
	B({ id = "mossstone", name = "Mossy Stones", kind = "path", shells = 20, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Stones the moss got to first." }),
	B({ id = "leafpath", name = "Leaf Litter", kind = "path", shells = 10, w = 2, d = 2, charm = 0.25, tier = 2, feel = "plant", blurb = "Red and gold leaves." }),
	B({ id = "meadow", name = "Flower Meadow", kind = "path", shells = 14, w = 2, d = 2, charm = 0.5, tier = 2, feel = "plant", blurb = "Grass full of flowers." }),
	B({ id = "raked", name = "Raked Gravel", kind = "path", shells = 20, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Gravel combed into lines." }),
	B({ id = "snowpath", name = "Snowy Path", kind = "path", shells = 16, w = 2, d = 2, charm = 0.5, tier = 3, feel = "snow", blurb = "Snow with footprints." }),
	B({ id = "sandstone", name = "Sandstone Tiles", kind = "path", shells = 30, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Warm yellow slabs." }),
	B({ id = "terracotta", name = "Terracotta Tiles", kind = "path", shells = 34, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Baked clay squares." }),
	B({ id = "checker", name = "Checker Tiles", kind = "path", shells = 30, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Black and white squares." }),
	B({ id = "brickroad", name = "Brick Road", kind = "path", shells = 40, w = 2, d = 2, charm = 0.5, tier = 4, blurb = "Red bricks in rows." }),
	B({ id = "crystalpath", name = "Crystal Path", kind = "path", shells = 70, w = 2, d = 2, charm = 1, tier = 5, feel = "magic", blurb = "Glows a little at night." }),
	B({ id = "basalt", name = "Basalt Steps", kind = "path", shells = 60, w = 2, d = 2, charm = 1, tier = 5, feel = "fire", blurb = "Black rock with warm cracks." }),
	B({ id = "marblewalk", name = "Marble Walk", kind = "path", shells = 90, w = 2, d = 2, charm = 1, tier = 5, blurb = "White marble, gold inlay." }),
	B({ id = "goldpath", name = "Gilded Walk", kind = "path", shells = 220, w = 2, d = 2, charm = 2, tier = 7, feel = "metal", blurb = "Gold edging on cream stone." }),
	B({ id = "starpath", name = "Starlit Path", kind = "path", shells = 300, w = 2, d = 2, charm = 2, tier = 8, feel = "magic", blurb = "Blue stone full of stars." }),
	-- water: 2 x 2 tiles drawn like paths into rivers and ponds (GAME_DESIGN 4.3); the founder wades through
	B({ id = "stream", name = "Stream", kind = "water", shells = 12, w = 2, d = 2, charm = 0.5, blurb = "Clear, shallow water." }),
	B({ id = "river", name = "Deep River", kind = "water", shells = 18, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Deep, with a current." }),
	B({ id = "lilypond", name = "Lily Pond", kind = "water", shells = 22, w = 2, d = 2, charm = 1, tier = 2, blurb = "Still water, lily pads." }),
	B({ id = "swamp", name = "Swamp Water", kind = "water", shells = 20, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Murky and still." }),
	B({ id = "lagoon", name = "Lagoon", kind = "water", shells = 30, w = 2, d = 2, charm = 1, tier = 4, blurb = "Bright reef blue." }),
	B({ id = "hotspring", name = "Hot Spring", kind = "water", shells = 40, w = 2, d = 2, charm = 1, tier = 5, blurb = "Warm and steaming." }),
	B({ id = "icepond", name = "Frozen Pond", kind = "water", shells = 30, w = 2, d = 2, charm = 1, tier = 6, feel = "snow", blurb = "Thick enough to stand on." }),
	-- fences: 2-stud lengths drawn along the grid lines (apart: Tuning.FencePieces)
	B({ id = "ropefence", name = "Rope Fence", kind = "fence", shells = 6, w = 2, d = 0, charm = 0.25, blurb = "Posts and a sagging rope." }),
	B({ id = "picket", name = "Picket Fence", kind = "fence", shells = 8, w = 2, d = 0, charm = 0.5, blurb = "White cottage pickets." }),
	B({ id = "splitrail", name = "Split Rail", kind = "fence", shells = 10, w = 2, d = 0, charm = 0.25, blurb = "Rough farm rails." }),
	B({ id = "bamboofence", name = "Bamboo Fence", kind = "fence", shells = 14, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Canes tied with cord." }),
	B({ id = "driftwood", name = "Driftwood Fence", kind = "fence", shells = 12, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Pale wood the sea brought in." }),
	B({ id = "wattle", name = "Woven Fence", kind = "fence", shells = 14, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Willow woven between stakes." }),
	B({ id = "hedgerow", name = "Hedgerow", kind = "fence", shells = 20, w = 2, d = 0, charm = 0.75, tier = 2, feel = "plant", blurb = "Clipped and green." }),
	B({ id = "gardengate", name = "Garden Gate", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 2, blurb = "A gate under a little arch." }),
	B({ id = "stonewall", name = "Low Stone Wall", kind = "fence", shells = 28, w = 2, d = 0, charm = 0.75, tier = 3, feel = "stone", blurb = "Field stones piled waist high." }),
	B({ id = "palisade", name = "Log Palisade", kind = "fence", shells = 26, w = 2, d = 0, charm = 0.75, tier = 3, blurb = "Sharpened logs." }),
	B({ id = "ironrail", name = "Iron Railing", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 4, feel = "metal", blurb = "Black bars with spear tips." }),
	B({ id = "lanternrope", name = "Lantern Rope", kind = "fence", shells = 45, w = 2, d = 0, charm = 1, tier = 4, feel = "fire", blurb = "Little lights on posts." }),
	B({ id = "brickwall", name = "Brick Wall", kind = "fence", shells = 55, w = 2, d = 0, charm = 1, tier = 5, feel = "stone", blurb = "Red brick with a stone cap." }),
	B({ id = "adobe", name = "Adobe Wall", kind = "fence", shells = 50, w = 2, d = 0, charm = 1, tier = 5, feel = "sand", blurb = "Sun dried mud." }),
	B({ id = "icewall", name = "Snowbank", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 6, feel = "snow", blurb = "Packed snow with icicles." }),
	B({ id = "shellwall", name = "Shell Wall", kind = "fence", shells = 60, w = 2, d = 0, charm = 1.5, tier = 6, feel = "stone", blurb = "White stone set with shells." }),
	B({ id = "crystalfence", name = "Crystal Fence", kind = "fence", shells = 120, w = 2, d = 0, charm = 2, tier = 8, feel = "magic", blurb = "Glowing points of crystal." }),
	-- water decor: bridges and docks over the water, and things that float on it
	B({ id = "plankbridge", name = "Plank Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 120, w = 2, d = 6, blurb = "Boards across a stream." }),
	B({ id = "dock", name = "Little Dock", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 300, w = 3, d = 4, tier = 2, blurb = "A jetty to sit on." }),
	B({ id = "ropebridge", name = "Rope Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 400, w = 2, d = 6, tier = 3, blurb = "Slats hung on two ropes." }),
	B({ id = "stonebridge", name = "Stone Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 900, w = 3, d = 6, tier = 3, feel = "stone", blurb = "One round arch of stone." }),
	B({ id = "waterwheel", name = "Waterwheel", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 1400, w = 3, d = 2, tier = 4, blurb = "Turns in the current." }),
	B({ id = "canal", name = "Canal Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 8600, w = 4, d = 3, tier = 5, feel = "stone", blurb = "A town bridge with railings." }),
	B({ id = "moonbridge", name = "Moon Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 3200, w = 3, d = 6, tier = 6, blurb = "A high red arch." }),
	B({ id = "lilypads", name = "Lily Pads", kind = "decor", tab = "water", sub = "float", water = "on", shells = 20, w = 2, d = 2, feel = "plant", blurb = "Round leaves floating flat." }),
	B({ id = "reeds", name = "Reeds", kind = "decor", tab = "water", sub = "float", water = "on", shells = 25, w = 2, d = 2, feel = "plant", blurb = "Tall reeds and cattails." }),
	B({ id = "steppingstones", name = "Stepping Stones", kind = "decor", tab = "water", sub = "float", water = "on", shells = 30, w = 2, d = 2, feel = "stone", blurb = "Hop across without wet feet." }),
	B({ id = "duckfloat", name = "Duck Decoy", kind = "decor", tab = "water", sub = "float", water = "on", shells = 60, w = 2, d = 2, tier = 2, blurb = "A wooden duck bobbing about." }),
	B({ id = "rowboat", name = "Rowboat", kind = "decor", tab = "water", sub = "float", water = "on", shells = 180, w = 2, d = 4, tier = 2, blurb = "Oars shipped, ready to go." }),
	B({ id = "lotus", name = "Lotus Flowers", kind = "decor", tab = "water", sub = "float", water = "on", shells = 90, w = 2, d = 2, tier = 3, feel = "plant", blurb = "Pink flowers on still water." }),
	B({ id = "littlefall", name = "Little Waterfall", kind = "decor", tab = "water", sub = "float", water = "over", shells = 600, w = 2, d = 2, tier = 3, feel = "water", blurb = "Spills over mossy rocks." }),
	B({ id = "waterlanterns", name = "Floating Lanterns", kind = "decor", tab = "water", sub = "float", water = "on", shells = 220, w = 2, d = 2, tier = 4, feel = "fire", blurb = "Paper lights drifting at dusk." }),
	-- nature: trees
	B({ id = "pine", name = "Pine Tree", kind = "decor", tab = "nature", sub = "trees", shells = 70, w = 2, d = 2, feel = "plant", blurb = "Tall and dark green." }),
	B({ id = "oak", name = "Oak Tree", kind = "decor", tab = "nature", sub = "trees", shells = 90, w = 3, d = 3, feel = "plant", blurb = "Round and leafy." }),
	B({ id = "palm", name = "Palm Tree", kind = "decor", tab = "nature", sub = "trees", shells = 120, w = 3, d = 3, feel = "plant", blurb = "Coconuts up top." }),
	B({ id = "deadtree", name = "Bare Tree", kind = "decor", tab = "nature", sub = "trees", shells = 80, w = 2, d = 2, tier = 2, feel = "wood", blurb = "Twisted branches, no leaves." }),
	B({ id = "birch", name = "Birch Tree", kind = "decor", tab = "nature", sub = "trees", shells = 110, w = 2, d = 2, tier = 2, feel = "plant", blurb = "White bark, light leaves." }),
	B({ id = "cherry", name = "Cherry Blossom", kind = "decor", tab = "nature", sub = "trees", shells = 600, w = 3, d = 3, tier = 3, feel = "plant", blurb = "A cloud of pink flowers." }),
	B({ id = "maple", name = "Maple Tree", kind = "decor", tab = "nature", sub = "trees", shells = 520, w = 3, d = 3, tier = 3, feel = "plant", blurb = "Leaves gone red and orange." }),
	B({ id = "jungletree", name = "Jungle Tree", kind = "decor", tab = "nature", sub = "trees", shells = 700, w = 3, d = 3, tier = 3, feel = "plant", blurb = "Huge leaves and hanging vines." }),
	B({ id = "willow", name = "Willow", kind = "decor", tab = "nature", sub = "trees", shells = 1800, w = 4, d = 4, tier = 4, feel = "plant", blurb = "Branches down to the ground." }),
	B({ id = "bigoak", name = "Great Oak", kind = "decor", tab = "nature", sub = "trees", shells = 6000, w = 5, d = 5, tier = 5, feel = "plant", blurb = "Older than anyone remembers." }),
	B({ id = "snowpine", name = "Snowy Pine", kind = "decor", tab = "nature", sub = "trees", shells = 300, w = 2, d = 2, tier = 6, feel = "snow", blurb = "Branches heavy with snow." }),
	B({ id = "starfruit", name = "Starfruit Tree", kind = "decor", tab = "nature", sub = "trees", shells = 2500, w = 3, d = 3, tier = 11, feel = "plant", blurb = "Fruit like little gold stars." }),
	B({ id = "redwood", name = "Redwood", kind = "decor", tab = "nature", sub = "trees", shells = 9000, w = 4, d = 4, tier = 17, feel = "plant", blurb = "Taller than a lighthouse." }),
	-- nature: plants and flowers
	B({ id = "fern", name = "Fern", kind = "decor", tab = "nature", sub = "plants", shells = 15, w = 1, d = 1, feel = "plant", blurb = "Feathery green fronds." }),
	B({ id = "tallgrass", name = "Tall Grass", kind = "decor", tab = "nature", sub = "plants", shells = 12, w = 2, d = 2, feel = "plant", blurb = "Grass that sways." }),
	B({ id = "bush", name = "Round Bush", kind = "decor", tab = "nature", sub = "plants", shells = 30, w = 2, d = 2, feel = "plant" }),
	B({ id = "berrybush", name = "Berry Bush", kind = "decor", tab = "nature", sub = "plants", shells = 45, w = 2, d = 2, feel = "plant", blurb = "Covered in red berries." }),
	B({ id = "tulips", name = "Tulip Row", kind = "decor", tab = "nature", sub = "plants", shells = 35, w = 2, d = 1, feel = "plant", blurb = "Bright spring colours." }),
	B({ id = "flowers", name = "Flower Bed", kind = "decor", tab = "nature", sub = "plants", shells = 40, w = 2, d = 2, feel = "plant" }),
	B({ id = "mushrooms", name = "Mushrooms", kind = "decor", tab = "nature", sub = "plants", shells = 30, w = 1, d = 1, tier = 2, feel = "plant", blurb = "Spotted caps in the grass." }),
	B({ id = "rosebush", name = "Rose Bush", kind = "decor", tab = "nature", sub = "plants", shells = 60, w = 2, d = 2, tier = 2, feel = "plant", blurb = "Red roses, mind the thorns." }),
	B({ id = "sunflowers", name = "Sunflowers", kind = "decor", tab = "nature", sub = "plants", shells = 70, w = 2, d = 2, tier = 2, feel = "plant", blurb = "Taller than a driftling." }),
	B({ id = "lavender", name = "Lavender", kind = "decor", tab = "nature", sub = "plants", shells = 45, w = 2, d = 1, tier = 2, feel = "plant", blurb = "Purple and smells lovely." }),
	B({ id = "pumpkins", name = "Pumpkin Patch", kind = "decor", tab = "nature", sub = "plants", shells = 80, w = 2, d = 2, tier = 2, feel = "plant", blurb = "Fat pumpkins on the vine." }),
	B({ id = "cactus", name = "Cactus", kind = "decor", tab = "nature", sub = "plants", shells = 70, w = 1, d = 1, tier = 3, feel = "plant", blurb = "Prickly, with one pink flower." }),
	B({ id = "monstera", name = "Big Leaf Plant", kind = "decor", tab = "nature", sub = "plants", shells = 120, w = 2, d = 2, tier = 3, feel = "plant", blurb = "Leaves as big as a door." }),
	B({ id = "bigcactus", name = "Tall Cactus", kind = "decor", tab = "nature", sub = "plants", shells = 240, w = 2, d = 2, tier = 4, feel = "plant", blurb = "Arms up like it's waving." }),
	B({ id = "giantshroom", name = "Giant Mushroom", kind = "decor", tab = "nature", sub = "plants", shells = 400, w = 2, d = 2, tier = 4, feel = "plant", blurb = "A red cap you could sit under." }),
	B({ id = "bonsai", name = "Bonsai", kind = "decor", tab = "nature", sub = "plants", shells = 350, w = 1, d = 1, tier = 4, feel = "plant", blurb = "A tiny old tree in a tray." }),
	B({ id = "glowshroom", name = "Glow Mushrooms", kind = "decor", tab = "nature", sub = "plants", shells = 260, w = 1, d = 1, tier = 6, feel = "magic", blurb = "Blue caps that light up." }),
	B({ id = "glassflowers", name = "Glass Flowers", kind = "decor", tab = "nature", sub = "plants", shells = 1800, w = 1, d = 1, tier = 15, feel = "magic", blurb = "Petals you can see through." }),
	-- nature: rocks
	B({ id = "boulder", name = "Boulder", kind = "decor", tab = "nature", sub = "rocks", shells = 25, w = 2, d = 2, feel = "stone", blurb = "One big round rock." }),
	B({ id = "rockpile", name = "Rock Pile", kind = "decor", tab = "nature", sub = "rocks", shells = 30, w = 2, d = 2, feel = "stone", blurb = "A heap of stones." }),
	B({ id = "mossrock", name = "Mossy Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 50, w = 2, d = 2, tier = 2, feel = "stone", blurb = "Green on the shady side." }),
	B({ id = "sandrock", name = "Desert Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 70, w = 2, d = 2, tier = 3, feel = "stone", blurb = "Worn by the wind." }),
	B({ id = "crystals", name = "Crystal Cluster", kind = "decor", tab = "nature", sub = "rocks", shells = 600, w = 2, d = 2, tier = 5, feel = "magic", blurb = "Purple points that shine." }),
	B({ id = "snowrock", name = "Snowy Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 120, w = 2, d = 2, tier = 6, feel = "snow", blurb = "Capped with snow." }),
	B({ id = "basaltcols", name = "Basalt Columns", kind = "decor", tab = "nature", sub = "rocks", shells = 700, w = 2, d = 2, tier = 6, feel = "stone", blurb = "Pillars of black rock." }),
	B({ id = "lavarock", name = "Lava Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 900, w = 2, d = 2, tier = 7, feel = "fire", blurb = "Still glowing in the cracks." }),
	B({ id = "geode", name = "Geode", kind = "decor", tab = "nature", sub = "rocks", shells = 3500, w = 2, d = 2, tier = 13, feel = "stone", blurb = "Plain outside, purple inside." }),
	-- decor by theme: the beach
	B({ id = "coconuts", name = "Coconut Pile", kind = "decor", sub = "beach", shells = 30, w = 1, d = 1, feel = "wood", blurb = "Fresh off the palm." }),
	B({ id = "sandcastle", name = "Sandcastle", kind = "decor", sub = "beach", shells = 50, w = 2, d = 2, feel = "sand" }),
	B({ id = "deckchair", name = "Deck Chair", kind = "decor", sub = "beach", shells = 60, w = 1, d = 2, feel = "cloth", blurb = "Low and striped." }),
	B({ id = "umbrella", name = "Beach Umbrella", kind = "decor", sub = "beach", shells = 70, w = 2, d = 2, feel = "cloth", blurb = "Shade with stripes." }),
	B({ id = "shellpile", name = "Shell Pile", kind = "decor", sub = "beach", shells = 80, w = 2, d = 2, feel = "sand" }),
	B({ id = "surfboards", name = "Surfboard Rack", kind = "decor", sub = "beach", shells = 140, w = 2, d = 1, tier = 2, blurb = "Three boards waiting for waves." }),
	B({ id = "lifeguard", name = "Lifeguard Chair", kind = "decor", sub = "beach", shells = 700, w = 2, d = 2, tier = 3, blurb = "A tall seat by the sea." }),
	B({ id = "beachhut", name = "Beach Hut", kind = "decor", sub = "beach", shells = 6000, w = 3, d = 3, tier = 12, blurb = "Towels drying on the rail." }),
	-- the garden
	B({ id = "gnome", name = "Garden Gnome", kind = "decor", sub = "garden", shells = 50, w = 1, d = 1, feel = "stone", blurb = "Red hat, very serious." }),
	B({ id = "wheelbarrow", name = "Wheelbarrow", kind = "decor", sub = "garden", shells = 70, w = 2, d = 1, blurb = "Soil and a trowel." }),
	B({ id = "birdbath", name = "Birdbath", kind = "decor", sub = "garden", shells = 80, w = 1, d = 1, feel = "stone", blurb = "A stone bowl of water." }),
	B({ id = "beehive", name = "Beehive", kind = "decor", sub = "garden", shells = 120, w = 1, d = 1, tier = 2, blurb = "A busy little box." }),
	B({ id = "trellis", name = "Rose Trellis", kind = "decor", sub = "garden", shells = 160, w = 2, d = 1, tier = 2, feel = "plant", blurb = "Roses climbing a lattice." }),
	B({ id = "flowerarch", name = "Flower Arch", kind = "decor", sub = "garden", shells = 530, w = 3, d = 1, tier = 2, feel = "plant" }),
	B({ id = "sundial", name = "Sundial", kind = "decor", sub = "garden", shells = 300, w = 1, d = 1, tier = 3, feel = "stone", blurb = "Works when it's sunny." }),
	B({ id = "gazebo", name = "Gazebo", kind = "decor", sub = "garden", shells = 4300, w = 4, d = 4, tier = 3 }),
	B({ id = "topiary", name = "Topiary", kind = "decor", sub = "garden", shells = 900, w = 2, d = 2, tier = 4, feel = "plant" }),
	B({ id = "hedgemaze", name = "Hedge Maze", kind = "decor", sub = "garden", shells = 12000, w = 5, d = 5, tier = 14, feel = "plant", blurb = "Easy to get lost in." }),
	-- the farm
	B({ id = "churns", name = "Milk Churns", kind = "decor", sub = "farm", shells = 40, w = 1, d = 1, feel = "metal", blurb = "Two tin churns." }),
	B({ id = "haybale", name = "Hay Bale", kind = "decor", sub = "farm", shells = 30, w = 2, d = 1, feel = "plant", blurb = "Tied with twine." }),
	B({ id = "scarecrow", name = "Scarecrow", kind = "decor", sub = "farm", shells = 60, w = 1, d = 1, feel = "cloth", blurb = "Keeps the gulls off." }),
	B({ id = "barrels", name = "Barrel Stack", kind = "decor", sub = "farm", shells = 70, w = 2, d = 2, blurb = "Three barrels, one on top." }),
	B({ id = "haystack", name = "Haystack", kind = "decor", sub = "farm", shells = 90, w = 2, d = 2, tier = 2, feel = "plant", blurb = "With a pitchfork in it." }),
	B({ id = "trough", name = "Water Trough", kind = "decor", sub = "farm", shells = 110, w = 2, d = 1, tier = 2, blurb = "Full to the brim." }),
	B({ id = "cart", name = "Farm Cart", kind = "decor", sub = "farm", shells = 260, w = 3, d = 2, tier = 2, blurb = "A load of veg." }),
	B({ id = "well", name = "Stone Well", kind = "decor", sub = "farm", shells = 300, w = 2, d = 2, tier = 2, feel = "stone", blurb = "A bucket on a rope." }),
	B({ id = "redbarn", name = "Red Barn", kind = "decor", sub = "farm", shells = 7000, w = 4, d = 4, tier = 11, blurb = "Big doors and a hay loft." }),
	-- the harbour
	B({ id = "bollard", name = "Mooring Post", kind = "decor", sub = "harbour", shells = 30, w = 1, d = 1, blurb = "A rope wound round it." }),
	B({ id = "buoy", name = "Buoy", kind = "decor", sub = "harbour", shells = 50, w = 1, d = 1, feel = "metal", blurb = "Red and white stripes." }),
	B({ id = "crates", name = "Crate Stack", kind = "decor", sub = "harbour", shells = 50, w = 2, d = 2, blurb = "Stamped and nailed shut." }),
	B({ id = "lobsterpots", name = "Lobster Pots", kind = "decor", sub = "harbour", shells = 90, w = 2, d = 2, tier = 2, blurb = "Wicker traps in a pile." }),
	B({ id = "netrack", name = "Net Rack", kind = "decor", sub = "harbour", shells = 140, w = 3, d = 1, tier = 2, feel = "cloth", blurb = "Nets hung out to dry." }),
	B({ id = "anchor", name = "Anchor", kind = "decor", sub = "harbour", shells = 160, w = 2, d = 1, tier = 2, feel = "metal", blurb = "Too heavy to lift." }),
	B({ id = "shipwheel", name = "Ship's Wheel", kind = "decor", sub = "harbour", shells = 260, w = 1, d = 1, tier = 3, blurb = "From a ship long gone." }),
	B({ id = "lighthouse", name = "Lighthouse", kind = "decor", sub = "harbour", shells = 9700, w = 4, d = 4, tier = 3, feel = "stone" }),
	B({ id = "galleon", name = "Old Galleon", kind = "decor", sub = "harbour", shells = 30000, w = 5, d = 3, tier = 13, blurb = "Ran aground and stayed." }),
	-- the town
	B({ id = "bin", name = "Bin", kind = "decor", sub = "town", shells = 25, w = 1, d = 1, feel = "metal", blurb = "Keeps the island tidy." }),
	B({ id = "signpost", name = "Signpost", kind = "decor", sub = "town", shells = 40, w = 1, d = 1, blurb = "Points four ways at once." }),
	B({ id = "planter", name = "Planter Box", kind = "decor", sub = "town", shells = 90, w = 2, d = 1, tier = 2, feel = "plant", blurb = "Flowers in a wooden box." }),
	B({ id = "postbox", name = "Post Box", kind = "decor", sub = "town", shells = 100, w = 1, d = 1, tier = 2, feel = "metal", blurb = "Red, with a slot." }),
	B({ id = "noticeboard", name = "Notice Board", kind = "decor", sub = "town", shells = 140, w = 2, d = 1, tier = 2, blurb = "Lost hats and lessons on offer." }),
	B({ id = "newsstand", name = "Newsstand", kind = "decor", sub = "town", shells = 900, w = 2, d = 2, tier = 4, blurb = "Papers and postcards." }),
	B({ id = "bandstand", name = "Bandstand", kind = "decor", sub = "town", shells = 11000, w = 4, d = 4, tier = 4 }),
	B({ id = "clocktower", name = "Clock Tower", kind = "decor", sub = "town", shells = 15000, w = 3, d = 3, tier = 4, feel = "stone" }),
	B({ id = "flowerclock", name = "Flower Clock", kind = "decor", sub = "town", shells = 8000, w = 3, d = 3, tier = 12, feel = "plant", blurb = "Hands over a bed of flowers." }),
	-- the jungle
	B({ id = "tikimask", name = "Tiki Mask", kind = "decor", sub = "jungle", shells = 140, w = 1, d = 1, tier = 2, blurb = "A carved face on a post." }),
	B({ id = "totem", name = "Totem Pole", kind = "decor", sub = "jungle", shells = 980, w = 2, d = 2, tier = 2 }),
	B({ id = "parrotperch", name = "Parrot Perch", kind = "decor", sub = "jungle", shells = 220, w = 1, d = 1, tier = 3, blurb = "A carved parrot on a branch." }),
	B({ id = "vinearch", name = "Vine Arch", kind = "decor", sub = "jungle", shells = 420, w = 3, d = 1, tier = 3, feel = "plant", blurb = "Two posts lost in creepers." }),
	B({ id = "idol", name = "Mossy Idol", kind = "decor", sub = "jungle", shells = 1200, w = 2, d = 2, tier = 4, feel = "stone", blurb = "A big stone head, half buried." }),
	B({ id = "templesteps", name = "Temple Steps", kind = "decor", sub = "jungle", shells = 20000, w = 4, d = 4, tier = 15, feel = "stone", blurb = "Steps up to a little shrine." }),
	-- frost
	B({ id = "snowman", name = "Snowman", kind = "decor", sub = "frost", shells = 80, w = 1, d = 1, tier = 2, feel = "snow", blurb = "Carrot nose, pebble smile." }),
	B({ id = "sled", name = "Sled", kind = "decor", sub = "frost", shells = 160, w = 2, d = 1, tier = 6, feel = "snow", blurb = "Waiting for a hill." }),
	B({ id = "icelantern", name = "Ice Lantern", kind = "decor", sub = "frost", shells = 200, w = 1, d = 1, tier = 6, feel = "snow", blurb = "A candle in a block of ice." }),
	B({ id = "icesculpture", name = "Ice Sculpture", kind = "decor", sub = "frost", shells = 1100, w = 2, d = 2, tier = 6, feel = "snow", blurb = "An ice swan." }),
	B({ id = "igloo", name = "Igloo", kind = "decor", sub = "frost", shells = 1500, w = 3, d = 3, tier = 6, feel = "snow", blurb = "Snow blocks in a dome." }),
	B({ id = "frozenfall", name = "Frozen Waterfall", kind = "decor", sub = "frost", shells = 15000, w = 3, d = 2, tier = 16, feel = "snow", blurb = "Stopped mid fall." }),
	-- autumn
	B({ id = "leafpile", name = "Leaf Pile", kind = "decor", sub = "autumn", shells = 30, w = 2, d = 2, tier = 2, feel = "plant", blurb = "Just right for jumping in." }),
	B({ id = "basket", name = "Harvest Basket", kind = "decor", sub = "autumn", shells = 60, w = 1, d = 1, tier = 2, feel = "plant", blurb = "Apples and squash." }),
	B({ id = "pumpkinstack", name = "Pumpkin Stack", kind = "decor", sub = "autumn", shells = 70, w = 1, d = 1, tier = 2, feel = "plant", blurb = "Biggest at the bottom." }),
	B({ id = "cornstalks", name = "Corn Stalks", kind = "decor", sub = "autumn", shells = 90, w = 2, d = 1, tier = 3, feel = "plant", blurb = "Tied in bundles." }),
	B({ id = "jackolantern", name = "Carved Pumpkin", kind = "decor", sub = "autumn", shells = 120, w = 1, d = 1, tier = 3, feel = "fire", blurb = "A grin lit from inside." }),
	B({ id = "ciderpress", name = "Cider Press", kind = "decor", sub = "autumn", shells = 4000, w = 2, d = 2, tier = 13, blurb = "Apples go in the top." }),
	-- the desert
	B({ id = "waterjars", name = "Water Jars", kind = "decor", sub = "desert", shells = 80, w = 1, d = 1, tier = 3, feel = "stone", blurb = "Cool water in clay." }),
	B({ id = "claypots", name = "Clay Pots", kind = "decor", sub = "desert", shells = 90, w = 2, d = 1, tier = 3, feel = "stone", blurb = "Painted pots in a row." }),
	B({ id = "rug", name = "Market Rug", kind = "decor", sub = "desert", shells = 300, w = 2, d = 2, tier = 5, feel = "cloth", blurb = "Woven red and gold." }),
	B({ id = "stripedtent", name = "Striped Tent", kind = "decor", sub = "desert", shells = 1400, w = 3, d = 3, tier = 5, feel = "cloth", blurb = "Cool shade on a hot day." }),
	B({ id = "sandarch", name = "Sandstone Arch", kind = "decor", sub = "desert", shells = 1600, w = 3, d = 1, tier = 5, feel = "stone", blurb = "A gateway of carved stone." }),
	B({ id = "obelisk", name = "Desert Obelisk", kind = "decor", sub = "desert", shells = 9000, w = 2, d = 2, tier = 14, feel = "stone", blurb = "Carved on all four sides." }),
	-- the fairy glade
	B({ id = "fairylantern", name = "Fairy Lantern", kind = "decor", sub = "fairy", shells = 300, w = 1, d = 1, tier = 5, feel = "magic", blurb = "A jar of tiny lights." }),
	B({ id = "mushroomring", name = "Mushroom Ring", kind = "decor", sub = "fairy", shells = 700, w = 3, d = 3, tier = 5, feel = "magic", blurb = "Don't step inside." }),
	B({ id = "moonstone", name = "Moonstone", kind = "decor", sub = "fairy", shells = 2200, w = 2, d = 2, tier = 6, feel = "magic", blurb = "Glows pale at night." }),
	B({ id = "wishingwell", name = "Wishing Well", kind = "decor", sub = "fairy", shells = 2600, w = 2, d = 2, tier = 6, feel = "magic", blurb = "Coins shine at the bottom." }),
	B({ id = "crystalarch", name = "Crystal Arch", kind = "decor", sub = "fairy", shells = 9000, w = 3, d = 1, tier = 8, feel = "magic", blurb = "Two crystals bent into an arch." }),
	B({ id = "fairyhouse", name = "Fairy Tree House", kind = "decor", sub = "fairy", shells = 16000, w = 3, d = 3, tier = 16, feel = "magic", blurb = "Tiny doors up the trunk." }),
	-- the zen garden
	B({ id = "rockgarden", name = "Rock Garden", kind = "decor", sub = "zen", shells = 70, w = 2, d = 2, feel = "stone" }),
	B({ id = "bambooscreen", name = "Bamboo Screen", kind = "decor", sub = "zen", shells = 200, w = 2, d = 1, tier = 4, blurb = "Canes tied in a panel." }),
	B({ id = "windchime", name = "Wind Chimes", kind = "decor", sub = "zen", shells = 220, w = 1, d = 1, tier = 4, feel = "metal", blurb = "Ring in the wind." }),
	B({ id = "stonelantern", name = "Stone Lantern", kind = "decor", sub = "zen", shells = 400, w = 1, d = 1, tier = 4, feel = "stone", blurb = "A small light in a stone house." }),
	B({ id = "zenbasin", name = "Water Basin", kind = "decor", sub = "zen", shells = 500, w = 1, d = 1, tier = 5, feel = "water", blurb = "Bamboo drips into a stone bowl." }),
	B({ id = "lanterntower", name = "Lantern Tower", kind = "decor", sub = "zen", shells = 4800, w = 2, d = 2, tier = 7, feel = "stone", blurb = "Stone roofs stacked five high." }),
	B({ id = "teahouse", name = "Tea Pavilion", kind = "decor", sub = "zen", shells = 25000, w = 4, d = 4, tier = 18, blurb = "The kettle's on." }),
	-- the volcano
	B({ id = "firebasin", name = "Fire Basin", kind = "decor", sub = "volcano", shells = 900, w = 1, d = 1, tier = 7, feel = "fire", blurb = "Flames in an iron bowl." }),
	B({ id = "steamvent", name = "Steam Vent", kind = "decor", sub = "volcano", shells = 1400, w = 2, d = 2, tier = 7, feel = "fire", blurb = "Hot breath from under the island." }),
	B({ id = "obsidian", name = "Obsidian Spire", kind = "decor", sub = "volcano", shells = 5000, w = 2, d = 2, tier = 8, feel = "stone", blurb = "Black glass, sharp as a knife." }),
	B({ id = "lavapool", name = "Lava Pool", kind = "decor", sub = "volcano", shells = 9000, w = 3, d = 3, tier = 9, feel = "fire", blurb = "Much too hot." }),
	B({ id = "emberforge", name = "Ember Forge", kind = "decor", sub = "volcano", shells = 22000, w = 3, d = 3, tier = 17, feel = "fire", blurb = "An anvil by the fire." }),
	-- grand pieces
	B({ id = "statue", name = "Guardian Statue", kind = "decor", sub = "grand", shells = 17000, w = 3, d = 3, tier = 3, feel = "stone" }),
	B({ id = "grandarch", name = "Grand Arch", kind = "decor", sub = "grand", shells = 32000, w = 5, d = 2, tier = 5, feel = "stone" }),
	B({ id = "observatory", name = "Observatory", kind = "decor", sub = "grand", shells = 43000, w = 4, d = 4, tier = 5, feel = "stone" }),
	B({ id = "sunspire", name = "Sun Spire", kind = "decor", sub = "grand", shells = 130000, w = 3, d = 3, tier = 6, feel = "magic" }),
	B({ id = "monument", name = "Founder Monument", kind = "decor", sub = "grand", shells = 160000, w = 4, d = 4, tier = 6, feel = "stone" }),
	B({ id = "goldstatue", name = "Golden Driftling", kind = "decor", sub = "grand", shells = 300000, w = 3, d = 3, tier = 7, feel = "metal", blurb = "A driftling cast in gold." }),
	B({ id = "bellspire", name = "Sky Bell Tower", kind = "decor", sub = "grand", shells = 520000, w = 3, d = 3, tier = 8, feel = "stone", blurb = "Heard on every island." }),
	B({ id = "crystalspire", name = "Crystal Spire", kind = "decor", sub = "grand", shells = 900000, w = 3, d = 3, tier = 9, feel = "magic", blurb = "A tower of grown crystal." }),
	B({ id = "rainbowarch", name = "Rainbow Arch", kind = "decor", sub = "grand", shells = 1500000, w = 5, d = 2, tier = 10, feel = "magic", blurb = "Every colour, end to end." }),
	B({ id = "colossus", name = "Driftling Colossus", kind = "decor", sub = "grand", shells = 2400000, w = 4, d = 4, tier = 12, feel = "stone", blurb = "A stone driftling, tower tall." }),
	B({ id = "moonwell", name = "Moonwell", kind = "decor", sub = "grand", shells = 4200000, w = 4, d = 4, tier = 15, feel = "magic", blurb = "A well that holds the moon." }),
	B({ id = "stargate", name = "Star Gate", kind = "decor", sub = "grand", shells = 7000000, w = 5, d = 2, tier = 18, feel = "magic", blurb = "A stone ring full of stars." }),
	B({ id = "seacrown", name = "Crown of the Sea", kind = "decor", sub = "grand", shells = 12000000, w = 5, d = 5, tier = 20, feel = "metal", blurb = "Rings of coral and gold." }),
	-- fun: seats
	B({ id = "logseats", name = "Log Seats", kind = "decor", tab = "fun", sub = "seats", shells = 50, w = 2, d = 2, blurb = "Logs round a stump table." }),
	B({ id = "bench", name = "Bench", kind = "decor", tab = "fun", sub = "seats", shells = 160, w = 3, d = 2 }),
	B({ id = "parkbench", name = "Park Bench", kind = "decor", tab = "fun", sub = "seats", shells = 220, w = 3, d = 1, tier = 2, feel = "metal", blurb = "Iron legs and green slats." }),
	B({ id = "hammock", name = "Hammock", kind = "decor", tab = "fun", sub = "seats", shells = 320, w = 4, d = 2, feel = "cloth" }),
	B({ id = "picnic", name = "Picnic Table", kind = "decor", tab = "fun", sub = "seats", shells = 430, w = 4, d = 3, tier = 2 }),
	B({ id = "stonebench", name = "Stone Bench", kind = "decor", tab = "fun", sub = "seats", shells = 380, w = 3, d = 1, tier = 3, feel = "stone", blurb = "Cool to sit on in summer." }),
	B({ id = "porchswing", name = "Porch Swing", kind = "decor", tab = "fun", sub = "seats", shells = 700, w = 3, d = 2, tier = 3, blurb = "A bench on chains." }),
	-- fun: lights
	B({ id = "gardenlights", name = "Garden Lights", kind = "decor", tab = "fun", sub = "lights", shells = 40, w = 1, d = 1, feel = "fire", blurb = "Little lamps along a border." }),
	B({ id = "torch", name = "Tiki Torch", kind = "decor", tab = "fun", sub = "lights", shells = 60, w = 1, d = 1, feel = "fire" }),
	B({ id = "firepit", name = "Fire Pit", kind = "decor", tab = "fun", sub = "lights", shells = 90, w = 2, d = 2, feel = "fire", blurb = "Stones round a fire." }),
	B({ id = "candles", name = "Candles", kind = "decor", tab = "fun", sub = "lights", shells = 60, w = 1, d = 1, tier = 2, feel = "fire", blurb = "Three candles on a stone." }),
	B({ id = "paperlanterns", name = "Paper Lanterns", kind = "decor", tab = "fun", sub = "lights", shells = 150, w = 2, d = 1, tier = 2, feel = "fire", blurb = "Round lanterns on a line." }),
	B({ id = "lamppost", name = "Lamp Post", kind = "decor", tab = "fun", sub = "lights", shells = 190, w = 1, d = 1, tier = 2, feel = "metal" }),
	B({ id = "stringlights", name = "String Lights", kind = "decor", tab = "fun", sub = "lights", shells = 260, w = 3, d = 1, tier = 3, feel = "fire", blurb = "Bulbs between two poles." }),
	B({ id = "streetlamp", name = "Street Lamp", kind = "decor", tab = "fun", sub = "lights", shells = 640, w = 1, d = 1, tier = 4, feel = "metal" }),
	-- fun: play
	B({ id = "sandbox", name = "Sandbox", kind = "decor", tab = "fun", sub = "play", shells = 90, w = 2, d = 2, feel = "sand", blurb = "A bucket and spade left in it." }),
	B({ id = "seesaw", name = "Seesaw", kind = "decor", tab = "fun", sub = "play", shells = 350, w = 3, d = 1, tier = 2, blurb = "Up, down, up." }),
	B({ id = "swing", name = "Swing Set", kind = "decor", tab = "fun", sub = "play", shells = 450, w = 3, d = 2, tier = 2, blurb = "Two swings on a frame." }),
	B({ id = "slide", name = "Slide", kind = "decor", tab = "fun", sub = "play", shells = 800, w = 3, d = 2, tier = 3, feel = "metal", blurb = "A ladder up, a slide down." }),
	B({ id = "trampoline", name = "Trampoline", kind = "decor", tab = "fun", sub = "play", shells = 1600, w = 3, d = 3, tier = 4, feel = "cloth", blurb = "Bounce as high as a hut." }),
	B({ id = "carousel", name = "Merry-Go-Round", kind = "decor", tab = "fun", sub = "play", shells = 1800, w = 3, d = 3, tier = 4, feel = "metal", blurb = "Hold on and spin." }),
	B({ id = "climbframe", name = "Climbing Frame", kind = "decor", tab = "fun", sub = "play", shells = 2400, w = 3, d = 3, tier = 5, blurb = "Bars and a lookout." }),
	B({ id = "bigwheel", name = "Big Wheel", kind = "decor", tab = "fun", sub = "play", shells = 26000, w = 4, d = 2, tier = 13, feel = "metal", blurb = "Once round for the view." }),
	-- fun: food and treats
	B({ id = "grill", name = "Grill", kind = "decor", tab = "fun", sub = "treats", shells = 160, w = 1, d = 1, tier = 2, feel = "fire", blurb = "Smoke and something tasty." }),
	B({ id = "lemonade", name = "Lemonade Stand", kind = "decor", tab = "fun", sub = "treats", shells = 300, w = 2, d = 1, tier = 2, blurb = "A jug and some cups." }),
	B({ id = "icecream", name = "Ice Cream Cart", kind = "decor", tab = "fun", sub = "treats", shells = 600, w = 2, d = 1, tier = 3, feel = "metal", blurb = "Three flavours and a bell." }),
	B({ id = "telescope", name = "Telescope", kind = "decor", tab = "fun", sub = "treats", shells = 900, w = 1, d = 1, tier = 4, feel = "metal", blurb = "Look at the other islands." }),
	B({ id = "tikibar", name = "Tiki Bar", kind = "decor", tab = "fun", sub = "treats", shells = 2200, w = 3, d = 2, tier = 4, blurb = "Grass roof, bamboo bar." }),
	-- fun: fountains
	B({ id = "drinkfountain", name = "Drinking Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 140, w = 1, d = 1, tier = 2, feel = "water", blurb = "A cool drink for anyone." }),
	B({ id = "smallfountain", name = "Little Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 700, w = 2, d = 2, tier = 2, feel = "water", blurb = "A jet of water in a bowl." }),
	B({ id = "fountain", name = "Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 2600, w = 5, d = 5, tier = 2, feel = "water" }),
	B({ id = "koipond", name = "Koi Pond", kind = "decor", tab = "fun", sub = "fountains", shells = 2500, w = 3, d = 3, tier = 5, feel = "water", blurb = "Orange fish under the lily pads." }),
	B({ id = "crystalfountain", name = "Crystal Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 85000, w = 5, d = 5, tier = 6, feel = "magic" }),
}
-- stylua: ignore end

-- the Tree of Life (GAME_DESIGN 6; Logic/Tree): every island has one from the start; it is never bought or cleared
-- away (tier 99 keeps it off every tab), but it can be moved. Its eggs lie in a ring on the lawn round its stones,
-- inside its footprint (Controllers/EggView)
table.insert(LIST, B({ id = "tree", name = "Tree of Life", kind = "tree", w = 8, d = 8, charm = 6, tier = 99, blurb = "Lays eggs round its roots." }))

local BY_ID: { [string]: BuildingDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

-- A piece's charm on an island of `tier`: a decor piece's tiles (w x d) times Tuning.DecorCharm at that tier, every
-- other piece its own `charm`. What the island's charm sums (Logic/Island.charm) and Build mode shows.
local function charmOf(d: BuildingDef, tier: number): number
	if d.kind == "decor" then
		local per = Tuning.DecorCharm[math.clamp(math.floor(tier), 1, #Tuning.DecorCharm)]
		return per * d.w * math.max(1, d.d)
	end
	return d.charm
end

return table.freeze({ list = LIST, byId = BY_ID, shellsFor = shellsFor, charmOf = charmOf })
