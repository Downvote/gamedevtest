--!strict
-- Titles a founder can wear under their name (GAME_DESIGN 14; the request of 2026-11-14: "make the player be outlined
-- white like the bakery game, with the name and title on top. make titles"). Pure.
--   Each is earned once and kept (Profile.titles); the founder wears one (Profile.title, "" for none), shown under
--   their name over their head (every player sees it: the "Title" attribute). `how` says what earns it, `n` how much:
--     "start"   every founder has it
--     "tier"    the island grown to tier n             "taken"  n eggs hatched (the tree's and the bag's)
--     "best"    a driftling of rarity n or rarer had    "seen"   n kinds in the Index (0: every kind)
--     "earned"  n shells made in all                    "hatched" n Hatchery eggs hatched
--     "days"    n island days lived                     "owned"  n cosmetics owned
--     "vip"     the VIP pass                            "starter" the starter pack
--     "track"   a pass track reward (Data/Track gives it)
--   `color`: its words' colour (UIKit / Palette keys).
export type Title = { id: string, name: string, how: string, n: number, color: string }

local LIST: { Title } = {}
local BY_ID: { [string]: Title } = {}
local function T(id: string, name: string, how: string, n: number, color: string?)
	local t: Title = { id = id, name = name, how = how, n = n, color = color or "text" }
	assert(BY_ID[id] == nil, "Titles: duplicate id " .. id)
	table.insert(LIST, t)
	BY_ID[id] = t
end

T("newcomer", "Newcomer", "start", 0, "text_dim")
-- the island
T("settler", "Settler", "tier", 2)
T("islander", "Islander", "tier", 3)
T("townfounder", "Town Founder", "tier", 5, "good")
T("baykeeper", "Bay Keeper", "tier", 7, "good")
T("havenbuilder", "Haven Builder", "tier", 10, "button")
T("isleshaper", "Isle Shaper", "tier", 13, "button")
T("cloudwalker", "Cloud Walker", "tier", 15, "purple")
T("starmapper", "Star Mapper", "tier", 17, "purple")
T("everdrifter", "Everdrifter", "tier", 20, "accent")
-- eggs and driftlings
T("eggfinder", "Egg Finder", "taken", 10)
T("egghunter", "Egg Hunter", "taken", 100, "good")
T("eggwhisperer", "Egg Whisperer", "taken", 500, "button")
T("clutchmaster", "Clutch Master", "taken", 2000, "accent")
T("luckyfind", "Lucky Find", "best", 4, "purple")
T("legendkeeper", "Legend Keeper", "best", 5, "accent")
T("mythkeeper", "Myth Keeper", "best", 6, "mythic")
T("starcatcher", "Star Catcher", "best", 7, "celestial")
T("collector", "Collector", "seen", 20, "good")
T("naturalist", "Naturalist", "seen", 50, "button")
T("archivist", "Archivist", "seen", 0, "accent")
T("matchmaker", "Matchmaker", "hatched", 10, "pink")
-- shells and time
T("shellsaver", "Shell Saver", "earned", 1e6, "good")
T("shellbaron", "Shell Baron", "earned", 1e9, "button")
T("shelltycoon", "Shell Tycoon", "earned", 1e12, "accent")
T("regular", "Regular", "days", 7)
T("oldsalt", "Old Salt", "days", 30, "good")
-- cosmetics
T("trendsetter", "Trendsetter", "owned", 20, "pink")
T("fashionicon", "Fashion Icon", "owned", 50, "accent")
-- the store
T("earlybird", "Early Bird", "starter", 0, "good")
T("vip", "VIP", "vip", 0, "accent")
-- the pass track (Data/Track)
T("deckhand", "Deckhand", "track", 0, "good")
T("firstmate", "First Mate", "track", 0, "button")
T("captain", "Captain", "track", 0, "accent")

return table.freeze({ list = LIST, byId = BY_ID })
