--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"     a string of 1-24 letters, digits or underscores (a building id ...)
--   "int"    a whole number in [0, 1e6] (a driftling or piece id; 0: none)
--   "small"  a whole number in [1, 16] (a look index)
--   "rarity" a whole number in [1, Traits.RMAX] (a driftling's rarity: 7)
--   "key"    a settings key ("pixel", "music", "sfx")
--   "coord"  a whole number in [-240, 64] (a plot-local stud: the biggest islands reach far north)
--   "rot"    a quarter turn: 0, 90, 180 or 270
--   "index"  a whole number in [1, 8192] (a placed piece: pieces, tiles and fences)
--   "cells"  1 to 40 cells "x,z" joined by ";", each a coord (path or water tiles drawn or erased: Logic/Plot.paint)
--   "edges"  1 to 40 edges "x,z,r" joined by ";", each a coord and r 0 or 90 (fences drawn or taken down: Plot.fence)
--   "tiles"  which tiles an eraser takes up: "path", "water" or "all"
--   "group"  what Build mode's Remove all takes away: "pieces", "tiles" or "fences"
--   "slot"   a cosmetics slot (Data/Cosmetics.SLOTS: "hat", "face", "neck", "back", "hand", "top")
--   "lookid" a string of 0-24 letters, digits or underscores (a cosmetic or a title; "" for none)
--   "level"  a whole number in [1, 30] (a pass track level)
--   "bool"   true or false
--   "any"    anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.
local Traits = require(script.Parent.Parent.Data.Traits)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Track = require(script.Parent.Parent.Data.Track)

local Validate = {}

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
	["inv.sell"] = { id = "id", n = "int" },
	["island.expand"] = {},
	["pal.work"] = { id = "int", uid = "int" },
	["pal.auto"] = { id = "int" },
	["pal.house"] = { id = "int", uid = "int", swap = "int" },
	["pal.sell"] = { id = "int" },
	["egg.hatch"] = { id = "int", swap = "int" },
	["breed.start"] = { uid = "int", a = "int", b = "int" },
	["founder.set"] = { skin = "small", hair = "small", style = "small", shirt = "small" },
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
	["quest.claim"] = {},
	["char.home"] = {},
	-- the store (GAME_DESIGN 14): wearing a cosmetic or a title, buying from the rotating shop, the pass track's rewards,
	-- hatching a bag egg, VIP's daily gift
	["look.wear"] = { slot = "slot", id = "lookid" },
	["title.set"] = { id = "lookid" },
	["shop.buy"] = { id = "id" },
	["track.claim"] = { lvl = "level", prem = "bool" },
	["bag.hatch"] = { id = "int", swap = "int" },
	["vip.daily"] = {},
}
Validate.ACTIONS = ACTIONS

local SETTINGS = { pixel = true, music = true, sfx = true }

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function check(kind: string, v: any): boolean
	if kind == "id" then
		return type(v) == "string" and #v >= 1 and #v <= 24 and string.match(v, "^[%w_]+$") ~= nil
	elseif kind == "int" then
		return isInt(v, 0, 1e6)
	elseif kind == "small" then
		return isInt(v, 1, 16)
	elseif kind == "rarity" then
		return isInt(v, 1, Traits.RMAX)
	elseif kind == "coord" then
		return isInt(v, -240, 64)
	elseif kind == "cells" or kind == "edges" then
		if type(v) ~= "string" or #v < 3 or #v > 40 * 13 then
			return false
		end
		local n = 0
		for part in string.gmatch(v, "[^;]+") do
			n += 1
			if kind == "cells" then
				local x, z = string.match(part, "^(%-?%d%d?%d?),(%-?%d%d?%d?)$")
				if x == nil or not isInt(tonumber(x), -240, 64) or not isInt(tonumber(z), -240, 64) then
					return false
				end
			else
				local x, z, r = string.match(part, "^(%-?%d%d?%d?),(%-?%d%d?%d?),(%d%d?)$")
				if x == nil or not isInt(tonumber(x), -240, 64) or not isInt(tonumber(z), -240, 64) or (r ~= "0" and r ~= "90") then
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
	elseif kind == "level" then
		return isInt(v, 1, Track.LEVELS)
	elseif kind == "bool" then
		return type(v) == "boolean"
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
