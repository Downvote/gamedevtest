--!strict
-- What a founder can look like (Types.Look indexes these). Pure. Palette keys. The skin, hair and shirt colours and
-- the hair styles are free; the pieces worn in Data/Cosmetics' slots are owned first (GAME_DESIGN 14).
--   More of each since the request of 2026-11-14 ("make much more cosmetics"): six skins, ten hair colours, ten styles,
--   fifteen shirt colours. New entries only ever go on the end (a save keeps an index).
-- The "Founder" Player attribute (PlotService sets it; every client draws that player's founder from it): encode(look)
-- = "skin.hair.style.shirt", and when they wear anything, "|hat|face|neck|back|hand|top" after it (ids, "" for none).
local SKIN: { string } = { "skin1", "skin2", "skin3", "skin4", "skin5", "skin6" }
local HAIR: { string } = { "hair_brown", "hair_black", "hair_blond", "hair_red", "hair_blue", "pink", "teal", "purple", "snow", "rock" }
-- hair styles (Models/CharacterModels draws them)
local STYLES: { string } = { "short", "long", "bun", "spiky", "curly", "pony", "twintails", "mohawk", "bob", "braid" }
local SHIRT: { string } = { "blue", "green", "orange", "purple", "pink", "berry_red", "yellow", "white", "teal", "coral", "cream", "black", "moss", "cherry", "gold" }
-- the slots a look's worn pieces go in, in the attribute's order
local WORN: { string } = { "hat", "face", "neck", "back", "hand", "top" }

local function encode(look: { [string]: any }): string
	local s = string.format("%d.%d.%d.%d", look.skin, look.hair, look.style, look.shirt)
	local parts: { string } = {}
	local any = false
	for i, slot in WORN do
		local v = look[slot]
		parts[i] = if type(v) == "string" then v else ""
		if parts[i] ~= "" then
			any = true
		end
	end
	return if any then s .. "|" .. table.concat(parts, "|") else s
end

-- The look in an attribute string, or nil (the indices are not checked against the lists: the caller clamps them).
local function decode(s: string): { [string]: any }?
	local base, rest = string.match(s, "^([%d%.]+)(.*)$")
	if base == nil then
		return nil
	end
	local k, h, st, sh = string.match(base, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if k == nil then
		return nil
	end
	local look: { [string]: any } = { skin = tonumber(k), hair = tonumber(h), style = tonumber(st), shirt = tonumber(sh) }
	if rest and string.sub(rest, 1, 1) == "|" then
		local i = 0
		for part in string.gmatch(string.sub(rest, 2) .. "|", "([^|]*)|") do
			i += 1
			local slot = WORN[i]
			if slot and part ~= "" and string.match(part, "^[%w_]+$") then
				look[slot] = part
			end
		end
	end
	return look
end

return table.freeze({ skin = SKIN, hair = HAIR, styles = STYLES, shirt = SHIRT, worn = WORN, encode = encode, decode = decode })
