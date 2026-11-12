--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"     a string of 1-24 letters, digits or underscores (a building id ...)
--   "int"    a whole number in [0, 1e6] (a driftling or piece id; 0: none)
--   "small"  a whole number in [1, 16] (a look index)
--   "rarity" a whole number in [1, 5] (a driftling's rarity)
--   "grow"   a Tree of Life upgrade: "luck" or "speed"
--   "key"    a settings key ("pixel", "music")
--   "coord"  a whole number in [-64, 64] (a plot-local stud)
--   "rot"    a quarter turn: 0, 90, 180 or 270
--   "index"  a whole number in [1, 1024] (a placed piece: pieces and path tiles)
--   "cells"  1 to 40 cells "x,z" joined by ";", each a coord (path tiles drawn or erased: Logic/Plot.paint)
--   "any"    anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.

local Validate = {}

local ACTIONS: { [string]: { [string]: string } } = {
	["plot.place"] = { id = "id", x = "coord", z = "coord", rot = "rot" },
	["plot.move"] = { i = "index", x = "coord", z = "coord", rot = "rot" },
	["plot.store"] = { i = "index" },
	["plot.paint"] = { id = "id", cells = "cells" },
	["plot.unpaint"] = { cells = "cells" },
	["plot.replace"] = { i = "index", id = "id" },
	["island.expand"] = {},
	["pal.work"] = { id = "int", uid = "int" },
	["pal.house"] = { id = "int", uid = "int", swap = "int" },
	["pal.sell"] = { id = "int" },
	["pen.sell"] = { r = "rarity" },
	["pen.best"] = {},
	["tree.upgrade"] = { what = "grow" },
	["breed.start"] = { uid = "int", a = "int", b = "int" },
	["founder.set"] = { skin = "small", hair = "small", style = "small", shirt = "small" },
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
	["quest.claim"] = {},
	["char.home"] = {},
}
Validate.ACTIONS = ACTIONS

local SETTINGS = { pixel = true, music = true }

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
		return isInt(v, 1, 5)
	elseif kind == "grow" then
		return v == "luck" or v == "speed"
	elseif kind == "coord" then
		return isInt(v, -64, 64)
	elseif kind == "cells" then
		if type(v) ~= "string" or #v < 3 or #v > 40 * 10 then
			return false
		end
		local n = 0
		for part in string.gmatch(v, "[^;]+") do
			n += 1
			local x, z = string.match(part, "^(%-?%d%d?),(%-?%d%d?)$")
			if x == nil or not isInt(tonumber(x), -64, 64) or not isInt(tonumber(z), -64, 64) then
				return false
			end
		end
		return n >= 1 and n <= 40 and string.match(v, ";;") == nil and string.sub(v, 1, 1) ~= ";" and string.sub(v, -1) ~= ";"
	elseif kind == "rot" then
		return v == 0 or v == 90 or v == 180 or v == 270
	elseif kind == "index" then
		return isInt(v, 1, 1024)
	elseif kind == "key" then
		return type(v) == "string" and SETTINGS[v] == true
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
