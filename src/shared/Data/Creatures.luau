--!strict
-- The driftlings (GAME_DESIGN 6): the creatures of the islets round the player's island, all our own. Pure. Each
-- lives on one islet kind (Data/Islets), fights with its level-1 stats grown by Logic/Battle, has a skill it uses every
-- few actions, a knack (the island buildings it helps at), a trust (how readily a snack befriends it), a rarity (1
-- common .. 5 legendary, Data/Traits: rarer ones turn up less often and are stronger) and a passive of its own (Data/
-- Traits effects: in battle and at work).
--   skill: "bash" (a big hit) | "quick" (two hits) | "zap" (hits every foe) | "heal" (mends the most hurt ally) |
--          "shell" (the side takes less damage for two rounds)
--   knack: "farm" | "fish" | "wood" | "shop" (Data/Buildings' knack)
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
	skill: string,
	knack: string,
	trust: number,
	shape: string,
	body: string,
	accent: string,
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
		skill = t.skill,
		knack = t.knack,
		trust = t.trust,
		shape = t.shape,
		body = t.body,
		accent = t.accent,
		blurb = t.blurb,
		passive = { name = t.pn, fx = t.fx },
		power = 0,
	}
end

-- stylua: ignore start
local LIST: { CreatureDef } = {
	-- Beaches (islet 1)
	C({ id = "pebblit", name = "Pebblit", islet = 1, rarity = 1, hp = 16, atk = 5, def = 6, spd = 3, skill = "shell", knack = "wood", trust = 0.6, shape = "blob", body = "steel", accent = "steel_dark", blurb = "A pebble that rolled off and kept rolling.", pn = "Rolling Stone", fx = { def = 0.1, wood = 0.15 } }),
	C({ id = "clawdle", name = "Clawdle", islet = 1, rarity = 1, hp = 13, atk = 7, def = 4, spd = 5, skill = "bash", knack = "fish", trust = 0.5, shape = "crab", body = "berry_red", accent = "orange", blurb = "Pinches anyone who gets close. It means well.", pn = "Snappy Pincers", fx = { atk = 0.1, fish = 0.15 } }),
	C({ id = "gullfin", name = "Gullfin", islet = 1, rarity = 2, hp = 12, atk = 5, def = 3, spd = 8, skill = "quick", knack = "fish", trust = 0.45, shape = "bird", body = "white", accent = "blue", blurb = "Part gull, part fish. Always hungry.", pn = "Diving Beak", fx = { spd = 0.08, fish = 0.25 } }),
	C({ id = "conchy", name = "Conchy", islet = 1, rarity = 2, hp = 15, atk = 4, def = 7, spd = 3, skill = "shell", knack = "shop", trust = 0.42, shape = "snail", body = "pink", accent = "cream", blurb = "Carries a tiny shop in its shell.", pn = "Pocket Shop", fx = { shop = 0.3 } }),
	C({ id = "shellback", name = "Shellback", islet = 1, rarity = 3, hp = 20, atk = 6, def = 9, spd = 3, skill = "shell", knack = "wood", trust = 0.32, shape = "turtle", body = "green", accent = "sand", blurb = "Sleeps a lot, but once it starts working it won't stop.", pn = "Slow and Steady", fx = { hp = 0.15, work = 0.12 } }),
	C({ id = "sunsprite", name = "Sunsprite", islet = 1, rarity = 4, hp = 17, atk = 9, def = 5, spd = 9, skill = "zap", knack = "farm", trust = 0.22, shape = "sprite", body = "gold", accent = "yellow", blurb = "Glows like noon, even at midnight.", pn = "Sunny Spell", fx = { atk = 0.12, farm = 0.35 } }),
	-- Meadows (islet 2)
	C({ id = "mossbun", name = "Mossbun", islet = 2, rarity = 1, hp = 18, atk = 5, def = 4, spd = 7, skill = "heal", knack = "farm", trust = 0.5, shape = "bun", body = "green", accent = "leaf_dark", blurb = "Its ears are soft moss.", pn = "Mossy Ears", fx = { hp = 0.1, farm = 0.15 } }),
	C({ id = "frondle", name = "Frondle", islet = 2, rarity = 1, hp = 16, atk = 8, def = 4, spd = 6, skill = "bash", knack = "farm", trust = 0.45, shape = "lizard", body = "leaf", accent = "yellow", blurb = "Hides in plain leaves.", pn = "Leaf Cloak", fx = { def = 0.08, farm = 0.18 } }),
	C({ id = "twiggle", name = "Twiggle", islet = 2, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, skill = "zap", knack = "wood", trust = 0.4, shape = "owl", body = "wood", accent = "wood_dark", blurb = "Made of sticks. Has a lot to say.", pn = "Woodwise", fx = { xp = 0.15, wood = 0.2 } }),
	C({ id = "hopsprout", name = "Hopsprout", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, skill = "heal", knack = "farm", trust = 0.38, shape = "frog", body = "leaf", accent = "pink", blurb = "Every hop plants a seed.", pn = "Seed Hopper", fx = { spd = 0.06, farm = 0.25 } }),
	C({ id = "bloomoth", name = "Bloomoth", islet = 2, rarity = 3, hp = 15, atk = 8, def = 4, spd = 9, skill = "zap", knack = "farm", trust = 0.3, shape = "moth", body = "pink", accent = "yellow", blurb = "Its wings smell of spring.", pn = "Pollen Dance", fx = { farm = 0.4, xp = 0.1 } }),
	C({ id = "elderbark", name = "Elderbark", islet = 2, rarity = 4, hp = 26, atk = 9, def = 9, spd = 3, skill = "bash", knack = "wood", trust = 0.2, shape = "golem", body = "wood", accent = "leaf", blurb = "A tree that decided to walk.", pn = "Old Roots", fx = { hp = 0.15, def = 0.1, wood = 0.35 } }),
	-- Mangroves (islet 6)
	C({ id = "murkle", name = "Murkle", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, skill = "heal", knack = "fish", trust = 0.48, shape = "frog", body = "leaf_dark", accent = "sand", blurb = "Sings to the mud at dusk.", pn = "Mud Bath", fx = { hp = 0.12, fish = 0.1 } }),
	C({ id = "reedle", name = "Reedle", islet = 6, rarity = 1, hp = 17, atk = 7, def = 5, spd = 7, skill = "quick", knack = "wood", trust = 0.46, shape = "lizard", body = "shallow", accent = "wood_dark", blurb = "Thin as a reed and gone before you spot it.", pn = "Reed Runner", fx = { spd = 0.08, wood = 0.12 } }),
	C({ id = "bogsnail", name = "Bogsnail", islet = 6, rarity = 2, hp = 19, atk = 5, def = 8, spd = 3, skill = "shell", knack = "farm", trust = 0.38, shape = "snail", body = "rock_dark", accent = "green", blurb = "Leaves a trail that makes plants grow.", pn = "Fertile Trail", fx = { farm = 0.3, def = 0.05 } }),
	C({ id = "mudmole", name = "Mudmole", islet = 6, rarity = 2, hp = 21, atk = 7, def = 7, spd = 4, skill = "bash", knack = "wood", trust = 0.36, shape = "mole", body = "wood_dark", accent = "sand", blurb = "Digs under roots for snacks.", pn = "Root Digger", fx = { wood = 0.25, hp = 0.05 } }),
	C({ id = "wispwing", name = "Wispwing", islet = 6, rarity = 3, hp = 16, atk = 9, def = 4, spd = 10, skill = "zap", knack = "shop", trust = 0.28, shape = "moth", body = "screen_on", accent = "leaf_dark", blurb = "A glow that leads travellers home.", pn = "Guiding Glow", fx = { shop = 0.3, spd = 0.08 } }),
	C({ id = "mirewyrm", name = "Mirewyrm", islet = 6, rarity = 4, hp = 30, atk = 10, def = 8, spd = 6, skill = "zap", knack = "fish", trust = 0.18, shape = "wyrm", body = "leaf_dark", accent = "yellow", blurb = "Older than the mangroves it hides in.", pn = "Swamp King", fx = { hp = 0.12, atk = 0.12, fish = 0.3 } }),
	-- Volcanoes (islet 3)
	C({ id = "emberpup", name = "Emberpup", islet = 3, rarity = 1, hp = 20, atk = 9, def = 5, spd = 7, skill = "bash", knack = "shop", trust = 0.4, shape = "pup", body = "orange", accent = "yellow", blurb = "Good to sit next to on a cold night.", pn = "Warm Welcome", fx = { shop = 0.15, atk = 0.06 } }),
	C({ id = "magmole", name = "Magmole", islet = 3, rarity = 1, hp = 24, atk = 7, def = 8, spd = 3, skill = "shell", knack = "wood", trust = 0.4, shape = "mole", body = "black", accent = "orange", blurb = "Digs through rock like sand.", pn = "Hot Claws", fx = { def = 0.1, wood = 0.15 } }),
	C({ id = "scorchwing", name = "Scorchwing", islet = 3, rarity = 2, hp = 17, atk = 8, def = 4, spd = 10, skill = "quick", knack = "shop", trust = 0.35, shape = "bat", body = "purple", accent = "orange", blurb = "Sleeps in the volcano's warm cracks.", pn = "Night Market", fx = { spd = 0.1, shop = 0.15 } }),
	C({ id = "cindertoad", name = "Cindertoad", islet = 3, rarity = 2, hp = 22, atk = 9, def = 6, spd = 5, skill = "heal", knack = "farm", trust = 0.33, shape = "frog", body = "rock_dark", accent = "orange", blurb = "Puffs smoke rings when content.", pn = "Ash Soil", fx = { farm = 0.25, hp = 0.06 } }),
	C({ id = "basaltor", name = "Basaltor", islet = 3, rarity = 3, hp = 30, atk = 10, def = 11, spd = 3, skill = "shell", knack = "wood", trust = 0.25, shape = "golem", body = "black", accent = "orange", blurb = "Cooled lava, still hot in the middle.", pn = "Molten Core", fx = { def = 0.15, wood = 0.3 } }),
	C({ id = "pyredrake", name = "Pyredrake", islet = 3, rarity = 4, hp = 28, atk = 13, def = 7, spd = 9, skill = "zap", knack = "shop", trust = 0.16, shape = "drake", body = "berry_red", accent = "orange", blurb = "Its sneeze lights every torch on the island.", pn = "Fire Breath", fx = { atk = 0.18, shop = 0.25 } }),
	C({ id = "pyrelord", name = "Pyrelord", islet = 3, rarity = 5, hp = 34, atk = 16, def = 9, spd = 10, skill = "zap", knack = "shop", trust = 0.1, shape = "drake", body = "gold", accent = "berry_red", blurb = "Wakes up once a century, usually grumpy.", pn = "Eruption", fx = { atk = 0.25, hp = 0.15, shop = 0.4 } }),
	-- Grottoes (islet 7)
	C({ id = "gemsnail", name = "Gemsnail", islet = 7, rarity = 1, hp = 20, atk = 7, def = 8, spd = 4, skill = "shell", knack = "shop", trust = 0.44, shape = "snail", body = "purple", accent = "screen_on", blurb = "Its shell is a geode.", pn = "Gem Shell", fx = { shop = 0.18, def = 0.06 } }),
	C({ id = "glowbat", name = "Glowbat", islet = 7, rarity = 1, hp = 18, atk = 8, def = 5, spd = 9, skill = "quick", knack = "fish", trust = 0.42, shape = "bat", body = "night", accent = "screen_on", blurb = "Lights the way through dark caves.", pn = "Echo Glow", fx = { spd = 0.1, fish = 0.1 } }),
	C({ id = "quartzle", name = "Quartzle", islet = 7, rarity = 2, hp = 22, atk = 7, def = 9, spd = 4, skill = "shell", knack = "wood", trust = 0.35, shape = "blob", body = "chalk", accent = "purple", blurb = "Hums when it is happy.", pn = "Crystal Hum", fx = { def = 0.12, work = 0.08 } }),
	C({ id = "crystowl", name = "Crystowl", islet = 7, rarity = 3, hp = 21, atk = 10, def = 6, spd = 8, skill = "zap", knack = "shop", trust = 0.26, shape = "owl", body = "screen_on", accent = "purple", blurb = "Can see through walls. Promises not to look.", pn = "Clear Sight", fx = { xp = 0.25, shop = 0.2 } }),
	C({ id = "prismoth", name = "Prismoth", islet = 7, rarity = 4, hp = 20, atk = 12, def = 6, spd = 11, skill = "zap", knack = "farm", trust = 0.16, shape = "moth", body = "pink", accent = "screen_on", blurb = "Turns sunlight into little rainbows.", pn = "Rainbow Wings", fx = { farm = 0.35, spd = 0.1, atk = 0.08 } }),
	-- Snowfields (islet 4)
	C({ id = "snowpuff", name = "Snowpuff", islet = 4, rarity = 1, hp = 26, atk = 8, def = 7, spd = 4, skill = "heal", knack = "farm", trust = 0.35, shape = "yeti", body = "white", accent = "blue", blurb = "A snowball that learned to hug.", pn = "Big Hug", fx = { hp = 0.15, farm = 0.1 } }),
	C({ id = "floe", name = "Floe", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 6, skill = "shell", knack = "fish", trust = 0.35, shape = "seal", body = "window", accent = "white", blurb = "Slides everywhere on its belly.", pn = "Belly Slide", fx = { spd = 0.06, fish = 0.2 } }),
	C({ id = "frostling", name = "Frostling", islet = 4, rarity = 2, hp = 18, atk = 10, def = 5, spd = 9, skill = "zap", knack = "shop", trust = 0.3, shape = "sprite", body = "screen_on", accent = "white", blurb = "Grins, and the windows ice over.", pn = "Cold Snap", fx = { atk = 0.1, shop = 0.15 } }),
	C({ id = "icetoad", name = "Icetoad", islet = 4, rarity = 2, hp = 25, atk = 8, def = 8, spd = 5, skill = "heal", knack = "fish", trust = 0.3, shape = "frog", body = "window", accent = "white", blurb = "Its croak frosts the windows.", pn = "Frost Croak", fx = { def = 0.08, fish = 0.2 } }),
	C({ id = "glacior", name = "Glacior", islet = 4, rarity = 3, hp = 34, atk = 10, def = 12, spd = 3, skill = "shell", knack = "wood", trust = 0.22, shape = "golem", body = "window", accent = "white", blurb = "A glacier with arms.", pn = "Permafrost", fx = { def = 0.18, hp = 0.1, wood = 0.2 } }),
	C({ id = "frostdrake", name = "Frostdrake", islet = 4, rarity = 4, hp = 30, atk = 13, def = 8, spd = 9, skill = "zap", knack = "fish", trust = 0.15, shape = "drake", body = "blue", accent = "white", blurb = "Freezes the sea to walk on it.", pn = "Ice Breath", fx = { atk = 0.15, fish = 0.35 } }),
	C({ id = "frostcrown", name = "Frostcrown", islet = 4, rarity = 5, hp = 40, atk = 14, def = 13, spd = 6, skill = "heal", knack = "farm", trust = 0.09, shape = "yeti", body = "gold", accent = "white", blurb = "Snow piles up wherever it stops.", pn = "Winter's Crown", fx = { hp = 0.25, def = 0.15, farm = 0.4 } }),
	-- Bluffs (islet 8)
	C({ id = "cloudbun", name = "Cloudbun", islet = 8, rarity = 1, hp = 22, atk = 8, def = 6, spd = 8, skill = "heal", knack = "farm", trust = 0.4, shape = "bun", body = "white", accent = "window", blurb = "Floats a little when it sneezes.", pn = "Fluffy Rain", fx = { farm = 0.2, hp = 0.08 } }),
	C({ id = "breezle", name = "Breezle", islet = 8, rarity = 1, hp = 20, atk = 9, def = 5, spd = 11, skill = "quick", knack = "fish", trust = 0.38, shape = "bird", body = "window", accent = "blue", blurb = "Rides the cliff winds all day.", pn = "Tailwind", fx = { spd = 0.12 } }),
	C({ id = "skyfox", name = "Skyfox", islet = 8, rarity = 2, hp = 23, atk = 10, def = 6, spd = 10, skill = "quick", knack = "shop", trust = 0.32, shape = "pup", body = "blue", accent = "white", blurb = "Chases clouds and sometimes catches one.", pn = "Cloud Chaser", fx = { spd = 0.08, shop = 0.2 } }),
	C({ id = "stormowl", name = "Stormowl", islet = 8, rarity = 3, hp = 24, atk = 12, def = 7, spd = 9, skill = "zap", knack = "wood", trust = 0.24, shape = "owl", body = "night", accent = "yellow", blurb = "Its hoot rolls like thunder.", pn = "Thunder Hoot", fx = { atk = 0.12, wood = 0.25 } }),
	C({ id = "thunderdrake", name = "Thunderdrake", islet = 8, rarity = 4, hp = 31, atk = 15, def = 8, spd = 10, skill = "zap", knack = "wood", trust = 0.14, shape = "drake", body = "purple", accent = "yellow", blurb = "Lightning is its favourite snack.", pn = "Charged Scales", fx = { atk = 0.15, spd = 0.1, wood = 0.3 } }),
	C({ id = "aurorawing", name = "Aurorawing", islet = 8, rarity = 5, hp = 32, atk = 15, def = 10, spd = 13, skill = "heal", knack = "shop", trust = 0.08, shape = "bat", body = "screen_on", accent = "pink", blurb = "Paints the night sky as it flies.", pn = "Northern Lights", fx = { spd = 0.18, xp = 0.3, shop = 0.4 } }),
	-- Reefs (islet 5)
	C({ id = "coralcrab", name = "Coralcrab", islet = 5, rarity = 1, hp = 24, atk = 10, def = 8, spd = 6, skill = "bash", knack = "fish", trust = 0.36, shape = "crab", body = "pink", accent = "orange", blurb = "Wears a coral crown it grew itself.", pn = "Coral Crown", fx = { def = 0.1, fish = 0.18 } }),
	C({ id = "lumajelly", name = "Lumajelly", islet = 5, rarity = 1, hp = 22, atk = 9, def = 6, spd = 7, skill = "heal", knack = "shop", trust = 0.3, shape = "jelly", body = "pink", accent = "purple", blurb = "Glows softly when it is happy.", pn = "Soft Glow", fx = { shop = 0.2, hp = 0.05 } }),
	C({ id = "pearlback", name = "Pearlback", islet = 5, rarity = 2, hp = 30, atk = 9, def = 11, spd = 4, skill = "shell", knack = "shop", trust = 0.26, shape = "turtle", body = "white", accent = "pink", blurb = "Grows a pearl on its shell every year.", pn = "Pearl Grower", fx = { shop = 0.3, def = 0.08 } }),
	C({ id = "novafox", name = "Novafox", islet = 5, rarity = 3, hp = 24, atk = 12, def = 6, spd = 10, skill = "quick", knack = "wood", trust = 0.25, shape = "pup", body = "gold", accent = "purple", blurb = "Its tail leaves a trail of stars.", pn = "Starry Tail", fx = { spd = 0.12, wood = 0.25 } }),
	C({ id = "tidewyrm", name = "Tidewyrm", islet = 5, rarity = 4, hp = 34, atk = 12, def = 9, spd = 7, skill = "zap", knack = "fish", trust = 0.15, shape = "wyrm", body = "blue", accent = "screen_on", blurb = "The deep's oldest swimmer.", pn = "Tidal Pull", fx = { hp = 0.12, fish = 0.4 } }),
	C({ id = "abyssmaw", name = "Abyssmaw", islet = 5, rarity = 5, hp = 42, atk = 17, def = 11, spd = 8, skill = "bash", knack = "fish", trust = 0.08, shape = "wyrm", body = "night", accent = "purple", blurb = "Sleeps at the bottom of the deepest trench.", pn = "Deep Hunger", fx = { atk = 0.22, hp = 0.2, fish = 0.5 } }),
	-- Ruins (islet 9)
	C({ id = "relicrab", name = "Relicrab", islet = 9, rarity = 1, hp = 26, atk = 11, def = 9, spd = 6, skill = "bash", knack = "shop", trust = 0.34, shape = "crab", body = "sand_dark", accent = "gold", blurb = "Hoards old coins under its shell.", pn = "Coin Hoard", fx = { shop = 0.25 } }),
	C({ id = "rubblet", name = "Rubblet", islet = 9, rarity = 1, hp = 28, atk = 10, def = 10, spd = 4, skill = "shell", knack = "wood", trust = 0.34, shape = "blob", body = "rock", accent = "sand", blurb = "A loose stone from a fallen wall.", pn = "Old Mortar", fx = { def = 0.12, wood = 0.12 } }),
	C({ id = "glyphowl", name = "Glyphowl", islet = 9, rarity = 2, hp = 25, atk = 11, def = 8, spd = 8, skill = "zap", knack = "farm", trust = 0.28, shape = "owl", body = "sand", accent = "gold", blurb = "Reads the old carvings aloud.", pn = "Ancient Lore", fx = { xp = 0.3, farm = 0.15 } }),
	C({ id = "sentinel", name = "Sentinel", islet = 9, rarity = 3, hp = 38, atk = 12, def = 14, spd = 3, skill = "shell", knack = "wood", trust = 0.2, shape = "golem", body = "rock", accent = "gold", blurb = "Still guards a door no one remembers.", pn = "Stone Guard", fx = { def = 0.2, hp = 0.12, work = 0.1 } }),
	C({ id = "runemoth", name = "Runemoth", islet = 9, rarity = 4, hp = 27, atk = 14, def = 8, spd = 12, skill = "zap", knack = "shop", trust = 0.14, shape = "moth", body = "gold", accent = "purple", blurb = "Its wings are covered in old spells.", pn = "Rune Wings", fx = { spd = 0.12, xp = 0.2, shop = 0.3 } }),
	C({ id = "solwyrm", name = "Solwyrm", islet = 9, rarity = 5, hp = 44, atk = 17, def = 12, spd = 9, skill = "heal", knack = "farm", trust = 0.07, shape = "wyrm", body = "gold", accent = "white", blurb = "The ruins were built to honour it.", pn = "Sun Blessing", fx = { hp = 0.2, atk = 0.15, work = 0.25 } }),
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

-- The skills' names (the battle log, the Driftlings panel).
local SKILLS: { [string]: string } = {
	bash = "Big Bonk",
	quick = "Double Dash",
	zap = "Splash Wave",
	heal = "Soothe",
	shell = "Shell Guard",
	rally = "Rally",
}

return table.freeze({ list = LIST, byId = BY_ID, skills = SKILLS })
