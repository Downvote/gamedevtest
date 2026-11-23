--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"     a string of 1-24 letters, digits or underscores (a building id ...)
--   "int"    a whole number in [0, 1e6] (a driftling or piece id; 0: none)
--   "small"  a whole number in [1, 32] (a look index)
--   "rarity" a whole number in [1, Traits.RMAX] (a driftling's rarity: 9)
--   "key"    a settings key ("pixel", "music", "sfx", "pals", "zoom", "lang", "text", "loading")
--   "coord"  a whole number in [-240, 160] (a plot-local stud: the top tier's island reaches far north and south of
--            its heart)
--   "rot"    a quarter turn: 0, 90, 180 or 270
--   "index"  a whole number in [1, 8192] (a placed piece: pieces, tiles and fences)
--   "cells"  1 to 40 cells "x,z" joined by ";", each a coord (path or water tiles drawn or erased: Logic/Plot.paint)
--   "edges"  1 to 40 edges "x,z,r" joined by ";", each a coord and r 0 or 90 (fences drawn or taken down: Plot.fence)
--   "tiles"  which tiles an eraser takes up: "path", "water" or "all"
--   "group"  what Build mode's Remove all takes away: "pieces", "tiles" or "fences"
--   "slot"   a cosmetics slot (Data/Cosmetics.SLOTS: "hat", "face", "neck", "back", "hand", "top")
--   "lookid" a string of 0-24 letters, digits or underscores (a cosmetic or a title; "" for none)
--   "look"   a whole look's code (Data/Looks.encode: digits, dots, bars, letters and underscores, at most 200; "" an
--            outfit deleted): Logic/Store.checkLook reads it
--   "outfit" a whole number in [1, Tuning.MaxOutfits + 1] (a saved outfit; one past the last adds one)
--   "level"  a whole number in [1, 30] (a pass track level)
--   "bool"   true or false
--   "uids"   1 to Plot.MANY_MAX piece uids (whole numbers 1 .. 1e9) joined by ",", none twice (Build mode's Select tool)
--   "offset" a whole number in [-400, 400] (a group moved or copied, in studs)
--   "layout" a whole number in [1, Tuning.LayoutSlots] (a saved layout's slot)
--   "any"    anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.
local Traits = require(script.Parent.Parent.Data.Traits)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Track = require(script.Parent.Parent.Data.Track)
local Tuning = require(script.Parent.Parent.Config.Tuning)

local Validate = {}

local UIDS_MAX = 300 -- (Logic/Plot.MANY_MAX: Validate doesn't require Plot, which requires far more)

local ACTIONS: { [string]: { [string]: string } } = {
	["plot.place"] = { id = "id", x = "coord", z = "coord", rot = "rot" },
	["plot.move"] = { i = "index", x = "coord", z = "coord", rot = "rot" },
	["plot.store"] = { i = "index" },
	["plot.paint"] = { id = "id", cells = "cells" },
	["plot.unpaint"] = { cells = "cells", kind = "tiles" },
	["plot.fence"] = { id = "id", edges = "edges" },
	["plot.unfence"] = { edges = "edges" },
	["plot.replace"] = { i = "index", id = "id" },
	["plot.clear"] = { what = "group" },
	-- Build mode's Undo, Select tool and saved layouts (GAME_DESIGN 4.7; Logic/Undo, Plot.moveMany, Logic/Layout)
	["plot.undo"] = {},
	["plot.moveMany"] = { uids = "uids", dx = "offset", dz = "offset", rot = "rot" },
	["plot.storeMany"] = { uids = "uids" },
	["plot.copyMany"] = { uids = "uids", dx = "offset", dz = "offset", rot = "rot" },
	["layout.save"] = { slot = "layout" },
	["layout.quote"] = { slot = "layout" },
	["layout.load"] = { slot = "layout" },
	["inv.sell"] = { id = "id", n = "int" },
	["island.expand"] = {},
	["pal.work"] = { id = "int", uid = "int" },
	["pal.auto"] = { id = "int" },
	["pal.house"] = { id = "int", uid = "int", swap = "int" },
	["pal.sell"] = { id = "int" },
	-- every driftling of a rarity sold (Logic/Tree.sellRarity)
	["pal.sellAll"] = { r = "rarity" },
	["egg.hatch"] = { id = "int", swap = "int" },
	-- the bulk hatch (every egg of rarity `min` or rarer, the tree's or the bag's) and Auto Hatch's floor (0 off:
	-- Logic/Tree.bulk, setAuto)
	["egg.bulk"] = { min = "rarity", bag = "bool" },
	["egg.auto"] = { r = "int" },
	["breed.start"] = { uid = "int", a = "int", b = "int" },
	["breed.hatch"] = { uid = "int" },
	-- every ready Hatchery egg hatched (Logic/Breed.hatchAll)
	["breed.hatchAll"] = {},
	["founder.set"] = { skin = "small", hair = "small", style = "small", shirt = "small" },
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
	["quest.claim"] = {},
	["char.home"] = {},
	-- another player's island (the islands float apart in the sky since 2026-11-20): its plot
	["char.visit"] = { plot = "small" },
	-- the store (GAME_DESIGN 14): wearing a cosmetic or a title, buying from the rotating shop, the pass track's rewards,
	-- hatching a bag egg, VIP's daily gift
	["look.wear"] = { slot = "slot", id = "lookid" },
	-- the customization screen (GAME_DESIGN 14.1): the whole look, and a saved outfit
	["look.set"] = { look = "look" },
	["outfit.set"] = { i = "outfit", look = "look" },
	["title.set"] = { id = "lookid" },
	["shop.buy"] = { id = "id" },
	["track.claim"] = { lvl = "level", prem = "bool" },
	["bag.hatch"] = { id = "int", swap = "int" },
	["vip.daily"] = {},
	-- offline earnings collected ("free", or "double" while it's free) and the group checked again (GAME_DESIGN 14.3)
	["offline.collect"] = { mode = "collect" },
	-- the rewards for coming back and playing (Logic/Rewards; GAME_DESIGN 15)
	["reward.daily"] = {},
	["reward.play"] = { i = "small" },
	["reward.task"] = { i = "small" },
	["reward.bonus"] = {},
	["reward.spin"] = {},
	["reward.index"] = { i = "small" },
	["code.redeem"] = { code = "code" },
	["group.check"] = {},
	-- a leaderboard's top rows (Logic/Social.BOARDS; GAME_DESIGN 16)
	["lb.get"] = { board = "board" },
}
Validate.ACTIONS = ACTIONS

local SETTINGS = { pixel = true, music = true, sfx = true, pals = true, zoom = true, lang = true, text = true, loading = true }

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function check(kind: string, v: any): boolean
	if kind == "id" then
		return type(v) == "string" and #v >= 1 and #v <= 24 and string.match(v, "^[%w_]+$") ~= nil
	elseif kind == "int" then
		return isInt(v, 0, 1e6)
	elseif kind == "small" then
		return isInt(v, 1, 32)
	elseif kind == "rarity" then
		return isInt(v, 1, Traits.RMAX)
	elseif kind == "coord" then
		return isInt(v, -240, 160)
	elseif kind == "cells" or kind == "edges" then
		if type(v) ~= "string" or #v < 3 or #v > 40 * 13 then
			return false
		end
		local n = 0
		for part in string.gmatch(v, "[^;]+") do
			n += 1
			if kind == "cells" then
				local x, z = string.match(part, "^(%-?%d%d?%d?),(%-?%d%d?%d?)$")
				if x == nil or not isInt(tonumber(x), -240, 160) or not isInt(tonumber(z), -240, 160) then
					return false
				end
			else
				local x, z, r = string.match(part, "^(%-?%d%d?%d?),(%-?%d%d?%d?),(%d%d?)$")
				if x == nil or not isInt(tonumber(x), -240, 160) or not isInt(tonumber(z), -240, 160) or (r ~= "0" and r ~= "90") then
					return false
				end
			end
		end
		return n >= 1 and n <= 40 and string.match(v, ";;") == nil and string.sub(v, 1, 1) ~= ";" and string.sub(v, -1) ~= ";"
	elseif kind == "tiles" then
		return v == "path" or v == "water" or v == "all"
	elseif kind == "group" then
		return v == "pieces" or v == "tiles" or v == "fences"
	elseif kind == "rot" then
		return v == 0 or v == 90 or v == 180 or v == 270
	elseif kind == "index" then
		return isInt(v, 1, 8192)
	elseif kind == "key" then
		return type(v) == "string" and SETTINGS[v] == true
	elseif kind == "slot" then
		return type(v) == "string" and Cosmetics.bySlot[v] ~= nil
	elseif kind == "lookid" then
		return type(v) == "string" and #v <= 24 and (v == "" or string.match(v, "^[%w_]+$") ~= nil)
	elseif kind == "look" then
		return type(v) == "string" and #v <= 200 and string.match(v, "^[%w_%.|]*$") ~= nil
	elseif kind == "outfit" then
		return isInt(v, 1, Tuning.MaxOutfits + 1)
	elseif kind == "level" then
		return isInt(v, 1, Track.LEVELS)
	elseif kind == "bool" then
		return type(v) == "boolean"
	elseif kind == "uids" then
		if type(v) ~= "string" or #v < 1 or #v > UIDS_MAX * 10 or string.match(v, "^%d[%d,]*%d$") == nil and string.match(v, "^%d$") == nil then
			return false
		end
		if string.match(v, ",,") ~= nil then
			return false
		end
		local seen: { [string]: boolean } = {}
		local n = 0
		for part in string.gmatch(v, "[^,]+") do
			n += 1
			if n > UIDS_MAX or #part > 9 or string.sub(part, 1, 1) == "0" or seen[part] then
				return false
			end
			seen[part] = true
		end
		return n >= 1
	elseif kind == "offset" then
		return isInt(v, -400, 400)
	elseif kind == "layout" then
		return isInt(v, 1, Tuning.LayoutSlots)
	elseif kind == "code" then
		return type(v) == "string" and #v >= 1 and #v <= 32 and string.match(v, "^[%w_%- ]+$") ~= nil
	elseif kind == "collect" then
		return v == "free" or v == "double"
	elseif kind == "board" then
		return v == "coins" or v == "charm" or v == "hatched" or v == "driftlings" -- (Logic/Social.BOARDS)
	elseif kind == "any" then
		local t = type(v)
		return t == "string" and #v <= 32 or t == "number" or t == "boolean"
	end
	return false
end

-- Whether `action` is known and `payload` fits its schema exactly.
function Validate.request(action: any, payload: any): (boolean, string?)
	if type(action) ~= "string" then
		return false, "unknown_action"
	end
	local schema = ACTIONS[action]
	if schema == nil then
		return false, "unknown_action"
	end
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return false, "bad_payload"
	end
	local n = 0
	for k, v in payload do
		n += 1
		if type(k) ~= "string" then
			return false, "bad_payload"
		end
		local kind = schema[k]
		if kind == nil or not check(kind, v) then
			return false, "bad_payload"
		end
	end
	for k in schema do
		if payload[k] == nil then
			return false, "bad_payload"
		end
	end
	if n > 8 then
		return false, "bad_payload"
	end
	return true, nil
end

return Validate
