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
	-- (more skins for the founders: Data/Looks, 2026-11-14)
	"skin5",
	"skin6",
}

-- Rich, warm colours (the request of 2026-11-14: "when i meant pastel color, i didnt mean desaturated it, i meant use
-- more cozy colors. saturate the game back more"): the cozy pass's colours with the colourful hues 15% fuller. Then
-- a pink sand (2026-11-14: "make the pallette more pinkish, changing the sand pink and the rest of the pallette to
-- match", then "not that pink, i meant a light pink, close to the color of actual sand"): the sand a pale beige with
-- a blush of pink, a fresher green lawn and leaves, a turquoise sea; the wood, rock, steel, foam and cream back near
-- the cozy colours with a quarter of the pink pass's blush left in them.
local COLORS: { [string]: number } = {
	ink = 0x2B1E2E,
	sky_day = 0x9ADAF9,
	sky_night = 0x212452,
	grass = 0x84DA72,
	grass_dark = 0x62BC5C,
	pavement = 0xD1C7BD,
	floor_a = 0xEEDDC4,
	floor_b = 0xE0C9B4,
	wall = 0xF4EFE7,
	wall_trim = 0xEE879E,
	window = 0xBDECFD,
	wood = 0xD28B58,
	wood_dark = 0x935839,
	steel = 0xBCC2CE,
	steel_dark = 0x7D8496,
	desk = 0xEACCB1,
	screen_off = 0x3C4A5E,
	screen_on = 0x64D9FD,
	screen_code = 0x93FAA3,
	plastic = 0xF2F0EA,
	plastic_dark = 0x9C9AA3,
	leaf = 0x60C46E,
	leaf_dark = 0x37935A,
	pot = 0xE47C56,
	paper = 0xFFFCF5,
	sofa = 0xF36464,
	rug = 0xFDCA62,
	road = 0x635D6B,

	cream = 0xFEF2DD,
	berry_red = 0xF63850,
	blue = 0x65A8F5,
	green = 0x6FD47E,
	yellow = 0xFDE074,
	orange = 0xFCA458,
	pink = 0xFEA8CA,
	purple = 0xA675DF,
	gold = 0xFCC933,
	black = 0x3B3442,
	white = 0xFFFFFF,

	sand = 0xFCDEC2,
	sand_dark = 0xE9C5A3,
	water = 0x2EBBC4,
	night = 0x2E2A52,
	chalk = 0x2A5F3D,

	shallow = 0x6FE0D2,
	foam = 0xF2F8F5,
	rock = 0x9E9692,
	rock_dark = 0x6E6664,

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
	skin5 = 0x5E3826,
	skin6 = 0xFFD7C7,
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
-- pallette and other details to emphasize it"), with a faint blush since the pink sand (the night's violet is
-- DayLight's). The same as the dynamic models' (INDOOR below).
local MODES: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.033, g = 0.995, b = 0.955 },
	plain = { r = 1, g = 1, b = 1 }, -- the colours as they are (the specs: a palette colour lands on itself)
	night = { r = 0.8, g = 0.84, b = 1.15 },
}

-- Inside the office the renderer tints by these instead (Render/Shading INDOOR): lit a little warmer by the lamps.
local INDOOR: { [string]: { r: number, g: number, b: number } } = {
	day = { r = 1.033, g = 0.998, b = 0.963 },
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

-- The interface's own colours (UIKit): since 2026-11-14 black see-through glass (glass, veil, rule) with white text,
-- quiet text the colour of the pink sand, buttons painted lagoon turquoise, mint, mango and coral, a sea-dark backdrop
-- behind a panel; the old driftwood plates and plank frames (plate, frame_*, nail_*) stay for the few swatches that
-- still use them.
local UI: { [string]: number } = {
	ink = 0x2A1C1C,
	plate = 0x3D2924,
	plate_light = 0x5B3D34,
	paper = 0xFFF2E0,
	paper_dark = 0xEDDBCA,
	text = 0xFFFFFF,
	text_dim = 0xE1CFBE,
	text_ink = 0x2A1C1C,
	accent = 0xFFCB30,
	good = 0x78DA8A,
	bad = 0xFF6F6A,
	button = 0x45BFC6,
	button_ok = 0x78DA8A,
	button_warn = 0xFFA553,
	button_off = 0x867263,
	button_close = 0xE9705F,
	frame_hi = 0xEAB887,
	frame = 0xBD8256,
	frame_lo = 0x84553C,
	frame_dark = 0x613D2B,
	nail_hi = 0xF7EEE2,
	nail_lo = 0x6F5D55,
	sea_shade = 0x0C2631,
	-- the request of 2026-11-14 ("make the ui appear like this instead, with a black transparent background and make it
	-- neater", with a picture of Random Bakery's HUD): the black glass behind every card, panel and bar (UIKit's
	-- GLASS_ALPHA see-through), the faint veil an item sits on over it, its rule, a dark button's face
	glass = 0x0A080C,
	veil = 0xFFFFFF,
	rule = 0xFFFFFF,
	xp = 0xC9A6FF,
	-- the two rarest rarities (Data/Traits, 2026-11-14): a rose pink and a starlight blue
	mythic = 0xFF6EB4,
	celestial = 0xA6F0FF,
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
