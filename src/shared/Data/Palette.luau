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
}

local COLORS: { [string]: number } = {
	ink = 0x2B1E2E,
	sky_day = 0x9FD8F2,
	sky_night = 0x1F2552,
	grass = 0x8ACB6C,
	grass_dark = 0x6FAE57,
	pavement = 0xCFC7BA,
	floor_a = 0xE9DCC4,
	floor_b = 0xD9C6A6,
	wall = 0xF4EFE6,
	wall_trim = 0xE68FA2,
	window = 0xC2EAF8,
	wood = 0xC88D5C,
	wood_dark = 0x8B5B3D,
	steel = 0xBAC3CE,
	steel_dark = 0x7B8696,
	desk = 0xE2C9A0,
	screen_off = 0x3C4A5E,
	screen_on = 0x6FD3F2,
	screen_code = 0x9BF2A8,
	plastic = 0xF2F0EA,
	plastic_dark = 0x9C9AA3,
	leaf = 0x6CC06A,
	leaf_dark = 0x3F8F4F,
	pot = 0xD9825B,
	paper = 0xFFFDF4,
	sofa = 0xE86F6F,
	rug = 0xF2C66D,

	cream = 0xFFF3D9,
	berry_red = 0xE8465B,
	blue = 0x70A9EA,
	green = 0x7DC971,
	yellow = 0xFFE172,
	orange = 0xFFA553,
	pink = 0xFFA7CA,
	purple = 0xA77DD7,
	gold = 0xFFCB30,
	black = 0x3B3442,
	white = 0xFFFFFF,

	skin1 = 0xFFE1C9,
	skin2 = 0xF1C39B,
	skin3 = 0xCB9063,
	skin4 = 0x7C4F35,
	hair_brown = 0x7B4B2B,
	hair_black = 0x2F2932,
	hair_blond = 0xF7D77B,
	hair_red = 0xD9603B,
	hair_blue = 0x5B7FD9,
	jeans = 0x4E6A9C,
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

-- Multiplicative tints (0.8..1.2) applied by the renderer and the classic lighting.
local MODES: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1, g = 1, b = 1 },
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

-- The interface's own colours (UIKit): plates, ink, text, accents.
local UI: { [string]: number } = {
	ink = 0x2B1E2E,
	plate = 0x2F2740,
	plate_light = 0x463B5C,
	paper = 0xFFF6E6,
	paper_dark = 0xEAD9BF,
	text = 0xFFFFFF,
	text_dim = 0xC9BEDB,
	text_ink = 0x2B1E2E,
	accent = 0xFFCB30,
	good = 0x7DD87A,
	bad = 0xFF6F7F,
	button = 0x5FB8F2,
	button_ok = 0x7DD87A,
	button_warn = 0xFFA553,
	button_off = 0x7A7088,
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
