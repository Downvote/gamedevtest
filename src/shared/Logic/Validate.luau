--!strict
-- Payload checks for every client request (docs/ARCHITECTURE.md 7.3). Pure. Router refuses anything that does not
-- pass with "bad_payload" before a service sees it. A schema maps field -> kind:
--   "id"    a string of 1-24 letters, digits or underscores (genre, topic, platform ids...)
--   "axis"  one of Types.Axis
--   "skill" one of Types.SkillKey
--   "size"  a Tuning.Sizes key
--   "int"   a whole number in [0, 1e6]
--   "small" a whole number in [1, 16]
--   "key"   a settings key ("pixel")
--   "any"   anything (the settings value; its service checks it)
-- Unknown fields are refused too, so a payload carries exactly what its action reads.
local Tuning = require(script.Parent.Parent.Config.Tuning)

local Validate = {}

local ACTIONS: { [string]: { [string]: string } } = {
	["project.start"] = { genre = "id", topic = "id", platform = "id", size = "size", focus = "axis", seed = "int" },
	["project.release"] = {},
	["staff.hire"] = { i = "small" },
	["staff.fire"] = { id = "int" },
	["staff.train"] = { id = "int", skill = "skill" },
	["staff.party"] = {},
	["research.genre"] = { id = "id" },
	["research.topic"] = { id = "id" },
	["office.move"] = {},
	["office.ad"] = {},
	["settings.set"] = { k = "key", v = "any" },
	["tut.next"] = {},
}
Validate.ACTIONS = ACTIONS

local AXIS = { fun = true, ideas = true, graphics = true, sound = true }
local SKILL = { code = true, design = true, art = true, sound = true }
local SETTINGS = { pixel = true }

local function isInt(v: any, lo: number, hi: number): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

local function check(kind: string, v: any): boolean
	if kind == "id" then
		return type(v) == "string" and #v >= 1 and #v <= 24 and string.match(v, "^[%w_]+$") ~= nil
	elseif kind == "axis" then
		return type(v) == "string" and AXIS[v] == true
	elseif kind == "skill" then
		return type(v) == "string" and SKILL[v] == true
	elseif kind == "size" then
		return type(v) == "string" and Tuning.Sizes[v] ~= nil
	elseif kind == "int" then
		return isInt(v, 0, 1e6)
	elseif kind == "small" then
		return isInt(v, 1, 16)
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
