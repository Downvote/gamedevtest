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
	form: { [string]: any }?, -- how its body plan varies (Models/DriftPlans*: ears, tail, horns, proportions...)
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
		form = t.form,
	}
end

-- stylua: ignore start
local LIST: { CreatureDef } = {
	-- Beaches (islet 1)
	C({ id = "pebblit", name = "Pebblit", islet = 1, rarity = 1, hp = 16, atk = 5, def = 6, spd = 3, knack = "wood", shape = "armadillo", body = "steel", accent = "steel_dark", blurb = "A pebble that rolled off and kept rolling.", pn = "Rolling Stone", fx = { charm = 1, wood = 0.15 } }),
	C({ id = "clawdle", name = "Clawdle", islet = 1, rarity = 1, hp = 13, atk = 7, def = 4, spd = 5, knack = "farm", shape = "crab", body = "berry_red", accent = "orange", blurb = "Pinches anyone who gets close. It means well.", pn = "Snappy Pincers", fx = { sell = 0.3, farm = 0.15 } }),
	C({ id = "gullfin", name = "Gullfin", islet = 1, rarity = 2, hp = 12, atk = 5, def = 3, spd = 8, knack = "farm", shape = "bird", body = "white", accent = "blue", blurb = "Part gull, part fish. Always hungry.", pn = "Diving Beak", fx = { luck = 0.04, farm = 0.25 } }),
	C({ id = "conchy", name = "Conchy", islet = 1, rarity = 2, hp = 15, atk = 4, def = 7, spd = 3, knack = "shop", shape = "snail", body = "pink", accent = "cream", blurb = "Carries a tiny shop in its shell.", pn = "Pocket Shop", fx = { shop = 0.3 } }),
	C({ id = "shellback", name = "Shellback", islet = 1, rarity = 3, hp = 20, atk = 6, def = 9, spd = 3, knack = "wood", shape = "turtle", body = "green", accent = "sand", blurb = "Sleeps a lot, but once it starts working it won't stop.", pn = "Slow and Steady", fx = { cost = -0.2, work = 0.12 } }),
	C({ id = "sunsprite", name = "Sunsprite", islet = 1, rarity = 4, hp = 17, atk = 9, def = 5, spd = 9, knack = "farm", shape = "sprite", body = "gold", accent = "yellow", blurb = "Glows like noon, even at midnight.", pn = "Sunny Spell", fx = { sell = 0.35, farm = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "sandkit", name = "Sandkit", islet = 1, rarity = 1, hp = 14, atk = 6, def = 4, spd = 6, knack = "shop", shape = "pup", body = "sand", accent = "cream", blurb = "Its ears hear the tide turn from the far end of the beach.", pn = "Big Ears", fx = { luck = 0.03, shop = 0.15 } }),
	C({ id = "puffpod", name = "Puffpod", islet = 1, rarity = 1, hp = 15, atk = 5, def = 6, spd = 3, knack = "farm", shape = "fish", body = "yellow", accent = "orange", blurb = "Blows up like a ball when it gets a fright. It gets a fright a lot.", pn = "Puff Up", fx = { charm = 1, farm = 0.15 } }),
	C({ id = "kelpup", name = "Kelpup", islet = 1, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, knack = "farm", shape = "otter", body = "wood", accent = "cream", blurb = "Naps on its back in the shallows, holding a shell.", pn = "Shell Nap", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "tidepip", name = "Tidepip", islet = 1, rarity = 2, hp = 12, atk = 6, def = 3, spd = 8, knack = "wood", shape = "bird", body = "sand", accent = "white", blurb = "Runs after the waves, then runs away from them.", pn = "Wave Chaser", fx = { luck = 0.05, wood = 0.2 } }),
	C({ id = "kelphorse", name = "Kelphorse", islet = 1, rarity = 3, hp = 16, atk = 7, def = 6, spd = 5, knack = "shop", shape = "seahorse", body = "coral", accent = "cream", blurb = "Holds on to the kelp with its tail and hums at passing boats.", pn = "Kelp Hum", fx = { shop = 0.3, luck = 0.03 } }),
	C({ id = "duneray", name = "Duneray", islet = 1, rarity = 4, hp = 18, atk = 9, def = 6, spd = 9, knack = "wood", shape = "ray", body = "sand", accent = "blue", blurb = "Skims over the sand at low tide, faster than the gulls.", pn = "Low Glide", fx = { wood = 0.35, sell = 0.25 } }),
	-- Meadows (islet 2)
	C({ id = "mossbun", name = "Mossbun", islet = 2, rarity = 1, hp = 18, atk = 5, def = 4, spd = 7, knack = "farm", shape = "bun", body = "green", accent = "leaf_dark", blurb = "Its ears are soft moss.", pn = "Mossy Ears", fx = { cost = -0.15, farm = 0.15 } }),
	C({ id = "frondle", name = "Frondle", islet = 2, rarity = 1, hp = 16, atk = 8, def = 4, spd = 6, knack = "farm", shape = "lizard", body = "leaf", accent = "yellow", blurb = "Hides in plain leaves.", pn = "Leaf Cloak", fx = { charm = 1, farm = 0.18 } }),
	C({ id = "twiggle", name = "Twiggle", islet = 2, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, knack = "wood", shape = "owl", body = "wood", accent = "wood_dark", blurb = "Made of sticks. Has a lot to say.", pn = "Woodwise", fx = { luck = 0.07, wood = 0.2 } }),
	C({ id = "hopsprout", name = "Hopsprout", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, knack = "farm", shape = "frog", body = "leaf", accent = "pink", blurb = "Every hop plants a seed.", pn = "Seed Hopper", fx = { luck = 0.03, farm = 0.25 } }),
	C({ id = "bloomoth", name = "Bloomoth", islet = 2, rarity = 3, hp = 15, atk = 8, def = 4, spd = 9, knack = "farm", shape = "moth", body = "pink", accent = "yellow", blurb = "Its wings smell of spring.", pn = "Pollen Dance", fx = { farm = 0.4, luck = 0.05 } }),
	C({ id = "elderbark", name = "Elderbark", islet = 2, rarity = 4, hp = 26, atk = 9, def = 9, spd = 3, knack = "wood", shape = "golem", body = "wood", accent = "leaf", blurb = "A tree that decided to walk.", pn = "Old Roots", fx = { cost = -0.2, charm = 1, wood = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "burrowby", name = "Burrowby", islet = 2, rarity = 1, hp = 17, atk = 5, def = 6, spd = 4, knack = "wood", shape = "hedgehog", body = "wood", accent = "cream", blurb = "Rolls into a ball whenever anyone says hello.", pn = "Prickle Roll", fx = { charm = 1, wood = 0.15 } }),
	C({ id = "puddlet", name = "Puddlet", islet = 2, rarity = 1, hp = 16, atk = 5, def = 4, spd = 6, knack = "farm", shape = "duck", body = "yellow", accent = "orange", blurb = "Follows the first thing it sees. Usually a bee.", pn = "Follow Along", fx = { farm = 0.18, luck = 0.02 } }),
	C({ id = "fawnlet", name = "Fawnlet", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, knack = "farm", shape = "deer", body = "wood", accent = "cream", blurb = "Lies very still in the long grass until you nearly step on it.", pn = "Long Grass", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "bumblet", name = "Bumblet", islet = 2, rarity = 2, hp = 14, atk = 6, def = 4, spd = 8, knack = "farm", shape = "moth", body = "yellow", accent = "black", blurb = "Hums the same three notes all day long.", pn = "Busy Buzz", fx = { farm = 0.28 } }),
	C({ id = "thistlemane", name = "Thistlemane", islet = 2, rarity = 3, hp = 18, atk = 8, def = 5, spd = 8, knack = "shop", shape = "cat", body = "gold", accent = "white", blurb = "Its mane blows away in the wind and grows back by supper.", pn = "Puff Mane", fx = { shop = 0.3, luck = 0.05 } }),
	C({ id = "mossbuck", name = "Mossbuck", islet = 2, rarity = 4, hp = 24, atk = 9, def = 8, spd = 6, knack = "wood", shape = "deer", body = "wood_dark", accent = "leaf", blurb = "Its antlers are so mossy that birds nest in them.", pn = "Green Crown", fx = { wood = 0.35, charm = 1, cost = -0.15 } }),
	-- Mangroves (islet 6)
	C({ id = "murkle", name = "Murkle", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, knack = "shop", shape = "frog", body = "leaf_dark", accent = "sand", blurb = "Sings to the mud at dusk.", pn = "Mud Bath", fx = { cost = -0.2, shop = 0.1 } }),
	C({ id = "reedle", name = "Reedle", islet = 6, rarity = 1, hp = 17, atk = 7, def = 5, spd = 7, knack = "wood", shape = "lizard", body = "shallow", accent = "wood_dark", blurb = "Thin as a reed and gone before you spot it.", pn = "Reed Runner", fx = { luck = 0.04, wood = 0.12 } }),
	C({ id = "bogsnail", name = "Bogsnail", islet = 6, rarity = 2, hp = 19, atk = 5, def = 8, spd = 3, knack = "farm", shape = "snail", body = "rock_dark", accent = "green", blurb = "Leaves a trail that makes plants grow.", pn = "Fertile Trail", fx = { farm = 0.3, charm = 1 } }),
	C({ id = "mudmole", name = "Mudmole", islet = 6, rarity = 2, hp = 21, atk = 7, def = 7, spd = 4, knack = "wood", shape = "mole", body = "wood_dark", accent = "sand", blurb = "Digs under roots for snacks.", pn = "Root Digger", fx = { wood = 0.25, cost = -0.1 } }),
	C({ id = "wispwing", name = "Wispwing", islet = 6, rarity = 3, hp = 16, atk = 9, def = 4, spd = 10, knack = "shop", shape = "moth", body = "screen_on", accent = "leaf_dark", blurb = "A glow that leads travellers home.", pn = "Guiding Glow", fx = { shop = 0.3, luck = 0.04 } }),
	C({ id = "mirewyrm", name = "Mirewyrm", islet = 6, rarity = 4, hp = 30, atk = 10, def = 8, spd = 6, knack = "wood", shape = "wyrm", body = "leaf_dark", accent = "yellow", blurb = "Older than the mangroves it hides in.", pn = "Swamp King", fx = { cost = -0.2, sell = 0.35, wood = 0.3 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "gillo", name = "Gillo", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, knack = "farm", shape = "lizard", body = "pink", accent = "coral", blurb = "Smiles all the time. Nobody knows why.", pn = "Big Smile", fx = { farm = 0.15, charm = 1 } }),
	C({ id = "slinkit", name = "Slinkit", islet = 6, rarity = 1, hp = 17, atk = 7, def = 4, spd = 8, knack = "wood", shape = "otter", body = "wood_dark", accent = "cream", blurb = "Slips between the roots faster than you can blink.", pn = "Root Slip", fx = { wood = 0.15, luck = 0.03 } }),
	C({ id = "dabbler", name = "Dabbler", islet = 6, rarity = 2, hp = 19, atk = 6, def = 6, spd = 6, knack = "farm", shape = "duck", body = "leaf_dark", accent = "sand", blurb = "Tips upside down to eat and stays like that for ages.", pn = "Bottoms Up", fx = { farm = 0.25, cost = -0.12 } }),
	C({ id = "snapmoss", name = "Snapmoss", islet = 6, rarity = 2, hp = 22, atk = 8, def = 9, spd = 3, knack = "wood", shape = "turtle", body = "rock_dark", accent = "leaf", blurb = "Moss grows on its shell, and it lets it.", pn = "Mossy Shell", fx = { wood = 0.22, charm = 1 } }),
	C({ id = "stiltbeak", name = "Stiltbeak", islet = 6, rarity = 3, hp = 18, atk = 10, def = 5, spd = 9, knack = "shop", shape = "bird", body = "steel", accent = "white", blurb = "Stands on one leg for hours, then strikes in a blink.", pn = "Patient Strike", fx = { shop = 0.3, luck = 0.05 } }),
	C({ id = "grinmire", name = "Grinmire", islet = 6, rarity = 4, hp = 30, atk = 11, def = 9, spd = 5, knack = "wood", shape = "lizard", body = "leaf_dark", accent = "sand", blurb = "Has a great many teeth and very good manners.", pn = "Mud Smile", fx = { wood = 0.35, sell = 0.25 } }),
	-- Volcanoes (islet 3)
	C({ id = "emberpup", name = "Emberpup", islet = 3, rarity = 1, hp = 20, atk = 9, def = 5, spd = 7, knack = "shop", shape = "pup", body = "orange", accent = "yellow", blurb = "Good to sit next to on a cold night.", pn = "Warm Welcome", fx = { shop = 0.15, sell = 0.2 } }),
	C({ id = "magmole", name = "Magmole", islet = 3, rarity = 1, hp = 24, atk = 7, def = 8, spd = 3, knack = "wood", shape = "mole", body = "black", accent = "orange", blurb = "Digs through rock like sand.", pn = "Hot Claws", fx = { charm = 1, wood = 0.15 } }),
	C({ id = "scorchwing", name = "Scorchwing", islet = 3, rarity = 2, hp = 17, atk = 8, def = 4, spd = 10, knack = "shop", shape = "bat", body = "purple", accent = "orange", blurb = "Sleeps in the volcano's warm cracks.", pn = "Night Market", fx = { luck = 0.05, shop = 0.15 } }),
	C({ id = "cindertoad", name = "Cindertoad", islet = 3, rarity = 2, hp = 22, atk = 9, def = 6, spd = 5, knack = "farm", shape = "frog", body = "rock_dark", accent = "orange", blurb = "Puffs smoke rings when content.", pn = "Ash Soil", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "basaltor", name = "Basaltor", islet = 3, rarity = 3, hp = 30, atk = 10, def = 11, spd = 3, knack = "wood", shape = "golem", body = "black", accent = "orange", blurb = "Cooled lava, still hot in the middle.", pn = "Molten Core", fx = { charm = 2, wood = 0.3 } }),
	C({ id = "pyredrake", name = "Pyredrake", islet = 3, rarity = 4, hp = 28, atk = 13, def = 7, spd = 9, knack = "shop", shape = "drake", body = "berry_red", accent = "orange", blurb = "Its sneeze lights every torch on the island.", pn = "Fire Breath", fx = { sell = 0.55, shop = 0.25 } }),
	C({ id = "pyrelord", name = "Pyrelord", islet = 3, rarity = 5, hp = 34, atk = 16, def = 9, spd = 10, knack = "shop", shape = "drake", body = "gold", accent = "berry_red", blurb = "Wakes up once a century, usually grumpy.", pn = "Eruption", fx = { sell = 0.75, cost = -0.2, shop = 0.4 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "cinderkit", name = "Cinderkit", islet = 3, rarity = 1, hp = 19, atk = 9, def = 5, spd = 8, knack = "shop", shape = "cat", body = "basalt", accent = "orange", blurb = "Naps on warm rocks and leaves sooty pawprints everywhere.", pn = "Sooty Paws", fx = { shop = 0.15, sell = 0.15 } }),
	C({ id = "emberquill", name = "Emberquill", islet = 3, rarity = 1, hp = 21, atk = 7, def = 8, spd = 4, knack = "wood", shape = "hedgehog", body = "rock_dark", accent = "orange", blurb = "Its spines glow when it gets cross.", pn = "Hot Quills", fx = { wood = 0.15, charm = 1 } }),
	C({ id = "smoulderbug", name = "Smoulderbug", islet = 3, rarity = 2, hp = 22, atk = 8, def = 8, spd = 4, knack = "farm", shape = "beetle", body = "black", accent = "orange", blurb = "Carries a hot coal on its back to keep warm.", pn = "Coal Carrier", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "obsidusk", name = "Obsidusk", islet = 3, rarity = 3, hp = 30, atk = 10, def = 10, spd = 3, knack = "wood", shape = "elephant", body = "basalt", accent = "orange", blurb = "Its tusks are black glass, so it is careful with them.", pn = "Glass Tusks", fx = { wood = 0.3, charm = 1 } }),
	C({ id = "blazemane", name = "Blazemane", islet = 3, rarity = 4, hp = 27, atk = 13, def = 7, spd = 9, knack = "shop", shape = "cat", body = "orange", accent = "berry_red", blurb = "Its mane is a fire that never burns the ones it likes.", pn = "Warm Mane", fx = { sell = 0.5, shop = 0.25 } }),
	C({ id = "ashwing", name = "Ashwing", islet = 3, rarity = 5, hp = 32, atk = 15, def = 8, spd = 11, knack = "farm", shape = "bird", body = "berry_red", accent = "gold", blurb = "Every spring it burns down to ash and hatches again.", pn = "Second Spring", fx = { farm = 0.45, cost = -0.2, sell = 0.3 } }),
	-- Grottoes (islet 7)
	C({ id = "gemsnail", name = "Gemsnail", islet = 7, rarity = 1, hp = 20, atk = 7, def = 8, spd = 4, knack = "shop", shape = "snail", body = "purple", accent = "screen_on", blurb = "Its shell is a geode.", pn = "Gem Shell", fx = { shop = 0.18, charm = 1 } }),
	C({ id = "glowbat", name = "Glowbat", islet = 7, rarity = 1, hp = 18, atk = 8, def = 5, spd = 9, knack = "wood", shape = "bat", body = "night", accent = "screen_on", blurb = "Lights the way through dark caves.", pn = "Echo Glow", fx = { luck = 0.05, wood = 0.1 } }),
	C({ id = "quartzle", name = "Quartzle", islet = 7, rarity = 2, hp = 22, atk = 7, def = 9, spd = 4, knack = "wood", shape = "hedgehog", body = "chalk", accent = "purple", blurb = "Hums when it is happy.", pn = "Crystal Hum", fx = { charm = 1, work = 0.08 } }),
	C({ id = "crystowl", name = "Crystowl", islet = 7, rarity = 3, hp = 21, atk = 10, def = 6, spd = 8, knack = "shop", shape = "owl", body = "screen_on", accent = "purple", blurb = "Can see through walls. Promises not to look.", pn = "Clear Sight", fx = { luck = 0.12, shop = 0.2 } }),
	C({ id = "prismoth", name = "Prismoth", islet = 7, rarity = 4, hp = 20, atk = 12, def = 6, spd = 11, knack = "farm", shape = "moth", body = "pink", accent = "screen_on", blurb = "Turns sunlight into little rainbows.", pn = "Rainbow Wings", fx = { farm = 0.35, luck = 0.05, sell = 0.25 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "spored", name = "Spored", islet = 7, rarity = 1, hp = 19, atk = 7, def = 7, spd = 5, knack = "farm", shape = "shroom", body = "purple", accent = "screen_on", blurb = "Glows a little brighter when you talk to it.", pn = "Spore Light", fx = { farm = 0.15, charm = 1 } }),
	C({ id = "shardbug", name = "Shardbug", islet = 7, rarity = 1, hp = 20, atk = 7, def = 9, spd = 4, knack = "wood", shape = "beetle", body = "slate", accent = "crystal", blurb = "Its shell is a geode. Knock on it and it rings.", pn = "Ringing Shell", fx = { wood = 0.15, luck = 0.03 } }),
	C({ id = "lumenfin", name = "Lumenfin", islet = 7, rarity = 2, hp = 20, atk = 8, def = 6, spd = 8, knack = "shop", shape = "fish", body = "night", accent = "yellow", blurb = "Carries a little lamp on its head and never trips.", pn = "Little Lamp", fx = { shop = 0.2, luck = 0.04 } }),
	C({ id = "amethare", name = "Amethare", islet = 7, rarity = 2, hp = 21, atk = 7, def = 7, spd = 8, knack = "farm", shape = "bun", body = "snow", accent = "crystal", blurb = "Its ears are two crystals. They chime when it hops.", pn = "Chime Ears", fx = { farm = 0.22, charm = 1 } }),
	C({ id = "opalback", name = "Opalback", islet = 7, rarity = 3, hp = 26, atk = 9, def = 11, spd = 4, knack = "shop", shape = "armadillo", body = "cream", accent = "pink", blurb = "Curls up into a ball and looks like a big opal.", pn = "Opal Roll", fx = { shop = 0.3, sell = 0.2 } }),
	C({ id = "prismhorn", name = "Prismhorn", islet = 7, rarity = 4, hp = 26, atk = 12, def = 8, spd = 10, knack = "wood", shape = "deer", body = "white", accent = "crystal", blurb = "Its horn splits torchlight into colours on the cave walls.", pn = "Light Split", fx = { wood = 0.35, luck = 0.06 } }),
	-- Snowfields (islet 4)
	C({ id = "snowpuff", name = "Snowpuff", islet = 4, rarity = 1, hp = 26, atk = 8, def = 7, spd = 4, knack = "farm", shape = "yeti", body = "white", accent = "blue", blurb = "A snowball that learned to hug.", pn = "Big Hug", fx = { cost = -0.2, farm = 0.1 } }),
	C({ id = "floe", name = "Floe", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 6, knack = "farm", shape = "seal", body = "window", accent = "white", blurb = "Slides everywhere on its belly.", pn = "Belly Slide", fx = { luck = 0.03, farm = 0.2 } }),
	C({ id = "frostling", name = "Frostling", islet = 4, rarity = 2, hp = 18, atk = 10, def = 5, spd = 9, knack = "shop", shape = "sprite", body = "screen_on", accent = "white", blurb = "Grins, and the windows ice over.", pn = "Cold Snap", fx = { sell = 0.3, shop = 0.15 } }),
	C({ id = "icetoad", name = "Icetoad", islet = 4, rarity = 2, hp = 25, atk = 8, def = 8, spd = 5, knack = "shop", shape = "frog", body = "window", accent = "white", blurb = "Its croak frosts the windows.", pn = "Frost Croak", fx = { charm = 1, shop = 0.2 } }),
	C({ id = "glacior", name = "Glacior", islet = 4, rarity = 3, hp = 34, atk = 10, def = 12, spd = 3, knack = "wood", shape = "golem", body = "window", accent = "white", blurb = "A glacier with arms.", pn = "Permafrost", fx = { charm = 2, cost = -0.15, wood = 0.2 } }),
	C({ id = "frostdrake", name = "Frostdrake", islet = 4, rarity = 4, hp = 30, atk = 13, def = 8, spd = 9, knack = "shop", shape = "drake", body = "blue", accent = "white", blurb = "Freezes the sea to walk on it.", pn = "Ice Breath", fx = { sell = 0.45, shop = 0.35 } }),
	C({ id = "frostcrown", name = "Frostcrown", islet = 4, rarity = 5, hp = 40, atk = 14, def = 13, spd = 6, knack = "farm", shape = "yeti", body = "gold", accent = "white", blurb = "Snow piles up wherever it stops.", pn = "Winter's Crown", fx = { cost = -0.4, charm = 2, farm = 0.4 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "slidget", name = "Slidget", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 5, knack = "farm", shape = "penguin", body = "slate", accent = "white", blurb = "Slides downhill on its tummy, then walks back up to do it again.", pn = "Tummy Slide", fx = { farm = 0.15, luck = 0.03 } }),
	C({ id = "rimekit", name = "Rimekit", islet = 4, rarity = 1, hp = 22, atk = 8, def = 6, spd = 7, knack = "wood", shape = "pup", body = "white", accent = "ice", blurb = "Its coat turns grey in summer and white again with the first snow.", pn = "Winter Coat", fx = { wood = 0.15, cost = -0.1 } }),
	C({ id = "tuskle", name = "Tuskle", islet = 4, rarity = 2, hp = 28, atk = 8, def = 9, spd = 3, knack = "wood", shape = "elephant", body = "wood", accent = "white", blurb = "Under the fur there is more fur.", pn = "Thick Fur", fx = { wood = 0.2, charm = 1 } }),
	C({ id = "peakhorn", name = "Peakhorn", islet = 4, rarity = 3, hp = 30, atk = 10, def = 9, spd = 7, knack = "shop", shape = "deer", body = "white", accent = "steel", blurb = "Stands on cliff edges just to see who is watching.", pn = "Sure Foot", fx = { shop = 0.3, luck = 0.04 } }),
	C({ id = "frostlynx", name = "Frostlynx", islet = 4, rarity = 4, hp = 28, atk = 12, def = 7, spd = 10, knack = "farm", shape = "cat", body = "window", accent = "white", blurb = "Walks on top of the snow without leaving a print.", pn = "Light Step", fx = { farm = 0.35, luck = 0.06 } }),
	C({ id = "glimmerfleece", name = "Glimmerfleece", islet = 4, rarity = 5, hp = 38, atk = 13, def = 12, spd = 6, knack = "shop", shape = "ram", body = "white", accent = "screen_on", blurb = "Its wool glows green and pink on the longest nights.", pn = "Night Fleece", fx = { shop = 0.4, luck = 0.15, cost = -0.15 } }),
	-- Bluffs (islet 8)
	C({ id = "cloudbun", name = "Cloudbun", islet = 8, rarity = 1, hp = 22, atk = 8, def = 6, spd = 8, knack = "farm", shape = "bun", body = "white", accent = "window", blurb = "Floats a little when it sneezes.", pn = "Fluffy Rain", fx = { farm = 0.2, cost = -0.1 } }),
	C({ id = "breezle", name = "Breezle", islet = 8, rarity = 1, hp = 20, atk = 9, def = 5, spd = 11, knack = "wood", shape = "bird", body = "window", accent = "blue", blurb = "Rides the cliff winds all day.", pn = "Tailwind", fx = { luck = 0.06 } }),
	C({ id = "skyfox", name = "Skyfox", islet = 8, rarity = 2, hp = 23, atk = 10, def = 6, spd = 10, knack = "shop", shape = "pup", body = "blue", accent = "white", blurb = "Chases clouds and sometimes catches one.", pn = "Cloud Chaser", fx = { luck = 0.04, shop = 0.2 } }),
	C({ id = "stormowl", name = "Stormowl", islet = 8, rarity = 3, hp = 24, atk = 12, def = 7, spd = 9, knack = "wood", shape = "owl", body = "night", accent = "yellow", blurb = "Its hoot rolls like thunder.", pn = "Thunder Hoot", fx = { sell = 0.35, wood = 0.25 } }),
	C({ id = "thunderdrake", name = "Thunderdrake", islet = 8, rarity = 4, hp = 31, atk = 15, def = 8, spd = 10, knack = "wood", shape = "drake", body = "purple", accent = "yellow", blurb = "Lightning is its favourite snack.", pn = "Charged Scales", fx = { sell = 0.45, luck = 0.05, wood = 0.3 } }),
	C({ id = "aurorawing", name = "Aurorawing", islet = 8, rarity = 5, hp = 32, atk = 15, def = 10, spd = 13, knack = "shop", shape = "bat", body = "screen_on", accent = "pink", blurb = "Paints the night sky as it flies.", pn = "Northern Lights", fx = { luck = 0.24, shop = 0.4 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "craglet", name = "Craglet", islet = 8, rarity = 1, hp = 21, atk = 8, def = 6, spd = 8, knack = "wood", shape = "deer", body = "cream", accent = "rock", blurb = "Climbs anything, including you.", pn = "Climber", fx = { wood = 0.15, luck = 0.03 } }),
	C({ id = "puffbill", name = "Puffbill", islet = 8, rarity = 1, hp = 20, atk = 8, def = 5, spd = 9, knack = "farm", shape = "penguin", body = "black", accent = "orange", blurb = "Carries six fish in its beak and drops every one.", pn = "Full Beak", fx = { farm = 0.18, sell = 0.15 } }),
	C({ id = "windhare", name = "Windhare", islet = 8, rarity = 2, hp = 22, atk = 9, def = 5, spd = 11, knack = "shop", shape = "bun", body = "sand", accent = "white", blurb = "Runs along the cliff top into the wind, just for fun.", pn = "Headwind", fx = { shop = 0.2, luck = 0.04 } }),
	C({ id = "sweepwing", name = "Sweepwing", islet = 8, rarity = 3, hp = 23, atk = 11, def = 6, spd = 11, knack = "wood", shape = "bird", body = "wood", accent = "cream", blurb = "Sleeps on the wing and lands about once a year.", pn = "Sky Nap", fx = { wood = 0.25, sell = 0.25 } }),
	C({ id = "galeram", name = "Galeram", islet = 8, rarity = 4, hp = 32, atk = 13, def = 10, spd = 7, knack = "farm", shape = "ram", body = "white", accent = "rock", blurb = "Its horns curl like the wind round the cliffs.", pn = "Gale Horns", fx = { farm = 0.35, cost = -0.2 } }),
	C({ id = "stormgriff", name = "Stormgriff", islet = 8, rarity = 5, hp = 34, atk = 16, def = 10, spd = 12, knack = "wood", shape = "griffin", body = "gold", accent = "white", blurb = "Flies in on the storm and tells everyone about it after.", pn = "Storm Rider", fx = { wood = 0.45, luck = 0.1, sell = 0.3 } }),
	-- Reefs (islet 5)
	C({ id = "coralcrab", name = "Coralcrab", islet = 5, rarity = 1, hp = 24, atk = 10, def = 8, spd = 6, knack = "farm", shape = "crab", body = "pink", accent = "orange", blurb = "Wears a coral crown it grew itself.", pn = "Coral Crown", fx = { charm = 1, farm = 0.18 } }),
	C({ id = "lumajelly", name = "Lumajelly", islet = 5, rarity = 1, hp = 22, atk = 9, def = 6, spd = 7, knack = "shop", shape = "jelly", body = "pink", accent = "purple", blurb = "Glows softly when it is happy.", pn = "Soft Glow", fx = { shop = 0.2, cost = -0.1 } }),
	C({ id = "pearlback", name = "Pearlback", islet = 5, rarity = 2, hp = 30, atk = 9, def = 11, spd = 4, knack = "shop", shape = "turtle", body = "white", accent = "pink", blurb = "Grows a pearl on its shell every year.", pn = "Pearl Grower", fx = { shop = 0.3, charm = 1 } }),
	C({ id = "novafox", name = "Novafox", islet = 5, rarity = 3, hp = 24, atk = 12, def = 6, spd = 10, knack = "wood", shape = "pup", body = "gold", accent = "purple", blurb = "Its tail leaves a trail of stars.", pn = "Starry Tail", fx = { luck = 0.06, wood = 0.25 } }),
	C({ id = "tidewyrm", name = "Tidewyrm", islet = 5, rarity = 4, hp = 34, atk = 12, def = 9, spd = 7, knack = "farm", shape = "wyrm", body = "blue", accent = "screen_on", blurb = "The deep's oldest swimmer.", pn = "Tidal Pull", fx = { cost = -0.2, farm = 0.4 } }),
	C({ id = "abyssmaw", name = "Abyssmaw", islet = 5, rarity = 5, hp = 42, atk = 17, def = 11, spd = 8, knack = "farm", shape = "wyrm", body = "night", accent = "purple", blurb = "Sleeps at the bottom of the deepest trench.", pn = "Deep Hunger", fx = { sell = 0.65, cost = -0.3, farm = 0.5 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "stripefin", name = "Stripefin", islet = 5, rarity = 1, hp = 22, atk = 9, def = 7, spd = 7, knack = "shop", shape = "fish", body = "orange", accent = "white", blurb = "Lives in an anemone and has never once paid rent.", pn = "Free Room", fx = { shop = 0.18, cost = -0.1 } }),
	C({ id = "squidge", name = "Squidge", islet = 5, rarity = 1, hp = 23, atk = 9, def = 6, spd = 7, knack = "farm", shape = "octo", body = "pink", accent = "purple", blurb = "Squirts ink when it laughs, so it tries not to.", pn = "Ink Squirt", fx = { farm = 0.18, charm = 1 } }),
	C({ id = "reefray", name = "Reefray", islet = 5, rarity = 2, hp = 28, atk = 9, def = 9, spd = 6, knack = "farm", shape = "ray", body = "blue", accent = "white", blurb = "Flaps slowly over the coral like a big blue blanket.", pn = "Slow Flap", fx = { farm = 0.25, luck = 0.03 } }),
	C({ id = "coralcurl", name = "Coralcurl", islet = 5, rarity = 3, hp = 25, atk = 11, def = 8, spd = 8, knack = "shop", shape = "seahorse", body = "pink", accent = "orange", blurb = "Its tail curls round anything you hand it.", pn = "Curly Grip", fx = { shop = 0.3, sell = 0.2 } }),
	C({ id = "tidegrip", name = "Tidegrip", islet = 5, rarity = 4, hp = 32, atk = 12, def = 9, spd = 8, knack = "wood", shape = "octo", body = "purple", accent = "pink", blurb = "Has eight arms and uses all of them to tidy up.", pn = "Eight Hands", fx = { wood = 0.35, work = 0.1 } }),
	C({ id = "elderreef", name = "Elderreef", islet = 5, rarity = 5, hp = 46, atk = 13, def = 15, spd = 4, knack = "farm", shape = "turtle", body = "green", accent = "pink", blurb = "A whole reef grows on its shell, fish and all.", pn = "Walking Reef", fx = { farm = 0.5, cost = -0.25, charm = 1 } }),
	-- Ruins (islet 9)
	C({ id = "relicrab", name = "Relicrab", islet = 9, rarity = 1, hp = 26, atk = 11, def = 9, spd = 6, knack = "shop", shape = "crab", body = "sand_dark", accent = "gold", blurb = "Hoards old coins under its shell.", pn = "Coin Hoard", fx = { shop = 0.25 } }),
	C({ id = "rubblet", name = "Rubblet", islet = 9, rarity = 1, hp = 28, atk = 10, def = 10, spd = 4, knack = "wood", shape = "crab", body = "rock", accent = "sand", blurb = "A loose stone from a fallen wall.", pn = "Old Mortar", fx = { charm = 1, wood = 0.12 } }),
	C({ id = "glyphowl", name = "Glyphowl", islet = 9, rarity = 2, hp = 25, atk = 11, def = 8, spd = 8, knack = "farm", shape = "owl", body = "sand", accent = "gold", blurb = "Reads the old carvings aloud.", pn = "Ancient Lore", fx = { luck = 0.15, farm = 0.15 } }),
	C({ id = "sentinel", name = "Sentinel", islet = 9, rarity = 3, hp = 38, atk = 12, def = 14, spd = 3, knack = "wood", shape = "golem", body = "rock", accent = "gold", blurb = "Still guards a door no one remembers.", pn = "Stone Guard", fx = { charm = 2, cost = -0.2, work = 0.1 } }),
	C({ id = "runemoth", name = "Runemoth", islet = 9, rarity = 4, hp = 27, atk = 14, def = 8, spd = 12, knack = "shop", shape = "moth", body = "gold", accent = "purple", blurb = "Its wings are covered in old spells.", pn = "Rune Wings", fx = { luck = 0.16, shop = 0.3 } }),
	C({ id = "solwyrm", name = "Solwyrm", islet = 9, rarity = 5, hp = 44, atk = 17, def = 12, spd = 9, knack = "farm", shape = "wyrm", body = "gold", accent = "white", blurb = "The ruins were built to honour it.", pn = "Sun Blessing", fx = { cost = -0.3, sell = 0.45, work = 0.25 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "tombcat", name = "Tombcat", islet = 9, rarity = 1, hp = 25, atk = 10, def = 8, spd = 7, knack = "shop", shape = "cat", body = "sand", accent = "gold", blurb = "Sits on the old steps all day as if it owns them.", pn = "Old Steps", fx = { shop = 0.2, luck = 0.03 } }),
	C({ id = "scarabit", name = "Scarabit", islet = 9, rarity = 1, hp = 26, atk = 9, def = 10, spd = 5, knack = "farm", shape = "beetle", body = "blue", accent = "gold", blurb = "Rolls a ball of dust up and down the stairs.", pn = "Dust Roller", fx = { farm = 0.18, cost = -0.1 } }),
	C({ id = "vinegeck", name = "Vinegeck", islet = 9, rarity = 2, hp = 24, atk = 10, def = 8, spd = 8, knack = "wood", shape = "lizard", body = "leaf", accent = "gold", blurb = "Turns the colour of whatever wall it sits on.", pn = "Wall Colour", fx = { wood = 0.22, luck = 0.05 } }),
	C({ id = "ruinape", name = "Ruinape", islet = 9, rarity = 3, hp = 28, atk = 12, def = 9, spd = 9, knack = "shop", shape = "monkey", body = "rock", accent = "white", blurb = "Swings from pillar to pillar and steals hats.", pn = "Hat Thief", fx = { shop = 0.3, sell = 0.2 } }),
	C({ id = "gildmane", name = "Gildmane", islet = 9, rarity = 4, hp = 32, atk = 14, def = 10, spd = 8, knack = "farm", shape = "cat", body = "gold", accent = "sand", blurb = "A lion of old gold. It purrs like a temple bell.", pn = "Bell Purr", fx = { farm = 0.35, sell = 0.3 } }),
	C({ id = "templeback", name = "Templeback", islet = 9, rarity = 5, hp = 48, atk = 14, def = 16, spd = 3, knack = "shop", shape = "turtle", body = "sand_dark", accent = "gold", blurb = "Carries a whole temple on its back and never once complains.", pn = "Holy Shell", fx = { shop = 0.45, cost = -0.25, charm = 1 } }),
	-- Moonwoods (islet 10, tier 11: the first mythic one)
	C({ id = "duskbun", name = "Duskbun", islet = 10, rarity = 1, hp = 30, atk = 11, def = 9, spd = 8, knack = "farm", shape = "bun", body = "slate", accent = "crystal", blurb = "Naps all day and gardens all night.", pn = "Night Shift", fx = { farm = 0.22, work = 0.06 } }),
	C({ id = "hushpup", name = "Hushpup", islet = 10, rarity = 2, hp = 30, atk = 13, def = 8, spd = 12, knack = "shop", shape = "pup", body = "black", accent = "crystal", blurb = "Walks so softly the shop bell never rings.", pn = "Soft Paws", fx = { shop = 0.25, sell = 0.25 } }),
	C({ id = "lunowl", name = "Lunowl", islet = 10, rarity = 3, hp = 31, atk = 13, def = 10, spd = 10, knack = "farm", shape = "owl", body = "white", accent = "crystal", blurb = "Counts the stars out loud and loses count every night.", pn = "Night Watch", fx = { farm = 0.3, luck = 0.05 } }),
	C({ id = "wispkin", name = "Wispkin", islet = 10, rarity = 4, hp = 30, atk = 16, def = 9, spd = 14, knack = "wood", shape = "sprite", body = "crystal", accent = "white", blurb = "A little light that chops wood when nobody is looking.", pn = "Hidden Hands", fx = { wood = 0.35, work = 0.12 } }),
	C({ id = "silverbark", name = "Silverbark", islet = 10, rarity = 5, hp = 48, atk = 16, def = 16, spd = 4, knack = "wood", shape = "golem", body = "steel", accent = "crystal", blurb = "The oldest tree in the wood. It walks when the moon is full.", pn = "Moonsap", fx = { wood = 0.45, cost = -0.3, work = 0.2 } }),
	C({ id = "moonveil", name = "Moonveil", islet = 10, rarity = 6, hp = 40, atk = 19, def = 12, spd = 15, knack = "shop", shape = "bat", body = "night", accent = "cherry", blurb = "Its wings cover the moon. It gives it back by morning.", pn = "Eclipse Wings", fx = { shop = 0.5, luck = 0.18, sell = 0.6 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "dimwing", name = "Dimwing", islet = 10, rarity = 1, hp = 28, atk = 12, def = 8, spd = 10, knack = "farm", shape = "moth", body = "slate", accent = "crystal", blurb = "Only comes out once the lamps are lit.", pn = "Lamp Moth", fx = { farm = 0.22, luck = 0.03 } }),
	C({ id = "moonfawn", name = "Moonfawn", islet = 10, rarity = 2, hp = 30, atk = 12, def = 9, spd = 11, knack = "wood", shape = "deer", body = "white", accent = "crystal", blurb = "Its spots glow like little moons.", pn = "Moon Spots", fx = { wood = 0.25, work = 0.06 } }),
	C({ id = "duskbear", name = "Duskbear", islet = 10, rarity = 3, hp = 38, atk = 13, def = 12, spd = 6, knack = "farm", shape = "bear", body = "night", accent = "crystal", blurb = "Sleeps all winter and dreams about honey.", pn = "Long Dream", fx = { farm = 0.3, cost = -0.15 } }),
	C({ id = "moonshroom", name = "Moonshroom", islet = 10, rarity = 4, hp = 34, atk = 14, def = 11, spd = 7, knack = "shop", shape = "shroom", body = "crystal", accent = "white", blurb = "Grows a new cap every full moon.", pn = "Full Moon Cap", fx = { shop = 0.4, luck = 0.08 } }),
	C({ id = "silverhoof", name = "Silverhoof", islet = 10, rarity = 5, hp = 44, atk = 16, def = 13, spd = 13, knack = "shop", shape = "deer", body = "white", accent = "steel", blurb = "Steps so softly the flowers stand back up behind it.", pn = "Soft Hooves", fx = { shop = 0.45, luck = 0.12, cost = -0.2 } }),
	C({ id = "moonhowl", name = "Moonhowl", islet = 10, rarity = 6, hp = 42, atk = 19, def = 12, spd = 15, knack = "farm", shape = "pup", body = "night", accent = "crystal", blurb = "Howls once at moonrise and the whole wood goes quiet.", pn = "Moon Howl", fx = { farm = 0.55, luck = 0.15, work = 0.2 } }),
	-- Cloudtops (islet 11, tier 14: the first celestial one)
	C({ id = "puffling", name = "Puffling", islet = 11, rarity = 1, hp = 34, atk = 12, def = 10, spd = 8, knack = "farm", shape = "ram", body = "white", accent = "window", blurb = "A loose bit of cloud that followed someone home.", pn = "Light Rain", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "cirrup", name = "Cirrup", islet = 11, rarity = 2, hp = 32, atk = 13, def = 9, spd = 13, knack = "shop", shape = "bird", body = "window", accent = "white", blurb = "Sings the weather a day before it comes.", pn = "Fair Forecast", fx = { shop = 0.25, luck = 0.04 } }),
	C({ id = "cloudjelly", name = "Cloudjelly", islet = 11, rarity = 3, hp = 34, atk = 14, def = 10, spd = 9, knack = "farm", shape = "jelly", body = "white", accent = "pink", blurb = "Floats over the fields and waters them on the way.", pn = "Drizzle Drift", fx = { farm = 0.35, work = 0.08 } }),
	C({ id = "billowbear", name = "Billowbear", islet = 11, rarity = 4, hp = 46, atk = 17, def = 14, spd = 6, knack = "wood", shape = "bear", body = "white", accent = "slate", blurb = "Hugs storm clouds until they calm down.", pn = "Storm Hug", fx = { wood = 0.35, cost = -0.15, work = 0.1 } }),
	C({ id = "skyshell", name = "Skyshell", islet = 11, rarity = 6, hp = 54, atk = 15, def = 18, spd = 5, knack = "farm", shape = "turtle", body = "window", accent = "white", blurb = "Carries a little cloud on its back with a farm on top.", pn = "Floating Field", fx = { farm = 0.55, work = 0.25, luck = 0.08 } }),
	C({ id = "cloudwhale", name = "Cloudwhale", islet = 11, rarity = 7, hp = 60, atk = 18, def = 16, spd = 8, knack = "shop", shape = "seal", body = "ice", accent = "white", blurb = "Swims through the clouds. Its song makes them hum.", pn = "Sky Song", fx = { shop = 0.6, luck = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "cloudpip", name = "Cloudpip", islet = 11, rarity = 1, hp = 32, atk = 12, def = 9, spd = 12, knack = "shop", shape = "bird", body = "white", accent = "pink", blurb = "Too light to land, so it hangs in the air and chirps.", pn = "Featherlight", fx = { shop = 0.25, luck = 0.03 } }),
	C({ id = "gustotter", name = "Gustotter", islet = 11, rarity = 2, hp = 34, atk = 13, def = 10, spd = 12, knack = "farm", shape = "otter", body = "window", accent = "white", blurb = "Swims through clouds as if they were water.", pn = "Cloud Swim", fx = { farm = 0.28, work = 0.06 } }),
	C({ id = "raindeer", name = "Raindeer", islet = 11, rarity = 3, hp = 36, atk = 14, def = 11, spd = 10, knack = "wood", shape = "deer", body = "slate", accent = "white", blurb = "Wherever it stops, it starts to drizzle.", pn = "Light Drizzle", fx = { wood = 0.35, work = 0.08 } }),
	C({ id = "stormphant", name = "Stormphant", islet = 11, rarity = 4, hp = 48, atk = 16, def = 15, spd = 6, knack = "shop", shape = "elephant", body = "slate", accent = "yellow", blurb = "Trumpets thunder and sprays rain out of its trunk.", pn = "Rain Trunk", fx = { shop = 0.4, cost = -0.15, luck = 0.05 } }),
	C({ id = "cloudgriff", name = "Cloudgriff", islet = 11, rarity = 6, hp = 50, atk = 18, def = 15, spd = 14, knack = "wood", shape = "griffin", body = "white", accent = "gold", blurb = "Nests on the highest cloud and keeps watch all night.", pn = "High Nest", fx = { wood = 0.55, work = 0.2, luck = 0.1 } }),
	C({ id = "skyherald", name = "Skyherald", islet = 11, rarity = 7, hp = 48, atk = 20, def = 14, spd = 17, knack = "farm", shape = "bird", body = "window", accent = "gold", blurb = "Sings the sun up every morning and has never missed one.", pn = "Dawn Song", fx = { farm = 0.6, luck = 0.3, work = 0.2 } }),
	-- Starfalls (islet 12, tier 17)
	C({ id = "glimmite", name = "Glimmite", islet = 12, rarity = 1, hp = 36, atk = 14, def = 12, spd = 7, knack = "wood", shape = "crab", body = "slate", accent = "screen_on", blurb = "Picks bits of fallen star out of the sand.", pn = "Star Picker", fx = { wood = 0.25, sell = 0.2 } }),
	C({ id = "cometail", name = "Cometail", islet = 12, rarity = 3, hp = 34, atk = 16, def = 10, spd = 15, knack = "shop", shape = "lizard", body = "blue", accent = "yellow", blurb = "Its tail keeps glowing a second after it runs past.", pn = "Bright Trail", fx = { shop = 0.35, luck = 0.05 } }),
	C({ id = "cratermole", name = "Cratermole", islet = 12, rarity = 5, hp = 44, atk = 19, def = 14, spd = 8, knack = "wood", shape = "mole", body = "basalt", accent = "screen_on", blurb = "Dug the crater wider looking for one more star.", pn = "Deep Dig", fx = { wood = 0.45, sell = 0.5, work = 0.2 } }),
	C({ id = "nebulynx", name = "Nebulynx", islet = 12, rarity = 6, hp = 42, atk = 20, def = 12, spd = 16, knack = "shop", shape = "cat", body = "purple", accent = "screen_on", blurb = "There are tiny galaxies in its fur. It knows each one by name.", pn = "Pocket Galaxy", fx = { shop = 0.55, luck = 0.2, sell = 0.7 } }),
	C({ id = "starweaver", name = "Starweaver", islet = 12, rarity = 7, hp = 44, atk = 21, def = 13, spd = 17, knack = "farm", shape = "moth", body = "night", accent = "crystal", blurb = "Spins new stars out of moonlight and hangs them up at dusk.", pn = "Star Loom", fx = { farm = 0.6, luck = 0.12, work = 0.35 } }),
	C({ id = "novawyrm", name = "Novawyrm", islet = 12, rarity = 7, hp = 62, atk = 22, def = 16, spd = 10, knack = "wood", shape = "wyrm", body = "night", accent = "gold", blurb = "Sleeps curled round the whole crater. When it yawns, a star lights up.", pn = "First Light", fx = { wood = 0.6, cost = -0.4, luck = 0.22 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "twinkbun", name = "Twinkbun", islet = 12, rarity = 1, hp = 34, atk = 13, def = 11, spd = 10, knack = "farm", shape = "bun", body = "night", accent = "yellow", blurb = "Twinkles whenever it twitches its nose.", pn = "Twinkle Nose", fx = { farm = 0.25, cost = -0.1 } }),
	C({ id = "craterbug", name = "Craterbug", islet = 12, rarity = 1, hp = 36, atk = 13, def = 13, spd = 6, knack = "wood", shape = "beetle", body = "basalt", accent = "screen_on", blurb = "Digs a little crater every night to sleep in.", pn = "Little Crater", fx = { wood = 0.25, sell = 0.2 } }),
	C({ id = "starfin", name = "Starfin", islet = 12, rarity = 3, hp = 34, atk = 16, def = 10, spd = 14, knack = "shop", shape = "fish", body = "night", accent = "screen_on", blurb = "Swims loops through the air as if it were still in space.", pn = "Loop Swim", fx = { shop = 0.35, luck = 0.05 } }),
	C({ id = "starshell", name = "Starshell", islet = 12, rarity = 5, hp = 52, atk = 17, def = 17, spd = 5, knack = "farm", shape = "turtle", body = "night", accent = "yellow", blurb = "The stars on its shell move round while it sleeps.", pn = "Sky Shell", fx = { farm = 0.45, sell = 0.5, work = 0.2 } }),
	C({ id = "cosmofleece", name = "Cosmofleece", islet = 12, rarity = 6, hp = 46, atk = 19, def = 14, spd = 12, knack = "shop", shape = "ram", body = "purple", accent = "screen_on", blurb = "Its fleece is full of tiny stars. Nobody is allowed to shear it.", pn = "Star Fleece", fx = { shop = 0.55, luck = 0.2, sell = 0.7 } }),
	C({ id = "starhart", name = "Starhart", islet = 12, rarity = 7, hp = 50, atk = 21, def = 15, spd = 16, knack = "wood", shape = "deer", body = "white", accent = "crystal", blurb = "Its antlers hold up the night sky, very gently.", pn = "Sky Antlers", fx = { wood = 0.6, cost = -0.4, luck = 0.22 } }),
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
	-- (the new ones of 2026-11-15)
	sandkit = { "bead", false, "fur" },
	puffpod = { "round", "orange", "scale" },
	kelpup = { "sparkle", "wood_dark", "fur" },
	tidepip = { "bead", false, "feather" },
	kelphorse = { "lashes", "pink", "scale" },
	duneray = { "sleepy", "blue", "skin" },
	burrowby = { "button", false, "fur" },
	puddlet = { "button", false, "feather" },
	fawnlet = { "sparkle", "wood_dark", "fur" },
	bumblet = { "sparkle", "yellow", "fluff" },
	thistlemane = { "happy", false, "fur", "fluff" },
	mossbuck = { "sleepy", "leaf", "fur", "bark" },
	cinderkit = { "slit", "orange", "fur" },
	emberquill = { "fierce", "orange", "fur", "ember" },
	smoulderbug = { "glow", "orange", "chitin", "ember" },
	obsidusk = { "glow", "orange", "stone" },
	blazemane = { "fierce", "berry_red", "fur", "ember" },
	ashwing = { "fierce", "gold", "feather", "ember" },
	slidget = { "sparkle", "blue", "feather" },
	rimekit = { "sleepy", "blue", "fluff" },
	tuskle = { "sleepy", "wood_dark", "fluff" },
	peakhorn = { "bar", "gold", "fluff" },
	frostlynx = { "ringed", "blue", "fluff" },
	glimmerfleece = { "glow", "screen_on", "fluff" },
	stripefin = { "sparkle", "orange", "scale" },
	squidge = { "happy", false, "skin" },
	reefray = { "bead", false, "skin" },
	coralcurl = { "ringed", "orange", "scale" },
	tidegrip = { "bar", "pink", "skin" },
	elderreef = { "button", false, "scale", "crystal" },
	gillo = { "happy", false, "skin" },
	slinkit = { "bead", false, "fur" },
	dabbler = { "bead", false, "feather" },
	snapmoss = { "fierce", "leaf", "scale", "bark" },
	stiltbeak = { "slit", "yellow", "feather" },
	grinmire = { "sleepy", "yellow", "scale" },
	spored = { "dot", false, "velvet" },
	shardbug = { "gem", "crystal", "chitin", "crystal" },
	lumenfin = { "glow", "yellow", "scale" },
	amethare = { "gem", "crystal", "fluff", "crystal" },
	opalback = { "gem", "pink", "skin", "crystal" },
	prismhorn = { "gem", "crystal", "fur", "crystal" },
	craglet = { "button", false, "fluff" },
	puffbill = { "round", "orange", "feather" },
	windhare = { "wide", "wood_dark", "fur" },
	sweepwing = { "ringed", "gold", "feather" },
	galeram = { "bar", "gold", "fluff" },
	stormgriff = { "fierce", "gold", "feather", "fur" },
	tombcat = { "bar", "gold", "fur" },
	scarabit = { "bead", false, "chitin" },
	vinegeck = { "ringed", "gold", "scale" },
	ruinape = { "round", "gold", "fur" },
	gildmane = { "sparkle", "gold", "fur", "fluff" },
	templeback = { "specs", "gold", "scale", "brick" },
	dimwing = { "sleepy", "crystal", "velvet" },
	moonfawn = { "lashes", "crystal", "fur" },
	duskbear = { "sleepy", "crystal", "fur" },
	moonshroom = { "sleepy", "white", "velvet" },
	silverhoof = { "ringed", "steel", "fur" },
	moonhowl = { "glow", "crystal", "fur" },
	cloudpip = { "happy", false, "fluff" },
	gustotter = { "happy", false, "fluff" },
	raindeer = { "round", "blue", "fur" },
	stormphant = { "round", "yellow", "skin" },
	cloudgriff = { "ringed", "gold", "feather", "fur" },
	skyherald = { "star", "gold", "feather" },
	twinkbun = { "star", "yellow", "fluff" },
	craterbug = { "compound", "screen_on", "chitin", "crystal" },
	starfin = { "star", "screen_on", "scale" },
	starshell = { "star", "yellow", "scale", "shell" },
	cosmofleece = { "star", "screen_on", "fluff" },
	starhart = { "star", "crystal", "fur", "crystal" },
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
