--!strict
-- What can stand on an island (GAME_DESIGN 4): buildings that make food, wood or shells, homes for villagers, huts
-- for driftlings, and decor for charm. Pure. Each piece is paid for when it is placed (shells and wood), may be placed
-- as often as the island's piece limit allows (Logic/Plot), and is built by Models/DecorModels. w x d: its footprint
-- in whole studs facing south (a quarter turn swaps them).
--   kind:  "food" | "wood" | "shop" (makes shells by selling food to visitors) | "home" | "nest" (a driftlings' hut)
--          | "breed" (the Hatchery: two driftlings make an egg, Logic/Breed) | "gen" (a boost building: every building
--          of a knack makes more) | "path" (a tile of path or road: apart from the piece limit, Tuning.PathPieces)
--          | "decor" | "tree" (the Tree of Life with its pen: every island's, never bought)
--   rate:  what it makes a turn with a villager working there (food, wood or shells); a shop eats `eats` food a turn
--   job:   the worker's title; knack: the driftlings that help there (Data/Creatures)
--   beds / slots: villagers it houses, driftlings it houses (a hut's room)
--   charm: what it adds to the island's charm (visitors come for it)
--   comfort: a home's or hut's share added to its residents' work (Logic/Island.homes)
--   boost / boostBy: a boost building's knack ("farm" "fish" "wood" "shop", or "all") and its share (each kind of boost
--          building counts once however many stand: Logic/Island.boosts)
--   tier:  the island tier it needs
export type BuildingDef = {
	id: string,
	name: string,
	kind: string,
	shells: number,
	wood: number,
	w: number,
	d: number,
	rate: number,
	eats: number,
	job: string,
	knack: string,
	beds: number,
	slots: number,
	charm: number,
	comfort: number,
	boost: string,
	boostBy: number,
	tier: number,
	blurb: string,
}

local function B(t: { [string]: any }): BuildingDef
	return {
		id = t.id,
		name = t.name,
		kind = t.kind,
		shells = t.shells or 0,
		wood = t.wood or 0,
		w = t.w,
		d = t.d,
		rate = t.rate or 0,
		eats = t.eats or 0,
		job = t.job or "",
		knack = t.knack or "",
		beds = t.beds or 0,
		slots = t.slots or 0,
		charm = t.charm or 0,
		comfort = t.comfort or 0,
		boost = t.boost or "",
		boostBy = t.boostBy or 0,
		tier = t.tier or 1,
		blurb = t.blurb or "",
	}
end

-- stylua: ignore start
local LIST: { BuildingDef } = {
	-- food
	B({ id = "patch", name = "Veggie Patch", kind = "food", shells = 40, w = 3, d = 3, rate = 12, job = "Farmer", knack = "farm", charm = 1, blurb = "Grows food." }),
	B({ id = "pier", name = "Fishing Pier", kind = "food", shells = 140, wood = 15, w = 3, d = 3, rate = 20, job = "Fisher", knack = "fish", charm = 1, blurb = "Lands fish." }),
	B({ id = "orchard", name = "Fruit Orchard", kind = "food", shells = 420, wood = 45, w = 4, d = 4, rate = 34, job = "Farmer", knack = "farm", charm = 3, tier = 2, blurb = "Lots of fruit." }),
	B({ id = "greenhouse", name = "Greenhouse", kind = "food", shells = 2600, wood = 260, w = 4, d = 3, rate = 80, job = "Gardener", knack = "farm", charm = 4, tier = 3, blurb = "Food all year." }),
	B({ id = "paddy", name = "Rice Terrace", kind = "food", shells = 9000, wood = 800, w = 4, d = 4, rate = 170, job = "Farmer", knack = "farm", charm = 5, tier = 4, blurb = "Steps of rice in still water." }),
	B({ id = "kelpfarm", name = "Kelp Farm", kind = "food", shells = 26000, wood = 2200, w = 4, d = 4, rate = 330, job = "Diver", knack = "fish", charm = 6, tier = 5, blurb = "Rows of kelp in a sea pen." }),
	B({ id = "skygarden", name = "Sky Garden", kind = "food", shells = 70000, wood = 6000, w = 5, d = 4, rate = 600, job = "Gardener", knack = "farm", charm = 12, tier = 6, blurb = "Gardens stacked up a glass tower." }),
	-- wood
	B({ id = "lumber", name = "Lumber Camp", kind = "wood", shells = 70, w = 4, d = 3, rate = 6, job = "Woodcutter", knack = "wood", blurb = "Chops wood." }),
	B({ id = "sawmill", name = "Sawmill", kind = "wood", shells = 600, wood = 40, w = 4, d = 4, rate = 18, job = "Sawyer", knack = "wood", charm = 1, tier = 2, blurb = "Saws more wood." }),
	B({ id = "timber", name = "Timber Works", kind = "wood", shells = 2800, wood = 120, w = 4, d = 4, rate = 32, job = "Sawyer", knack = "wood", charm = 2, tier = 3, blurb = "A crane and stacks of planks." }),
	B({ id = "bamboo", name = "Bamboo Grove", kind = "wood", shells = 8000, wood = 300, w = 4, d = 3, rate = 60, job = "Woodcutter", knack = "wood", charm = 4, tier = 4, blurb = "Bamboo grows back by the day." }),
	B({ id = "grandmill", name = "Grand Mill", kind = "wood", shells = 24000, wood = 900, w = 5, d = 4, rate = 110, job = "Millwright", knack = "wood", charm = 6, tier = 5, blurb = "A waterwheel turns its saws." }),
	-- shells: shops sell food to the visitors
	B({ id = "stall", name = "Snack Stall", kind = "shop", shells = 90, wood = 10, w = 3, d = 2, rate = 36, eats = 9, job = "Vendor", knack = "shop", charm = 2, blurb = "Sells snacks to visitors." }),
	B({ id = "cafe", name = "Beach Cafe", kind = "shop", shells = 900, wood = 90, w = 4, d = 3, rate = 120, eats = 24, job = "Cook", knack = "shop", charm = 5, tier = 2, blurb = "Visitors stop here to eat." }),
	B({ id = "inn", name = "Seaside Inn", kind = "shop", shells = 5200, wood = 520, w = 5, d = 4, rate = 340, eats = 55, job = "Innkeeper", knack = "shop", charm = 10, tier = 3, blurb = "Visitors stay the night." }),
	B({ id = "bakery", name = "Bakery", kind = "shop", shells = 14000, wood = 1400, w = 4, d = 3, rate = 700, eats = 90, job = "Baker", knack = "shop", charm = 12, tier = 4, blurb = "Warm bread for the whole town." }),
	B({ id = "bazaar", name = "Grand Bazaar", kind = "shop", shells = 40000, wood = 3600, w = 5, d = 4, rate = 1500, eats = 160, job = "Trader", knack = "shop", charm = 20, tier = 5, blurb = "Stalls under striped awnings." }),
	B({ id = "hotel", name = "Grand Hotel", kind = "shop", shells = 110000, wood = 9000, w = 5, d = 5, rate = 3200, eats = 280, job = "Concierge", knack = "shop", charm = 35, tier = 6, blurb = "Visitors come from every sea." }),
	-- homes: beds, and comfort for those who live there
	B({ id = "tent", name = "Tent", kind = "home", shells = 30, w = 2, d = 2, beds = 1, blurb = "A bed for one villager." }),
	B({ id = "hut", name = "Grass Shack", kind = "home", shells = 140, wood = 20, w = 3, d = 3, beds = 2, charm = 1, comfort = 0.03, blurb = "Beds for two." }),
	B({ id = "cottage", name = "Cottage", kind = "home", shells = 700, wood = 80, w = 4, d = 3, beds = 4, charm = 3, comfort = 0.06, tier = 2, blurb = "Beds for four." }),
	B({ id = "longhouse", name = "Longhouse", kind = "home", shells = 2400, wood = 260, w = 5, d = 3, beds = 5, charm = 4, comfort = 0.08, tier = 3, blurb = "A long timber hall for five." }),
	B({ id = "townhouse", name = "Townhouse", kind = "home", shells = 7000, wood = 700, w = 4, d = 4, beds = 6, charm = 6, comfort = 0.12, tier = 4, blurb = "Two floors with a balcony." }),
	B({ id = "villa", name = "Villa", kind = "home", shells = 20000, wood = 2000, w = 5, d = 4, beds = 6, charm = 10, comfort = 0.18, tier = 5, blurb = "Tiled roofs and a courtyard." }),
	B({ id = "manor", name = "Manor", kind = "home", shells = 60000, wood = 5000, w = 5, d = 5, beds = 10, charm = 16, comfort = 0.25, tier = 6, blurb = "Three floors, towers and a garden." }),
	-- nests: room for driftlings, and comfort
	B({ id = "nest", name = "Driftling Hut", kind = "nest", shells = 50, wood = 5, w = 2, d = 2, slots = 2, blurb = "Room for two driftlings. They work from here." }),
	B({ id = "burrow", name = "Cozy Burrow", kind = "nest", shells = 380, wood = 40, w = 3, d = 3, slots = 4, charm = 1, comfort = 0.05, tier = 2, blurb = "Room for four." }),
	B({ id = "den", name = "Driftling Den", kind = "nest", shells = 2000, wood = 200, w = 3, d = 3, slots = 5, charm = 3, comfort = 0.08, tier = 3, blurb = "A mossy den with soft beds." }),
	B({ id = "roost", name = "Treetop Roost", kind = "nest", shells = 6500, wood = 600, w = 4, d = 4, slots = 6, charm = 5, comfort = 0.12, tier = 4, blurb = "Nests in a great tree." }),
	B({ id = "grotto", name = "Spring Grotto", kind = "nest", shells = 18000, wood = 1600, w = 4, d = 4, slots = 8, charm = 8, comfort = 0.18, tier = 5, blurb = "A warm spring under a rock." }),
	B({ id = "palace", name = "Driftling Palace", kind = "nest", shells = 55000, wood = 4500, w = 5, d = 5, slots = 12, charm = 14, comfort = 0.25, tier = 6, blurb = "The comfiest hut there is." }),
	-- the Hatchery (GAME_DESIGN 6.1): an egg at a time
	B({ id = "hatchery", name = "Hatchery", kind = "breed", shells = 3600, wood = 320, w = 4, d = 4, charm = 3, tier = 3, blurb = "Two driftlings and a feast make an egg." }),
	-- training
	-- boosts: every building of a knack makes more (each kind counts once)
	B({ id = "toolshed", name = "Tool Shed", kind = "gen", shells = 1200, wood = 120, w = 2, d = 2, charm = 1, boost = "wood", boostBy = 0.1, tier = 2, blurb = "Sharp axes: wood +10%." }),
	B({ id = "windmill", name = "Windmill", kind = "gen", shells = 1500, wood = 150, w = 3, d = 3, charm = 4, boost = "farm", boostBy = 0.1, tier = 2, blurb = "Grinds the harvest: farms +10%." }),
	B({ id = "smokehouse", name = "Smokehouse", kind = "gen", shells = 1400, wood = 140, w = 3, d = 3, charm = 2, boost = "fish", boostBy = 0.1, tier = 2, blurb = "Smoked fish keeps: fishing +10%." }),
	B({ id = "market", name = "Market Hall", kind = "gen", shells = 5000, wood = 500, w = 4, d = 3, charm = 8, boost = "shop", boostBy = 0.12, tier = 3, blurb = "Brings the buyers: shops +12%." }),
	B({ id = "watertower", name = "Water Tower", kind = "gen", shells = 12000, wood = 1200, w = 3, d = 3, charm = 6, boost = "all", boostBy = 0.06, tier = 4, blurb = "Fresh water for all: everything +6%." }),
	B({ id = "townhall", name = "Town Hall", kind = "gen", shells = 36000, wood = 3000, w = 5, d = 4, charm = 30, boost = "all", boostBy = 0.1, tier = 5, blurb = "The town runs smoothly: everything +10%." }),
	B({ id = "beacon", name = "Sun Beacon", kind = "gen", shells = 90000, wood = 7000, w = 3, d = 3, charm = 40, boost = "all", boostBy = 0.15, tier = 6, blurb = "Its light never sets: everything +15%." }),
	-- paths: tiles of path and road (apart from the piece limit)
	B({ id = "dirtpath", name = "Dirt Path", kind = "path", shells = 5, w = 2, d = 2, blurb = "A trodden path." }),
	B({ id = "stonepath", name = "Stone Path", kind = "path", shells = 15, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Flat stones set in sand." }),
	B({ id = "brickroad", name = "Brick Road", kind = "path", shells = 40, wood = 1, w = 2, d = 2, charm = 0.5, tier = 4, blurb = "A town's red brick road." }),
	B({ id = "marblewalk", name = "Marble Walk", kind = "path", shells = 90, wood = 2, w = 2, d = 2, charm = 1, tier = 5, blurb = "White marble with a gold inlay." }),
	-- decor
	B({ id = "flowers", name = "Flower Bed", kind = "decor", shells = 40, w = 2, d = 2, charm = 2 }),
	B({ id = "bush", name = "Round Bush", kind = "decor", shells = 30, w = 2, d = 2, charm = 1 }),
	B({ id = "fence", name = "Picket Fence", kind = "decor", shells = 25, w = 2, d = 1, charm = 1 }),
	B({ id = "torch", name = "Tiki Torch", kind = "decor", shells = 60, w = 1, d = 1, charm = 2 }),
	B({ id = "sandcastle", name = "Sandcastle", kind = "decor", shells = 50, w = 2, d = 2, charm = 2 }),
	B({ id = "rockgarden", name = "Rock Garden", kind = "decor", shells = 70, w = 2, d = 2, charm = 2 }),
	B({ id = "shellpile", name = "Shell Pile", kind = "decor", shells = 80, w = 2, d = 2, charm = 3 }),
	B({ id = "palm", name = "Palm Tree", kind = "decor", shells = 120, wood = 5, w = 3, d = 3, charm = 4 }),
	B({ id = "bench", name = "Bench", kind = "decor", shells = 150, wood = 10, w = 3, d = 2, charm = 4 }),
	B({ id = "hammock", name = "Hammock", kind = "decor", shells = 300, wood = 25, w = 4, d = 2, charm = 6 }),
	B({ id = "hedge", name = "Hedge", kind = "decor", shells = 120, w = 3, d = 1, charm = 2, tier = 2 }),
	B({ id = "lamppost", name = "Lamp Post", kind = "decor", shells = 180, wood = 10, w = 1, d = 1, charm = 3, tier = 2 }),
	B({ id = "picnic", name = "Picnic Table", kind = "decor", shells = 400, wood = 30, w = 4, d = 3, charm = 7, tier = 2 }),
	B({ id = "flowerarch", name = "Flower Arch", kind = "decor", shells = 500, wood = 30, w = 3, d = 1, charm = 6, tier = 2 }),
	B({ id = "totem", name = "Totem Pole", kind = "decor", shells = 900, wood = 80, w = 2, d = 2, charm = 12, tier = 2 }),
	B({ id = "fountain", name = "Fountain", kind = "decor", shells = 2500, wood = 100, w = 5, d = 5, charm = 25, tier = 2 }),
	B({ id = "gazebo", name = "Gazebo", kind = "decor", shells = 4000, wood = 300, w = 4, d = 4, charm = 30, tier = 3 }),
	B({ id = "lighthouse", name = "Lighthouse", kind = "decor", shells = 9000, wood = 700, w = 4, d = 4, charm = 60, tier = 3 }),
	B({ id = "statue", name = "Guardian Statue", kind = "decor", shells = 16000, wood = 900, w = 3, d = 3, charm = 90, tier = 3 }),
	B({ id = "streetlamp", name = "Street Lamp", kind = "decor", shells = 600, wood = 40, w = 1, d = 1, charm = 5, tier = 4 }),
	B({ id = "topiary", name = "Topiary", kind = "decor", shells = 900, w = 2, d = 2, charm = 7, tier = 4 }),
	B({ id = "bandstand", name = "Bandstand", kind = "decor", shells = 10000, wood = 700, w = 4, d = 4, charm = 55, tier = 4 }),
	B({ id = "clocktower", name = "Clock Tower", kind = "decor", shells = 14000, wood = 1000, w = 3, d = 3, charm = 70, tier = 4 }),
	B({ id = "canal", name = "Canal Bridge", kind = "decor", shells = 8000, wood = 600, w = 4, d = 3, charm = 40, tier = 5 }),
	B({ id = "grandarch", name = "Grand Arch", kind = "decor", shells = 30000, wood = 2000, w = 5, d = 2, charm = 120, tier = 5 }),
	B({ id = "observatory", name = "Observatory", kind = "decor", shells = 40000, wood = 3000, w = 4, d = 4, charm = 150, tier = 5 }),
	B({ id = "crystalfountain", name = "Crystal Fountain", kind = "decor", shells = 80000, wood = 5000, w = 5, d = 5, charm = 260, tier = 6 }),
	B({ id = "sunspire", name = "Sun Spire", kind = "decor", shells = 120000, wood = 9000, w = 3, d = 3, charm = 350, tier = 6 }),
	B({ id = "monument", name = "Founder Monument", kind = "decor", shells = 150000, wood = 10000, w = 4, d = 4, charm = 420, tier = 6 }),
}
-- stylua: ignore end

-- the Tree of Life and its pen (GAME_DESIGN 6; Logic/Tree): every island has one from the start; it is never bought or
-- cleared away (tier 99 keeps it off every tab) and doesn't count toward the piece limit, but it can be moved
table.insert(LIST, B({ id = "tree", name = "Tree of Life", kind = "tree", w = 6, d = 4, charm = 4, tier = 99, blurb = "Grows a driftling every few seconds into its pen." }))

local BY_ID: { [string]: BuildingDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
