--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"    a string of 1-24 letters, digits or underscores (a decor id ...)
--   "upgrade" "speed" or "luck"
--   "slot"  a minigame slot: 1, 2 or 3
--   "bit"   0 or 1
--   "int"   a whole number in [0, 1e6]
--   "small" a whole number in [1, 16] (a board index, a look index)
--   "key"   a settings key ("pixel")
--   "coord" a whole number in [-64, 64] (a plot-local stud)
--   "rot"   a quarter turn: 0, 90, 180 or 270
--   "index" a whole number in [1, 64] (a placed piece)
--   "any"   anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.

local Validate = {}

local ACTIONS: { [string]: { [string]: string } } = {
	["game.make"] = { a = "small", b = "small", c = "small" },
	["game.launch"] = {},
	["micro.start"] = { slot = "slot" },
	["micro.finish"] = { token = "int", won = "bit" },
	["upgrade.buy"] = { k = "upgrade" },
	["founder.set"] = { skin = "small", hair = "small", style = "small", shirt = "small" },
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
	["plot.buy"] = { id = "id" },
	["plot.place"] = { id = "id", x = "coord", z = "coord", rot = "rot" },
	["plot.move"] = { i = "index", x = "coord", z = "coord", rot = "rot" },
	["plot.store"] = { i = "index" },
	["char.home"] = {},
}
Validate.ACTIONS = ACTIONS

local UPGRADES = { speed = true, luck = true }
local SETTINGS = { pixel = true }

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function check(kind: string, v: any): boolean
	if kind == "id" then
		return type(v) == "string" and #v >= 1 and #v <= 24 and string.match(v, "^[%w_]+$") ~= nil
	elseif kind == "upgrade" then
		return type(v) == "string" and UPGRADES[v] == true
	elseif kind == "slot" then
		return isInt(v, 1, 3)
	elseif kind == "bit" then
		return v == 0 or v == 1
	elseif kind == "int" then
		return isInt(v, 0, 1e6)
	elseif kind == "small" then
		return isInt(v, 1, 16)
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
