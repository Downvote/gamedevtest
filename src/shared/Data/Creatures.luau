--!strict
-- The driftlings (GAME_DESIGN 6): the creatures of the islets round the player's island, all our own. Pure. Each
-- lives on one islet (Data/Islets), fights with its level-1 stats grown by Logic/Battle, has a skill it uses every
-- few actions, a knack (the island buildings it helps at), and a trust (how readily a treat befriends it).
--   skill: "bash" (a big hit) | "quick" (two hits) | "zap" (hits every foe) | "heal" (mends the most hurt ally) |
--          "shell" (the side takes less damage for two rounds)
--   knack: "farm" | "fish" | "wood" | "shop" (Data/Buildings' knack)
--   shape: its 3D model (Models/MicroModels "drift_<shape>"), body / accent: its palette colours
export type CreatureDef = {
	id: string,
	name: string,
	islet: number,
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
}

-- stylua: ignore start
local LIST: { CreatureDef } = {
	-- Pebble Beach
	{ id = "pebblit", name = "Pebblit", islet = 1, hp = 16, atk = 5, def = 6, spd = 3, skill = "shell", knack = "wood", trust = 0.6, shape = "blob", body = "steel", accent = "steel_dark", blurb = "A pebble that rolled off and kept rolling." },
	{ id = "clawdle", name = "Clawdle", islet = 1, hp = 13, atk = 7, def = 4, spd = 5, skill = "bash", knack = "fish", trust = 0.5, shape = "crab", body = "berry_red", accent = "orange", blurb = "Snaps first, makes friends later." },
	{ id = "gullfin", name = "Gullfin", islet = 1, hp = 12, atk = 5, def = 3, spd = 8, skill = "quick", knack = "fish", trust = 0.45, shape = "bird", body = "white", accent = "blue", blurb = "Half gull, half fish, all appetite." },
	-- Mossgrove
	{ id = "mossbun", name = "Mossbun", islet = 2, hp = 18, atk = 5, def = 4, spd = 7, skill = "heal", knack = "farm", trust = 0.5, shape = "bun", body = "green", accent = "leaf_dark", blurb = "Its ears are soft moss." },
	{ id = "frondle", name = "Frondle", islet = 2, hp = 16, atk = 8, def = 4, spd = 6, skill = "bash", knack = "farm", trust = 0.45, shape = "lizard", body = "leaf", accent = "yellow", blurb = "Hides in plain leaves." },
	{ id = "twiggle", name = "Twiggle", islet = 2, hp = 15, atk = 6, def = 5, spd = 6, skill = "zap", knack = "wood", trust = 0.4, shape = "owl", body = "wood", accent = "wood_dark", blurb = "An owl of sticks and opinions." },
	-- Cinder Rock
	{ id = "emberpup", name = "Emberpup", islet = 3, hp = 20, atk = 9, def = 5, spd = 7, skill = "bash", knack = "shop", trust = 0.4, shape = "pup", body = "orange", accent = "yellow", blurb = "Warm to the touch, warmer to friends." },
	{ id = "magmole", name = "Magmole", islet = 3, hp = 24, atk = 7, def = 8, spd = 3, skill = "shell", knack = "wood", trust = 0.4, shape = "mole", body = "black", accent = "orange", blurb = "Digs through rock like sand." },
	{ id = "scorchwing", name = "Scorchwing", islet = 3, hp = 17, atk = 8, def = 4, spd = 10, skill = "quick", knack = "shop", trust = 0.35, shape = "bat", body = "purple", accent = "orange", blurb = "Sleeps in the volcano's warm cracks." },
	-- Frostcap
	{ id = "snowpuff", name = "Snowpuff", islet = 4, hp = 26, atk = 8, def = 7, spd = 4, skill = "heal", knack = "farm", trust = 0.35, shape = "yeti", body = "white", accent = "blue", blurb = "A snowball that learned to hug." },
	{ id = "floe", name = "Floe", islet = 4, hp = 24, atk = 7, def = 8, spd = 6, skill = "shell", knack = "fish", trust = 0.35, shape = "seal", body = "window", accent = "white", blurb = "Slides everywhere on its belly." },
	{ id = "frostling", name = "Frostling", islet = 4, hp = 18, atk = 10, def = 5, spd = 9, skill = "zap", knack = "shop", trust = 0.3, shape = "sprite", body = "screen_on", accent = "white", blurb = "A spark of winter with a grin." },
	-- Coral Deep
	{ id = "lumajelly", name = "Lumajelly", islet = 5, hp = 22, atk = 9, def = 6, spd = 7, skill = "heal", knack = "shop", trust = 0.3, shape = "jelly", body = "pink", accent = "purple", blurb = "Glows softly when it is happy." },
	{ id = "novafox", name = "Novafox", islet = 5, hp = 24, atk = 12, def = 6, spd = 10, skill = "quick", knack = "wood", trust = 0.25, shape = "pup", body = "gold", accent = "purple", blurb = "Its tail leaves a trail of stars." },
	{ id = "tidewyrm", name = "Tidewyrm", islet = 5, hp = 34, atk = 12, def = 9, spd = 7, skill = "zap", knack = "fish", trust = 0.15, shape = "wyrm", body = "blue", accent = "screen_on", blurb = "The deep's oldest swimmer." },
}
-- stylua: ignore end

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
