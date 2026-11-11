--!strict
-- The kinds of ground behind the wild places (GAME_DESIGN 7; Data/Sites names the place of each kind: the Tide Pool
-- is a beach, the Cave a grotto). Pure. A place is made up from its kind, its level and a seed (Logic/Expedition.chart:
-- its name, driftlings, path and loot). `lvl` is the level a kind's driftlings first turn up at (the stray from
-- another kind is picked from those open at the place's level): beaches from the start, meadows from 5, mangroves
-- from 7, volcanoes from 10, grottoes from 13, snowfields from 16, bluffs from 20, reefs from 23, ruins from 28
-- (GAME_DESIGN 7: "make much more creatures, some rarer than others, and more islands as well").
--   stage: its 3D set (UI/MicroStage, laid out by the island's seed); wild: the driftlings that live there (Data/
--   Creatures' islet: every one of the kind, the rarer seen less often; another kind's may stray in); first / last: the
--   words its islands' names are made of; titles: what a guardian is called.
local Creatures = require(script.Parent.Creatures)
export type IsletDef = {
	id: number,
	name: string, -- the kind ("Beach")
	plural: string, -- ("Beaches")
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
	{ id = 1, name = "Beach", plural = "Beaches", stage = "loot", lvl = 1, wild = {}, color = "sand",
		first = { "Pebble", "Sunny", "Driftwood", "Seashell", "Gull", "Sandy", "Starfish", "Tidepool" },
		last = { "Beach", "Cay", "Key", "Sands", "Shoal", "Spit", "Cove" },
		blurb = "Warm sand, tide pools and grumpy crabs." },
	{ id = 2, name = "Meadow", plural = "Meadows", stage = "leap", lvl = 5, wild = {}, color = "leaf",
		first = { "Moss", "Fern", "Clover", "Willow", "Thistle", "Bramble", "Dewy", "Hollow" },
		last = { "Grove", "Glen", "Meadow", "Dell", "Isle", "Green", "Thicket" },
		blurb = "A green maze of ferns and mossy stones." },
	{ id = 3, name = "Volcano", plural = "Volcanoes", stage = "dino", lvl = 10, wild = {}, color = "orange",
		first = { "Cinder", "Ember", "Ash", "Smoke", "Scorch", "Magma", "Sulfur", "Char" },
		last = { "Rock", "Peak", "Isle", "Crag", "Cone", "Key", "Bluff" },
		blurb = "A smoking volcano with hot sands." },
	{ id = 4, name = "Snowfield", plural = "Snowfields", stage = "frost", lvl = 16, wild = {}, color = "window",
		first = { "Frost", "Snow", "Ice", "Hail", "Glacier", "Rime", "Winter", "Shiver" },
		last = { "Cap", "Peak", "Isle", "Drift", "Fell", "Point", "Ridge" },
		blurb = "Snowy peaks where nothing stays still." },
	{ id = 5, name = "Reef", plural = "Reefs", stage = "fish", lvl = 23, wild = {}, color = "blue",
		first = { "Coral", "Pearl", "Kelp", "Lagoon", "Azure", "Glimmer", "Sunken", "Brine" },
		last = { "Deep", "Reef", "Shallows", "Atoll", "Hollow", "Trench", "Gardens" },
		blurb = "A sunken reef that glows at the bottom of the sea." },
	{ id = 6, name = "Mangrove", plural = "Mangroves", stage = "swamp", lvl = 7, wild = {}, color = "leaf_dark",
		first = { "Murk", "Reed", "Bog", "Fen", "Marsh", "Tangle", "Mire", "Root" },
		last = { "Mangrove", "Bayou", "Fen", "Hollow", "Water", "Tangle", "Isle" },
		blurb = "Tangled roots over warm brown water." },
	{ id = 7, name = "Grotto", plural = "Grottoes", stage = "grotto", lvl = 13, wild = {}, color = "purple",
		first = { "Crystal", "Gem", "Echo", "Glow", "Amethyst", "Prism", "Hollow", "Quartz" },
		last = { "Grotto", "Cave", "Cavern", "Hollow", "Isle", "Vault", "Deep" },
		blurb = "Glowing crystals in a cave by the sea." },
	{ id = 8, name = "Bluffs", plural = "Bluffs", stage = "bluffs", lvl = 20, wild = {}, color = "wood",
		first = { "Windy", "Cloud", "Storm", "High", "Eagle", "Thunder", "Gale", "Sky" },
		last = { "Bluffs", "Heights", "Cliffs", "Peak", "Ridge", "Point", "Crest" },
		blurb = "Grassy cliffs high in the sea wind." },
	{ id = 9, name = "Ruins", plural = "Ruins", stage = "ruins", lvl = 28, wild = {}, color = "sand_dark",
		first = { "Lost", "Sun", "Old", "Fallen", "Golden", "Silent", "Ancient", "Forgotten" },
		last = { "Ruins", "Temple", "Isle", "Steps", "Court", "Columns", "Citadel" },
		blurb = "The broken stones of an old city." },
}
-- Each kind's driftlings: every species of its islet, the commonest first.
for _, d in LIST do
	local out: { string } = {}
	for _, c in Creatures.list do
		if c.islet == d.id then
			table.insert(out, c.id)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Creatures.byId[a].rarity, Creatures.byId[b].rarity
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	d.wild = out
end

-- What a guardian is called before its kind's name ("Old Frondle").
local TITLES = { "King", "Queen", "Old", "Great", "Elder", "Grumpy", "Mighty", "Big", "Shiny", "Wild" }
-- stylua: ignore end

return table.freeze({ list = LIST, titles = TITLES })
