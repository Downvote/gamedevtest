--!strict
-- What can stand on an island (GAME_DESIGN 4): buildings that make food, wood or shells, homes for villagers, nests
-- for driftlings, the training yard, and decor for charm. Pure. Each piece is paid for when it is placed (shells and
-- wood), may be placed as often as the island's piece limit allows (Logic/Plot), and is built by
-- Models/DecorModels. w x d: its footprint in whole studs facing south (a quarter turn swaps them).
--   kind:  "food" | "wood" | "shop" (makes shells by selling food to visitors) | "home" | "nest" | "train" | "breed"
--          (the Hatchery: two driftlings make an egg, Logic/Breed) | "decor"
--   rate:  what it makes a day with a villager working there (food, wood or shells); a shop eats `eats` food a day
--   job:   the worker's title; knack: the driftlings that help there (Data/Creatures)
--   beds / slots: villagers it houses, driftlings it nests
--   charm: what it adds to the island's charm (visitors come for it)
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
	-- wood
	B({ id = "lumber", name = "Lumber Camp", kind = "wood", shells = 70, w = 4, d = 3, rate = 6, job = "Woodcutter", knack = "wood", blurb = "Chops wood." }),
	B({ id = "sawmill", name = "Sawmill", kind = "wood", shells = 600, wood = 40, w = 4, d = 4, rate = 18, job = "Sawyer", knack = "wood", charm = 1, tier = 2, blurb = "Saws more wood." }),
	-- shells: shops sell food to the visitors
	B({ id = "stall", name = "Snack Stall", kind = "shop", shells = 90, wood = 10, w = 3, d = 2, rate = 36, eats = 9, job = "Vendor", knack = "shop", charm = 2, blurb = "Sells snacks to visitors." }),
	B({ id = "cafe", name = "Beach Cafe", kind = "shop", shells = 900, wood = 90, w = 4, d = 3, rate = 120, eats = 24, job = "Cook", knack = "shop", charm = 5, tier = 2, blurb = "Visitors love it." }),
	B({ id = "inn", name = "Seaside Inn", kind = "shop", shells = 5200, wood = 520, w = 5, d = 4, rate = 340, eats = 55, job = "Innkeeper", knack = "shop", charm = 10, tier = 3, blurb = "Visitors stay the night." }),
	-- homes
	B({ id = "tent", name = "Tent", kind = "home", shells = 30, w = 2, d = 2, beds = 1, blurb = "A bed for one villager." }),
	B({ id = "hut", name = "Grass Hut", kind = "home", shells = 140, wood = 20, w = 3, d = 3, beds = 2, charm = 1, blurb = "Beds for two." }),
	B({ id = "cottage", name = "Cottage", kind = "home", shells = 700, wood = 80, w = 4, d = 3, beds = 4, charm = 3, tier = 2, blurb = "Beds for four." }),
	-- nests
	B({ id = "nest", name = "Driftling Nest", kind = "nest", shells = 50, wood = 5, w = 2, d = 2, slots = 2, blurb = "Room for two driftlings." }),
	B({ id = "burrow", name = "Cozy Burrow", kind = "nest", shells = 380, wood = 40, w = 3, d = 3, slots = 4, charm = 1, tier = 2, blurb = "Room for four." }),
	-- the Hatchery (GAME_DESIGN 6.1): an egg at a time
	B({ id = "hatchery", name = "Hatchery", kind = "breed", shells = 3600, wood = 320, w = 4, d = 4, charm = 3, tier = 3, blurb = "Two driftlings and a feast make an egg." }),
	-- training
	B({ id = "yard", name = "Training Yard", kind = "train", shells = 450, wood = 50, w = 4, d = 4, charm = 1, tier = 2, blurb = "Resting villagers and driftlings train." }),
	-- decor
	B({ id = "flowers", name = "Flower Bed", kind = "decor", shells = 40, w = 2, d = 2, charm = 2 }),
	B({ id = "bush", name = "Round Bush", kind = "decor", shells = 30, w = 2, d = 2, charm = 1 }),
	B({ id = "torch", name = "Tiki Torch", kind = "decor", shells = 60, w = 1, d = 1, charm = 2 }),
	B({ id = "shellpile", name = "Shell Pile", kind = "decor", shells = 80, w = 2, d = 2, charm = 3 }),
	B({ id = "palm", name = "Palm Tree", kind = "decor", shells = 120, wood = 5, w = 3, d = 3, charm = 4 }),
	B({ id = "bench", name = "Bench", kind = "decor", shells = 150, wood = 10, w = 3, d = 2, charm = 4 }),
	B({ id = "hammock", name = "Hammock", kind = "decor", shells = 300, wood = 25, w = 4, d = 2, charm = 6 }),
	B({ id = "picnic", name = "Picnic Table", kind = "decor", shells = 400, wood = 30, w = 4, d = 3, charm = 7, tier = 2 }),
	B({ id = "totem", name = "Totem Pole", kind = "decor", shells = 900, wood = 80, w = 2, d = 2, charm = 12, tier = 2 }),
	B({ id = "fountain", name = "Fountain", kind = "decor", shells = 2500, wood = 100, w = 5, d = 5, charm = 25, tier = 2 }),
	B({ id = "lighthouse", name = "Lighthouse", kind = "decor", shells = 9000, wood = 700, w = 4, d = 4, charm = 60, tier = 3 }),
	B({ id = "statue", name = "Guardian Statue", kind = "decor", shells = 16000, wood = 900, w = 3, d = 3, charm = 90, tier = 3 }),
}
-- stylua: ignore end

local BY_ID: { [string]: BuildingDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
