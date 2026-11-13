--!strict
-- What can stand on an island (GAME_DESIGN 4): buildings that make wood or shells, huts for the driftlings (who do
-- all the work: no villagers since 2026-11-12), and decor for charm. Pure. Each piece is paid for in wood when it is
-- placed ("make wood the main resource for building/expanding": the old shells and wood prices added up; `shells`
-- stays 0, kept for a piece that might cost both), may be placed as often as the island's piece limit allows
-- (Logic/Plot), and is built by Models/DecorModels. w x d: its footprint in whole studs facing south (a quarter turn
-- swaps them).
--   kind:  "farm" (sells what it grows or catches: shells) | "wood" | "shop" (sells to the visitors: shells)
--          | "nest" (a driftlings' hut) | "breed" (the Hatchery: two driftlings make an egg, Logic/Breed) | "gen" (a
--          boost building: every building of a knack makes more) | "path" (a tile of path or road: apart from the
--          piece limit, Tuning.PathPieces) | "decor"
--   rate:  what it makes a turn with one common driftling working there (wood or shells; Logic/Island); the wood
--          buildings make three times what they did when the shells paid for building, the farms three times what
--          they grew when it was food
--   knack: the driftlings that work there (Data/Creatures)
--   slots: the driftlings a hut houses (its room)
--   charm: what it adds to the island's charm (visitors come for it)
--   comfort: a hut's share added to its residents' work (Logic/Island.homes)
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
	knack: string,
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
		knack = t.knack or "",
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
	-- farms: they sell what they grow or catch (shells)
	B({ id = "patch", name = "Veggie Patch", kind = "farm", wood = 40, w = 3, d = 3, rate = 36, knack = "farm", charm = 1, blurb = "Grows veggies to sell." }),
	B({ id = "pier", name = "Fishing Pier", kind = "farm", wood = 160, w = 3, d = 3, rate = 60, knack = "fish", charm = 1, blurb = "Lands fish to sell." }),
	B({ id = "orchard", name = "Fruit Orchard", kind = "farm", wood = 460, w = 4, d = 4, rate = 102, knack = "farm", charm = 3, tier = 2, blurb = "Lots of fruit to sell." }),
	B({ id = "greenhouse", name = "Greenhouse", kind = "farm", wood = 2900, w = 4, d = 3, rate = 240, knack = "farm", charm = 4, tier = 3, blurb = "Something to sell all year." }),
	B({ id = "paddy", name = "Rice Terrace", kind = "farm", wood = 9800, w = 4, d = 4, rate = 510, knack = "farm", charm = 5, tier = 4, blurb = "Steps of rice in still water." }),
	B({ id = "kelpfarm", name = "Kelp Farm", kind = "farm", wood = 28000, w = 4, d = 4, rate = 990, knack = "fish", charm = 6, tier = 5, blurb = "Rows of kelp in a sea pen." }),
	B({ id = "skygarden", name = "Sky Garden", kind = "farm", wood = 76000, w = 5, d = 4, rate = 1800, knack = "farm", charm = 12, tier = 6, blurb = "Gardens stacked up a glass tower." }),
	-- wood
	B({ id = "lumber", name = "Lumber Camp", kind = "wood", wood = 70, w = 4, d = 3, rate = 30, knack = "wood", blurb = "Chops wood." }),
	B({ id = "sawmill", name = "Sawmill", kind = "wood", wood = 640, w = 4, d = 4, rate = 54, knack = "wood", charm = 1, tier = 2, blurb = "Saws more wood." }),
	B({ id = "timber", name = "Timber Works", kind = "wood", wood = 2900, w = 4, d = 4, rate = 96, knack = "wood", charm = 2, tier = 3, blurb = "A crane and stacks of planks." }),
	B({ id = "bamboo", name = "Bamboo Grove", kind = "wood", wood = 8300, w = 4, d = 3, rate = 180, knack = "wood", charm = 4, tier = 4, blurb = "Bamboo grows back by the day." }),
	B({ id = "grandmill", name = "Grand Mill", kind = "wood", wood = 25000, w = 5, d = 4, rate = 330, knack = "wood", charm = 6, tier = 5, blurb = "A waterwheel turns its saws." }),
	-- shops: they sell to the visitors (shells)
	B({ id = "stall", name = "Snack Stall", kind = "shop", wood = 100, w = 3, d = 2, rate = 36, knack = "shop", charm = 2, blurb = "Sells snacks to visitors." }),
	B({ id = "cafe", name = "Beach Cafe", kind = "shop", wood = 990, w = 4, d = 3, rate = 120, knack = "shop", charm = 5, tier = 2, blurb = "Visitors stop here for a bite." }),
	B({ id = "inn", name = "Seaside Inn", kind = "shop", wood = 5700, w = 5, d = 4, rate = 340, knack = "shop", charm = 10, tier = 3, blurb = "Visitors stay the night." }),
	B({ id = "bakery", name = "Bakery", kind = "shop", wood = 15000, w = 4, d = 3, rate = 700, knack = "shop", charm = 12, tier = 4, blurb = "Warm bread for the whole town." }),
	B({ id = "bazaar", name = "Grand Bazaar", kind = "shop", wood = 44000, w = 5, d = 4, rate = 1500, knack = "shop", charm = 20, tier = 5, blurb = "Stalls under striped awnings." }),
	B({ id = "hotel", name = "Grand Hotel", kind = "shop", wood = 120000, w = 5, d = 5, rate = 3200, knack = "shop", charm = 35, tier = 6, blurb = "Visitors come from every sea." }),
	-- huts (kind "nest"): room for driftlings, and comfort
	B({ id = "nest", name = "Driftling Hut", kind = "nest", wood = 55, w = 2, d = 2, slots = 2, blurb = "Room for two driftlings. They work from here." }),
	B({ id = "burrow", name = "Cozy Burrow", kind = "nest", wood = 420, w = 3, d = 3, slots = 4, charm = 1, comfort = 0.05, tier = 2, blurb = "Room for four." }),
	B({ id = "den", name = "Driftling Den", kind = "nest", wood = 2200, w = 3, d = 3, slots = 5, charm = 3, comfort = 0.08, tier = 3, blurb = "A mossy den with soft beds." }),
	B({ id = "roost", name = "Treetop Roost", kind = "nest", wood = 7100, w = 4, d = 4, slots = 6, charm = 5, comfort = 0.12, tier = 4, blurb = "Nests in a great tree." }),
	B({ id = "grotto", name = "Spring Grotto", kind = "nest", wood = 20000, w = 4, d = 4, slots = 8, charm = 8, comfort = 0.18, tier = 5, blurb = "A warm spring under a rock." }),
	B({ id = "palace", name = "Driftling Palace", kind = "nest", wood = 60000, w = 5, d = 5, slots = 12, charm = 14, comfort = 0.25, tier = 6, blurb = "The comfiest hut there is." }),
	-- the Hatchery (GAME_DESIGN 6.1): an egg at a time
	B({ id = "hatchery", name = "Hatchery", kind = "breed", wood = 3900, w = 4, d = 4, charm = 3, tier = 3, blurb = "Two driftlings and a feast make an egg." }),
	-- boosts: every building of a knack makes more (each kind counts once)
	B({ id = "toolshed", name = "Tool Shed", kind = "gen", wood = 1300, w = 2, d = 2, charm = 1, boost = "wood", boostBy = 0.1, tier = 2, blurb = "Sharp axes: wood +10%." }),
	B({ id = "windmill", name = "Windmill", kind = "gen", wood = 1600, w = 3, d = 3, charm = 4, boost = "farm", boostBy = 0.1, tier = 2, blurb = "Grinds the harvest: farms +10%." }),
	B({ id = "smokehouse", name = "Smokehouse", kind = "gen", wood = 1500, w = 3, d = 3, charm = 2, boost = "fish", boostBy = 0.1, tier = 2, blurb = "Smoked fish keeps: fishing +10%." }),
	B({ id = "market", name = "Market Hall", kind = "gen", wood = 5500, w = 4, d = 3, charm = 8, boost = "shop", boostBy = 0.12, tier = 3, blurb = "Brings the buyers: shops +12%." }),
	B({ id = "watertower", name = "Water Tower", kind = "gen", wood = 13000, w = 3, d = 3, charm = 6, boost = "all", boostBy = 0.06, tier = 4, blurb = "Fresh water for all: everything +6%." }),
	B({ id = "townhall", name = "Town Hall", kind = "gen", wood = 39000, w = 5, d = 4, charm = 30, boost = "all", boostBy = 0.1, tier = 5, blurb = "The town runs smoothly: everything +10%." }),
	B({ id = "beacon", name = "Sun Beacon", kind = "gen", wood = 97000, w = 3, d = 3, charm = 40, boost = "all", boostBy = 0.15, tier = 6, blurb = "Its light never sets: everything +15%." }),
	-- paths: tiles of path and road (apart from the piece limit)
	B({ id = "dirtpath", name = "Dirt Path", kind = "path", wood = 5, w = 2, d = 2, blurb = "A trodden path." }),
	B({ id = "stonepath", name = "Stone Path", kind = "path", wood = 15, w = 2, d = 2, charm = 0.25, tier = 2, blurb = "Flat stones set in sand." }),
	B({ id = "brickroad", name = "Brick Road", kind = "path", wood = 40, w = 2, d = 2, charm = 0.5, tier = 4, blurb = "A town's red brick road." }),
	B({ id = "marblewalk", name = "Marble Walk", kind = "path", wood = 90, w = 2, d = 2, charm = 1, tier = 5, blurb = "White marble with a gold inlay." }),
	-- decor
	B({ id = "flowers", name = "Flower Bed", kind = "decor", wood = 40, w = 2, d = 2, charm = 2 }),
	B({ id = "bush", name = "Round Bush", kind = "decor", wood = 30, w = 2, d = 2, charm = 1 }),
	B({ id = "fence", name = "Picket Fence", kind = "decor", wood = 25, w = 2, d = 1, charm = 1 }),
	B({ id = "torch", name = "Tiki Torch", kind = "decor", wood = 60, w = 1, d = 1, charm = 2 }),
	B({ id = "sandcastle", name = "Sandcastle", kind = "decor", wood = 50, w = 2, d = 2, charm = 2 }),
	B({ id = "rockgarden", name = "Rock Garden", kind = "decor", wood = 70, w = 2, d = 2, charm = 2 }),
	B({ id = "shellpile", name = "Shell Pile", kind = "decor", wood = 80, w = 2, d = 2, charm = 3 }),
	B({ id = "palm", name = "Palm Tree", kind = "decor", wood = 120, w = 3, d = 3, charm = 4 }),
	B({ id = "bench", name = "Bench", kind = "decor", wood = 160, w = 3, d = 2, charm = 4 }),
	B({ id = "hammock", name = "Hammock", kind = "decor", wood = 320, w = 4, d = 2, charm = 6 }),
	B({ id = "hedge", name = "Hedge", kind = "decor", wood = 120, w = 3, d = 1, charm = 2, tier = 2 }),
	B({ id = "lamppost", name = "Lamp Post", kind = "decor", wood = 190, w = 1, d = 1, charm = 3, tier = 2 }),
	B({ id = "picnic", name = "Picnic Table", kind = "decor", wood = 430, w = 4, d = 3, charm = 7, tier = 2 }),
	B({ id = "flowerarch", name = "Flower Arch", kind = "decor", wood = 530, w = 3, d = 1, charm = 6, tier = 2 }),
	B({ id = "totem", name = "Totem Pole", kind = "decor", wood = 980, w = 2, d = 2, charm = 12, tier = 2 }),
	B({ id = "fountain", name = "Fountain", kind = "decor", wood = 2600, w = 5, d = 5, charm = 25, tier = 2 }),
	B({ id = "gazebo", name = "Gazebo", kind = "decor", wood = 4300, w = 4, d = 4, charm = 30, tier = 3 }),
	B({ id = "lighthouse", name = "Lighthouse", kind = "decor", wood = 9700, w = 4, d = 4, charm = 60, tier = 3 }),
	B({ id = "statue", name = "Guardian Statue", kind = "decor", wood = 17000, w = 3, d = 3, charm = 90, tier = 3 }),
	B({ id = "streetlamp", name = "Street Lamp", kind = "decor", wood = 640, w = 1, d = 1, charm = 5, tier = 4 }),
	B({ id = "topiary", name = "Topiary", kind = "decor", wood = 900, w = 2, d = 2, charm = 7, tier = 4 }),
	B({ id = "bandstand", name = "Bandstand", kind = "decor", wood = 11000, w = 4, d = 4, charm = 55, tier = 4 }),
	B({ id = "clocktower", name = "Clock Tower", kind = "decor", wood = 15000, w = 3, d = 3, charm = 70, tier = 4 }),
	B({ id = "canal", name = "Canal Bridge", kind = "decor", wood = 8600, w = 4, d = 3, charm = 40, tier = 5 }),
	B({ id = "grandarch", name = "Grand Arch", kind = "decor", wood = 32000, w = 5, d = 2, charm = 120, tier = 5 }),
	B({ id = "observatory", name = "Observatory", kind = "decor", wood = 43000, w = 4, d = 4, charm = 150, tier = 5 }),
	B({ id = "crystalfountain", name = "Crystal Fountain", kind = "decor", wood = 85000, w = 5, d = 5, charm = 260, tier = 6 }),
	B({ id = "sunspire", name = "Sun Spire", kind = "decor", wood = 130000, w = 3, d = 3, charm = 350, tier = 6 }),
	B({ id = "monument", name = "Founder Monument", kind = "decor", wood = 160000, w = 4, d = 4, charm = 420, tier = 6 }),
}
-- stylua: ignore end

local BY_ID: { [string]: BuildingDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
