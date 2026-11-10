--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"     a string of 1-24 letters, digits or underscores (a building id ...)
--   "int"    a whole number in [0, 1e6] (a villager, driftling or piece id; 0: none)
--   "small"  a whole number in [1, 16] (a look index)
--   "isle"   a whole number in [1, 64] (an island of the sea chart)
--   "party"  up to three members "v<id>" / "p<id>" joined by commas ("" for the captain alone)
--   "act"    a battle move: "fight", "guard", "treat" or "flee"
--   "target" a wild driftling in the battle ("w1".."w9") or "" (none)
--   "key"    a settings key ("pixel")
--   "coord"  a whole number in [-64, 64] (a plot-local stud)
--   "rot"    a quarter turn: 0, 90, 180 or 270
--   "index"  a whole number in [1, 64] (a placed piece)
--   "any"    anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.

local Validate = {}

local ACTIONS: { [string]: { [string]: string } } = {
	["plot.place"] = { id = "id", x = "coord", z = "coord", rot = "rot" },
	["plot.move"] = { i = "index", x = "coord", z = "coord", rot = "rot" },
	["plot.store"] = { i = "index" },
	["plot.upgrade"] = { i = "index" },
	["island.expand"] = {},
	["folk.work"] = { id = "int", uid = "int" },
	["folk.dismiss"] = { id = "int" },
	["pal.work"] = { id = "int", uid = "int" },
	["pal.release"] = { id = "int" },
	["exp.start"] = { isle = "isle", party = "party" },
	["boat.upgrade"] = {},
	["exp.next"] = {},
	["exp.act"] = { act = "act", target = "target" },
	["exp.home"] = {},
	["founder.set"] = { skin = "small", hair = "small", style = "small", shirt = "small" },
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
	["char.home"] = {},
}
Validate.ACTIONS = ACTIONS

local ACTS = { fight = true, guard = true, treat = true, flee = true }
local SETTINGS = { pixel = true }

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
	elseif kind == "isle" then
		return isInt(v, 1, 64)
	elseif kind == "party" then
		if type(v) ~= "string" or #v > 40 then
			return false
		end
		if v == "" then
			return true
		end
		local n = 0
		for part in string.gmatch(v, "[^,]+") do
			n += 1
			if string.match(part, "^[vp]%d+$") == nil or #part > 8 then
				return false
			end
		end
		return n >= 1 and n <= 3 and string.match(v, ",,") == nil and string.sub(v, 1, 1) ~= "," and string.sub(v, -1) ~= ","
	elseif kind == "act" then
		return type(v) == "string" and ACTS[v] == true
	elseif kind == "target" then
		return v == "" or (type(v) == "string" and string.match(v, "^w%d$") ~= nil)
	elseif kind == "coord" then
		return isInt(v, -64, 64)
	elseif kind == "rot" then
		return v == 0 or v == 90 or v == 180 or v == 270
	elseif kind == "index" then
		return isInt(v, 1, 64)
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
