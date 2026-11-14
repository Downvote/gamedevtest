--!strict
-- Colour palette (docs/ARCHITECTURE.md 5). Pure. Colours are 0xRRGGBB numbers.
-- `order` is the renderer's fixed LUT order; `themes` are the office tiers' floors and walls (Data/Office names the
-- theme of each tier); the renderer adds them to the LUT after `order` (Shading.defaultColors).
-- Keys the copied Random Bakery modules read stay: ink, sky_day, sky_night, gold, yellow, white, berry_red, pink,
-- wall_trim, orange, blue, green, purple, cream (Render/Shading's sprite legend).

local ORDER: { string } = {
	-- world / building
	"ink",
	"sky_day",
	"sky_night",
	"grass",
	"grass_dark",
	"pavement",
	"floor_a",
	"floor_b",
	"wall",
	"wall_trim",
	"window",
	"wood",
	"wood_dark",
	"steel",
	"steel_dark",
	"desk",
	"screen_off",
	"screen_on",
	"screen_code",
	"plastic",
	"plastic_dark",
	"leaf",
	"leaf_dark",
	"pot",
	"paper",
	"sofa",
	"rug",
	"road",
	-- generic hues
	"cream",
	"berry_red",
	"blue",
	"green",
	"yellow",
	"orange",
	"pink",
	"purple",
	"gold",
	"black",
	"white",
	-- the microgames' stages
	"sand",
	"sand_dark",
	"water",
	"night",
	"chalk",
	-- the coast
	"shallow",
	"foam",
	"rock",
	"rock_dark",
	-- characters
	"skin1",
	"skin2",
	"skin3",
	"skin4",
	"hair_brown",
	"hair_black",
	"hair_blond",
	"hair_red",
	"hair_blue",
	"jeans",
	-- the build catalog's themes (GAME_DESIGN 4: "enough paths, fences and other detail to make a lot of vastly
	-- different themed islands")
	"moss",
	"maple",
	"bamboo",
	"clay",
	"slate",
	"snow",
	"ice",
	"lava",
	"basalt",
	"crystal",
	"cherry",
	"teal",
	"swamp",
	"coral",
	"straw",
	"brick",
}

-- Rich, warm colours (the request of 2026-11-14: "when i meant pastel color, i didnt mean desaturated it, i meant use
-- more cozy colors. saturate the game back more"): the cozy pass's colours with the colourful hues 15% fuller. Then
-- pink led (2026-11-14: "make the pallette more pinkish, changing the sand pink and the rest of the pallette to
-- match"): pink sand, a fresher green lawn and leaves, a turquoise sea, rosy wood, mauve rock and steel, pink-white foam
-- and cream.
local COLORS: { [string]: number } = {
	ink = 0x2B1E2E,
	sky_day = 0xA2D8F8,
	sky_night = 0x272252,
	grass = 0x84DA72,
	grass_dark = 0x62BC5C,
	pavement = 0xD8C6C6,
	floor_a = 0xF0DCCF,
	floor_b = 0xE2C2AE,
	wall = 0xF6EEEB,
	wall_trim = 0xEE879E,
	window = 0xBDECFD,
	wood = 0xD2896A,
	wood_dark = 0x925646,
	steel = 0xC2BFCF,
	steel_dark = 0x837E96,
	desk = 0xEBC7A8,
	screen_off = 0x3C4A5E,
	screen_on = 0x64D9FD,
	screen_code = 0x93FAA3,
	plastic = 0xF2F0EA,
	plastic_dark = 0x9C9AA3,
	leaf = 0x60C46E,
	leaf_dark = 0x37935A,
	pot = 0xE2786A,
	paper = 0xFFFAF7,
	sofa = 0xF36464,
	rug = 0xFDCA62,
	road = 0x66596B,

	cream = 0xFFF1E6,
	berry_red = 0xF63850,
	blue = 0x65A8F5,
	green = 0x6FD47E,
	yellow = 0xFDE074,
	orange = 0xFCA05E,
	pink = 0xFEA8CA,
	purple = 0xA675DF,
	gold = 0xFCC933,
	black = 0x3B3442,
	white = 0xFFFFFF,

	sand = 0xFCC0B8,
	sand_dark = 0xEC9E99,
	water = 0x2EBBC4,
	night = 0x2E2A52,
	chalk = 0x2A5F3D,

	shallow = 0x6FE0D2,
	foam = 0xFDF3F3,
	rock = 0xA0929B,
	rock_dark = 0x70626C,

	skin1 = 0xFEE1CA,
	skin2 = 0xF9C293,
	skin3 = 0xD58F59,
	skin4 = 0x834D2E,
	hair_brown = 0x834923,
	hair_black = 0x2F2932,
	hair_blond = 0xFDDA75,
	hair_red = 0xE7582D,
	hair_blue = 0x507AE4,
	jeans = 0x4668A4,

	moss = 0x6FA240,
	maple = 0xEF5F2B,
	bamboo = 0xCDCD61,
	clay = 0xD06333,
	slate = 0x5E6779,
	snow = 0xF1F6FB,
	ice = 0xB1E2F5,
	lava = 0xFC7D2E,
	basalt = 0x433D48,
	crystal = 0xC393F8,
	cherry = 0xFEC4DA,
	teal = 0x3BC2AE,
	swamp = 0x598452,
	coral = 0xFD8D7A,
	straw = 0xF1C95D,
	brick = 0xC04B2E,
}

-- The office tiers' surfaces (Data/Office: theme per tier). floor_a / floor_b: the two floor tile tones, wall /
-- wall_trim: the back walls and their skirting and crown.
local THEMES: { [string]: { [string]: number } } = {
	garage = {
		floor_a = 0xB9B4AA,
		floor_b = 0xA8A296,
		wall = 0xDCD5C6,
		wall_trim = 0x8F7D6B,
	},
	loft = {
		floor_a = 0xDDAE7E,
		floor_b = 0xC79563,
		wall = 0xCF8466,
		wall_trim = 0xF4E9DA,
	},
	studio = {
		floor_a = 0x7FB3C4,
		floor_b = 0x6C9FB2,
		wall = 0xF6F1E7,
		wall_trim = 0x2E7D8F,
	},
}

-- Multiplicative tints (0.8..1.2) applied by the renderer and the classic lighting. The day is a little warm, like
-- the light late on a summer afternoon (the request of 2026-11-13: "make the entire game feel more cozy, such as the
-- pallette and other details to emphasize it"), and since the pink pass a touch rosy (the night's violet is
-- DayLight's). The same as the dynamic models' (INDOOR below).
local MODES: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.04, g = 0.98, b = 0.97 },
	plain = { r = 1, g = 1, b = 1 }, -- the colours as they are (the specs: a palette colour lands on itself)
	night = { r = 0.8, g = 0.84, b = 1.15 },
}

-- Inside the office the renderer tints by these instead (Render/Shading INDOOR): lit a little warmer by the lamps.
local INDOOR: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.04, g = 0.99, b = 0.97 },
	night = { r = 1.04, g = 0.94, b = 0.86 },
}

