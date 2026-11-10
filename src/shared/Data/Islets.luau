--!strict
-- The kinds of island the party can find at sea (GAME_DESIGN 7). Pure. Every expedition sails to an island of its
-- own, made up when it sets sail (Logic/Expedition.chart: its kind, name, driftlings, path and loot from a seed and
-- the level the captain picked). A kind can turn up once the level reaches its `lvl`: beaches from the start,
-- meadows from 5, volcanoes from 10, snowfields from 16, reefs from 23.
--   stage: its 3D set (UI/MicroStage, laid out by the island's seed); wild: the driftlings that live there (another
--   kind's may stray in); first / last: the words its islands' names are made of; titles: what a guardian is called.
export type IsletDef = {
	id: number,
	name: string, -- the kind ("Beach")
	plural: string, -- ("Beaches": the Explore panel, the Index)
	stage: string,
	lvl: number,
	wild: { string },
	first: { string },
	last: { string },
	color: string,
	blurb: string,
}

-- stylua: ignore start
local LIST: { IsletDef } = {
	{ id = 1, name = "Beach", plural = "Beaches", stage = "loot", lvl = 1, wild = { "pebblit", "clawdle", "gullfin" }, color = "sand",
		first = { "Pebble", "Sunny", "Driftwood", "Seashell", "Gull", "Sandy", "Starfish", "Tidepool" },
		last = { "Beach", "Cay", "Key", "Sands", "Shoal", "Spit", "Cove" },
		blurb = "Warm sand, tide pools and grumpy crabs." },
	{ id = 2, name = "Meadow", plural = "Meadows", stage = "leap", lvl = 5, wild = { "mossbun", "frondle", "twiggle" }, color = "leaf",
		first = { "Moss", "Fern", "Clover", "Willow", "Thistle", "Bramble", "Dewy", "Hollow" },
		last = { "Grove", "Glen", "Meadow", "Dell", "Isle", "Green", "Thicket" },
		blurb = "A green maze of ferns and mossy stones." },
	{ id = 3, name = "Volcano", plural = "Volcanoes", stage = "dino", lvl = 10, wild = { "emberpup", "magmole", "scorchwing" }, color = "orange",
		first = { "Cinder", "Ember", "Ash", "Smoke", "Scorch", "Magma", "Sulfur", "Char" },
		last = { "Rock", "Peak", "Isle", "Crag", "Cone", "Key", "Bluff" },
		blurb = "A smoking volcano with hot sands." },
	{ id = 4, name = "Snowfield", plural = "Snowfields", stage = "frost", lvl = 16, wild = { "snowpuff", "floe", "frostling" }, color = "window",
		first = { "Frost", "Snow", "Ice", "Hail", "Glacier", "Rime", "Winter", "Shiver" },
		last = { "Cap", "Peak", "Isle", "Drift", "Fell", "Point", "Ridge" },
		blurb = "Snowy peaks where nothing stays still." },
	{ id = 5, name = "Reef", plural = "Reefs", stage = "fish", lvl = 23, wild = { "lumajelly", "novafox", "tidewyrm" }, color = "blue",
		first = { "Coral", "Pearl", "Kelp", "Lagoon", "Azure", "Glimmer", "Sunken", "Brine" },
		last = { "Deep", "Reef", "Shallows", "Atoll", "Hollow", "Trench", "Gardens" },
		blurb = "A sunken reef that glows at the bottom of the sea." },
}

-- What a guardian is called before its kind's name ("Old Frondle").
local TITLES = { "King", "Queen", "Old", "Great", "Elder", "Grumpy", "Mighty", "Big", "Shiny", "Wild" }
-- stylua: ignore end

return table.freeze({ list = LIST, titles = TITLES })
