--!strict
-- The driftlings (GAME_DESIGN 6): the creatures that hatch from the Tree of Life's eggs, all our own. Pure. Each comes
-- from one kind of land (Data/Islets: a kind's driftlings hatch once the island reaches that kind's tier), has a knack
-- (the island buildings it helps at), a rarity (1 common .. 7 celestial, Data/Traits: the tree lays rarer eggs less
-- often, and rarer ones work faster) and a passive of its own (Data/Traits effects). The mythic and celestial ones
-- live on the kinds of land a tier 11 island and up opens (Moonwood, Cloudtop, Starfall: 2026-11-14).
--   knack: "farm" | "wood" | "shop" (Data/Buildings' knack: the Work tab's three groups; the request of 2026-11-14,
--   "make it such that creatures are adept in either wood, farm or shops as seen in the build tab instead of individual
--   things like fishing", moved the twelve fishers: the sea's catchers to farms, the rest to wood or shops)
--   hp, atk, def, spd: its make-up, which only ranks it for breeding (`power`)
--   shape: its 3D model (Models/DriftModels: one of its body plans), body / accent: its palette colours
--   power: its breeding rank (Logic/Breed: a child is the species nearest its parents' average; higher is stronger)
export type Passive = { name: string, fx: { [string]: number } }
export type CreatureDef = {
	id: string,
	name: string,
	islet: number,
	rarity: number,
	hp: number,
	atk: number,
	def: number,
	spd: number,
	knack: string,
	shape: string,
	body: string,
	accent: string,
	eye: string, -- its eyes (Models/DriftKit's eye styles, Creatures.EYES)
	iris: string?, -- their colour where the style has one (a palette key)
	tex: string, -- the texture on its body colour (Render/DynTex)
	tex2: string?, -- and on its accent colour, where that is a big surface (a shell, crystals)
	blurb: string,
	passive: Passive,
	power: number,
}

local function C(t: { [string]: any }): CreatureDef
	return {
		id = t.id,
		name = t.name,
		islet = t.islet,
		rarity = t.rarity or 1,
		hp = t.hp,
		atk = t.atk,
		def = t.def,
		spd = t.spd,
		knack = t.knack,
		shape = t.shape,
		body = t.body,
		accent = t.accent,
		eye = "sparkle",
		iris = nil,
		tex = "skin",
		tex2 = nil,
		blurb = t.blurb,
		passive = { name = t.pn, fx = t.fx },
		power = 0,
	}
end

-- stylua: ignore start
local LIST: { CreatureDef } = {
	-- Beaches (islet 1)
	C({ id = "pebblit", name = "Pebblit", islet = 1, rarity = 1, hp = 16, atk = 5, def = 6, spd = 3, knack = "wood", shape = "blob", body = "steel", accent = "steel_dark", blurb = "A pebble that rolled off and kept rolling.", pn = "Rolling Stone", fx = { charm = 1, wood = 0.15 } }),
	C({ id = "clawdle", name = "Clawdle", islet = 1, rarity = 1, hp = 13, atk = 7, def = 4, spd = 5, knack = "farm", shape = "crab", body = "berry_red", accent = "orange", blurb = "Pinches anyone who gets close. It means well.", pn = "Snappy Pincers", fx = { sell = 0.3, farm = 0.15 } }),
	C({ id = "gullfin", name = "Gullfin", islet = 1, rarity = 2, hp = 12, atk = 5, def = 3, spd = 8, knack = "farm", shape = "bird", body = "white", accent = "blue", blurb = "Part gull, part fish. Always hungry.", pn = "Diving Beak", fx = { luck = 0.04, farm = 0.25 } }),
	C({ id = "conchy", name = "Conchy", islet = 1, rarity = 2, hp = 15, atk = 4, def = 7, spd = 3, knack = "shop", shape = "snail", body = "pink", accent = "cream", blurb = "Carries a tiny shop in its shell.", pn = "Pocket Shop", fx = { shop = 0.3 } }),
	C({ id = "shellback", name = "Shellback", islet = 1, rarity = 3, hp = 20, atk = 6, def = 9, spd = 3, knack = "wood", shape = "turtle", body = "green", accent = "sand", blurb = "Sleeps a lot, but once it starts working it won't stop.", pn = "Slow and Steady", fx = { cost = -0.2, work = 0.12 } }),
	C({ id = "sunsprite", name = "Sunsprite", islet = 1, rarity = 4, hp = 17, atk = 9, def = 5, spd = 9, knack = "farm", shape = "sprite", body = "gold", accent = "yellow", blurb = "Glows like noon, even at midnight.", pn = "Sunny Spell", fx = { sell = 0.35, farm = 0.35 } }),
	-- Meadows (islet 2)
	C({ id = "mossbun", name = "Mossbun", islet = 2, rarity = 1, hp = 18, atk = 5, def = 4, spd = 7, knack = "farm", shape = "bun", body = "green", accent = "leaf_dark", blurb = "Its ears are soft moss.", pn = "Mossy Ears", fx = { cost = -0.15, farm = 0.15 } }),
	C({ id = "frondle", name = "Frondle", islet = 2, rarity = 1, hp = 16, atk = 8, def = 4, spd = 6, knack = "farm", shape = "lizard", body = "leaf", accent = "yellow", blurb = "Hides in plain leaves.", pn = "Leaf Cloak", fx = { charm = 1, farm = 0.18 } }),
	C({ id = "twiggle", name = "Twiggle", islet = 2, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, knack = "wood", shape = "owl", body = "wood", accent = "wood_dark", blurb = "Made of sticks. Has a lot to say.", pn = "Woodwise", fx = { luck = 0.07, wood = 0.2 } }),
	C({ id = "hopsprout", name = "Hopsprout", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, knack = "farm", shape = "frog", body = "leaf", accent = "pink", blurb = "Every hop plants a seed.", pn = "Seed Hopper", fx = { luck = 0.03, farm = 0.25 } }),
	C({ id = "bloomoth", name = "Bloomoth", islet = 2, rarity = 3, hp = 15, atk = 8, def = 4, spd = 9, knack = "farm", shape = "moth", body = "pink", accent = "yellow", blurb = "Its wings smell of spring.", pn = "Pollen Dance", fx = { farm = 0.4, luck = 0.05 } }),
	C({ id = "elderbark", name = "Elderbark", islet = 2, rarity = 4, hp = 26, atk = 9, def = 9, spd = 3, knack = "wood", shape = "golem", body = "wood", accent = "leaf", blurb = "A tree that decided to walk.", pn = "Old Roots", fx = { cost = -0.2, charm = 1, wood = 0.35 } }),
	-- Mangroves (islet 6)
	C({ id = "murkle", name = "Murkle", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, knack = "shop", shape = "frog", body = "leaf_dark", accent = "sand", blurb = "Sings to the mud at dusk.", pn = "Mud Bath", fx = { cost = -0.2, shop = 0.1 } }),
	C({ id = "reedle", name = "Reedle", islet = 6, rarity = 1, hp = 17, atk = 7, def = 5, spd = 7, knack = "wood", shape = "lizard", body = "shallow", accent = "wood_dark", blurb = "Thin as a reed and gone before you spot it.", pn = "Reed Runner", fx = { luck = 0.04, wood = 0.12 } }),
	C({ id = "bogsnail", name = "Bogsnail", islet = 6, rarity = 2, hp = 19, atk = 5, def = 8, spd = 3, knack = "farm", shape = "snail", body = "rock_dark", accent = "green", blurb = "Leaves a trail that makes plants grow.", pn = "Fertile Trail", fx = { farm = 0.3, charm = 1 } }),
	C({ id = "mudmole", name = "Mudmole", islet = 6, rarity = 2, hp = 21, atk = 7, def = 7, spd = 4, knack = "wood", shape = "mole", body = "wood_dark", accent = "sand", blurb = "Digs under roots for snacks.", pn = "Root Digger", fx = { wood = 0.25, cost = -0.1 } }),
	C({ id = "wispwing", name = "Wispwing", islet = 6, rarity = 3, hp = 16, atk = 9, def = 4, spd = 10, knack = "shop", shape = "moth", body = "screen_on", accent = "leaf_dark", blurb = "A glow that leads travellers home.", pn = "Guiding Glow", fx = { shop = 0.3, luck = 0.04 } }),
	C({ id = "mirewyrm", name = "Mirewyrm", islet = 6, rarity = 4, hp = 30, atk = 10, def = 8, spd = 6, knack = "wood", shape = "wyrm", body = "leaf_dark", accent = "yellow", blurb = "Older than the mangroves it hides in.", pn = "Swamp King", fx = { cost = -0.2, sell = 0.35, wood = 0.3 } }),
	-- Volcanoes (islet 3)
	C({ id = "emberpup", name = "Emberpup", islet = 3, rarity = 1, hp = 20, atk = 9, def = 5, spd = 7, knack = "shop", shape = "pup", body = "orange", accent = "yellow", blurb = "Good to sit next to on a cold night.", pn = "Warm Welcome", fx = { shop = 0.15, sell = 0.2 } }),
	C({ id = "magmole", name = "Magmole", islet = 3, rarity = 1, hp = 24, atk = 7, def = 8, spd = 3, knack = "wood", shape = "mole", body = "black", accent = "orange", blurb = "Digs through rock like sand.", pn = "Hot Claws", fx = { charm = 1, wood = 0.15 } }),
	C({ id = "scorchwing", name = "Scorchwing", islet = 3, rarity = 2, hp = 17, atk = 8, def = 4, spd = 10, knack = "shop", shape = "bat", body = "purple", accent = "orange", blurb = "Sleeps in the volcano's warm cracks.", pn = "Night Market", fx = { luck = 0.05, shop = 0.15 } }),
	C({ id = "cindertoad", name = "Cindertoad", islet = 3, rarity = 2, hp = 22, atk = 9, def = 6, spd = 5, knack = "farm", shape = "frog", body = "rock_dark", accent = "orange", blurb = "Puffs smoke rings when content.", pn = "Ash Soil", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "basaltor", name = "Basaltor", islet = 3, rarity = 3, hp = 30, atk = 10, def = 11, spd = 3, knack = "wood", shape = "golem", body = "black", accent = "orange", blurb = "Cooled lava, still hot in the middle.", pn = "Molten Core", fx = { charm = 2, wood = 0.3 } }),
	C({ id = "pyredrake", name = "Pyredrake", islet = 3, rarity = 4, hp = 28, atk = 13, def = 7, spd = 9, knack = "shop", shape = "drake", body = "berry_red", accent = "orange", blurb = "Its sneeze lights every torch on the island.", pn = "Fire Breath", fx = { sell = 0.55, shop = 0.25 } }),
	C({ id = "pyrelord", name = "Pyrelord", islet = 3, rarity = 5, hp = 34, atk = 16, def = 9, spd = 10, knack = "shop", shape = "drake", body = "gold", accent = "berry_red", blurb = "Wakes up once a century, usually grumpy.", pn = "Eruption", fx = { sell = 0.75, cost = -0.2, shop = 0.4 } }),
	-- Grottoes (islet 7)
	C({ id = "gemsnail", name = "Gemsnail", islet = 7, rarity = 1, hp = 20, atk = 7, def = 8, spd = 4, knack = "shop", shape = "snail", body = "purple", accent = "screen_on", blurb = "Its shell is a geode.", pn = "Gem Shell", fx = { shop = 0.18, charm = 1 } }),
	C({ id = "glowbat", name = "Glowbat", islet = 7, rarity = 1, hp = 18, atk = 8, def = 5, spd = 9, knack = "wood", shape = "bat", body = "night", accent = "screen_on", blurb = "Lights the way through dark caves.", pn = "Echo Glow", fx = { luck = 0.05, wood = 0.1 } }),
	C({ id = "quartzle", name = "Quartzle", islet = 7, rarity = 2, hp = 22, atk = 7, def = 9, spd = 4, knack = "wood", shape = "blob", body = "chalk", accent = "purple", blurb = "Hums when it is happy.", pn = "Crystal Hum", fx = { charm = 1, work = 0.08 } }),
	C({ id = "crystowl", name = "Crystowl", islet = 7, rarity = 3, hp = 21, atk = 10, def = 6, spd = 8, knack = "shop", shape = "owl", body = "screen_on", accent = "purple", blurb = "Can see through walls. Promises not to look.", pn = "Clear Sight", fx = { luck = 0.12, shop = 0.2 } }),
	C({ id = "prismoth", name = "Prismoth", islet = 7, rarity = 4, hp = 20, atk = 12, def = 6, spd = 11, knack = "farm", shape = "moth", body = "pink", accent = "screen_on", blurb = "Turns sunlight into little rainbows.", pn = "Rainbow Wings", fx = { farm = 0.35, luck = 0.05, sell = 0.25 } }),
	-- Snowfields (islet 4)
	C({ id = "snowpuff", name = "Snowpuff", islet = 4, rarity = 1, hp = 26, atk = 8, def = 7, spd = 4, knack = "farm", shape = "yeti", body = "white", accent = "blue", blurb = "A snowball that learned to hug.", pn = "Big Hug", fx = { cost = -0.2, farm = 0.1 } }),
	C({ id = "floe", name = "Floe", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 6, knack = "farm", shape = "seal", body = "window", accent = "white", blurb = "Slides everywhere on its belly.", pn = "Belly Slide", fx = { luck = 0.03, farm = 0.2 } }),
	C({ id = "frostling", name = "Frostling", islet = 4, rarity = 2, hp = 18, atk = 10, def = 5, spd = 9, knack = "shop", shape = "sprite", body = "screen_on", accent = "white", blurb = "Grins, and the windows ice over.", pn = "Cold Snap", fx = { sell = 0.3, shop = 0.15 } }),
	C({ id = "icetoad", name = "Icetoad", islet = 4, rarity = 2, hp = 25, atk = 8, def = 8, spd = 5, knack = "shop", shape = "frog", body = "window", accent = "white", blurb = "Its croak frosts the windows.", pn = "Frost Croak", fx = { charm = 1, shop = 0.2 } }),
	C({ id = "glacior", name = "Glacior", islet = 4, rarity = 3, hp = 34, atk = 10, def = 12, spd = 3, knack = "wood", shape = "golem", body = "window", accent = "white", blurb = "A glacier with arms.", pn = "Permafrost", fx = { charm = 2, cost = -0.15, wood = 0.2 } }),
	C({ id = "frostdrake", name = "Frostdrake", islet = 4, rarity = 4, hp = 30, atk = 13, def = 8, spd = 9, knack = "shop", shape = "drake", body = "blue", accent = "white", blurb = "Freezes the sea to walk on it.", pn = "Ice Breath", fx = { sell = 0.45, shop = 0.35 } }),
	C({ id = "frostcrown", name = "Frostcrown", islet = 4, rarity = 5, hp = 40, atk = 14, def = 13, spd = 6, knack = "farm", shape = "yeti", body = "gold", accent = "white", blurb = "Snow piles up wherever it stops.", pn = "Winter's Crown", fx = { cost = -0.4, charm = 2, farm = 0.4 } }),
	-- Bluffs (islet 8)
	C({ id = "cloudbun", name = "Cloudbun", islet = 8, rarity = 1, hp = 22, atk = 8, def = 6, spd = 8, knack = "farm", shape = "bun", body = "white", accent = "window", blurb = "Floats a little when it sneezes.", pn = "Fluffy Rain", fx = { farm = 0.2, cost = -0.1 } }),
	C({ id = "breezle", name = "Breezle", islet = 8, rarity = 1, hp = 20, atk = 9, def = 5, spd = 11, knack = "wood", shape = "bird", body = "window", accent = "blue", blurb = "Rides the cliff winds all day.", pn = "Tailwind", fx = { luck = 0.06 } }),
	C({ id = "skyfox", name = "Skyfox", islet = 8, rarity = 2, hp = 23, atk = 10, def = 6, spd = 10, knack = "shop", shape = "pup", body = "blue", accent = "white", blurb = "Chases clouds and sometimes catches one.", pn = "Cloud Chaser", fx = { luck = 0.04, shop = 0.2 } }),
	C({ id = "stormowl", name = "Stormowl", islet = 8, rarity = 3, hp = 24, atk = 12, def = 7, spd = 9, knack = "wood", shape = "owl", body = "night", accent = "yellow", blurb = "Its hoot rolls like thunder.", pn = "Thunder Hoot", fx = { sell = 0.35, wood = 0.25 } }),
	C({ id = "thunderdrake", name = "Thunderdrake", islet = 8, rarity = 4, hp = 31, atk = 15, def = 8, spd = 10, knack = "wood", shape = "drake", body = "purple", accent = "yellow", blurb = "Lightning is its favourite snack.", pn = "Charged Scales", fx = { sell = 0.45, luck = 0.05, wood = 0.3 } }),
	C({ id = "aurorawing", name = "Aurorawing", islet = 8, rarity = 5, hp = 32, atk = 15, def = 10, spd = 13, knack = "shop", shape = "bat", body = "screen_on", accent = "pink", blurb = "Paints the night sky as it flies.", pn = "Northern Lights", fx = { luck = 0.24, shop = 0.4 } }),
	-- Reefs (islet 5)
	C({ id = "coralcrab", name = "Coralcrab", islet = 5, rarity = 1, hp = 24, atk = 10, def = 8, spd = 6, knack = "farm", shape = "crab", body = "pink", accent = "orange", blurb = "Wears a coral crown it grew itself.", pn = "Coral Crown", fx = { charm = 1, farm = 0.18 } }),
	C({ id = "lumajelly", name = "Lumajelly", islet = 5, rarity = 1, hp = 22, atk = 9, def = 6, spd = 7, knack = "shop", shape = "jelly", body = "pink", accent = "purple", blurb = "Glows softly when it is happy.", pn = "Soft Glow", fx = { shop = 0.2, cost = -0.1 } }),
	C({ id = "pearlback", name = "Pearlback", islet = 5, rarity = 2, hp = 30, atk = 9, def = 11, spd = 4, knack = "shop", shape = "turtle", body = "white", accent = "pink", blurb = "Grows a pearl on its shell every year.", pn = "Pearl Grower", fx = { shop = 0.3, charm = 1 } }),
	C({ id = "novafox", name = "Novafox", islet = 5, rarity = 3, hp = 24, atk = 12, def = 6, spd = 10, knack = "wood", shape = "pup", body = "gold", accent = "purple", blurb = "Its tail leaves a trail of stars.", pn = "Starry Tail", fx = { luck = 0.06, wood = 0.25 } }),
	C({ id = "tidewyrm", name = "Tidewyrm", islet = 5, rarity = 4, hp = 34, atk = 12, def = 9, spd = 7, knack = "farm", shape = "wyrm", body = "blue", accent = "screen_on", blurb = "The deep's oldest swimmer.", pn = "Tidal Pull", fx = { cost = -0.2, farm = 0.4 } }),
	C({ id = "abyssmaw", name = "Abyssmaw", islet = 5, rarity = 5, hp = 42, atk = 17, def = 11, spd = 8, knack = "farm", shape = "wyrm", body = "night", accent = "purple", blurb = "Sleeps at the bottom of the deepest trench.", pn = "Deep Hunger", fx = { sell = 0.65, cost = -0.3, farm = 0.5 } }),
	-- Ruins (islet 9)
	C({ id = "relicrab", name = "Relicrab", islet = 9, rarity = 1, hp = 26, atk = 11, def = 9, spd = 6, knack = "shop", shape = "crab", body = "sand_dark", accent = "gold", blurb = "Hoards old coins under its shell.", pn = "Coin Hoard", fx = { shop = 0.25 } }),
	C({ id = "rubblet", name = "Rubblet", islet = 9, rarity = 1, hp = 28, atk = 10, def = 10, spd = 4, knack = "wood", shape = "blob", body = "rock", accent = "sand", blurb = "A loose stone from a fallen wall.", pn = "Old Mortar", fx = { charm = 1, wood = 0.12 } }),
	C({ id = "glyphowl", name = "Glyphowl", islet = 9, rarity = 2, hp = 25, atk = 11, def = 8, spd = 8, knack = "farm", shape = "owl", body = "sand", accent = "gold", blurb = "Reads the old carvings aloud.", pn = "Ancient Lore", fx = { luck = 0.15, farm = 0.15 } }),
	C({ id = "sentinel", name = "Sentinel", islet = 9, rarity = 3, hp = 38, atk = 12, def = 14, spd = 3, knack = "wood", shape = "golem", body = "rock", accent = "gold", blurb = "Still guards a door no one remembers.", pn = "Stone Guard", fx = { charm = 2, cost = -0.2, work = 0.1 } }),
	C({ id = "runemoth", name = "Runemoth", islet = 9, rarity = 4, hp = 27, atk = 14, def = 8, spd = 12, knack = "shop", shape = "moth", body = "gold", accent = "purple", blurb = "Its wings are covered in old spells.", pn = "Rune Wings", fx = { luck = 0.16, shop = 0.3 } }),
	C({ id = "solwyrm", name = "Solwyrm", islet = 9, rarity = 5, hp = 44, atk = 17, def = 12, spd = 9, knack = "farm", shape = "wyrm", body = "gold", accent = "white", blurb = "The ruins were built to honour it.", pn = "Sun Blessing", fx = { cost = -0.3, sell = 0.45, work = 0.25 } }),
	-- Moonwoods (islet 10, tier 11: the first mythic one)
	C({ id = "duskbun", name = "Duskbun", islet = 10, rarity = 1, hp = 30, atk = 11, def = 9, spd = 8, knack = "farm", shape = "bun", body = "slate", accent = "crystal", blurb = "Naps all day and gardens all night.", pn = "Night Shift", fx = { farm = 0.22, work = 0.06 } }),
	C({ id = "hushpup", name = "Hushpup", islet = 10, rarity = 2, hp = 30, atk = 13, def = 8, spd = 12, knack = "shop", shape = "pup", body = "black", accent = "crystal", blurb = "Walks so softly the shop bell never rings.", pn = "Soft Paws", fx = { shop = 0.25, sell = 0.25 } }),
	C({ id = "lunowl", name = "Lunowl", islet = 10, rarity = 3, hp = 31, atk = 13, def = 10, spd = 10, knack = "farm", shape = "owl", body = "white", accent = "crystal", blurb = "Counts the stars out loud and loses count every night.", pn = "Night Watch", fx = { farm = 0.3, luck = 0.05 } }),
	C({ id = "wispkin", name = "Wispkin", islet = 10, rarity = 4, hp = 30, atk = 16, def = 9, spd = 14, knack = "wood", shape = "sprite", body = "crystal", accent = "white", blurb = "A little light that chops wood when nobody is looking.", pn = "Hidden Hands", fx = { wood = 0.35, work = 0.12 } }),
	C({ id = "silverbark", name = "Silverbark", islet = 10, rarity = 5, hp = 48, atk = 16, def = 16, spd = 4, knack = "wood", shape = "golem", body = "steel", accent = "crystal", blurb = "The oldest tree in the wood. It walks when the moon is full.", pn = "Moonsap", fx = { wood = 0.45, cost = -0.3, work = 0.2 } }),
	C({ id = "moonveil", name = "Moonveil", islet = 10, rarity = 6, hp = 40, atk = 19, def = 12, spd = 15, knack = "shop", shape = "bat", body = "night", accent = "cherry", blurb = "Its wings cover the moon. It gives it back by morning.", pn = "Eclipse Wings", fx = { shop = 0.5, luck = 0.18, sell = 0.6 } }),
	-- Cloudtops (islet 11, tier 14: the first celestial one)
	C({ id = "puffling", name = "Puffling", islet = 11, rarity = 1, hp = 34, atk = 12, def = 10, spd = 8, knack = "farm", shape = "blob", body = "white", accent = "window", blurb = "A loose bit of cloud that followed someone home.", pn = "Light Rain", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "cirrup", name = "Cirrup", islet = 11, rarity = 2, hp = 32, atk = 13, def = 9, spd = 13, knack = "shop", shape = "bird", body = "window", accent = "white", blurb = "Sings the weather a day before it comes.", pn = "Fair Forecast", fx = { shop = 0.25, luck = 0.04 } }),
	C({ id = "cloudjelly", name = "Cloudjelly", islet = 11, rarity = 3, hp = 34, atk = 14, def = 10, spd = 9, knack = "farm", shape = "jelly", body = "white", accent = "pink", blurb = "Floats over the fields and waters them on the way.", pn = "Drizzle Drift", fx = { farm = 0.35, work = 0.08 } }),
	C({ id = "billowbear", name = "Billowbear", islet = 11, rarity = 4, hp = 46, atk = 17, def = 14, spd = 6, knack = "wood", shape = "yeti", body = "white", accent = "slate", blurb = "Hugs storm clouds until they calm down.", pn = "Storm Hug", fx = { wood = 0.35, cost = -0.15, work = 0.1 } }),
	C({ id = "skyshell", name = "Skyshell", islet = 11, rarity = 6, hp = 54, atk = 15, def = 18, spd = 5, knack = "farm", shape = "turtle", body = "window", accent = "white", blurb = "Carries a little cloud on its back with a farm on top.", pn = "Floating Field", fx = { farm = 0.55, work = 0.25, luck = 0.08 } }),
	C({ id = "cloudwhale", name = "Cloudwhale", islet = 11, rarity = 7, hp = 60, atk = 18, def = 16, spd = 8, knack = "shop", shape = "seal", body = "ice", accent = "white", blurb = "Swims through the clouds. Its song makes them hum.", pn = "Sky Song", fx = { shop = 0.6, luck = 0.35 } }),
	-- Starfalls (islet 12, tier 17)
	C({ id = "glimmite", name = "Glimmite", islet = 12, rarity = 1, hp = 36, atk = 14, def = 12, spd = 7, knack = "wood", shape = "crab", body = "slate", accent = "screen_on", blurb = "Picks bits of fallen star out of the sand.", pn = "Star Picker", fx = { wood = 0.25, sell = 0.2 } }),
	C({ id = "cometail", name = "Cometail", islet = 12, rarity = 3, hp = 34, atk = 16, def = 10, spd = 15, knack = "shop", shape = "lizard", body = "blue", accent = "yellow", blurb = "Its tail keeps glowing a second after it runs past.", pn = "Bright Trail", fx = { shop = 0.35, luck = 0.05 } }),
	C({ id = "cratermole", name = "Cratermole", islet = 12, rarity = 5, hp = 44, atk = 19, def = 14, spd = 8, knack = "wood", shape = "mole", body = "basalt", accent = "screen_on", blurb = "Dug the crater wider looking for one more star.", pn = "Deep Dig", fx = { wood = 0.45, sell = 0.5, work = 0.2 } }),
	C({ id = "nebulynx", name = "Nebulynx", islet = 12, rarity = 6, hp = 42, atk = 20, def = 12, spd = 16, knack = "shop", shape = "pup", body = "purple", accent = "screen_on", blurb = "There are tiny galaxies in its fur. It knows each one by name.", pn = "Pocket Galaxy", fx = { shop = 0.55, luck = 0.2, sell = 0.7 } }),
	C({ id = "starweaver", name = "Starweaver", islet = 12, rarity = 7, hp = 44, atk = 21, def = 13, spd = 17, knack = "farm", shape = "moth", body = "night", accent = "crystal", blurb = "Spins new stars out of moonlight and hangs them up at dusk.", pn = "Star Loom", fx = { farm = 0.6, luck = 0.12, work = 0.35 } }),
	C({ id = "novawyrm", name = "Novawyrm", islet = 12, rarity = 7, hp = 62, atk = 22, def = 16, spd = 10, knack = "wood", shape = "wyrm", body = "night", accent = "gold", blurb = "Sleeps curled round the whole crater. When it yawns, a star lights up.", pn = "First Light", fx = { wood = 0.6, cost = -0.4, luck = 0.22 } }),
}
-- stylua: ignore end

-- The breeding rank: a species' strength (its stats and rarity), so a pair's child lands between them.
for _, d in LIST do
	d.power = math.floor((d.hp + d.atk * 2.5 + d.def * 2 + d.spd * 1.5) * (1 + 0.12 * (d.rarity - 1)) + 0.5)
end

local BY_ID: { [string]: CreatureDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

-- Each one's eyes and texture (the request of 2026-11-14: "Can you use different eyes for each? Also, apply texture
-- to each of them"): no two of a body plan share a style of eye, and the iris colours set apart the rest.
--   id = { eye style, iris (palette key or false), body texture, accent texture or nil }
-- stylua: ignore start
local LOOKS: { [string]: { any } } = {
	pebblit = { "button", false, "stone" },      quartzle = { "gem", "purple", "crystal", "crystal" }, rubblet = { "sleepy", "sand", "brick" },
	clawdle = { "fierce", "orange", "chitin" },   coralcrab = { "lashes", "orange", "chitin" },    relicrab = { "ringed", "gold", "chitin" },
	gullfin = { "wide", "blue", "feather" },      breezle = { "sleepy", "blue", "feather" },
	conchy = { "sparkle", "pink", "skin", "shell" }, bogsnail = { "sleepy", "green", "skin", "shell" }, gemsnail = { "gem", "screen_on", "skin", "crystal" },
	shellback = { "sleepy", "sand", "scale", "shell" }, pearlback = { "round", "pink", "scale", "shell" },
	sunsprite = { "star", "yellow", "velvet" },   frostling = { "fierce", "blue", "ice" },
	mossbun = { "sparkle", "leaf_dark", "fur" },  cloudbun = { "lashes", "window", "fluff" },
	frondle = { "slit", "yellow", "scale" },      reedle = { "bead", false, "scale" },
	twiggle = { "button", false, "bark" },        crystowl = { "ringed", "purple", "feather" },   stormowl = { "glow", "yellow", "feather" }, glyphowl = { "specs", "gold", "feather" },
	hopsprout = { "round", "gold", "skin" },      murkle = { "bar", "sand", "skin" },             cindertoad = { "happy", false, "ember" }, icetoad = { "wide", "blue", "ice" },
	bloomoth = { "compound", "pink", "velvet" },  wispwing = { "glow", "yellow", "velvet" },      prismoth = { "heart", "pink", "velvet" }, runemoth = { "ringed", "purple", "velvet" },
	elderbark = { "sleepy", "leaf", "bark" },     basaltor = { "glow", "orange", "ember" },        glacior = { "bead", false, "ice" },       sentinel = { "visor", "gold", "stone" },
	mudmole = { "dot", false, "velvet" },         magmole = { "glow", "orange", "ember" },
	emberpup = { "sparkle", "yellow", "fur" },    skyfox = { "round", "blue", "fur" },             novafox = { "star", "purple", "fur" },
	scorchwing = { "fierce", "orange", "fur" },   glowbat = { "glow", "screen_on", "fur" },        aurorawing = { "star", "pink", "fur" },
	snowpuff = { "happy", false, "fluff" },       frostcrown = { "sleepy", "blue", "fluff" },
	floe = { "button", false, "skin" },
	lumajelly = { "sparkle", "purple", "jelly" },
	pyredrake = { "slit", "orange", "scale" },    pyrelord = { "fierce", "berry_red", "scale" },   frostdrake = { "gem", "white", "scale" }, thunderdrake = { "wide", "yellow", "scale" },
	mirewyrm = { "sleepy", "yellow", "scale" },   tidewyrm = { "ringed", "screen_on", "scale" },   abyssmaw = { "glow", "purple", "scale" }, solwyrm = { "slit", "gold", "scale" },
	-- (the kinds of the tiers past the capital, 2026-11-14)
	duskbun = { "sleepy", "crystal", "fluff" },   hushpup = { "lashes", "cherry", "fur" },         lunowl = { "wide", "yellow", "feather" },
	wispkin = { "glow", "screen_on", "velvet" },  silverbark = { "gem", "crystal", "bark", "crystal" }, moonveil = { "ringed", "cherry", "velvet" },
	puffling = { "happy", false, "fluff" },       cirrup = { "round", "blue", "feather" },         cloudjelly = { "sleepy", "pink", "jelly" },
	billowbear = { "round", "slate", "fluff" },   skyshell = { "gem", "screen_on", "scale", "shell" }, cloudwhale = { "star", "yellow", "skin" },
	glimmite = { "dot", false, "chitin" },        cometail = { "star", "yellow", "scale" },        cratermole = { "wide", "screen_on", "stone" },
	nebulynx = { "gem", "screen_on", "fur" },     starweaver = { "star", "yellow", "velvet" },     novawyrm = { "star", "gold", "scale" },
}
-- stylua: ignore end
for _, d in LIST do
	local look = LOOKS[d.id]
	if look then
		d.eye = look[1]
		d.iris = if look[2] then look[2] else nil
		d.tex = look[3]
		d.tex2 = look[4]
	end
end

-- The eye styles (Models/DriftKit draws each).
local EYES = {
	"sparkle", "lashes", "button", "bead", "dot", "star", "heart", "round", "wide", "specs", "slit", "bar", "ringed",
	"sleepy", "fierce", "happy", "glow", "gem", "visor", "compound",
}

return table.freeze({ list = LIST, byId = BY_ID, EYES = EYES })
