--!strict
-- The pass track (GAME_DESIGN 14.3; the request of 2026-11-14: "a gamepass track with eggs, money and cosmetics along
-- with a premium track"). Pure.
--   A season lasts Tuning.TrackSecs on the sea's clock; its points (Profile.track.xp) come from play (Tuning.TrackXp:
--   eggs hatched, Hatchery eggs, quests, growing the island, time on the island). LEVELS levels, level L costing
--   Tuning.TrackBase + Tuning.TrackStep x (L - 1) points. Each level has a free reward and a premium one (the premium
--   side opens with the Premium Track pass, for this season and every one after). A reward is one of:
--     { kind = "shells", mins = m }  shells: m minutes of what the island makes now (at least Tuning.RewardFloor a
--                                    minute times Tuning.EggTier by its tier: Logic/Store.minutes)
--     { kind = "egg", r = r }        an egg of rarity r into the bag (Logic/Tree.bagAdd)
--     { kind = "look", id = id }     a cosmetic (Data/Cosmetics); one already owned pays its shells instead
--     { kind = "title", id = id }    a title (Data/Titles)
--   A new season starts the points and the claims again; what was won is kept.
export type Reward = { kind: string, mins: number?, r: number?, id: string? }
export type Level = { free: Reward, prem: Reward }

local LEVELS = 30

local FREE_LOOKS: { [number]: string } = { [3] = "leafpaint", [8] = "driftears", [13] = "feathercollar", [18] = "eggbasket", [23] = "tikitorch", [28] = "lifevest" }
local PREM_LOOKS: { [number]: string } = { [5] = "glowvisor", [10] = "trident", [15] = "drakewings", [20] = "tiderobe", [25] = "starcape", [30] = "tidecrown" }
local FREE_EGGS: { [number]: number } = { [5] = 2, [10] = 3, [15] = 3, [20] = 4, [25] = 4 }
local PREM_EGGS: { [number]: number } = { [3] = 3, [6] = 3, [9] = 4, [12] = 4, [16] = 4, [18] = 5, [22] = 5, [24] = 5, [27] = 6, [29] = 6 }

local list: { Level } = {}
for L = 1, LEVELS do
	local free: Reward
	if L == 30 then
		free = { kind = "title", id = "firstmate" }
	elseif L == 15 then
		free = { kind = "title", id = "deckhand" }
	elseif FREE_LOOKS[L] then
		free = { kind = "look", id = FREE_LOOKS[L] }
	elseif FREE_EGGS[L] then
		free = { kind = "egg", r = FREE_EGGS[L] }
	else
		free = { kind = "shells", mins = 4 + math.floor(L / 2) }
	end
	local prem: Reward
	if L == 30 then
		prem = { kind = "title", id = "captain" }
	elseif PREM_LOOKS[L] then
		prem = { kind = "look", id = PREM_LOOKS[L] }
	elseif PREM_EGGS[L] then
		prem = { kind = "egg", r = PREM_EGGS[L] }
	else
		prem = { kind = "shells", mins = 10 + L }
	end
	table.insert(list, { free = free, prem = prem })
end
-- (the last level's free side also brings a legendary egg, the premium side's a mythic one: Logic/Store.claim pays
-- these extras with the title)
local EXTRA: { free: Reward, prem: Reward } = { free = { kind = "egg", r = 5 }, prem = { kind = "egg", r = 6 } }

return table.freeze({ LEVELS = LEVELS, list = list, extra = EXTRA })
