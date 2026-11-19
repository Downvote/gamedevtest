--!strict
-- The driftlings (GAME_DESIGN 6): the creatures that hatch from the Tree of Life's eggs, all our own. Pure. Each comes
-- from one kind of land (Data/Islets: a kind's driftlings hatch from the tree's eggs once the island reaches that kind's
-- tier, and now and then before: Logic/Tree.pool), has a rarity (1 common .. 7 celestial, Data/Traits: the tree lays
-- rarer eggs less often, and rarer ones work faster) and a passive of its own (Data/Traits effects). The mythic and
-- celestial ones live on the kinds of land a tier 11 island and up opens (Moonwood, Cloudtop, Starfall: 2026-11-14).
--   (Each had a knack, the kind of work building it helped at, till the request of 2026-11-19: "remove work building
--   types. They all now fall in the same category of work ... Passives and mutations that have different work
--   building types now are just one". A passive's farm, wood or shop share became work; a few became boost building,
--   charm share or Hatchery time passives: "Make mutations and rework some passives to boost boost buildings. Make
--   mutations and rework some passives to give a percentage boost to charm, while keeping some as a flat boost".)
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
	C({ id = "pebblit", name = "Pebblit", islet = 1, rarity = 1, hp = 16, atk = 5, def = 6, spd = 3, shape = "armadillo", body = "steel", accent = "steel_dark", blurb = "A pebble that never stopped rolling.", pn = "Rolling Stone", fx = { work = 0.15, charm = 1 } }),
	C({ id = "clawdle", name = "Clawdle", islet = 1, rarity = 1, hp = 13, atk = 7, def = 4, spd = 5, shape = "crab", body = "berry_red", accent = "orange", blurb = "Pinches people. It means well.", pn = "Snappy Pincers", fx = { work = 0.15, sell = 0.3 } }),
	C({ id = "gullfin", name = "Gullfin", islet = 1, rarity = 2, hp = 12, atk = 5, def = 3, spd = 8, shape = "bird", body = "white", accent = "blue", blurb = "Eats anything that floats.", pn = "Diving Beak", fx = { work = 0.25, luck = 0.04 } }),
	C({ id = "conchy", name = "Conchy", islet = 1, rarity = 2, hp = 15, atk = 4, def = 7, spd = 3, shape = "snail", body = "pink", accent = "cream", blurb = "Keeps a shop in its shell.", pn = "Pocket Shop", fx = { work = 0.3 } }),
	C({ id = "shellback", name = "Shellback", islet = 1, rarity = 3, hp = 20, atk = 6, def = 9, spd = 3, shape = "turtle", body = "green", accent = "sand", blurb = "Naps a lot, then works for days.", pn = "Slow and Steady", fx = { work = 0.12, cost = -0.2 } }),
	C({ id = "sunsprite", name = "Sunsprite", islet = 1, rarity = 4, hp = 17, atk = 9, def = 5, spd = 9, shape = "sprite", body = "gold", accent = "yellow", blurb = "Glows like noon at midnight.", pn = "Sunny Spell", fx = { work = 0.35, sell = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "sandkit", name = "Sandkit", islet = 1, rarity = 1, hp = 14, atk = 6, def = 4, spd = 6, shape = "pup", body = "sand", accent = "cream", blurb = "Can hear the tide turn.", pn = "Big Ears", fx = { work = 0.15, luck = 0.03 } }),
	C({ id = "puffpod", name = "Puffpod", islet = 1, rarity = 1, hp = 15, atk = 5, def = 6, spd = 3, shape = "fish", body = "yellow", accent = "orange", blurb = "Puffs up at every little fright.", pn = "Puff Up", fx = { work = 0.15, charm = 1 } }),
	C({ id = "kelpup", name = "Kelpup", islet = 1, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, shape = "otter", body = "wood", accent = "cream", blurb = "Naps afloat, hugging a shell.", pn = "Shell Nap", fx = { work = 0.125, hatch = 0.06, cost = -0.1 } }),
	C({ id = "tidepip", name = "Tidepip", islet = 1, rarity = 2, hp = 12, atk = 6, def = 3, spd = 8, shape = "bird", body = "sand", accent = "white", blurb = "Darts in and out with the waves.", pn = "Wave Chaser", fx = { work = 0.2, luck = 0.05 } }),
	C({ id = "kelphorse", name = "Kelphorse", islet = 1, rarity = 3, hp = 16, atk = 7, def = 6, spd = 5, shape = "seahorse", body = "coral", accent = "cream", blurb = "Hums at boats from the kelp.", pn = "Kelp Hum", fx = { boost = 0.12, luck = 0.03 } }),
	C({ id = "duneray", name = "Duneray", islet = 1, rarity = 4, hp = 18, atk = 9, def = 6, spd = 9, shape = "ray", body = "sand", accent = "blue", blurb = "Skims the sand faster than gulls.", pn = "Low Glide", fx = { work = 0.35, sell = 0.25 } }),
	-- Meadows (islet 2)
	C({ id = "mossbun", name = "Mossbun", islet = 2, rarity = 1, hp = 18, atk = 5, def = 4, spd = 7, shape = "bun", body = "green", accent = "leaf_dark", blurb = "Its ears are soft moss.", pn = "Mossy Ears", fx = { work = 0.15, cost = -0.15 } }),
	C({ id = "frondle", name = "Frondle", islet = 2, rarity = 1, hp = 16, atk = 8, def = 4, spd = 6, shape = "lizard", body = "leaf", accent = "yellow", blurb = "Hides in plain leaves.", pn = "Leaf Cloak", fx = { work = 0.18, charm = 1 } }),
	C({ id = "twiggle", name = "Twiggle", islet = 2, rarity = 2, hp = 15, atk = 6, def = 5, spd = 6, shape = "owl", body = "wood", accent = "wood_dark", blurb = "A chatty bundle of sticks.", pn = "Woodwise", fx = { work = 0.2, luck = 0.07 } }),
	C({ id = "hopsprout", name = "Hopsprout", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, shape = "frog", body = "leaf", accent = "pink", blurb = "Every hop plants a seed.", pn = "Seed Hopper", fx = { work = 0.25, luck = 0.03 } }),
	C({ id = "bloomoth", name = "Bloomoth", islet = 2, rarity = 3, hp = 15, atk = 8, def = 4, spd = 9, shape = "moth", body = "pink", accent = "yellow", blurb = "Its wings smell of spring.", pn = "Pollen Dance", fx = { work = 0.4, luck = 0.05 } }),
	C({ id = "elderbark", name = "Elderbark", islet = 2, rarity = 4, hp = 26, atk = 9, def = 9, spd = 3, shape = "golem", body = "wood", accent = "leaf", blurb = "A tree that decided to walk.", pn = "Old Roots", fx = { work = 0.35, charm = 1, cost = -0.2 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "burrowby", name = "Burrowby", islet = 2, rarity = 1, hp = 17, atk = 5, def = 6, spd = 4, shape = "hedgehog", body = "wood", accent = "cream", blurb = "Curls up when you say hello.", pn = "Prickle Roll", fx = { work = 0.15, charm = 1 } }),
	C({ id = "puddlet", name = "Puddlet", islet = 2, rarity = 1, hp = 16, atk = 5, def = 4, spd = 6, shape = "duck", body = "yellow", accent = "orange", blurb = "Thinks a bee is its mum.", pn = "Follow Along", fx = { work = 0.09, hatch = 0.04, luck = 0.02 } }),
	C({ id = "fawnlet", name = "Fawnlet", islet = 2, rarity = 2, hp = 16, atk = 6, def = 4, spd = 8, shape = "deer", body = "wood", accent = "cream", blurb = "Lies still till you nearly step on it.", pn = "Long Grass", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "bumblet", name = "Bumblet", islet = 2, rarity = 2, hp = 14, atk = 6, def = 4, spd = 8, shape = "moth", body = "yellow", accent = "black", blurb = "Knows one tune. Buzzes it all day.", pn = "Busy Buzz", fx = { boost = 0.08 } }),
	C({ id = "thistlemane", name = "Thistlemane", islet = 2, rarity = 3, hp = 18, atk = 8, def = 5, spd = 8, shape = "cat", body = "gold", accent = "white", blurb = "Its mane blows off and grows back.", pn = "Puff Mane", fx = { boost = 0.12, luck = 0.05 } }),
	C({ id = "mossbuck", name = "Mossbuck", islet = 2, rarity = 4, hp = 24, atk = 9, def = 8, spd = 6, shape = "deer", body = "wood_dark", accent = "leaf", blurb = "Birds nest in its mossy antlers.", pn = "Green Crown", fx = { work = 0.35, charm = 1, cost = -0.15 } }),
	-- Mangroves (islet 6)
	C({ id = "murkle", name = "Murkle", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, shape = "frog", body = "leaf_dark", accent = "sand", blurb = "Sings to the mud at dusk.", pn = "Mud Bath", fx = { work = 0.1, cost = -0.2 } }),
	C({ id = "reedle", name = "Reedle", islet = 6, rarity = 1, hp = 17, atk = 7, def = 5, spd = 7, shape = "lizard", body = "shallow", accent = "wood_dark", blurb = "Gone before you spot it.", pn = "Reed Runner", fx = { work = 0.12, luck = 0.04 } }),
	C({ id = "bogsnail", name = "Bogsnail", islet = 6, rarity = 2, hp = 19, atk = 5, def = 8, spd = 3, shape = "snail", body = "rock_dark", accent = "green", blurb = "Plants sprout along its trail.", pn = "Fertile Trail", fx = { work = 0.15, hatch = 0.06, charm = 1 } }),
	C({ id = "mudmole", name = "Mudmole", islet = 6, rarity = 2, hp = 21, atk = 7, def = 7, spd = 4, shape = "mole", body = "wood_dark", accent = "sand", blurb = "Digs under roots for snacks.", pn = "Root Digger", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "wispwing", name = "Wispwing", islet = 6, rarity = 3, hp = 16, atk = 9, def = 4, spd = 10, shape = "moth", body = "screen_on", accent = "leaf_dark", blurb = "Guides lost walkers home.", pn = "Guiding Glow", fx = { boost = 0.12, luck = 0.04 } }),
	C({ id = "mirewyrm", name = "Mirewyrm", islet = 6, rarity = 4, hp = 30, atk = 10, def = 8, spd = 6, shape = "wyrm", body = "leaf_dark", accent = "yellow", blurb = "Older than the mangroves.", pn = "Swamp King", fx = { work = 0.3, cost = -0.2, sell = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "gillo", name = "Gillo", islet = 6, rarity = 1, hp = 18, atk = 6, def = 5, spd = 6, shape = "lizard", body = "pink", accent = "coral", blurb = "Smiles at nothing in particular.", pn = "Big Smile", fx = { work = 0.15, charmPct = 0.03 } }),
	C({ id = "slinkit", name = "Slinkit", islet = 6, rarity = 1, hp = 17, atk = 7, def = 4, spd = 8, shape = "otter", body = "wood_dark", accent = "cream", blurb = "Slips through roots in a blink.", pn = "Root Slip", fx = { work = 0.15, luck = 0.03 } }),
	C({ id = "dabbler", name = "Dabbler", islet = 6, rarity = 2, hp = 19, atk = 6, def = 6, spd = 6, shape = "duck", body = "leaf_dark", accent = "sand", blurb = "Eats upside down, for ages.", pn = "Bottoms Up", fx = { work = 0.25, cost = -0.12 } }),
	C({ id = "snapmoss", name = "Snapmoss", islet = 6, rarity = 2, hp = 22, atk = 8, def = 9, spd = 3, shape = "turtle", body = "rock_dark", accent = "leaf", blurb = "Lets moss grow on its shell.", pn = "Mossy Shell", fx = { work = 0.22, charmPct = 0.05 } }),
	C({ id = "stiltbeak", name = "Stiltbeak", islet = 6, rarity = 3, hp = 18, atk = 10, def = 5, spd = 9, shape = "bird", body = "steel", accent = "white", blurb = "Waits on one leg for hours.", pn = "Patient Strike", fx = { work = 0.3, luck = 0.05 } }),
	C({ id = "grinmire", name = "Grinmire", islet = 6, rarity = 4, hp = 30, atk = 11, def = 9, spd = 5, shape = "lizard", body = "leaf_dark", accent = "sand", blurb = "Very polite, for all those teeth.", pn = "Mud Smile", fx = { work = 0.35, sell = 0.25 } }),
	-- Volcanoes (islet 3)
	C({ id = "emberpup", name = "Emberpup", islet = 3, rarity = 1, hp = 20, atk = 9, def = 5, spd = 7, shape = "pup", body = "orange", accent = "yellow", blurb = "Good company on a cold night.", pn = "Warm Welcome", fx = { work = 0.075, hatch = 0.04, sell = 0.2 } }),
	C({ id = "magmole", name = "Magmole", islet = 3, rarity = 1, hp = 24, atk = 7, def = 8, spd = 3, shape = "mole", body = "black", accent = "orange", blurb = "Digs through rock like sand.", pn = "Hot Claws", fx = { work = 0.15, charm = 1 } }),
	C({ id = "scorchwing", name = "Scorchwing", islet = 3, rarity = 2, hp = 17, atk = 8, def = 4, spd = 10, shape = "bat", body = "purple", accent = "orange", blurb = "Roosts in warm volcano cracks.", pn = "Night Market", fx = { boost = 0.08, luck = 0.05 } }),
	C({ id = "cindertoad", name = "Cindertoad", islet = 3, rarity = 2, hp = 22, atk = 9, def = 6, spd = 5, shape = "frog", body = "rock_dark", accent = "orange", blurb = "Puffs smoke rings when content.", pn = "Ash Soil", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "basaltor", name = "Basaltor", islet = 3, rarity = 3, hp = 30, atk = 10, def = 11, spd = 3, shape = "golem", body = "black", accent = "orange", blurb = "Cooled lava, still warm inside.", pn = "Molten Core", fx = { work = 0.3, charmPct = 0.07 } }),
	C({ id = "pyredrake", name = "Pyredrake", islet = 3, rarity = 4, hp = 28, atk = 13, def = 7, spd = 9, shape = "drake", body = "berry_red", accent = "orange", blurb = "One sneeze lights every torch.", pn = "Fire Breath", fx = { work = 0.25, sell = 0.55 } }),
	C({ id = "pyrelord", name = "Pyrelord", islet = 3, rarity = 5, hp = 34, atk = 16, def = 9, spd = 10, shape = "drake", body = "gold", accent = "berry_red", blurb = "Wakes once a century, grumpy.", pn = "Eruption", fx = { work = 0.4, cost = -0.2, sell = 0.75 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "cinderkit", name = "Cinderkit", islet = 3, rarity = 1, hp = 19, atk = 9, def = 5, spd = 8, shape = "cat", body = "basalt", accent = "orange", blurb = "Sooty pawprints on everything.", pn = "Sooty Paws", fx = { work = 0.15, sell = 0.15 } }),
	C({ id = "emberquill", name = "Emberquill", islet = 3, rarity = 1, hp = 21, atk = 7, def = 8, spd = 4, shape = "hedgehog", body = "rock_dark", accent = "orange", blurb = "Bristles with sparks when cross.", pn = "Hot Quills", fx = { work = 0.15, charm = 1 } }),
	C({ id = "smoulderbug", name = "Smoulderbug", islet = 3, rarity = 2, hp = 22, atk = 8, def = 8, spd = 4, shape = "beetle", body = "black", accent = "orange", blurb = "Carries a hot coal for warmth.", pn = "Coal Carrier", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "obsidusk", name = "Obsidusk", islet = 3, rarity = 3, hp = 30, atk = 10, def = 10, spd = 3, shape = "elephant", body = "basalt", accent = "orange", blurb = "Careful with its glass tusks.", pn = "Glass Tusks", fx = { work = 0.3, charm = 1 } }),
	C({ id = "blazemane", name = "Blazemane", islet = 3, rarity = 4, hp = 27, atk = 13, def = 7, spd = 9, shape = "cat", body = "orange", accent = "berry_red", blurb = "A mane of fire, safe to pet.", pn = "Warm Mane", fx = { work = 0.25, sell = 0.5 } }),
	C({ id = "ashwing", name = "Ashwing", islet = 3, rarity = 5, hp = 32, atk = 15, def = 8, spd = 11, shape = "bird", body = "berry_red", accent = "gold", blurb = "Hatches again from its own ash.", pn = "Second Spring", fx = { work = 0.45, cost = -0.2, sell = 0.3 } }),
	-- Grottoes (islet 7)
	C({ id = "gemsnail", name = "Gemsnail", islet = 7, rarity = 1, hp = 20, atk = 7, def = 8, spd = 4, shape = "snail", body = "purple", accent = "screen_on", blurb = "Its shell is a geode.", pn = "Gem Shell", fx = { work = 0.18, charmPct = 0.03 } }),
	C({ id = "glowbat", name = "Glowbat", islet = 7, rarity = 1, hp = 18, atk = 8, def = 5, spd = 9, shape = "bat", body = "night", accent = "screen_on", blurb = "Lights up dark caves.", pn = "Echo Glow", fx = { work = 0.1, luck = 0.05 } }),
	C({ id = "quartzle", name = "Quartzle", islet = 7, rarity = 2, hp = 22, atk = 7, def = 9, spd = 4, shape = "hedgehog", body = "chalk", accent = "purple", blurb = "Hums when it's happy.", pn = "Crystal Hum", fx = { work = 0.08, charm = 1 } }),
	C({ id = "crystowl", name = "Crystowl", islet = 7, rarity = 3, hp = 21, atk = 10, def = 6, spd = 8, shape = "owl", body = "screen_on", accent = "purple", blurb = "Sees through walls, but won't peek.", pn = "Clear Sight", fx = { work = 0.2, luck = 0.12 } }),
	C({ id = "prismoth", name = "Prismoth", islet = 7, rarity = 4, hp = 20, atk = 12, def = 6, spd = 11, shape = "moth", body = "pink", accent = "screen_on", blurb = "Turns sunlight into little rainbows.", pn = "Rainbow Wings", fx = { work = 0.35, charmPct = 0.1, luck = 0.05, sell = 0.25 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "spored", name = "Spored", islet = 7, rarity = 1, hp = 19, atk = 7, def = 7, spd = 5, shape = "shroom", body = "purple", accent = "screen_on", blurb = "Brightens when you talk to it.", pn = "Spore Light", fx = { work = 0.15, charm = 1 } }),
	C({ id = "shardbug", name = "Shardbug", islet = 7, rarity = 1, hp = 20, atk = 7, def = 9, spd = 4, shape = "beetle", body = "slate", accent = "crystal", blurb = "Rings like a bell when knocked.", pn = "Ringing Shell", fx = { work = 0.15, luck = 0.03 } }),
	C({ id = "lumenfin", name = "Lumenfin", islet = 7, rarity = 2, hp = 20, atk = 8, def = 6, spd = 8, shape = "fish", body = "night", accent = "yellow", blurb = "Has a lamp on its head.", pn = "Little Lamp", fx = { work = 0.2, luck = 0.04 } }),
	C({ id = "amethare", name = "Amethare", islet = 7, rarity = 2, hp = 21, atk = 7, def = 7, spd = 8, shape = "bun", body = "snow", accent = "crystal", blurb = "Crystal ears that chime when it hops.", pn = "Chime Ears", fx = { work = 0.22, charmPct = 0.05 } }),
	C({ id = "opalback", name = "Opalback", islet = 7, rarity = 3, hp = 26, atk = 9, def = 11, spd = 4, shape = "armadillo", body = "cream", accent = "pink", blurb = "Rolled up, it's one big opal.", pn = "Opal Roll", fx = { work = 0.3, charmPct = 0.07, sell = 0.2 } }),
	C({ id = "prismhorn", name = "Prismhorn", islet = 7, rarity = 4, hp = 26, atk = 12, def = 8, spd = 10, shape = "deer", body = "white", accent = "crystal", blurb = "Throws colours on the cave walls.", pn = "Light Split", fx = { work = 0.35, luck = 0.06 } }),
	-- Snowfields (islet 4)
	C({ id = "snowpuff", name = "Snowpuff", islet = 4, rarity = 1, hp = 26, atk = 8, def = 7, spd = 4, shape = "yeti", body = "white", accent = "blue", blurb = "A snowball that learned to hug.", pn = "Big Hug", fx = { work = 0.1, charmPct = 0.03, cost = -0.2 } }),
	C({ id = "floe", name = "Floe", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 6, shape = "seal", body = "window", accent = "white", blurb = "Slides everywhere on its belly.", pn = "Belly Slide", fx = { work = 0.2, luck = 0.03 } }),
	C({ id = "frostling", name = "Frostling", islet = 4, rarity = 2, hp = 18, atk = 10, def = 5, spd = 9, shape = "sprite", body = "screen_on", accent = "white", blurb = "Grins, and the windows ice over.", pn = "Cold Snap", fx = { work = 0.15, sell = 0.3 } }),
	C({ id = "icetoad", name = "Icetoad", islet = 4, rarity = 2, hp = 25, atk = 8, def = 8, spd = 5, shape = "frog", body = "window", accent = "white", blurb = "Croaks little puffs of frost.", pn = "Frost Croak", fx = { work = 0.2, charm = 1 } }),
	C({ id = "glacior", name = "Glacior", islet = 4, rarity = 3, hp = 34, atk = 10, def = 12, spd = 3, shape = "golem", body = "window", accent = "white", blurb = "A glacier with arms.", pn = "Permafrost", fx = { work = 0.2, charmPct = 0.07, cost = -0.15 } }),
	C({ id = "frostdrake", name = "Frostdrake", islet = 4, rarity = 4, hp = 30, atk = 13, def = 8, spd = 9, shape = "drake", body = "blue", accent = "white", blurb = "Freezes the sea to walk on it.", pn = "Ice Breath", fx = { work = 0.35, sell = 0.45 } }),
	C({ id = "frostcrown", name = "Frostcrown", islet = 4, rarity = 5, hp = 40, atk = 14, def = 13, spd = 6, shape = "yeti", body = "gold", accent = "white", blurb = "Snow piles up wherever it stops.", pn = "Winter's Crown", fx = { work = 0.4, charmPct = 0.14, cost = -0.4 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "slidget", name = "Slidget", islet = 4, rarity = 1, hp = 24, atk = 7, def = 8, spd = 5, shape = "penguin", body = "slate", accent = "white", blurb = "Walks back up to slide again.", pn = "Tummy Slide", fx = { work = 0.15, luck = 0.03 } }),
	C({ id = "rimekit", name = "Rimekit", islet = 4, rarity = 1, hp = 22, atk = 8, def = 6, spd = 7, shape = "pup", body = "white", accent = "ice", blurb = "Turns white with the first snow.", pn = "Winter Coat", fx = { work = 0.15, cost = -0.1 } }),
	C({ id = "tuskle", name = "Tuskle", islet = 4, rarity = 2, hp = 28, atk = 8, def = 9, spd = 3, shape = "elephant", body = "wood", accent = "white", blurb = "Under its fur is more fur.", pn = "Thick Fur", fx = { work = 0.2, charm = 1 } }),
	C({ id = "peakhorn", name = "Peakhorn", islet = 4, rarity = 3, hp = 30, atk = 10, def = 9, spd = 7, shape = "deer", body = "white", accent = "steel", blurb = "Shows off on cliff edges.", pn = "Sure Foot", fx = { work = 0.3, luck = 0.04 } }),
	C({ id = "frostlynx", name = "Frostlynx", islet = 4, rarity = 4, hp = 28, atk = 12, def = 7, spd = 10, shape = "cat", body = "window", accent = "white", blurb = "Leaves no prints in the snow.", pn = "Light Step", fx = { work = 0.35, luck = 0.06 } }),
	C({ id = "glimmerfleece", name = "Glimmerfleece", islet = 4, rarity = 5, hp = 38, atk = 13, def = 12, spd = 6, shape = "ram", body = "white", accent = "screen_on", blurb = "Its wool glows on the longest nights.", pn = "Night Fleece", fx = { work = 0.4, luck = 0.15, cost = -0.15 } }),
	-- Bluffs (islet 8)
	C({ id = "cloudbun", name = "Cloudbun", islet = 8, rarity = 1, hp = 22, atk = 8, def = 6, spd = 8, shape = "bun", body = "white", accent = "window", blurb = "Floats a little when it sneezes.", pn = "Fluffy Rain", fx = { work = 0.2, cost = -0.1 } }),
	C({ id = "breezle", name = "Breezle", islet = 8, rarity = 1, hp = 20, atk = 9, def = 5, spd = 11, shape = "bird", body = "window", accent = "blue", blurb = "Rides the cliff winds all day.", pn = "Tailwind", fx = { luck = 0.06 } }),
	C({ id = "skyfox", name = "Skyfox", islet = 8, rarity = 2, hp = 23, atk = 10, def = 6, spd = 10, shape = "pup", body = "blue", accent = "white", blurb = "Chases clouds. Caught one once.", pn = "Cloud Chaser", fx = { work = 0.2, luck = 0.04 } }),
	C({ id = "stormowl", name = "Stormowl", islet = 8, rarity = 3, hp = 24, atk = 12, def = 7, spd = 9, shape = "owl", body = "night", accent = "yellow", blurb = "Its hoot rolls like thunder.", pn = "Thunder Hoot", fx = { work = 0.25, sell = 0.35 } }),
	C({ id = "thunderdrake", name = "Thunderdrake", islet = 8, rarity = 4, hp = 31, atk = 15, def = 8, spd = 10, shape = "drake", body = "purple", accent = "yellow", blurb = "Snacks on lightning.", pn = "Charged Scales", fx = { work = 0.3, luck = 0.05, sell = 0.45 } }),
	C({ id = "aurorawing", name = "Aurorawing", islet = 8, rarity = 5, hp = 32, atk = 15, def = 10, spd = 13, shape = "bat", body = "screen_on", accent = "pink", blurb = "Paints the sky at night.", pn = "Northern Lights", fx = { boost = 0.22, luck = 0.24 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "craglet", name = "Craglet", islet = 8, rarity = 1, hp = 21, atk = 8, def = 6, spd = 8, shape = "deer", body = "cream", accent = "rock", blurb = "Climbs anything, including you.", pn = "Climber", fx = { work = 0.15, luck = 0.03 } }),
	C({ id = "puffbill", name = "Puffbill", islet = 8, rarity = 1, hp = 20, atk = 8, def = 5, spd = 9, shape = "penguin", body = "black", accent = "orange", blurb = "Drops every fish it catches.", pn = "Full Beak", fx = { work = 0.18, sell = 0.15 } }),
	C({ id = "windhare", name = "Windhare", islet = 8, rarity = 2, hp = 22, atk = 9, def = 5, spd = 11, shape = "bun", body = "sand", accent = "white", blurb = "Races the wind for fun.", pn = "Headwind", fx = { work = 0.2, luck = 0.04 } }),
	C({ id = "sweepwing", name = "Sweepwing", islet = 8, rarity = 3, hp = 23, atk = 11, def = 6, spd = 11, shape = "bird", body = "wood", accent = "cream", blurb = "Lands about once a year.", pn = "Sky Nap", fx = { work = 0.25, sell = 0.25 } }),
	C({ id = "galeram", name = "Galeram", islet = 8, rarity = 4, hp = 32, atk = 13, def = 10, spd = 7, shape = "ram", body = "white", accent = "rock", blurb = "Its horns curl like the wind.", pn = "Gale Horns", fx = { work = 0.35, cost = -0.2 } }),
	C({ id = "stormgriff", name = "Stormgriff", islet = 8, rarity = 5, hp = 34, atk = 16, def = 10, spd = 12, shape = "griffin", body = "gold", accent = "white", blurb = "Rides in on storms, then brags.", pn = "Storm Rider", fx = { boost = 0.22, luck = 0.1, sell = 0.3 } }),
	-- Reefs (islet 5)
	C({ id = "coralcrab", name = "Coralcrab", islet = 5, rarity = 1, hp = 24, atk = 10, def = 8, spd = 6, shape = "crab", body = "pink", accent = "orange", blurb = "Grew its own coral crown.", pn = "Coral Crown", fx = { work = 0.18, charmPct = 0.03 } }),
	C({ id = "lumajelly", name = "Lumajelly", islet = 5, rarity = 1, hp = 22, atk = 9, def = 6, spd = 7, shape = "jelly", body = "pink", accent = "purple", blurb = "Drifts by like a pink lantern.", pn = "Soft Glow", fx = { work = 0.2, cost = -0.1 } }),
	C({ id = "pearlback", name = "Pearlback", islet = 5, rarity = 2, hp = 30, atk = 9, def = 11, spd = 4, shape = "turtle", body = "white", accent = "pink", blurb = "Grows a new pearl each year.", pn = "Pearl Grower", fx = { work = 0.3, charmPct = 0.05 } }),
	C({ id = "novafox", name = "Novafox", islet = 5, rarity = 3, hp = 24, atk = 12, def = 6, spd = 10, shape = "pup", body = "gold", accent = "purple", blurb = "Trails stars from its tail.", pn = "Starry Tail", fx = { work = 0.25, luck = 0.06 } }),
	C({ id = "tidewyrm", name = "Tidewyrm", islet = 5, rarity = 4, hp = 34, atk = 12, def = 9, spd = 7, shape = "wyrm", body = "blue", accent = "screen_on", blurb = "The deep's oldest swimmer.", pn = "Tidal Pull", fx = { work = 0.2, hatch = 0.1, cost = -0.2 } }),
	C({ id = "abyssmaw", name = "Abyssmaw", islet = 5, rarity = 5, hp = 42, atk = 17, def = 11, spd = 8, shape = "wyrm", body = "night", accent = "purple", blurb = "Sleeps in the deepest trench.", pn = "Deep Hunger", fx = { work = 0.5, cost = -0.3, sell = 0.65 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "stripefin", name = "Stripefin", islet = 5, rarity = 1, hp = 22, atk = 9, def = 7, spd = 7, shape = "fish", body = "orange", accent = "white", blurb = "Lives in an anemone, rent free.", pn = "Free Room", fx = { work = 0.18, cost = -0.1 } }),
	C({ id = "squidge", name = "Squidge", islet = 5, rarity = 1, hp = 23, atk = 9, def = 6, spd = 7, shape = "octo", body = "pink", accent = "purple", blurb = "Squirts ink when it laughs.", pn = "Ink Squirt", fx = { work = 0.18, charm = 1 } }),
	C({ id = "reefray", name = "Reefray", islet = 5, rarity = 2, hp = 28, atk = 9, def = 9, spd = 6, shape = "ray", body = "blue", accent = "white", blurb = "Flaps slowly over the coral.", pn = "Slow Flap", fx = { work = 0.25, luck = 0.03 } }),
	C({ id = "coralcurl", name = "Coralcurl", islet = 5, rarity = 3, hp = 25, atk = 11, def = 8, spd = 8, shape = "seahorse", body = "pink", accent = "orange", blurb = "Holds anything with its tail.", pn = "Curly Grip", fx = { work = 0.3, sell = 0.2 } }),
	C({ id = "tidegrip", name = "Tidegrip", islet = 5, rarity = 4, hp = 32, atk = 12, def = 9, spd = 8, shape = "octo", body = "purple", accent = "pink", blurb = "Tidies with all eight arms.", pn = "Eight Hands", fx = { work = 0.1, boost = 0.16 } }),
	C({ id = "elderreef", name = "Elderreef", islet = 5, rarity = 5, hp = 46, atk = 13, def = 15, spd = 4, shape = "turtle", body = "green", accent = "pink", blurb = "A whole reef lives on its shell.", pn = "Walking Reef", fx = { work = 0.5, charmPct = 0.14, cost = -0.25 } }),
	-- Ruins (islet 9)
	C({ id = "relicrab", name = "Relicrab", islet = 9, rarity = 1, hp = 26, atk = 11, def = 9, spd = 6, shape = "crab", body = "sand_dark", accent = "gold", blurb = "Hoards old coins.", pn = "Coin Hoard", fx = { work = 0.25 } }),
	C({ id = "rubblet", name = "Rubblet", islet = 9, rarity = 1, hp = 28, atk = 10, def = 10, spd = 4, shape = "crab", body = "rock", accent = "sand", blurb = "A stone from a fallen wall.", pn = "Old Mortar", fx = { work = 0.12, charm = 1 } }),
	C({ id = "glyphowl", name = "Glyphowl", islet = 9, rarity = 2, hp = 25, atk = 11, def = 8, spd = 8, shape = "owl", body = "sand", accent = "gold", blurb = "Reads the old carvings aloud.", pn = "Ancient Lore", fx = { work = 0.15, luck = 0.15 } }),
	C({ id = "sentinel", name = "Sentinel", islet = 9, rarity = 3, hp = 38, atk = 12, def = 14, spd = 3, shape = "golem", body = "rock", accent = "gold", blurb = "Guards a door everyone forgot.", pn = "Stone Guard", fx = { work = 0.1, boost = 0.12, charm = 2, cost = -0.2 } }),
	C({ id = "runemoth", name = "Runemoth", islet = 9, rarity = 4, hp = 27, atk = 14, def = 8, spd = 12, shape = "moth", body = "gold", accent = "purple", blurb = "Old spells cover its wings.", pn = "Rune Wings", fx = { boost = 0.16, luck = 0.16 } }),
	C({ id = "solwyrm", name = "Solwyrm", islet = 9, rarity = 5, hp = 44, atk = 17, def = 12, spd = 9, shape = "wyrm", body = "gold", accent = "white", blurb = "The ruins were built for it.", pn = "Sun Blessing", fx = { work = 0.25, boost = 0.22, cost = -0.3, sell = 0.45 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "tombcat", name = "Tombcat", islet = 9, rarity = 1, hp = 25, atk = 10, def = 8, spd = 7, shape = "cat", body = "sand", accent = "gold", blurb = "Lords it over the old steps.", pn = "Old Steps", fx = { work = 0.2, luck = 0.03 } }),
	C({ id = "scarabit", name = "Scarabit", islet = 9, rarity = 1, hp = 26, atk = 9, def = 10, spd = 5, shape = "beetle", body = "blue", accent = "gold", blurb = "Rolls dust balls up the stairs.", pn = "Dust Roller", fx = { work = 0.18, cost = -0.1 } }),
	C({ id = "vinegeck", name = "Vinegeck", islet = 9, rarity = 2, hp = 24, atk = 10, def = 8, spd = 8, shape = "lizard", body = "leaf", accent = "gold", blurb = "Matches whatever wall it sits on.", pn = "Wall Colour", fx = { work = 0.22, luck = 0.05 } }),
	C({ id = "ruinape", name = "Ruinape", islet = 9, rarity = 3, hp = 28, atk = 12, def = 9, spd = 9, shape = "monkey", body = "rock", accent = "white", blurb = "Swings by and steals your hat.", pn = "Hat Thief", fx = { work = 0.3, sell = 0.2 } }),
	C({ id = "gildmane", name = "Gildmane", islet = 9, rarity = 4, hp = 32, atk = 14, def = 10, spd = 8, shape = "cat", body = "gold", accent = "sand", blurb = "Purrs like a temple bell.", pn = "Bell Purr", fx = { work = 0.35, charmPct = 0.1, sell = 0.3 } }),
	C({ id = "templeback", name = "Templeback", islet = 9, rarity = 5, hp = 48, atk = 14, def = 16, spd = 3, shape = "turtle", body = "sand_dark", accent = "gold", blurb = "Carries a temple and doesn't mind.", pn = "Holy Shell", fx = { boost = 0.22, charm = 1, cost = -0.25 } }),
	-- Moonwoods (islet 10, tier 11: the first mythic one)
	C({ id = "duskbun", name = "Duskbun", islet = 10, rarity = 1, hp = 30, atk = 11, def = 9, spd = 8, shape = "bun", body = "slate", accent = "crystal", blurb = "Gardens all night.", pn = "Night Shift", fx = { work = 0.28 } }),
	C({ id = "hushpup", name = "Hushpup", islet = 10, rarity = 2, hp = 30, atk = 13, def = 8, spd = 12, shape = "pup", body = "black", accent = "crystal", blurb = "Never sets off the shop bell.", pn = "Soft Paws", fx = { work = 0.125, hatch = 0.06, sell = 0.25 } }),
	C({ id = "lunowl", name = "Lunowl", islet = 10, rarity = 3, hp = 31, atk = 13, def = 10, spd = 10, shape = "owl", body = "white", accent = "crystal", blurb = "Counts stars and always loses count.", pn = "Night Watch", fx = { work = 0.15, hatch = 0.08, luck = 0.05 } }),
	C({ id = "wispkin", name = "Wispkin", islet = 10, rarity = 4, hp = 30, atk = 16, def = 9, spd = 14, shape = "sprite", body = "crystal", accent = "white", blurb = "Chops wood when no one's looking.", pn = "Hidden Hands", fx = { work = 0.12, boost = 0.16 } }),
	C({ id = "silverbark", name = "Silverbark", islet = 10, rarity = 5, hp = 48, atk = 16, def = 16, spd = 4, shape = "golem", body = "steel", accent = "crystal", blurb = "Takes slow walks by moonlight.", pn = "Moonsap", fx = { work = 0.65, cost = -0.3 } }),
	C({ id = "moonveil", name = "Moonveil", islet = 10, rarity = 6, hp = 40, atk = 19, def = 12, spd = 15, shape = "bat", body = "night", accent = "cherry", blurb = "Borrows the moon overnight.", pn = "Eclipse Wings", fx = { work = 0.5, charmPct = 0.2, luck = 0.18, sell = 0.6 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "dimwing", name = "Dimwing", islet = 10, rarity = 1, hp = 28, atk = 12, def = 8, spd = 10, shape = "moth", body = "slate", accent = "crystal", blurb = "Comes out when the lamps go on.", pn = "Lamp Moth", fx = { work = 0.22, luck = 0.03 } }),
	C({ id = "moonfawn", name = "Moonfawn", islet = 10, rarity = 2, hp = 30, atk = 12, def = 9, spd = 11, shape = "deer", body = "white", accent = "crystal", blurb = "Its spots glow like little moons.", pn = "Moon Spots", fx = { work = 0.31 } }),
	C({ id = "duskbear", name = "Duskbear", islet = 10, rarity = 3, hp = 38, atk = 13, def = 12, spd = 6, shape = "bear", body = "night", accent = "crystal", blurb = "Dreams of honey all winter.", pn = "Long Dream", fx = { work = 0.15, hatch = 0.08, cost = -0.15 } }),
	C({ id = "moonshroom", name = "Moonshroom", islet = 10, rarity = 4, hp = 34, atk = 14, def = 11, spd = 7, shape = "shroom", body = "crystal", accent = "white", blurb = "Grows a new cap every full moon.", pn = "Full Moon Cap", fx = { work = 0.4, luck = 0.08 } }),
	C({ id = "silverhoof", name = "Silverhoof", islet = 10, rarity = 5, hp = 44, atk = 16, def = 13, spd = 13, shape = "deer", body = "white", accent = "steel", blurb = "Flowers spring back up behind it.", pn = "Soft Hooves", fx = { work = 0.45, luck = 0.12, cost = -0.2 } }),
	C({ id = "moonhowl", name = "Moonhowl", islet = 10, rarity = 6, hp = 42, atk = 19, def = 12, spd = 15, shape = "pup", body = "night", accent = "crystal", blurb = "Howls the wood quiet at moonrise.", pn = "Moon Howl", fx = { work = 0.475, hatch = 0.17, luck = 0.15 } }),
	-- Cloudtops (islet 11, tier 14: the first celestial one)
	C({ id = "puffling", name = "Puffling", islet = 11, rarity = 1, hp = 34, atk = 12, def = 10, spd = 8, shape = "ram", body = "white", accent = "window", blurb = "A stray scrap of cloud.", pn = "Light Rain", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "cirrup", name = "Cirrup", islet = 11, rarity = 2, hp = 32, atk = 13, def = 9, spd = 13, shape = "bird", body = "window", accent = "white", blurb = "Sings tomorrow's weather.", pn = "Fair Forecast", fx = { boost = 0.08, luck = 0.04 } }),
	C({ id = "cloudjelly", name = "Cloudjelly", islet = 11, rarity = 3, hp = 34, atk = 14, def = 10, spd = 9, shape = "jelly", body = "white", accent = "pink", blurb = "Waters the fields as it drifts.", pn = "Drizzle Drift", fx = { work = 0.43 } }),
	C({ id = "billowbear", name = "Billowbear", islet = 11, rarity = 4, hp = 46, atk = 17, def = 14, spd = 6, shape = "bear", body = "white", accent = "slate", blurb = "Hugs storms until they calm down.", pn = "Storm Hug", fx = { work = 0.45, cost = -0.15 } }),
	C({ id = "skyshell", name = "Skyshell", islet = 11, rarity = 6, hp = 54, atk = 15, def = 18, spd = 5, shape = "turtle", body = "window", accent = "white", blurb = "Farms a little cloud on its back.", pn = "Floating Field", fx = { work = 0.525, hatch = 0.17, luck = 0.08 } }),
	C({ id = "cloudwhale", name = "Cloudwhale", islet = 11, rarity = 7, hp = 60, atk = 18, def = 16, spd = 8, shape = "seal", body = "ice", accent = "white", blurb = "The clouds hum along with its song.", pn = "Sky Song", fx = { work = 0.6, charmPct = 0.28, luck = 0.35 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "cloudpip", name = "Cloudpip", islet = 11, rarity = 1, hp = 32, atk = 12, def = 9, spd = 12, shape = "bird", body = "white", accent = "pink", blurb = "Too light to land.", pn = "Featherlight", fx = { work = 0.25, luck = 0.03 } }),
	C({ id = "gustotter", name = "Gustotter", islet = 11, rarity = 2, hp = 34, atk = 13, def = 10, spd = 12, shape = "otter", body = "window", accent = "white", blurb = "Swims through clouds like water.", pn = "Cloud Swim", fx = { work = 0.34 } }),
	C({ id = "raindeer", name = "Raindeer", islet = 11, rarity = 3, hp = 36, atk = 14, def = 11, spd = 10, shape = "deer", body = "slate", accent = "white", blurb = "Brings its own drizzle.", pn = "Light Drizzle", fx = { work = 0.43 } }),
	C({ id = "stormphant", name = "Stormphant", islet = 11, rarity = 4, hp = 48, atk = 16, def = 15, spd = 6, shape = "elephant", body = "slate", accent = "yellow", blurb = "Sprays rain from its trunk.", pn = "Rain Trunk", fx = { work = 0.4, luck = 0.05, cost = -0.15 } }),
	C({ id = "cloudgriff", name = "Cloudgriff", islet = 11, rarity = 6, hp = 50, atk = 18, def = 15, spd = 14, shape = "griffin", body = "white", accent = "gold", blurb = "Nests on the highest cloud.", pn = "High Nest", fx = { work = 0.75, luck = 0.1 } }),
	C({ id = "skyherald", name = "Skyherald", islet = 11, rarity = 7, hp = 48, atk = 20, def = 14, spd = 17, shape = "bird", body = "window", accent = "gold", blurb = "Never once missed a sunrise.", pn = "Dawn Song", fx = { work = 0.2, boost = 0.4, luck = 0.3 } }),
	-- Starfalls (islet 12, tier 17)
	C({ id = "glimmite", name = "Glimmite", islet = 12, rarity = 1, hp = 36, atk = 14, def = 12, spd = 7, shape = "crab", body = "slate", accent = "screen_on", blurb = "Picks star bits from the sand.", pn = "Star Picker", fx = { work = 0.25, sell = 0.2 } }),
	C({ id = "cometail", name = "Cometail", islet = 12, rarity = 3, hp = 34, atk = 16, def = 10, spd = 15, shape = "lizard", body = "blue", accent = "yellow", blurb = "Runs faster than its own glow.", pn = "Bright Trail", fx = { work = 0.35, luck = 0.05 } }),
	C({ id = "cratermole", name = "Cratermole", islet = 12, rarity = 5, hp = 44, atk = 19, def = 14, spd = 8, shape = "mole", body = "basalt", accent = "screen_on", blurb = "Always digging for one more star.", pn = "Deep Dig", fx = { work = 0.65, sell = 0.5 } }),
	C({ id = "nebulynx", name = "Nebulynx", islet = 12, rarity = 6, hp = 42, atk = 20, def = 12, spd = 16, shape = "cat", body = "purple", accent = "screen_on", blurb = "Knows every galaxy in its fur.", pn = "Pocket Galaxy", fx = { work = 0.55, luck = 0.2, sell = 0.7 } }),
	C({ id = "starweaver", name = "Starweaver", islet = 12, rarity = 7, hp = 44, atk = 21, def = 13, spd = 17, shape = "moth", body = "night", accent = "crystal", blurb = "Spins stars from moonlight.", pn = "Star Loom", fx = { work = 0.35, boost = 0.4, luck = 0.12 } }),
	C({ id = "novawyrm", name = "Novawyrm", islet = 12, rarity = 7, hp = 62, atk = 22, def = 16, spd = 10, shape = "wyrm", body = "night", accent = "gold", blurb = "Each yawn lights a new star.", pn = "First Light", fx = { work = 0.6, luck = 0.22, cost = -0.4 } }),
	-- (the new ones of 2026-11-15, "add alot more extra ones with more variation to them")
	C({ id = "twinkbun", name = "Twinkbun", islet = 12, rarity = 1, hp = 34, atk = 13, def = 11, spd = 10, shape = "bun", body = "night", accent = "yellow", blurb = "Twinkles whenever it twitches its nose.", pn = "Twinkle Nose", fx = { work = 0.25, cost = -0.1 } }),
	C({ id = "craterbug", name = "Craterbug", islet = 12, rarity = 1, hp = 36, atk = 13, def = 13, spd = 6, shape = "beetle", body = "basalt", accent = "screen_on", blurb = "Digs a crater bed each night.", pn = "Little Crater", fx = { work = 0.25, sell = 0.2 } }),
	C({ id = "starfin", name = "Starfin", islet = 12, rarity = 3, hp = 34, atk = 16, def = 10, spd = 14, shape = "fish", body = "night", accent = "screen_on", blurb = "Still thinks it's in space.", pn = "Loop Swim", fx = { work = 0.35, luck = 0.05 } }),
	C({ id = "starshell", name = "Starshell", islet = 12, rarity = 5, hp = 52, atk = 17, def = 17, spd = 5, shape = "turtle", body = "night", accent = "yellow", blurb = "Its stars turn while it sleeps.", pn = "Sky Shell", fx = { work = 0.65, sell = 0.5 } }),
	C({ id = "cosmofleece", name = "Cosmofleece", islet = 12, rarity = 6, hp = 46, atk = 19, def = 14, spd = 12, shape = "ram", body = "purple", accent = "screen_on", blurb = "Too starry to shear.", pn = "Star Fleece", fx = { work = 0.55, luck = 0.2, sell = 0.7 } }),
	C({ id = "starhart", name = "Starhart", islet = 12, rarity = 7, hp = 50, atk = 21, def = 15, spd = 16, shape = "deer", body = "white", accent = "crystal", blurb = "Holds up the night sky, gently.", pn = "Sky Antlers", fx = { work = 0.6, luck = 0.22, cost = -0.4 } }),
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
-- to each of them"). Since the request of 2026-11-16, "Make all of their eyes small beads instead", every driftling
-- has small glossy bead eyes; its iris colour still tints the ring of light low in each bead.
--   id = { eye style, iris (palette key or false), body texture, accent texture or nil }
-- stylua: ignore start
local LOOKS: { [string]: { any } } = {
	pebblit = { "bead", false, "stone" },      quartzle = { "bead", "purple", "crystal", "crystal" }, rubblet = { "bead", "sand", "brick" },
	clawdle = { "bead", "orange", "chitin" },   coralcrab = { "bead", "orange", "chitin" },    relicrab = { "bead", "gold", "chitin" },
	gullfin = { "bead", "blue", "feather" },      breezle = { "bead", "blue", "feather" },
	conchy = { "bead", "pink", "skin", "shell" }, bogsnail = { "bead", "green", "skin", "shell" }, gemsnail = { "bead", "screen_on", "skin", "crystal" },
	shellback = { "bead", "sand", "scale", "shell" }, pearlback = { "bead", "pink", "scale", "shell" },
	sunsprite = { "bead", "yellow", "velvet" },   frostling = { "bead", "blue", "ice" },
	mossbun = { "bead", "leaf_dark", "fur" },  cloudbun = { "bead", "window", "fluff" },
	frondle = { "bead", "yellow", "scale" },      reedle = { "bead", false, "scale" },
	twiggle = { "bead", false, "bark" },        crystowl = { "bead", "purple", "feather" },   stormowl = { "bead", "yellow", "feather" }, glyphowl = { "bead", "gold", "feather" },
	hopsprout = { "bead", "gold", "skin" },      murkle = { "bead", "sand", "skin" },             cindertoad = { "bead", false, "ember" }, icetoad = { "bead", "blue", "ice" },
	bloomoth = { "bead", "pink", "velvet" },  wispwing = { "bead", "yellow", "velvet" },      prismoth = { "bead", "pink", "velvet" }, runemoth = { "bead", "purple", "velvet" },
	elderbark = { "bead", "leaf", "bark" },     basaltor = { "bead", "orange", "ember" },        glacior = { "bead", false, "ice" },       sentinel = { "bead", "gold", "stone" },
	mudmole = { "bead", false, "velvet" },         magmole = { "bead", "orange", "ember" },
	emberpup = { "bead", "yellow", "fur" },    skyfox = { "bead", "blue", "fur" },             novafox = { "bead", "purple", "fur" },
	scorchwing = { "bead", "orange", "fur" },   glowbat = { "bead", "screen_on", "fur" },        aurorawing = { "bead", "pink", "fur" },
	snowpuff = { "bead", false, "fluff" },       frostcrown = { "bead", "blue", "fluff" },
	floe = { "bead", false, "skin" },
	lumajelly = { "bead", "purple", "jelly" },
	pyredrake = { "bead", "orange", "scale" },    pyrelord = { "bead", "berry_red", "scale" },   frostdrake = { "bead", "white", "scale" }, thunderdrake = { "bead", "yellow", "scale" },
	mirewyrm = { "bead", "yellow", "scale" },   tidewyrm = { "bead", "screen_on", "scale" },   abyssmaw = { "bead", "purple", "scale" }, solwyrm = { "bead", "gold", "scale" },
	-- (the kinds of the tiers past the capital, 2026-11-14)
	duskbun = { "bead", "crystal", "fluff" },   hushpup = { "bead", "cherry", "fur" },         lunowl = { "bead", "yellow", "feather" },
	wispkin = { "bead", "screen_on", "velvet" },  silverbark = { "bead", "crystal", "bark", "crystal" }, moonveil = { "bead", "cherry", "velvet" },
	puffling = { "bead", false, "fluff" },       cirrup = { "bead", "blue", "feather" },         cloudjelly = { "bead", "pink", "jelly" },
	billowbear = { "bead", "slate", "fluff" },   skyshell = { "bead", "screen_on", "scale", "shell" }, cloudwhale = { "bead", "yellow", "skin" },
	glimmite = { "bead", false, "chitin" },        cometail = { "bead", "yellow", "scale" },        cratermole = { "bead", "screen_on", "stone" },
	nebulynx = { "bead", "screen_on", "fur" },     starweaver = { "bead", "yellow", "velvet" },     novawyrm = { "bead", "gold", "scale" },
	-- (the new ones of 2026-11-15)
	sandkit = { "bead", false, "fur" },
	puffpod = { "bead", "orange", "scale" },
	kelpup = { "bead", "wood_dark", "fur" },
	tidepip = { "bead", false, "feather" },
	kelphorse = { "bead", "pink", "scale" },
	duneray = { "bead", "blue", "skin" },
	burrowby = { "bead", false, "fur" },
	puddlet = { "bead", false, "feather" },
	fawnlet = { "bead", "wood_dark", "fur" },
	bumblet = { "bead", "yellow", "fluff" },
	thistlemane = { "bead", false, "fur", "fluff" },
	mossbuck = { "bead", "leaf", "fur", "bark" },
	cinderkit = { "bead", "orange", "fur" },
	emberquill = { "bead", "orange", "fur", "ember" },
	smoulderbug = { "bead", "orange", "chitin", "ember" },
	obsidusk = { "bead", "orange", "stone" },
	blazemane = { "bead", "berry_red", "fur", "ember" },
	ashwing = { "bead", "gold", "feather", "ember" },
	slidget = { "bead", "blue", "feather" },
	rimekit = { "bead", "blue", "fluff" },
	tuskle = { "bead", "wood_dark", "fluff" },
	peakhorn = { "bead", "gold", "fluff" },
	frostlynx = { "bead", "blue", "fluff" },
	glimmerfleece = { "bead", "screen_on", "fluff" },
	stripefin = { "bead", "orange", "scale" },
	squidge = { "bead", false, "skin" },
	reefray = { "bead", false, "skin" },
	coralcurl = { "bead", "orange", "scale" },
	tidegrip = { "bead", "pink", "skin" },
	elderreef = { "bead", false, "scale", "crystal" },
	gillo = { "bead", false, "skin" },
	slinkit = { "bead", false, "fur" },
	dabbler = { "bead", false, "feather" },
	snapmoss = { "bead", "leaf", "scale", "bark" },
	stiltbeak = { "bead", "yellow", "feather" },
	grinmire = { "bead", "yellow", "scale" },
	spored = { "bead", false, "velvet" },
	shardbug = { "bead", "crystal", "chitin", "crystal" },
	lumenfin = { "bead", "yellow", "scale" },
	amethare = { "bead", "crystal", "fluff", "crystal" },
	opalback = { "bead", "pink", "skin", "crystal" },
	prismhorn = { "bead", "crystal", "fur", "crystal" },
	craglet = { "bead", false, "fluff" },
	puffbill = { "bead", "orange", "feather" },
	windhare = { "bead", "wood_dark", "fur" },
	sweepwing = { "bead", "gold", "feather" },
	galeram = { "bead", "gold", "fluff" },
	stormgriff = { "bead", "gold", "feather", "fur" },
	tombcat = { "bead", "gold", "fur" },
	scarabit = { "bead", false, "chitin" },
	vinegeck = { "bead", "gold", "scale" },
	ruinape = { "bead", "gold", "fur" },
	gildmane = { "bead", "gold", "fur", "fluff" },
	templeback = { "bead", "gold", "scale", "brick" },
	dimwing = { "bead", "crystal", "velvet" },
	moonfawn = { "bead", "crystal", "fur" },
	duskbear = { "bead", "crystal", "fur" },
	moonshroom = { "bead", "white", "velvet" },
	silverhoof = { "bead", "steel", "fur" },
	moonhowl = { "bead", "crystal", "fur" },
	cloudpip = { "bead", false, "fluff" },
	gustotter = { "bead", false, "fluff" },
	raindeer = { "bead", "blue", "fur" },
	stormphant = { "bead", "yellow", "skin" },
	cloudgriff = { "bead", "gold", "feather", "fur" },
	skyherald = { "bead", "gold", "feather" },
	twinkbun = { "bead", "yellow", "fluff" },
	craterbug = { "bead", "screen_on", "chitin", "crystal" },
	starfin = { "bead", "screen_on", "scale" },
	starshell = { "bead", "yellow", "scale", "shell" },
	cosmofleece = { "bead", "screen_on", "fluff" },
	starhart = { "bead", "crystal", "fur", "crystal" },
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
