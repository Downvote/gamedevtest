--!strict
-- Platforms (GAME_DESIGN 6.1). Pure. from / to: the years it is on sale (to = 0: for good); licence: paid when a
-- game for it starts; market: how many people can buy it (sales factor); loves: genres its players love
-- (Tuning.LoveMult on quality); color / accent: its icon's body and screen (Palette keys); kind: the icon's shape.
export type PlatformDef = {
	id: string,
	name: string,
	short: string,
	from: number,
	to: number,
	licence: number,
	market: number,
	loves: { string },
	color: string,
	accent: string,
	kind: string,
}

local LIST: { PlatformDef } = {
	{ id = "pc", name = "Home PC", short = "PC", from = 1, to = 0, licence = 0, market = 1.0, loves = { "strategy", "simulation" }, color = "plastic", accent = "screen_on", kind = "pc" },
	{ id = "pocket", name = "Pocket Pal", short = "Pocket", from = 1, to = 10, licence = 6000, market = 1.2, loves = { "puzzle", "rpg" }, color = "yellow", accent = "screen_code", kind = "handheld" },
	{ id = "bytebox", name = "Byte Box", short = "Byte Box", from = 3, to = 14, licence = 20000, market = 1.8, loves = { "action", "sports" }, color = "black", accent = "green", kind = "console" },
	{ id = "phone", name = "Smartphone", short = "Phone", from = 5, to = 0, licence = 8000, market = 2.2, loves = { "puzzle", "rhythm" }, color = "steel_dark", accent = "screen_on", kind = "phone" },
	{ id = "orbit", name = "Orbit VR", short = "VR", from = 9, to = 0, licence = 60000, market = 2.0, loves = { "action", "simulation" }, color = "white", accent = "purple", kind = "vr" },
	{ id = "cloud", name = "Cloud Arcade", short = "Cloud", from = 13, to = 0, licence = 120000, market = 3.2, loves = { "racing", "adventure" }, color = "sky_day", accent = "white", kind = "cloud" },
}

local BY_ID: { [string]: PlatformDef } = {}
for _, p in LIST do
	BY_ID[p.id] = p
end

return table.freeze({ list = LIST, byId = BY_ID })