-- Window sunlight on the office floor (Shading SUNLIT): the indoor tint times this.
local SUNLIT = { r = 1.06, g = 1.02, b = 0.9 }

-- The four scores' colours in the UI and the popups (Types.Axis).
local AXIS: { [string]: number } = {
	fun = 0xFF7FB0,
	ideas = 0xFFD84A,
	graphics = 0x66B8FF,
	sound = 0x7FE07A,
}

-- The four combo matches' colours (Types.Match).
local MATCH: { [string]: number } = {
	great = 0xFFB238,
	good = 0x6CCB5F,
	okay = 0xB8B8C0,
	poor = 0xE8465B,
}

-- The interface's own colours (UIKit), an island's (GAME_DESIGN 2: "more in theme with the island theme"): dark
-- rosewood plates in frames of rosy planks (frame_*), nail heads, pink sand quiet text, buttons painted lagoon
-- turquoise, mint, mango and coral, a sea-dark backdrop behind a panel.
local UI: { [string]: number } = {
	ink = 0x2C1A20,
	plate = 0x3E2629,
	plate_light = 0x5E3B3E,
	paper = 0xFFF1EC,
	paper_dark = 0xF0CFC6,
	text = 0xFFFFFF,
	text_dim = 0xE6C3BC,
	text_ink = 0x2C1A20,
	accent = 0xFFCB30,
	good = 0x78DA8A,
	bad = 0xFF6F6A,
	button = 0x45BFC6,
	button_ok = 0x78DA8A,
	button_warn = 0xFFA553,
	button_off = 0x8A6E6E,
	button_close = 0xEC6E6E,
	frame_hi = 0xF0B5A0,
	frame = 0xC47E68,
	frame_lo = 0x8A5149,
	frame_dark = 0x643937,
	nail_hi = 0xFAEDEA,
	nail_lo = 0x735B5B,
	sea_shade = 0x0C2A31,
}

local Palette: {
	colors: { [string]: number },
	order: { string },
	themes: { [string]: { [string]: number } },
	modes: { [string]: { r: number, g: number, b: number } },
	indoor: { [string]: { r: number, g: number, b: number } },
	sunlit: { r: number, g: number, b: number },
	axis: { [string]: number },
	match: { [string]: number },
	ui: { [string]: number },
} = {
	colors = COLORS,
	order = ORDER,
	themes = THEMES,
	modes = MODES,
	indoor = INDOOR,
	sunlit = SUNLIT,
	axis = AXIS,
	match = MATCH,
	ui = UI,
}

return table.freeze(Palette)
