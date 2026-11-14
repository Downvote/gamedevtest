--!strict
-- What can stand on an island (GAME_DESIGN 4): buildings that make shells, huts for the driftlings (who do all the
-- work: no villagers since 2026-11-12), and decor for charm. Pure. Each piece is paid for in shells when it is placed
-- (the request of 2026-11-14: "make shells the main currency, allowing you to buy decor and expansions with it. remove
-- wood as a currency": the prices that were wood are shells now, one for one), may be placed as often as the island's
-- piece limit allows (Logic/Plot), and is built by Models/DecorModels. w x d: its footprint in whole studs facing south (a quarter turn
-- swaps them).
--   kind:  "farm" (sells what it grows or catches) | "wood" (sells what it cuts) | "shop" (sells snacks and stays):
--          the Work tab's three groups, each making shells
--          | "nest" (a driftlings' hut) | "breed" (the Hatchery: two driftlings make an egg, Logic/Breed) | "gen" (a
--          boost building: every building of a knack makes more) | "path" (a 2 x 2 tile of path or road: drawn, apart
--          from the piece limit with the water, Tuning.PathPieces) | "water" (a 2 x 2 tile of water: drawn, for rivers
--          and ponds; GAME_DESIGN 4: "add the ability to add water to make rivers") | "fence" (a 2-stud length of fence
--          along a grid line: drawn, apart, Tuning.FencePieces; w 2, d 0) | "decor" (nature, themed decor and the
--          things to do, seats and lights: Build mode's Nature, Decor, Fun and Water tabs) | "tree" (the Tree of Life:
--          every island's, never bought)
--   rate:  the shells it makes a turn with one common driftling working there (Logic/Island). The wood buildings made
--          wood until 2026-11-14; selling it, they make about what a farm of the same price makes (the Lumber Camp 36,
--          the Sawmill 130, Timber Works 240, the Bamboo Grove 440, the Grand Mill 880)
--   knack: the driftlings that work there (Data/Creatures)
--   slots: the driftlings a hut houses (its room)
--   charm: what it adds to the island's charm (more charm, more shells: Logic/Island.charmBonus)
--   comfort: a hut's share added to its residents' work (Logic/Island.homes)
--   boost / boostBy: a boost building's knack ("farm" "wood" "shop", or "all") and its share (each kind of boost
--          building counts once however many stand: Logic/Island.boosts)
--   tier:  the island tier it needs
--   tab / sub: where Build mode lists it (its tab, and the row of chips under it: a decor piece's theme, a nature
--          piece's kind, a work building's kind); from its kind when not given
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
	knack: string,
	slots: number,
	charm: number,
	comfort: number,
	boost: string,
	boostBy: number,
	tier: number,
	blurb: string,
	tab: string,
	sub: string,
	water: string,
	feel: string,
}

-- A kind's tab, chip row and feel when a piece doesn't give its own.
local TAB: { [string]: string } = { farm = "work", wood = "work", shop = "work", gen = "work", nest = "nest", breed = "nest", path = "path", water = "water", fence = "fence", decor = "decor", tree = "" }
local SUB: { [string]: string } = { farm = "farm", wood = "wood", shop = "shop", gen = "gen", water = "tiles" }
local FEEL: { [string]: string } = { path = "stone", water = "water", fence = "wood", farm = "plant" }

-- A wood price in shells for a piece of a tier (Tuning.WoodShells for each wood, times WoodTierUp for each tier past the
-- second), to two figures (1 at least; nothing stays nothing).
local function shellsFor(wood: number, tier: number): number
	if wood <= 0 then
		return 0
	end
	local w = wood * Tuning.WoodShells * Tuning.WoodTierUp ^ math.max(0, tier - 2)
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
	return {
		id = t.id,
		name = t.name,
		kind = t.kind,
		shells = priceOf(t.kind, t.shells or 0, t.tier or 1),
		w = t.w,
		d = t.d,
		rate = t.rate or 0,
		knack = t.knack or "",
		slots = t.slots or 0,
		charm = t.charm or 0,
		comfort = t.comfort or 0,
		boost = t.boost or "",
		boostBy = t.boostBy or 0,
		tier = t.tier or 1,
		blurb = t.blurb or "",
		tab = t.tab or TAB[t.kind] or "decor",
		sub = t.sub or SUB[t.kind] or "",
		water = t.water or "",
		feel = t.feel or FEEL[t.kind] or "wood",
	}
end

