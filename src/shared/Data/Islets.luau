--!strict
-- The islets the player sails to on expeditions (GAME_DESIGN 7). Pure. They open one after another: beating an
-- islet's guardian (the last node) opens the next. An expedition walks the islet's path of nodes in order:
--   "start" (the landing), "loot" (food and wood lying about), "chest" (shells), "wild" (a battle with the islet's
--   driftlings), "rest" (the party heals), "boss" (the guardian and its friends)
-- lvl: the wild driftlings' level at the landing (it grows along the path); loot: a loot node's food, wood and a
-- chest's shells; reward: shells for beating the guardian (the first time; later trips half); stage: its 3D set
-- (UI/MicroStage).
export type IsletDef = {
	id: number,
	name: string,
	stage: string,
	lvl: number,
	wild: { string },
	boss: string,
	bossName: string,
	nodes: { string },
	loot: { food: number, wood: number, shells: number },
	reward: number,
	color: string,
	blurb: string,
}

-- stylua: ignore start
local LIST: { IsletDef } = {
	{ id = 1, name = "Pebble Beach", stage = "loot", lvl = 1, wild = { "pebblit", "clawdle", "gullfin" }, boss = "clawdle", bossName = "King Clawdle",
		nodes = { "start", "loot", "wild", "loot", "wild", "rest", "wild", "boss" }, loot = { food = 8, wood = 6, shells = 30 }, reward = 250, color = "sand", blurb = "Warm sand, tide pools and grumpy crabs." },
	{ id = 2, name = "Mossgrove", stage = "leap", lvl = 5, wild = { "mossbun", "frondle", "twiggle" }, boss = "frondle", bossName = "Old Frondle",
		nodes = { "start", "wild", "loot", "wild", "chest", "wild", "rest", "wild", "boss" }, loot = { food = 18, wood = 16, shells = 80 }, reward = 900, color = "leaf", blurb = "A green maze of ferns and mossy stones." },
	{ id = 3, name = "Cinder Rock", stage = "dino", lvl = 10, wild = { "emberpup", "magmole", "scorchwing" }, boss = "magmole", bossName = "Magma Magmole",
		nodes = { "start", "wild", "loot", "wild", "wild", "chest", "rest", "wild", "wild", "boss" }, loot = { food = 30, wood = 34, shells = 220 }, reward = 3000, color = "orange", blurb = "A smoking volcano with hot sands." },
	{ id = 4, name = "Frostcap", stage = "frost", lvl = 16, wild = { "snowpuff", "floe", "frostling" }, boss = "snowpuff", bossName = "Great Snowpuff",
		nodes = { "start", "wild", "chest", "wild", "loot", "wild", "rest", "wild", "wild", "boss" }, loot = { food = 50, wood = 60, shells = 500 }, reward = 8000, color = "window", blurb = "Snowy peaks where nothing stays still." },
	{ id = 5, name = "Coral Deep", stage = "fish", lvl = 23, wild = { "lumajelly", "novafox", "tidewyrm" }, boss = "tidewyrm", bossName = "Elder Tidewyrm",
		nodes = { "start", "wild", "loot", "wild", "chest", "wild", "wild", "rest", "wild", "wild", "boss" }, loot = { food = 80, wood = 90, shells = 1100 }, reward = 22000, color = "blue", blurb = "A sunken reef that glows at the bottom of the sea." },
}
-- stylua: ignore end

return table.freeze({ list = LIST })
