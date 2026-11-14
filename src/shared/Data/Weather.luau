--!strict
-- The seasons and the weather (GAME_DESIGN 13; docs/ARCHITECTURE.md 5). Pure. The request (2026-11-14): "also, make
-- weather and seasons, and eggs spawns are affected by these with different mutations".
--   Four seasons come round on the sea's clock (Logic/Weather; Tuning.SeasonSecs each), every season a run of
--   weather spells (Tuning.WeatherSecs), each picked by the season's odds (`odds`, weights). A weather kind may touch
--   the eggs the Tree of Life lays while it lasts (Tuning.WeatherTouch): a touched egg hatches with the kind's
--   mutation (its `family` in Data/Traits). A season's own islets (`favour`, Data/Islets ids) give its eggs more of
--   their kinds (Tuning.SeasonFavour). `grade` is the light it brings (Controllers/DayLight, over the day's own).
--   Weather.SEASONS (in order), Weather.seasonById, Weather.KINDS, Weather.byId
export type Grade = { mr: number, mg: number, mb: number, lift: number, sat: number }
export type Kind = {
	id: string,
	name: string, -- the HUD chip's word ("Rain")
	laid: string, -- an egg it touched, in the tree panel ("Laid in the rain")
	starts: string, -- the notice as it starts ("It started to rain.")
	family: string?, -- the mutation family its eggs carry (Data/Traits.weather); nil: it touches no egg
	icon: string, -- the chip's 11 x 11 sprite (UI/ArtData "mini_<icon>")
	grade: Grade?, -- the light it brings (nil: the day's own)
	mark: string, -- the colour of its mark on a touched egg (Models/EggModels; a palette key)
}
export type Season = {
	id: string,
	name: string,
	icon: string,
	odds: { { kind: string, w: number } }, -- its weather and how often each comes
	favour: { number }, -- Data/Islets ids whose kinds its eggs bring more often
	blurb: string,
}

local Weather = {}

-- stylua: ignore start
Weather.KINDS = {
	{ id = "sunny", name = "Sunny", laid = "Laid in the sun", starts = "The sun is out.", icon = "sun", mark = "yellow" },
	{ id = "breezy", name = "Breezy", laid = "Laid in a breeze", starts = "A breeze picks up.", icon = "breeze", mark = "white" },
	{ id = "rain", name = "Rain", laid = "Laid in the rain", starts = "It started to rain.", family = "rainy", icon = "rain", mark = "blue",
		grade = { mr = 0.93, mg = 0.96, mb = 1.03, lift = 6, sat = 0.84 } },
	{ id = "storm", name = "Storm", laid = "Laid in a storm", starts = "A storm rolls in.", family = "stormy", icon = "storm", mark = "purple",
		grade = { mr = 0.85, mg = 0.88, mb = 0.97, lift = 6, sat = 0.76 } },
	{ id = "fog", name = "Fog", laid = "Laid in the fog", starts = "Fog drifts in from the sea.", family = "misty", icon = "fog", mark = "steel",
		grade = { mr = 1.01, mg = 1.02, mb = 1.04, lift = 16, sat = 0.8 } },
	{ id = "snow", name = "Snow", laid = "Laid in the snow", starts = "It started to snow.", family = "frosty", icon = "snow", mark = "white",
		grade = { mr = 1.03, mg = 1.05, mb = 1.09, lift = 6, sat = 0.92 } },
	{ id = "blossom", name = "Blossom wind", laid = "Laid in the blossom wind", starts = "Petals are blowing in.", family = "bloomy", icon = "petal", mark = "pink",
		grade = { mr = 1.05, mg = 1.03, mb = 1.04, lift = 3, sat = 1.03 } },
	{ id = "haze", name = "Heat haze", laid = "Laid in the heat", starts = "It's a hot one.", family = "sunny", icon = "heat", mark = "orange",
		grade = { mr = 1.07, mg = 1.04, mb = 0.97, lift = 2, sat = 1.05 } },
	{ id = "leaves", name = "Falling leaves", laid = "Laid under falling leaves", starts = "The leaves are coming down.", family = "autumn", icon = "leaf", mark = "orange",
		grade = { mr = 1.05, mg = 1.01, mb = 0.95, lift = 2, sat = 1.03 } },
} :: { Kind }

Weather.SEASONS = {
	{ id = "spring", name = "Spring", icon = "season_spring", favour = { 2, 6 }, blurb = "Meadow and mangrove kinds come more often.",
		odds = { { kind = "sunny", w = 30 }, { kind = "blossom", w = 26 }, { kind = "rain", w = 24 }, { kind = "breezy", w = 14 }, { kind = "storm", w = 6 } } },
	{ id = "summer", name = "Summer", icon = "season_summer", favour = { 1, 3, 5 }, blurb = "Beach, volcano and reef kinds come more often.",
		odds = { { kind = "sunny", w = 38 }, { kind = "haze", w = 26 }, { kind = "breezy", w = 14 }, { kind = "rain", w = 12 }, { kind = "storm", w = 10 } } },
	{ id = "autumn", name = "Autumn", icon = "season_autumn", favour = { 8, 9 }, blurb = "Bluff and ruin kinds come more often.",
		odds = { { kind = "leaves", w = 30 }, { kind = "breezy", w = 18 }, { kind = "rain", w = 20 }, { kind = "fog", w = 22 }, { kind = "storm", w = 10 } } },
	{ id = "winter", name = "Winter", icon = "season_winter", favour = { 4, 7 }, blurb = "Snowfield and grotto kinds come more often.",
		odds = { { kind = "snow", w = 40 }, { kind = "fog", w = 20 }, { kind = "sunny", w = 22 }, { kind = "breezy", w = 12 }, { kind = "storm", w = 6 } } },
} :: { Season }
-- stylua: ignore end

local BY_ID: { [string]: Kind } = {}
for _, k in Weather.KINDS do
	BY_ID[k.id] = k
end
Weather.byId = BY_ID

local SEASON_BY_ID: { [string]: Season } = {}
for _, s in Weather.SEASONS do
	SEASON_BY_ID[s.id] = s
end
Weather.seasonById = SEASON_BY_ID

return Weather