-- stylua: ignore start
local LIST: { BuildingDef } = {
	-- farms: they sell what they grow or catch (shells)
	B({ id = "patch", name = "Veggie Patch", kind = "farm", shells = 40, w = 3, d = 3, rate = 36, knack = "farm", charm = 1, blurb = "Grows veggies to sell." }),
	B({ id = "pier", name = "Fishing Pier", kind = "farm", shells = 160, w = 3, d = 3, rate = 60, knack = "farm", charm = 1, blurb = "Lands fish to sell." }),
	B({ id = "orchard", name = "Fruit Orchard", kind = "farm", shells = 460, w = 4, d = 4, rate = 102, knack = "farm", charm = 3, tier = 2, blurb = "Lots of fruit to sell." }),
	B({ id = "greenhouse", name = "Greenhouse", kind = "farm", shells = 2900, w = 4, d = 3, rate = 240, knack = "farm", charm = 4, tier = 3, blurb = "Something to sell all year." }),
	B({ id = "paddy", name = "Rice Terrace", kind = "farm", shells = 9800, w = 4, d = 4, rate = 510, knack = "farm", charm = 5, tier = 4, blurb = "Steps of rice in still water." }),
	B({ id = "kelpfarm", name = "Kelp Farm", kind = "farm", shells = 28000, w = 4, d = 4, rate = 990, knack = "farm", charm = 6, tier = 5, blurb = "Rows of kelp in a sea pen." }),
	B({ id = "skygarden", name = "Sky Garden", kind = "farm", shells = 76000, w = 5, d = 4, rate = 1800, knack = "farm", charm = 12, tier = 6, blurb = "Gardens stacked up a glass tower." }),
	-- wood
	B({ id = "lumber", name = "Lumber Camp", kind = "wood", shells = 70, w = 4, d = 3, rate = 36, knack = "wood", blurb = "Chops wood to sell." }),
	B({ id = "sawmill", name = "Sawmill", kind = "wood", shells = 640, w = 4, d = 4, rate = 130, knack = "wood", charm = 1, tier = 2, blurb = "Saws planks to sell." }),
	B({ id = "timber", name = "Timber Works", kind = "wood", shells = 2900, w = 4, d = 4, rate = 240, knack = "wood", charm = 2, tier = 3, blurb = "A crane and stacks of planks." }),
	B({ id = "bamboo", name = "Bamboo Grove", kind = "wood", shells = 8300, w = 4, d = 3, rate = 440, knack = "wood", charm = 4, tier = 4, blurb = "Bamboo grows back by the day." }),
	B({ id = "grandmill", name = "Grand Mill", kind = "wood", shells = 25000, w = 5, d = 4, rate = 880, knack = "wood", charm = 6, tier = 5, blurb = "A waterwheel turns its saws." }),
	-- shops: snacks, meals and rooms (shells)
	B({ id = "stall", name = "Snack Stall", kind = "shop", shells = 100, w = 3, d = 2, rate = 36, knack = "shop", charm = 2, blurb = "Sells snacks by the path." }),
	B({ id = "cafe", name = "Beach Cafe", kind = "shop", shells = 990, w = 4, d = 3, rate = 120, knack = "shop", charm = 5, tier = 2, blurb = "Iced drinks and a bite to eat." }),
	B({ id = "inn", name = "Seaside Inn", kind = "shop", shells = 5700, w = 5, d = 4, rate = 340, knack = "shop", charm = 10, tier = 3, blurb = "Rooms with a view of the sea." }),
	B({ id = "bakery", name = "Bakery", kind = "shop", shells = 15000, w = 4, d = 3, rate = 700, knack = "shop", charm = 12, tier = 4, blurb = "Warm bread for the whole town." }),
	B({ id = "bazaar", name = "Grand Bazaar", kind = "shop", shells = 44000, w = 5, d = 4, rate = 1500, knack = "shop", charm = 20, tier = 5, blurb = "Stalls under striped awnings." }),
	B({ id = "hotel", name = "Grand Hotel", kind = "shop", shells = 120000, w = 5, d = 5, rate = 3200, knack = "shop", charm = 35, tier = 6, blurb = "Five floors of rooms over the bay." }),
	-- huts (kind "nest"): room for driftlings, and comfort
	B({ id = "nest", name = "Driftling Hut", kind = "nest", shells = 55, w = 2, d = 2, slots = 2, blurb = "Room for two driftlings. They work from here." }),
	B({ id = "burrow", name = "Cozy Burrow", kind = "nest", shells = 420, w = 3, d = 3, slots = 4, charm = 1, comfort = 0.05, tier = 2, blurb = "Room for four." }),
	B({ id = "den", name = "Driftling Den", kind = "nest", shells = 2200, w = 3, d = 3, slots = 5, charm = 3, comfort = 0.08, tier = 3, blurb = "A mossy den with soft beds." }),
	B({ id = "roost", name = "Treetop Roost", kind = "nest", shells = 7100, w = 4, d = 4, slots = 6, charm = 5, comfort = 0.12, tier = 4, blurb = "Nests in a great tree." }),
	B({ id = "grotto", name = "Spring Grotto", kind = "nest", shells = 20000, w = 4, d = 4, slots = 8, charm = 8, comfort = 0.18, tier = 5, blurb = "A warm spring under a rock." }),
	B({ id = "palace", name = "Driftling Palace", kind = "nest", shells = 60000, w = 5, d = 5, slots = 12, charm = 14, comfort = 0.25, tier = 6, blurb = "The comfiest hut there is." }),
	-- the Hatchery (GAME_DESIGN 6.1): an egg at a time
	B({ id = "hatchery", name = "Hatchery", kind = "breed", shells = 3900, w = 4, d = 4, charm = 3, tier = 3, blurb = "Two driftlings and a feast make an egg." }),
	-- boosts: every building of a knack makes more (each kind counts once)
	B({ id = "toolshed", name = "Tool Shed", kind = "gen", shells = 1300, w = 2, d = 2, charm = 1, boost = "wood", boostBy = 0.1, tier = 2, blurb = "Sharp axes: wood +10%." }),
	B({ id = "windmill", name = "Windmill", kind = "gen", shells = 1600, w = 3, d = 3, charm = 4, boost = "farm", boostBy = 0.1, tier = 2, blurb = "Grinds the harvest: farms +10%." }),
	B({ id = "smokehouse", name = "Smokehouse", kind = "gen", shells = 1500, w = 3, d = 3, charm = 2, boost = "farm", boostBy = 0.1, tier = 2, blurb = "Smoked fish keeps: farms +10%." }),
	B({ id = "market", name = "Market Hall", kind = "gen", shells = 5500, w = 4, d = 3, charm = 8, boost = "shop", boostBy = 0.12, tier = 3, blurb = "Brings the buyers: shops +12%." }),
	B({ id = "watertower", name = "Water Tower", kind = "gen", shells = 13000, w = 3, d = 3, charm = 6, boost = "all", boostBy = 0.06, tier = 4, blurb = "Fresh water for all: everything +6%." }),
	B({ id = "townhall", name = "Town Hall", kind = "gen", shells = 39000, w = 5, d = 4, charm = 30, boost = "all", boostBy = 0.1, tier = 5, blurb = "The town runs smoothly: everything +10%." }),
	B({ id = "beacon", name = "Sun Beacon", kind = "gen", shells = 97000, w = 3, d = 3, charm = 40, boost = "all", boostBy = 0.15, tier = 6, blurb = "Its light never sets: everything +15%." }),
	-- paths: 2 x 2 tiles of path and road, drawn (apart from the piece limit, with the water: Tuning.PathPieces)
	B({ id = "dirtpath", name = "Dirt Path", kind = "path", shells = 5, w = 2, d = 2, feel = "sand", blurb = "A trodden path." }),
	B({ id = "sandtrail", name = "Sand Trail", kind = "path", shells = 4, w = 2, d = 2, feel = "sand", blurb = "Soft sand, packed down." }),
	B({ id = "gravel", name = "Gravel Path", kind = "path", shells = 8, w = 2, d = 2, blurb = "Grey grit that crunches." }),
	B({ id = "shellpath", name = "Shell Path", kind = "path", shells = 10, w = 2, d = 2, charm = 0.25, feel = "sand", blurb = "Crushed shells, pale and bright." }),
	B({ id = "plankwalk", name = "Plank Walk", kind = "path", shells = 12, w = 2, d = 2, charm = 0.25, feel = "wood", blurb = "Boards laid side by side." }),
	B({ id = "stonepath", name = "Stone Path", kind = "path", shells = 15, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Flat stones set in sand." }),
	B({ id = "flagstone", name = "Flagstones", kind = "path", shells = 18, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Big flat stones with grass between." }),
	B({ id = "cobble", name = "Cobblestones", kind = "path", shells = 22, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Round stones, old and worn." }),
	B({ id = "mossstone", name = "Mossy Stones", kind = "path", shells = 20, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Stones the moss got to first." }),
	B({ id = "leafpath", name = "Leaf Litter", kind = "path", shells = 10, w = 2, d = 2, charm = 0.25, tier = 2, feel = "plant", blurb = "Red and gold leaves on the ground." }),
	B({ id = "meadow", name = "Flower Meadow", kind = "path", shells = 14, w = 2, d = 2, charm = 0.5, tier = 2, feel = "plant", blurb = "Long grass full of small flowers." }),
	B({ id = "raked", name = "Raked Gravel", kind = "path", shells = 20, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Gravel combed into lines." }),
	B({ id = "snowpath", name = "Snowy Path", kind = "path", shells = 16, w = 2, d = 2, charm = 0.5, tier = 3, feel = "snow", blurb = "Snow with footprints in it." }),
	B({ id = "sandstone", name = "Sandstone Tiles", kind = "path", shells = 30, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Warm yellow slabs." }),
	B({ id = "terracotta", name = "Terracotta Tiles", kind = "path", shells = 34, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Baked clay squares." }),
	B({ id = "checker", name = "Checker Tiles", kind = "path", shells = 30, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Black and white squares." }),
	B({ id = "brickroad", name = "Brick Road", kind = "path", shells = 40, w = 2, d = 2, charm = 0.5, tier = 4, blurb = "A town's red brick road." }),
	B({ id = "crystalpath", name = "Crystal Path", kind = "path", shells = 70, w = 2, d = 2, charm = 1, tier = 5, feel = "magic", blurb = "Stones that glow a little at night." }),
	B({ id = "basalt", name = "Basalt Steps", kind = "path", shells = 60, w = 2, d = 2, charm = 1, tier = 5, feel = "fire", blurb = "Black rock with warm cracks." }),
	B({ id = "marblewalk", name = "Marble Walk", kind = "path", shells = 90, w = 2, d = 2, charm = 1, tier = 5, blurb = "White marble with a gold inlay." }),
	B({ id = "goldpath", name = "Gilded Walk", kind = "path", shells = 220, w = 2, d = 2, charm = 2, tier = 7, feel = "metal", blurb = "Gold edging on cream stone." }),
	B({ id = "starpath", name = "Starlit Path", kind = "path", shells = 300, w = 2, d = 2, charm = 2, tier = 8, feel = "magic", blurb = "Dark blue stone full of little stars." }),
	-- water: 2 x 2 tiles drawn like paths into rivers and ponds (GAME_DESIGN 4.3); the founder wades through
	B({ id = "stream", name = "Stream", kind = "water", shells = 12, w = 2, d = 2, charm = 0.5, blurb = "Clear, shallow water." }),
	B({ id = "river", name = "Deep River", kind = "water", shells = 18, w = 2, d = 2, charm = 0.5, tier = 2, blurb = "Darker water with a current." }),
	B({ id = "lilypond", name = "Lily Pond", kind = "water", shells = 22, w = 2, d = 2, charm = 1, tier = 2, blurb = "Still water with pads on it." }),
	B({ id = "swamp", name = "Swamp Water", kind = "water", shells = 20, w = 2, d = 2, charm = 0.5, tier = 3, blurb = "Murky green and very still." }),
	B({ id = "lagoon", name = "Lagoon", kind = "water", shells = 30, w = 2, d = 2, charm = 1, tier = 4, blurb = "Bright blue-green, like the reef." }),
	B({ id = "hotspring", name = "Hot Spring", kind = "water", shells = 40, w = 2, d = 2, charm = 1, tier = 5, blurb = "Warm water that steams." }),
	B({ id = "icepond", name = "Frozen Pond", kind = "water", shells = 30, w = 2, d = 2, charm = 1, tier = 6, feel = "snow", blurb = "Ice thick enough to stand on." }),
	-- fences: 2-stud lengths drawn along the grid lines (apart: Tuning.FencePieces)
	B({ id = "ropefence", name = "Rope Fence", kind = "fence", shells = 6, w = 2, d = 0, charm = 0.25, blurb = "Posts and a sagging rope." }),
	B({ id = "picket", name = "Picket Fence", kind = "fence", shells = 8, w = 2, d = 0, charm = 0.5, blurb = "White pickets for a cottage garden." }),
	B({ id = "splitrail", name = "Split Rail", kind = "fence", shells = 10, w = 2, d = 0, charm = 0.25, blurb = "Rough rails for a farm." }),
	B({ id = "bamboofence", name = "Bamboo Fence", kind = "fence", shells = 14, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Canes tied with cord." }),
	B({ id = "driftwood", name = "Driftwood Fence", kind = "fence", shells = 12, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Pale wood the sea brought in." }),
	B({ id = "wattle", name = "Woven Fence", kind = "fence", shells = 14, w = 2, d = 0, charm = 0.5, tier = 2, blurb = "Willow woven between stakes." }),
	B({ id = "hedgerow", name = "Hedgerow", kind = "fence", shells = 20, w = 2, d = 0, charm = 0.75, tier = 2, feel = "plant", blurb = "A clipped green hedge." }),
	B({ id = "gardengate", name = "Garden Gate", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 2, blurb = "A white gate under a little arch." }),
	B({ id = "stonewall", name = "Low Stone Wall", kind = "fence", shells = 28, w = 2, d = 0, charm = 0.75, tier = 3, feel = "stone", blurb = "Field stones piled waist high." }),
	B({ id = "palisade", name = "Log Palisade", kind = "fence", shells = 26, w = 2, d = 0, charm = 0.75, tier = 3, blurb = "Sharpened logs side by side." }),
	B({ id = "ironrail", name = "Iron Railing", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 4, feel = "metal", blurb = "Black bars with spear tips." }),
	B({ id = "lanternrope", name = "Lantern Rope", kind = "fence", shells = 45, w = 2, d = 0, charm = 1, tier = 4, feel = "fire", blurb = "Posts strung with little lights." }),
	B({ id = "brickwall", name = "Brick Wall", kind = "fence", shells = 55, w = 2, d = 0, charm = 1, tier = 5, feel = "stone", blurb = "Red brick with a stone cap." }),
	B({ id = "adobe", name = "Adobe Wall", kind = "fence", shells = 50, w = 2, d = 0, charm = 1, tier = 5, feel = "sand", blurb = "Smooth mud walls, sun dried." }),
	B({ id = "icewall", name = "Snowbank", kind = "fence", shells = 40, w = 2, d = 0, charm = 1, tier = 6, feel = "snow", blurb = "Packed snow with icicles." }),
	B({ id = "shellwall", name = "Shell Wall", kind = "fence", shells = 60, w = 2, d = 0, charm = 1.5, tier = 6, feel = "stone", blurb = "White stone set with shells." }),
	B({ id = "crystalfence", name = "Crystal Fence", kind = "fence", shells = 120, w = 2, d = 0, charm = 2, tier = 8, feel = "magic", blurb = "Glowing points of crystal." }),
	-- water decor: bridges and docks over the water, and things that float on it
	B({ id = "plankbridge", name = "Plank Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 120, w = 2, d = 6, charm = 4, blurb = "Boards across a stream." }),
	B({ id = "dock", name = "Little Dock", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 300, w = 3, d = 4, charm = 6, tier = 2, blurb = "A short jetty to sit on." }),
	B({ id = "ropebridge", name = "Rope Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 400, w = 2, d = 6, charm = 8, tier = 3, blurb = "Slats hung on two ropes." }),
	B({ id = "stonebridge", name = "Stone Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 900, w = 3, d = 6, charm = 12, tier = 3, feel = "stone", blurb = "One round arch of stone." }),
	B({ id = "waterwheel", name = "Waterwheel", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 1400, w = 3, d = 2, charm = 16, tier = 4, blurb = "It turns in the current." }),
	B({ id = "canal", name = "Canal Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 8600, w = 4, d = 3, charm = 40, tier = 5, feel = "stone", blurb = "A town bridge with railings." }),
	B({ id = "moonbridge", name = "Moon Bridge", kind = "decor", tab = "water", sub = "bridge", water = "over", shells = 3200, w = 3, d = 6, charm = 26, tier = 6, blurb = "A high red arch over still water." }),
	B({ id = "lilypads", name = "Lily Pads", kind = "decor", tab = "water", sub = "float", water = "on", shells = 20, w = 2, d = 2, charm = 1, feel = "plant", blurb = "Round leaves floating flat." }),
	B({ id = "reeds", name = "Reeds", kind = "decor", tab = "water", sub = "float", water = "on", shells = 25, w = 2, d = 2, charm = 1, feel = "plant", blurb = "Tall reeds and cattails." }),
	B({ id = "steppingstones", name = "Stepping Stones", kind = "decor", tab = "water", sub = "float", water = "on", shells = 30, w = 2, d = 2, charm = 1, feel = "stone", blurb = "Hop across without wet feet." }),
	B({ id = "duckfloat", name = "Duck Decoy", kind = "decor", tab = "water", sub = "float", water = "on", shells = 60, w = 2, d = 2, charm = 2, tier = 2, blurb = "A wooden duck bobbing about." }),
	B({ id = "rowboat", name = "Rowboat", kind = "decor", tab = "water", sub = "float", water = "on", shells = 180, w = 2, d = 4, charm = 4, tier = 2, blurb = "Oars shipped, ready to go." }),
	B({ id = "lotus", name = "Lotus Flowers", kind = "decor", tab = "water", sub = "float", water = "on", shells = 90, w = 2, d = 2, charm = 3, tier = 3, feel = "plant", blurb = "Pink flowers on still water." }),
	B({ id = "littlefall", name = "Little Waterfall", kind = "decor", tab = "water", sub = "float", water = "over", shells = 600, w = 2, d = 2, charm = 8, tier = 3, feel = "water", blurb = "Water spilling over mossy rocks." }),
	B({ id = "waterlanterns", name = "Floating Lanterns", kind = "decor", tab = "water", sub = "float", water = "on", shells = 220, w = 2, d = 2, charm = 5, tier = 4, feel = "fire", blurb = "Paper lights drifting at dusk." }),
	-- nature: trees
	B({ id = "pine", name = "Pine Tree", kind = "decor", tab = "nature", sub = "trees", shells = 70, w = 2, d = 2, charm = 3, feel = "plant", blurb = "Tall and dark green." }),
	B({ id = "oak", name = "Oak Tree", kind = "decor", tab = "nature", sub = "trees", shells = 90, w = 3, d = 3, charm = 3, feel = "plant", blurb = "A round, leafy shade tree." }),
	B({ id = "palm", name = "Palm Tree", kind = "decor", tab = "nature", sub = "trees", shells = 120, w = 3, d = 3, charm = 4, feel = "plant", blurb = "Coconuts up top." }),
	B({ id = "deadtree", name = "Bare Tree", kind = "decor", tab = "nature", sub = "trees", shells = 80, w = 2, d = 2, charm = 2, tier = 2, feel = "wood", blurb = "Twisted branches, no leaves." }),
	B({ id = "birch", name = "Birch Tree", kind = "decor", tab = "nature", sub = "trees", shells = 110, w = 2, d = 2, charm = 4, tier = 2, feel = "plant", blurb = "White bark, light leaves." }),
	B({ id = "cherry", name = "Cherry Blossom", kind = "decor", tab = "nature", sub = "trees", shells = 600, w = 3, d = 3, charm = 9, tier = 3, feel = "plant", blurb = "A cloud of pink flowers." }),
	B({ id = "maple", name = "Maple Tree", kind = "decor", tab = "nature", sub = "trees", shells = 520, w = 3, d = 3, charm = 8, tier = 3, feel = "plant", blurb = "Leaves gone red and orange." }),
	B({ id = "jungletree", name = "Jungle Tree", kind = "decor", tab = "nature", sub = "trees", shells = 700, w = 3, d = 3, charm = 9, tier = 3, feel = "plant", blurb = "Huge leaves and hanging vines." }),
	B({ id = "willow", name = "Willow", kind = "decor", tab = "nature", sub = "trees", shells = 1800, w = 4, d = 4, charm = 15, tier = 4, feel = "plant", blurb = "Long branches down to the ground." }),
	B({ id = "bigoak", name = "Great Oak", kind = "decor", tab = "nature", sub = "trees", shells = 6000, w = 5, d = 5, charm = 30, tier = 5, feel = "plant", blurb = "Older than anyone remembers." }),
	B({ id = "snowpine", name = "Snowy Pine", kind = "decor", tab = "nature", sub = "trees", shells = 300, w = 2, d = 2, charm = 6, tier = 6, feel = "snow", blurb = "Branches heavy with snow." }),
	-- nature: plants and flowers
	B({ id = "fern", name = "Fern", kind = "decor", tab = "nature", sub = "plants", shells = 15, w = 1, d = 1, charm = 1, feel = "plant", blurb = "Feathery green fronds." }),
	B({ id = "tallgrass", name = "Tall Grass", kind = "decor", tab = "nature", sub = "plants", shells = 12, w = 2, d = 2, charm = 1, feel = "plant", blurb = "Grass that sways." }),
	B({ id = "bush", name = "Round Bush", kind = "decor", tab = "nature", sub = "plants", shells = 30, w = 2, d = 2, charm = 1, feel = "plant" }),
	B({ id = "berrybush", name = "Berry Bush", kind = "decor", tab = "nature", sub = "plants", shells = 45, w = 2, d = 2, charm = 2, feel = "plant", blurb = "Covered in red berries." }),
	B({ id = "tulips", name = "Tulip Row", kind = "decor", tab = "nature", sub = "plants", shells = 35, w = 2, d = 1, charm = 2, feel = "plant", blurb = "Red, yellow and pink." }),
	B({ id = "flowers", name = "Flower Bed", kind = "decor", tab = "nature", sub = "plants", shells = 40, w = 2, d = 2, charm = 2, feel = "plant" }),
	B({ id = "mushrooms", name = "Mushrooms", kind = "decor", tab = "nature", sub = "plants", shells = 30, w = 1, d = 1, charm = 1, tier = 2, feel = "plant", blurb = "Spotted caps in the grass." }),
	B({ id = "rosebush", name = "Rose Bush", kind = "decor", tab = "nature", sub = "plants", shells = 60, w = 2, d = 2, charm = 3, tier = 2, feel = "plant", blurb = "Red roses, mind the thorns." }),
	B({ id = "sunflowers", name = "Sunflowers", kind = "decor", tab = "nature", sub = "plants", shells = 70, w = 2, d = 2, charm = 3, tier = 2, feel = "plant", blurb = "Taller than a driftling." }),
	B({ id = "lavender", name = "Lavender", kind = "decor", tab = "nature", sub = "plants", shells = 45, w = 2, d = 1, charm = 2, tier = 2, feel = "plant", blurb = "Purple and smells lovely." }),
	B({ id = "pumpkins", name = "Pumpkin Patch", kind = "decor", tab = "nature", sub = "plants", shells = 80, w = 2, d = 2, charm = 3, tier = 2, feel = "plant", blurb = "Fat orange pumpkins on the vine." }),
	B({ id = "cactus", name = "Cactus", kind = "decor", tab = "nature", sub = "plants", shells = 70, w = 1, d = 1, charm = 2, tier = 3, feel = "plant", blurb = "Prickly, with one pink flower." }),
	B({ id = "monstera", name = "Big Leaf Plant", kind = "decor", tab = "nature", sub = "plants", shells = 120, w = 2, d = 2, charm = 3, tier = 3, feel = "plant", blurb = "Leaves as big as a door." }),
	B({ id = "bigcactus", name = "Tall Cactus", kind = "decor", tab = "nature", sub = "plants", shells = 240, w = 2, d = 2, charm = 5, tier = 4, feel = "plant", blurb = "Arms up like it's waving." }),
	B({ id = "giantshroom", name = "Giant Mushroom", kind = "decor", tab = "nature", sub = "plants", shells = 400, w = 2, d = 2, charm = 6, tier = 4, feel = "plant", blurb = "A red cap you could sit under." }),
	B({ id = "bonsai", name = "Bonsai", kind = "decor", tab = "nature", sub = "plants", shells = 350, w = 1, d = 1, charm = 5, tier = 4, feel = "plant", blurb = "A tiny old tree in a tray." }),
	B({ id = "glowshroom", name = "Glow Mushrooms", kind = "decor", tab = "nature", sub = "plants", shells = 260, w = 1, d = 1, charm = 5, tier = 6, feel = "magic", blurb = "Blue caps that light up." }),
	-- nature: rocks
	B({ id = "boulder", name = "Boulder", kind = "decor", tab = "nature", sub = "rocks", shells = 25, w = 2, d = 2, charm = 1, feel = "stone", blurb = "One big round rock." }),
	B({ id = "rockpile", name = "Rock Pile", kind = "decor", tab = "nature", sub = "rocks", shells = 30, w = 2, d = 2, charm = 1, feel = "stone", blurb = "A heap of smaller stones." }),
	B({ id = "mossrock", name = "Mossy Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 50, w = 2, d = 2, charm = 2, tier = 2, feel = "stone", blurb = "Green on the shady side." }),
	B({ id = "sandrock", name = "Desert Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 70, w = 2, d = 2, charm = 2, tier = 3, feel = "stone", blurb = "Red rock worn by the wind." }),
	B({ id = "crystals", name = "Crystal Cluster", kind = "decor", tab = "nature", sub = "rocks", shells = 600, w = 2, d = 2, charm = 9, tier = 5, feel = "magic", blurb = "Purple points that shine." }),
	B({ id = "snowrock", name = "Snowy Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 120, w = 2, d = 2, charm = 3, tier = 6, feel = "snow", blurb = "A rock with a cap of snow." }),
	B({ id = "basaltcols", name = "Basalt Columns", kind = "decor", tab = "nature", sub = "rocks", shells = 700, w = 2, d = 2, charm = 9, tier = 6, feel = "stone", blurb = "Six-sided pillars of black rock." }),
	B({ id = "lavarock", name = "Lava Rock", kind = "decor", tab = "nature", sub = "rocks", shells = 900, w = 2, d = 2, charm = 11, tier = 7, feel = "fire", blurb = "Still glowing in the cracks." }),
	-- decor by theme: the beach
	B({ id = "coconuts", name = "Coconut Pile", kind = "decor", sub = "beach", shells = 30, w = 1, d = 1, charm = 1, feel = "wood", blurb = "Fresh off the palm." }),
	B({ id = "sandcastle", name = "Sandcastle", kind = "decor", sub = "beach", shells = 50, w = 2, d = 2, charm = 2, feel = "sand" }),
	B({ id = "deckchair", name = "Deck Chair", kind = "decor", sub = "beach", shells = 60, w = 1, d = 2, charm = 2, feel = "cloth", blurb = "Striped and low to the ground." }),
	B({ id = "umbrella", name = "Beach Umbrella", kind = "decor", sub = "beach", shells = 70, w = 2, d = 2, charm = 2, feel = "cloth", blurb = "Shade with stripes." }),
	B({ id = "shellpile", name = "Shell Pile", kind = "decor", sub = "beach", shells = 80, w = 2, d = 2, charm = 3, feel = "sand" }),
	B({ id = "surfboards", name = "Surfboard Rack", kind = "decor", sub = "beach", shells = 140, w = 2, d = 1, charm = 3, tier = 2, blurb = "Three boards waiting for waves." }),
	B({ id = "lifeguard", name = "Lifeguard Chair", kind = "decor", sub = "beach", shells = 700, w = 2, d = 2, charm = 9, tier = 3, blurb = "A tall chair to watch the sea." }),
	-- the garden
	B({ id = "gnome", name = "Garden Gnome", kind = "decor", sub = "garden", shells = 50, w = 1, d = 1, charm = 2, feel = "stone", blurb = "Red hat, very serious." }),
	B({ id = "wheelbarrow", name = "Wheelbarrow", kind = "decor", sub = "garden", shells = 70, w = 2, d = 1, charm = 2, blurb = "Full of soil and a trowel." }),
	B({ id = "birdbath", name = "Birdbath", kind = "decor", sub = "garden", shells = 80, w = 1, d = 1, charm = 2, feel = "stone", blurb = "A stone bowl of water." }),
	B({ id = "beehive", name = "Beehive", kind = "decor", sub = "garden", shells = 120, w = 1, d = 1, charm = 3, tier = 2, blurb = "A busy little box." }),
	B({ id = "trellis", name = "Rose Trellis", kind = "decor", sub = "garden", shells = 160, w = 2, d = 1, charm = 3, tier = 2, feel = "plant", blurb = "Roses climbing a lattice." }),
	B({ id = "flowerarch", name = "Flower Arch", kind = "decor", sub = "garden", shells = 530, w = 3, d = 1, charm = 6, tier = 2, feel = "plant" }),
	B({ id = "sundial", name = "Sundial", kind = "decor", sub = "garden", shells = 300, w = 1, d = 1, charm = 5, tier = 3, feel = "stone", blurb = "Tells the time when it's sunny." }),
	B({ id = "gazebo", name = "Gazebo", kind = "decor", sub = "garden", shells = 4300, w = 4, d = 4, charm = 30, tier = 3 }),
	B({ id = "topiary", name = "Topiary", kind = "decor", sub = "garden", shells = 900, w = 2, d = 2, charm = 7, tier = 4, feel = "plant" }),
	-- the farm
	B({ id = "churns", name = "Milk Churns", kind = "decor", sub = "farm", shells = 40, w = 1, d = 1, charm = 1, feel = "metal", blurb = "Two tin churns by the gate." }),
	B({ id = "haybale", name = "Hay Bale", kind = "decor", sub = "farm", shells = 30, w = 2, d = 1, charm = 1, feel = "plant", blurb = "Tied with twine." }),
	B({ id = "scarecrow", name = "Scarecrow", kind = "decor", sub = "farm", shells = 60, w = 1, d = 1, charm = 2, feel = "cloth", blurb = "Keeps the gulls off." }),
	B({ id = "barrels", name = "Barrel Stack", kind = "decor", sub = "farm", shells = 70, w = 2, d = 2, charm = 2, blurb = "Three barrels, one on top." }),
	B({ id = "haystack", name = "Haystack", kind = "decor", sub = "farm", shells = 90, w = 2, d = 2, charm = 2, tier = 2, feel = "plant", blurb = "A round stack with a pitchfork." }),
	B({ id = "trough", name = "Water Trough", kind = "decor", sub = "farm", shells = 110, w = 2, d = 1, charm = 2, tier = 2, blurb = "Wooden, full to the brim." }),
	B({ id = "cart", name = "Farm Cart", kind = "decor", sub = "farm", shells = 260, w = 3, d = 2, charm = 4, tier = 2, blurb = "Two wheels and a load of veg." }),
	B({ id = "well", name = "Stone Well", kind = "decor", sub = "farm", shells = 300, w = 2, d = 2, charm = 5, tier = 2, feel = "stone", blurb = "A bucket on a rope." }),
	-- the harbour
	B({ id = "bollard", name = "Mooring Post", kind = "decor", sub = "harbour", shells = 30, w = 1, d = 1, charm = 1, blurb = "A rope wound round it." }),
	B({ id = "buoy", name = "Buoy", kind = "decor", sub = "harbour", shells = 50, w = 1, d = 1, charm = 1, feel = "metal", blurb = "Red and white stripes." }),
	B({ id = "crates", name = "Crate Stack", kind = "decor", sub = "harbour", shells = 50, w = 2, d = 2, charm = 1, blurb = "Stamped and nailed shut." }),
	B({ id = "lobsterpots", name = "Lobster Pots", kind = "decor", sub = "harbour", shells = 90, w = 2, d = 2, charm = 2, tier = 2, blurb = "Wicker traps in a pile." }),
	B({ id = "netrack", name = "Net Rack", kind = "decor", sub = "harbour", shells = 140, w = 3, d = 1, charm = 3, tier = 2, feel = "cloth", blurb = "Nets hung out to dry." }),
	B({ id = "anchor", name = "Anchor", kind = "decor", sub = "harbour", shells = 160, w = 2, d = 1, charm = 3, tier = 2, feel = "metal", blurb = "Too heavy to lift." }),
	B({ id = "shipwheel", name = "Ship's Wheel", kind = "decor", sub = "harbour", shells = 260, w = 1, d = 1, charm = 4, tier = 3, blurb = "From a ship long gone." }),
	B({ id = "lighthouse", name = "Lighthouse", kind = "decor", sub = "harbour", shells = 9700, w = 4, d = 4, charm = 60, tier = 3, feel = "stone" }),
	-- the town
	B({ id = "bin", name = "Bin", kind = "decor", sub = "town", shells = 25, w = 1, d = 1, charm = 1, feel = "metal", blurb = "Keeps the island tidy." }),
	B({ id = "signpost", name = "Signpost", kind = "decor", sub = "town", shells = 40, w = 1, d = 1, charm = 1, blurb = "Points four ways at once." }),
	B({ id = "planter", name = "Planter Box", kind = "decor", sub = "town", shells = 90, w = 2, d = 1, charm = 2, tier = 2, feel = "plant", blurb = "Flowers in a wooden box." }),
	B({ id = "postbox", name = "Post Box", kind = "decor", sub = "town", shells = 100, w = 1, d = 1, charm = 2, tier = 2, feel = "metal", blurb = "Red, with a slot." }),
	B({ id = "noticeboard", name = "Notice Board", kind = "decor", sub = "town", shells = 140, w = 2, d = 1, charm = 3, tier = 2, blurb = "Lost hats and lessons on offer." }),
	B({ id = "newsstand", name = "Newsstand", kind = "decor", sub = "town", shells = 900, w = 2, d = 2, charm = 8, tier = 4, blurb = "Papers and postcards." }),
	B({ id = "bandstand", name = "Bandstand", kind = "decor", sub = "town", shells = 11000, w = 4, d = 4, charm = 55, tier = 4 }),
	B({ id = "clocktower", name = "Clock Tower", kind = "decor", sub = "town", shells = 15000, w = 3, d = 3, charm = 70, tier = 4, feel = "stone" }),
	-- the jungle
	B({ id = "tikimask", name = "Tiki Mask", kind = "decor", sub = "jungle", shells = 140, w = 1, d = 1, charm = 3, tier = 2, blurb = "A carved face on a post." }),
	B({ id = "totem", name = "Totem Pole", kind = "decor", sub = "jungle", shells = 980, w = 2, d = 2, charm = 12, tier = 2 }),
	B({ id = "parrotperch", name = "Parrot Perch", kind = "decor", sub = "jungle", shells = 220, w = 1, d = 1, charm = 4, tier = 3, blurb = "A carved parrot on a branch." }),
	B({ id = "vinearch", name = "Vine Arch", kind = "decor", sub = "jungle", shells = 420, w = 3, d = 1, charm = 6, tier = 3, feel = "plant", blurb = "Two posts lost in creepers." }),
	B({ id = "idol", name = "Mossy Idol", kind = "decor", sub = "jungle", shells = 1200, w = 2, d = 2, charm = 13, tier = 4, feel = "stone", blurb = "A big stone head, half buried." }),
	-- frost
	B({ id = "snowman", name = "Snowman", kind = "decor", sub = "frost", shells = 80, w = 1, d = 1, charm = 2, tier = 2, feel = "snow", blurb = "Carrot nose, pebble smile." }),
	B({ id = "sled", name = "Sled", kind = "decor", sub = "frost", shells = 160, w = 2, d = 1, charm = 3, tier = 6, feel = "snow", blurb = "Red runners, waiting for a hill." }),
	B({ id = "icelantern", name = "Ice Lantern", kind = "decor", sub = "frost", shells = 200, w = 1, d = 1, charm = 4, tier = 6, feel = "snow", blurb = "A candle in a block of ice." }),
	B({ id = "icesculpture", name = "Ice Sculpture", kind = "decor", sub = "frost", shells = 1100, w = 2, d = 2, charm = 12, tier = 6, feel = "snow", blurb = "A swan carved out of ice." }),
	B({ id = "igloo", name = "Igloo", kind = "decor", sub = "frost", shells = 1500, w = 3, d = 3, charm = 14, tier = 6, feel = "snow", blurb = "Snow blocks in a dome." }),
	-- autumn
	B({ id = "leafpile", name = "Leaf Pile", kind = "decor", sub = "autumn", shells = 30, w = 2, d = 2, charm = 1, tier = 2, feel = "plant", blurb = "Just right for jumping in." }),
	B({ id = "basket", name = "Harvest Basket", kind = "decor", sub = "autumn", shells = 60, w = 1, d = 1, charm = 2, tier = 2, feel = "plant", blurb = "Apples, squash and a corn cob." }),
	B({ id = "pumpkinstack", name = "Pumpkin Stack", kind = "decor", sub = "autumn", shells = 70, w = 1, d = 1, charm = 2, tier = 2, feel = "plant", blurb = "Three pumpkins, biggest at the bottom." }),
	B({ id = "cornstalks", name = "Corn Stalks", kind = "decor", sub = "autumn", shells = 90, w = 2, d = 1, charm = 2, tier = 3, feel = "plant", blurb = "Dry stalks tied in bundles." }),
	B({ id = "jackolantern", name = "Carved Pumpkin", kind = "decor", sub = "autumn", shells = 120, w = 1, d = 1, charm = 3, tier = 3, feel = "fire", blurb = "A grin lit from inside." }),
	-- the desert
	B({ id = "waterjars", name = "Water Jars", kind = "decor", sub = "desert", shells = 80, w = 1, d = 1, charm = 2, tier = 3, feel = "stone", blurb = "Tall clay jars, cool inside." }),
	B({ id = "claypots", name = "Clay Pots", kind = "decor", sub = "desert", shells = 90, w = 2, d = 1, charm = 2, tier = 3, feel = "stone", blurb = "Painted pots in a row." }),
	B({ id = "rug", name = "Market Rug", kind = "decor", sub = "desert", shells = 300, w = 2, d = 2, charm = 5, tier = 5, feel = "cloth", blurb = "Woven red and gold." }),
	B({ id = "stripedtent", name = "Striped Tent", kind = "decor", sub = "desert", shells = 1400, w = 3, d = 3, charm = 14, tier = 5, feel = "cloth", blurb = "Cool shade on a hot day." }),
	B({ id = "sandarch", name = "Sandstone Arch", kind = "decor", sub = "desert", shells = 1600, w = 3, d = 1, charm = 15, tier = 5, feel = "stone", blurb = "A gateway of carved stone." }),
	-- the fairy glade
	B({ id = "fairylantern", name = "Fairy Lantern", kind = "decor", sub = "fairy", shells = 300, w = 1, d = 1, charm = 5, tier = 5, feel = "magic", blurb = "A jar of tiny lights." }),
	B({ id = "mushroomring", name = "Mushroom Ring", kind = "decor", sub = "fairy", shells = 700, w = 3, d = 3, charm = 9, tier = 5, feel = "magic", blurb = "Don't step inside." }),
	B({ id = "moonstone", name = "Moonstone", kind = "decor", sub = "fairy", shells = 2200, w = 2, d = 2, charm = 20, tier = 6, feel = "magic", blurb = "A pale stone that glows at night." }),
	B({ id = "wishingwell", name = "Wishing Well", kind = "decor", sub = "fairy", shells = 2600, w = 2, d = 2, charm = 22, tier = 6, feel = "magic", blurb = "Coins shine at the bottom." }),
	B({ id = "crystalarch", name = "Crystal Arch", kind = "decor", sub = "fairy", shells = 9000, w = 3, d = 1, charm = 50, tier = 8, feel = "magic", blurb = "Two crystals bent into an arch." }),
	-- the zen garden
	B({ id = "rockgarden", name = "Rock Garden", kind = "decor", sub = "zen", shells = 70, w = 2, d = 2, charm = 2, feel = "stone" }),
	B({ id = "bambooscreen", name = "Bamboo Screen", kind = "decor", sub = "zen", shells = 200, w = 2, d = 1, charm = 4, tier = 4, blurb = "Canes tied in a panel." }),
	B({ id = "windchime", name = "Wind Chimes", kind = "decor", sub = "zen", shells = 220, w = 1, d = 1, charm = 4, tier = 4, feel = "metal", blurb = "They ring when the wind comes." }),
	B({ id = "stonelantern", name = "Stone Lantern", kind = "decor", sub = "zen", shells = 400, w = 1, d = 1, charm = 6, tier = 4, feel = "stone", blurb = "A small light in a stone house." }),
	B({ id = "zenbasin", name = "Water Basin", kind = "decor", sub = "zen", shells = 500, w = 1, d = 1, charm = 6, tier = 5, feel = "water", blurb = "Bamboo drips into a stone bowl." }),
	B({ id = "lanterntower", name = "Lantern Tower", kind = "decor", sub = "zen", shells = 4800, w = 2, d = 2, charm = 32, tier = 7, feel = "stone", blurb = "Stone roofs stacked five high." }),
	-- the volcano
	B({ id = "firebasin", name = "Fire Basin", kind = "decor", sub = "volcano", shells = 900, w = 1, d = 1, charm = 10, tier = 7, feel = "fire", blurb = "Flames in an iron bowl." }),
	B({ id = "steamvent", name = "Steam Vent", kind = "decor", sub = "volcano", shells = 1400, w = 2, d = 2, charm = 14, tier = 7, feel = "fire", blurb = "Hot breath from under the island." }),
	B({ id = "obsidian", name = "Obsidian Spire", kind = "decor", sub = "volcano", shells = 5000, w = 2, d = 2, charm = 34, tier = 8, feel = "stone", blurb = "Black glass, sharp as a knife." }),
	B({ id = "lavapool", name = "Lava Pool", kind = "decor", sub = "volcano", shells = 9000, w = 3, d = 3, charm = 50, tier = 9, feel = "fire", blurb = "Bubbling and much too hot." }),
	-- grand pieces
	B({ id = "statue", name = "Guardian Statue", kind = "decor", sub = "grand", shells = 17000, w = 3, d = 3, charm = 90, tier = 3, feel = "stone" }),
	B({ id = "grandarch", name = "Grand Arch", kind = "decor", sub = "grand", shells = 32000, w = 5, d = 2, charm = 120, tier = 5, feel = "stone" }),
	B({ id = "observatory", name = "Observatory", kind = "decor", sub = "grand", shells = 43000, w = 4, d = 4, charm = 150, tier = 5, feel = "stone" }),
	B({ id = "sunspire", name = "Sun Spire", kind = "decor", sub = "grand", shells = 130000, w = 3, d = 3, charm = 350, tier = 6, feel = "magic" }),
	B({ id = "monument", name = "Founder Monument", kind = "decor", sub = "grand", shells = 160000, w = 4, d = 4, charm = 420, tier = 6, feel = "stone" }),
	B({ id = "goldstatue", name = "Golden Driftling", kind = "decor", sub = "grand", shells = 300000, w = 3, d = 3, charm = 620, tier = 7, feel = "metal", blurb = "A driftling cast in gold." }),
	B({ id = "bellspire", name = "Sky Bell Tower", kind = "decor", sub = "grand", shells = 520000, w = 3, d = 3, charm = 850, tier = 8, feel = "stone", blurb = "Its bell rings over every island." }),
	B({ id = "crystalspire", name = "Crystal Spire", kind = "decor", sub = "grand", shells = 900000, w = 3, d = 3, charm = 1150, tier = 9, feel = "magic", blurb = "A tower grown out of crystal." }),
	B({ id = "rainbowarch", name = "Rainbow Arch", kind = "decor", sub = "grand", shells = 1500000, w = 5, d = 2, charm = 1600, tier = 10, feel = "magic", blurb = "Every colour, end to end." }),
	-- fun: seats
	B({ id = "logseats", name = "Log Seats", kind = "decor", tab = "fun", sub = "seats", shells = 50, w = 2, d = 2, charm = 2, blurb = "Logs round a stump table." }),
	B({ id = "bench", name = "Bench", kind = "decor", tab = "fun", sub = "seats", shells = 160, w = 3, d = 2, charm = 4 }),
	B({ id = "parkbench", name = "Park Bench", kind = "decor", tab = "fun", sub = "seats", shells = 220, w = 3, d = 1, charm = 4, tier = 2, feel = "metal", blurb = "Iron legs and green slats." }),
	B({ id = "hammock", name = "Hammock", kind = "decor", tab = "fun", sub = "seats", shells = 320, w = 4, d = 2, charm = 6, feel = "cloth" }),
	B({ id = "picnic", name = "Picnic Table", kind = "decor", tab = "fun", sub = "seats", shells = 430, w = 4, d = 3, charm = 7, tier = 2 }),
	B({ id = "stonebench", name = "Stone Bench", kind = "decor", tab = "fun", sub = "seats", shells = 380, w = 3, d = 1, charm = 5, tier = 3, feel = "stone", blurb = "Cool to sit on in summer." }),
	B({ id = "porchswing", name = "Porch Swing", kind = "decor", tab = "fun", sub = "seats", shells = 700, w = 3, d = 2, charm = 8, tier = 3, blurb = "A bench on chains under a frame." }),
	-- fun: lights
	B({ id = "gardenlights", name = "Garden Lights", kind = "decor", tab = "fun", sub = "lights", shells = 40, w = 1, d = 1, charm = 1, feel = "fire", blurb = "Little lamps along a border." }),
	B({ id = "torch", name = "Tiki Torch", kind = "decor", tab = "fun", sub = "lights", shells = 60, w = 1, d = 1, charm = 2, feel = "fire" }),
	B({ id = "firepit", name = "Fire Pit", kind = "decor", tab = "fun", sub = "lights", shells = 90, w = 2, d = 2, charm = 3, feel = "fire", blurb = "A ring of stones and a fire." }),
	B({ id = "candles", name = "Candles", kind = "decor", tab = "fun", sub = "lights", shells = 60, w = 1, d = 1, charm = 2, tier = 2, feel = "fire", blurb = "Three candles on a stone." }),
	B({ id = "paperlanterns", name = "Paper Lanterns", kind = "decor", tab = "fun", sub = "lights", shells = 150, w = 2, d = 1, charm = 3, tier = 2, feel = "fire", blurb = "Round lanterns on a line." }),
	B({ id = "lamppost", name = "Lamp Post", kind = "decor", tab = "fun", sub = "lights", shells = 190, w = 1, d = 1, charm = 3, tier = 2, feel = "metal" }),
	B({ id = "stringlights", name = "String Lights", kind = "decor", tab = "fun", sub = "lights", shells = 260, w = 3, d = 1, charm = 4, tier = 3, feel = "fire", blurb = "Bulbs strung between two poles." }),
	B({ id = "streetlamp", name = "Street Lamp", kind = "decor", tab = "fun", sub = "lights", shells = 640, w = 1, d = 1, charm = 5, tier = 4, feel = "metal" }),
	-- fun: play
	B({ id = "sandbox", name = "Sandbox", kind = "decor", tab = "fun", sub = "play", shells = 90, w = 2, d = 2, charm = 2, feel = "sand", blurb = "A bucket and spade left in it." }),
	B({ id = "seesaw", name = "Seesaw", kind = "decor", tab = "fun", sub = "play", shells = 350, w = 3, d = 1, charm = 5, tier = 2, blurb = "Up, down, up." }),
	B({ id = "swing", name = "Swing Set", kind = "decor", tab = "fun", sub = "play", shells = 450, w = 3, d = 2, charm = 6, tier = 2, blurb = "Two swings on a frame." }),
	B({ id = "slide", name = "Slide", kind = "decor", tab = "fun", sub = "play", shells = 800, w = 3, d = 2, charm = 8, tier = 3, feel = "metal", blurb = "A ladder up, a slide down." }),
	B({ id = "trampoline", name = "Trampoline", kind = "decor", tab = "fun", sub = "play", shells = 1600, w = 3, d = 3, charm = 12, tier = 4, feel = "cloth", blurb = "Bounce as high as a hut." }),
	B({ id = "carousel", name = "Merry-Go-Round", kind = "decor", tab = "fun", sub = "play", shells = 1800, w = 3, d = 3, charm = 13, tier = 4, feel = "metal", blurb = "Hold on and spin." }),
	B({ id = "climbframe", name = "Climbing Frame", kind = "decor", tab = "fun", sub = "play", shells = 2400, w = 3, d = 3, charm = 15, tier = 5, blurb = "Bars, ropes and a lookout." }),
	-- fun: food and treats
	B({ id = "grill", name = "Grill", kind = "decor", tab = "fun", sub = "treats", shells = 160, w = 1, d = 1, charm = 3, tier = 2, feel = "fire", blurb = "Smoke and something tasty." }),
	B({ id = "lemonade", name = "Lemonade Stand", kind = "decor", tab = "fun", sub = "treats", shells = 300, w = 2, d = 1, charm = 5, tier = 2, blurb = "A jug, some cups, a sign." }),
	B({ id = "icecream", name = "Ice Cream Cart", kind = "decor", tab = "fun", sub = "treats", shells = 600, w = 2, d = 1, charm = 7, tier = 3, feel = "metal", blurb = "Three flavours and a bell." }),
	B({ id = "telescope", name = "Telescope", kind = "decor", tab = "fun", sub = "treats", shells = 900, w = 1, d = 1, charm = 8, tier = 4, feel = "metal", blurb = "Look at the other islands." }),
	B({ id = "tikibar", name = "Tiki Bar", kind = "decor", tab = "fun", sub = "treats", shells = 2200, w = 3, d = 2, charm = 16, tier = 4, blurb = "A grass roof over a bamboo bar." }),
	-- fun: fountains
	B({ id = "drinkfountain", name = "Drinking Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 140, w = 1, d = 1, charm = 3, tier = 2, feel = "water", blurb = "A cool drink for anyone." }),
	B({ id = "smallfountain", name = "Little Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 700, w = 2, d = 2, charm = 9, tier = 2, feel = "water", blurb = "A jet of water in a bowl." }),
	B({ id = "fountain", name = "Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 2600, w = 5, d = 5, charm = 25, tier = 2, feel = "water" }),
	B({ id = "koipond", name = "Koi Pond", kind = "decor", tab = "fun", sub = "fountains", shells = 2500, w = 3, d = 3, charm = 24, tier = 5, feel = "water", blurb = "Orange fish under the lily pads." }),
	B({ id = "crystalfountain", name = "Crystal Fountain", kind = "decor", tab = "fun", sub = "fountains", shells = 85000, w = 5, d = 5, charm = 260, tier = 6, feel = "magic" }),
}
-- stylua: ignore end

-- the Tree of Life (GAME_DESIGN 6; Logic/Tree): every island has one from the start; it is never bought or cleared
-- away (tier 99 keeps it off every tab), but it can be moved. Its eggs lie in a ring on the lawn round its stones,
-- inside its footprint (Controllers/EggView)
table.insert(LIST, B({ id = "tree", name = "Tree of Life", kind = "tree", w = 8, d = 8, charm = 6, tier = 99, blurb = "Lays eggs round its roots every few minutes." }))

local BY_ID: { [string]: BuildingDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID, shellsFor = shellsFor })
