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

-- The colours are soft pastels (the request of 2026-11-13: "could everything use a more pastelish colour pallette?"):
-- each a lighter, gentler take on the hue it was, the darks lifted less so they still read as darks; ink stays ink.
local COLORS: { [string]: number } = {
	ink = 0x2B1E2E,
	sky_day = 0xADDCF1,
	sky_night = 0x40477E,
	grass = 0xACD493,
	grass_dark = 0x93BB7E,
	pavement = 0xD5CFC4,
	floor_a = 0xE8DCC7,
	floor_b = 0xDDCFB6,
	wall = 0xF3EFE7,
	wall_trim = 0xE8A6B4,
	window = 0xC4E9F6,
	wood = 0xD3AB8A,
	wood_dark = 0x9C7258,
	steel = 0xC4CCD4,
	steel_dark = 0x888F9A,
	desk = 0xE4D1B1,
	screen_off = 0x3C4A5E,
	screen_on = 0x91DAF1,
	screen_code = 0xABF1B5,
	plastic = 0xF2F0EA,
	plastic_dark = 0x9D9BA2,
	leaf = 0x98CC91,
	leaf_dark = 0x6CAA76,
	pot = 0xDFA388,
	paper = 0xFEFCF5,
	sofa = 0xE99292,
	rug = 0xF0D090,
	road = 0x787580,

	cream = 0xFCF2DC,
	berry_red = 0xE97A88,
	blue = 0x92BCEB,
	green = 0x9FD496,
	yellow = 0xF5E196,
	orange = 0xF3BA85,
	pink = 0xF7B3CE,
	purple = 0xBB9CDD,
	gold = 0xF1D172,
	black = 0x4A4253,
	white = 0xFFFFFF,

	sand = 0xF2DAAF,
	sand_dark = 0xE1C59B,
	water = 0x78BDD1,
	night = 0x504C79,
	chalk = 0x4F7E60,

	shallow = 0x92D8DA,
	foam = 0xEEF9F6,
	rock = 0xB6B1AC,
	rock_dark = 0x827D77,

	skin1 = 0xFAE2CE,
	skin2 = 0xF0CBAB,
	skin3 = 0xD5AC8E,
	skin4 = 0x946A52,
	hair_brown = 0x966849,
	hair_black = 0x5A525F,
	hair_blond = 0xF4DC97,
	hair_red = 0xDF8D74,
	hair_blue = 0x88A0DF,
	jeans = 0x677CA2,

	moss = 0x99BC79,
	maple = 0xE39173,
	bamboo = 0xD0D092,
	clay = 0xD19378,
	slate = 0x737B8A,
	snow = 0xF1F6FB,
	ice = 0xBCE1EF,
	lava = 0xF1A16F,
	basalt = 0x665F6B,
	crystal = 0xCBABEF,
	cherry = 0xFAC8DB,
	teal = 0x7DC9BD,
	swamp = 0x738F6D,
	coral = 0xF5A799,
	straw = 0xE8D08E,
	brick = 0xCC8270,
}

-- The office tiers' surfaces (Data/Office: theme per tier). floor_a / floor_b: the two floor tile tones, wall /
-- wall_trim: the back walls and their skirting and crown.
local THEMES: { [string]: { [string]: number } } = {
	garage = {
		floor_a = 0xC7C3BC,
		floor_b = 0xC2BEB6,
		wall = 0xDED8CB,
		wall_trim = 0xAEA295,
	},
	loft = {
		floor_a = 0xE1BF9C,
		floor_b = 0xD2B08E,
		wall = 0xDEAA95,
		wall_trim = 0xF3E9DB,
	},
	studio = {
		floor_a = 0x9FC4D0,
		floor_b = 0x95B7C4,
		wall = 0xF5F1E8,
		wall_trim = 0x4B92A3,
	},
}

-- Multiplicative tints (0.8..1.2) applied by the renderer and the classic lighting. The day is a little warm, like
-- the light late on a summer afternoon (the request of 2026-11-13: "make the entire game feel more cozy, such as the
-- pallette and other details to emphasize it"), the same as the dynamic models' (INDOOR below).
local MODES: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.03, g = 1, b = 0.95 },
	plain = { r = 1, g = 1, b = 1 }, -- the colours as they are (the specs: a palette colour lands on itself)
	night = { r = 0.8, g = 0.84, b = 1.15 },
}

-- Inside the office the renderer tints by these instead (Render/Shading INDOOR): lit a little warmer by the lamps.
local INDOOR: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.03, g = 1, b = 0.96 },
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

-- The interface's own colours (UIKit), pastel like the world's (buttons, frames and accents soft, the plates a gentle
-- dark so white text still reads on them), an island's (GAME_DESIGN 2: "more in theme with the island theme"): dark
-- driftwood plates in frames of planks (frame_*), nail heads, sand-coloured quiet text, buttons painted lagoon blue,
-- palm green, mango and coral, a sea-dark backdrop behind a panel.
local UI: { [string]: number } = {
	ink = 0x2A1C1A,
	plate = 0x4B3A42,
	plate_light = 0x67525B,
	paper = 0xFFF6E8,
	paper_dark = 0xEEDCC6,
	text = 0xFFFFFF,
	text_dim = 0xE8D7C3,
	text_ink = 0x2A1C1A,
	accent = 0xFFD86E,
	good = 0x9FE09B,
	bad = 0xFF9B95,
	button = 0x7FC6E2,
	button_ok = 0x97D994,
	button_warn = 0xF8BB86,
	button_off = 0x9E8E84,
	button_close = 0xEC9584,
	frame_hi = 0xF2D0A6,
	frame = 0xD5A87E,
	frame_lo = 0xA67F64,
	frame_dark = 0x7C5C49,
	nail_hi = 0xF6EEDF,
	nail_lo = 0x87766C,
	sea_shade = 0x0C2531,
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
