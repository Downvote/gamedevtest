--!strict
-- What a founder can look like (Types.Look indexes these). Pure. Palette keys. The skin, hair, eye and shirt colours,
-- the hair styles, bangs, aprons and the accessory colours are free; the pieces worn in Data/Cosmetics' slots are
-- owned first (GAME_DESIGN 14).
--   More of each since the request of 2026-11-14 ("make much more cosmetics"), and Random Bakery's whole "My baker"
--   screen since 2026-11-20 ("Port the entire character customization menu from the bakery game to this game, such
--   accessory colors and other features, along with the accessories it has"): eleven skins, seventeen hair colours,
--   nineteen styles, eighteen shirt colours, then the bakery's bangs, a second hair colour (the middle of the fringe),
--   an eye colour and the other eye's, its aprons, a colour for each piece worn and a turn for what is in the hand.
--   New entries only ever go on the end of a list (a save keeps an index).
-- Each list has its names beside it (`names.<list>[i]`, what the customization screen calls an option).
--
-- Accessory colours (the bakery's "Colour each accessory"): every slot a piece is worn in (hat, face, neck, back, hand,
-- top) and the apron carry a tint, Types.Look's hatTint .. apronTint, an index into TINTS (1 Original: the piece's own
-- colours). A tinted piece takes the tint for its main colour and keeps its accent, shines and gems (`tinted`: a
-- one-colour piece takes the tint all over, an accent that is a darker tone of the main colour takes the tint's darker
-- tone, an accent that is the tint takes the piece's own colour). The rainbow pieces take none (Data/Cosmetics
-- `rainbow`).
--
-- The "Founder" Player attribute (PlotService sets it; every client draws that player's founder from it) and a saved
-- outfit are encode(look):
--   "skin.hair.style.shirt"                                   (the first four, always)
--   ".bangs.hair2.eye.eye2.apron.turn"                        (only when one of them is not its default)
--   "|hat|face|neck|back|hand|top"                            (ids, "" for none; only when anything is worn or tinted)
--   "|tints"                                                  (a character a tint slot in TINT_FIELDS' order, TINTS'
--                                                              `code`; only when anything is tinted)
-- so every string from before reads as it was made.
local SKIN: { string } = { "skin1", "skin2", "skin3", "skin4", "skin5", "skin6", "yellow", "green", "sky_day", "purple", "pink" }
local SKIN_NAMES: { string } = { "Fair", "Light", "Tan", "Deep", "Dark", "Rosy", "Classic", "Mint", "Sky", "Lilac", "Rose" }
local HAIR: { string } = {
	"hair_brown", "hair_black", "hair_blond", "hair_red", "hair_blue", "pink", "teal", "purple", "snow", "rock",
	"chocolate", "choco_dark", "steel", "berry_red", "green", "orange", "hair_pink",
}
local HAIR_NAMES: { string } = {
	"Brown", "Black", "Blond", "Red", "Blue", "Pink", "Teal", "Purple", "Snow", "Grey",
	"Auburn", "Dark brown", "Silver", "Cherry", "Mint", "Ginger", "Bubblegum",
}
-- hair styles (Models/CharacterModels draws them; "bald" none at all)
local STYLES: { string } = {
	"short", "long", "bun", "spiky", "curly", "pony", "twintails", "mohawk", "bob", "braid",
	"pigtails", "afro", "sideswept", "spacebuns", "wavy", "pixie", "sidepony", "mullet", "bald",
}
local STYLE_NAMES: { string } = {
	"Short", "Long", "Bun", "Spiky", "Curly", "Ponytail", "Twin tails", "Mohawk", "Bob", "Braid",
	"Pigtails", "Afro", "Side swept", "Space buns", "Wavy", "Pixie", "Side ponytail", "Mullet", "Bald",
}
local SHIRT: { string } = {
	"blue", "green", "orange", "purple", "pink", "berry_red", "yellow", "white", "teal", "coral", "cream", "black",
	"moss", "cherry", "gold", "sky_day", "chocolate", "steel_dark",
}
local SHIRT_NAMES: { string } = {
	"Blue", "Green", "Orange", "Purple", "Pink", "Cherry", "Lemon", "White", "Teal", "Coral", "Cream", "Black",
	"Moss", "Blossom", "Gold", "Sky", "Cocoa", "Slate",
}
-- the eyes (both, or the left one when the other eye differs)
local EYES: { string } = {
	"black", "choco_dark", "chocolate", "r_uncommon", "r_rare", "blue", "sky_night", "steel_dark", "r_epic", "r_mythic",
	"berry_red", "r_legend", "gold",
}
local EYE_NAMES: { string } = {
	"Black", "Brown", "Hazel", "Green", "Blue", "Sky", "Navy", "Grey", "Violet", "Pink", "Red", "Amber", "Gold",
}
-- the front of the hair, whatever the style ("auto": the style's own)
export type Option = { id: string, name: string, color: string?, accent: string?, pattern: string?, shade: string?, code: string? }
local BANGS: { Option } = {
	{ id = "auto", name = "Hair's own" },
	{ id = "blunt", name = "Blunt" },
	{ id = "sidepart", name = "Side part" },
	{ id = "parted", name = "Parted" },
	{ id = "wispy", name = "Wispy" },
	{ id = "pointy", name = "Pointy" },
	{ id = "swoop", name = "Swoop" },
	{ id = "cropped", name = "Cropped" },
	{ id = "three", name = "Three strands" },
	{ id = "none", name = "None" },
}
-- aprons over the shirt (the bakery's): pattern "plain" (a pocket), "stripes", "bands", "dots", "cloak" (a ragged
-- cloak in its place), "corn" (candy corn's three bands); `color` the body, `accent` the pattern
local APRONS: { Option } = {
	{ id = "none", name = "No apron", pattern = "none" },
	{ id = "cream", name = "Cream", color = "cream", pattern = "plain" },
	{ id = "white", name = "White", color = "white", pattern = "plain" },
	{ id = "pink", name = "Pink", color = "pink", pattern = "plain" },
	{ id = "cherry", name = "Cherry", color = "berry_red", pattern = "plain" },
	{ id = "sky", name = "Sky", color = "sky_day", pattern = "plain" },
	{ id = "mint", name = "Mint", color = "green", pattern = "plain" },
	{ id = "lemon", name = "Lemon", color = "yellow", pattern = "plain" },
	{ id = "cocoa", name = "Cocoa", color = "chocolate", pattern = "plain" },
	{ id = "candy", name = "Candy stripe", color = "pink", accent = "white", pattern = "stripes" },
	{ id = "sailor", name = "Sailor stripe", color = "blue", accent = "white", pattern = "stripes" },
	{ id = "picnic", name = "Picnic bands", color = "berry_red", accent = "white", pattern = "bands" },
	{ id = "dotty", name = "Polka dots", color = "pink", accent = "white", pattern = "dots" },
	{ id = "minty_dots", name = "Mint dots", color = "green", accent = "cream", pattern = "dots" },
	{ id = "tattered_cloak", name = "Tattered Cloak", color = "black", accent = "purple", pattern = "cloak" },
	{ id = "candy_corn", name = "Candy Corn", color = "orange", accent = "yellow", pattern = "corn" },
}
-- Accessory colours: Original, then 20 palette colours, the rainbow then the neutrals. `code`: the tint's character in
-- a look's code (stable, never reused); `shade`: its darker second tone (what a piece's darker tone of its own colour
-- becomes, TONES).
-- stylua: ignore start
local TINTS: { Option } = {
	{ id = "orig", name = "Original", code = "0" },
	{ id = "red", name = "Red", color = "berry_red", shade = "plate_lacquer", code = "a" },
	{ id = "ruby", name = "Ruby", color = "plate_lacquer", shade = "choco_dark", code = "b" },
	{ id = "orange", name = "Orange", color = "orange", shade = "wood", code = "c" },
	{ id = "yellow", name = "Yellow", color = "yellow", shade = "gold", code = "d" },
	{ id = "gold", name = "Gold", color = "gold", shade = "plate_gold", code = "e" },
	{ id = "green", name = "Green", color = "green", shade = "r_uncommon", code = "f" },
	{ id = "sky", name = "Sky Blue", color = "sky_day", shade = "blue", code = "g" },
	{ id = "blue", name = "Blue", color = "blue", shade = "sky_night", code = "h" },
	{ id = "navy", name = "Navy", color = "sky_night", shade = "black", code = "i" },
	{ id = "violet", name = "Violet", color = "r_epic", shade = "purple", code = "j" },
	{ id = "lilac", name = "Lilac", color = "purple", shade = "r_epic", code = "k" },
	{ id = "pink", name = "Pink", color = "pink", shade = "r_mythic", code = "l" },
	{ id = "hot_pink", name = "Hot Pink", color = "r_mythic", shade = "berry_red", code = "m" },
	{ id = "brown", name = "Brown", color = "chocolate", shade = "choco_dark", code = "n" },
	{ id = "dark_brown", name = "Dark brown", color = "choco_dark", shade = "black", code = "o" },
	{ id = "cream", name = "Cream", color = "cream", shade = "sponge", code = "p" },
	{ id = "white", name = "White", color = "white", shade = "cream", code = "q" },
	{ id = "silver", name = "Silver", color = "steel", shade = "steel_dark", code = "r" },
	{ id = "grey", name = "Grey", color = "street", shade = "black", code = "s" },
	{ id = "black", name = "Black", color = "black", shade = "street", code = "t" },
}
-- an accent that is the darker tone of its piece's own colour (under a tint it takes the tint's `shade`)
local TONES: { [string]: string } = {
	gold = "plate_gold", yellow = "gold", steel = "steel_dark", wood = "wood_dark", chocolate = "choco_dark",
	blue = "sky_night", white = "cream", pink = "r_mythic",
}
-- stylua: ignore end
-- What is in the hand, turned about the fist: degrees forward (no further than 90 either way, or long pieces reach the
-- ground), in the order the screen's Turn button steps through them.
local TURNS: { Option } = {
	{ id = "0", name = "Straight" },
	{ id = "45", name = "Tipped forward" },
	{ id = "90", name = "Flat forward" },
	{ id = "-90", name = "Flat back" },
	{ id = "-45", name = "Tipped back" },
}

-- the slots a look's worn pieces go in, in the attribute's order
local WORN: { string } = { "hat", "face", "neck", "back", "hand", "top" }
-- the tint fields, in the order of their characters in the code (each worn slot's, then the apron's)
local TINT_FIELDS: { string } = { "hatTint", "faceTint", "neckTint", "backTint", "handTint", "topTint", "apronTint" }
local TINT_OF: { [string]: string } = {
	hat = "hatTint", face = "faceTint", neck = "neckTint", back = "backTint", hand = "handTint", top = "topTint", apron = "apronTint",
}
-- the extra fields after the first four, in their order, with their defaults (0: none / the same)
local EXTRA: { string } = { "bangs", "hair2", "eye", "eye2", "apron", "turn" }
local EXTRA_DEFAULT: { [string]: number } = { bangs = 1, hair2 = 0, eye = 1, eye2 = 0, apron = 1, turn = 1 }

local TINT_BY_CODE: { [string]: number } = {}
local SHADE_OF: { [string]: string } = {}
for i, o in TINTS do
	TINT_BY_CODE[o.code :: string] = i
	if o.color and o.shade then
		SHADE_OF[o.color] = o.shade
	end
end

local function num(look: { [string]: any }, key: string): number
	local v = look[key]
	return if type(v) == "number" then v else EXTRA_DEFAULT[key] or 1
end

local function encode(look: { [string]: any }): string
	local s = string.format("%d.%d.%d.%d", look.skin, look.hair, look.style, look.shirt)
	local extra = false
	for _, k in EXTRA do
		if num(look, k) ~= EXTRA_DEFAULT[k] then
			extra = true
		end
	end
	if extra then
		local parts: { string } = {}
		for i, k in EXTRA do
			parts[i] = string.format("%d", num(look, k))
		end
		s ..= "." .. table.concat(parts, ".")
	end
	local codes: { string } = {}
	local tinted = false
	for i, f in TINT_FIELDS do
		local t = look[f]
		local o = if type(t) == "number" then TINTS[t] else nil
		codes[i] = if o then o.code :: string else "0"
		if codes[i] ~= "0" then
			tinted = true
		end
	end
	local parts: { string } = {}
	local any = false
	for i, slot in WORN do
		local v = look[slot]
		parts[i] = if type(v) == "string" then v else ""
		if parts[i] ~= "" then
			any = true
		end
	end
	if any or tinted then
		s ..= "|" .. table.concat(parts, "|")
	end
	if tinted then
		s ..= "|" .. table.concat(codes, "")
	end
	return s
end

-- The look in an attribute string, or nil (the indices are not checked against the lists: the caller clamps them).
local function decode(s: string): { [string]: any }?
	local base, rest = string.match(s, "^([%d%.]+)(.*)$")
	if base == nil then
		return nil
	end
	local nums: { number } = {}
	for d in string.gmatch(base, "[^%.]+") do
		local n = tonumber(d)
		if n == nil or n ~= math.floor(n) then
			return nil
		end
		table.insert(nums, n)
	end
	if #nums ~= 4 and #nums ~= 4 + #EXTRA then
		return nil
	end
	local look: { [string]: any } = { skin = nums[1], hair = nums[2], style = nums[3], shirt = nums[4] }
	for i, k in EXTRA do
		look[k] = nums[4 + i] or EXTRA_DEFAULT[k]
	end
	if rest and string.sub(rest, 1, 1) == "|" then
		local i = 0
		for part in string.gmatch(string.sub(rest, 2) .. "|", "([^|]*)|") do
			i += 1
			local slot = WORN[i]
			if slot then
				if part ~= "" and string.match(part, "^[%w_]+$") then
					look[slot] = part
				end
			elseif i == #WORN + 1 then
				-- the tints: a character a field
				for k, f in TINT_FIELDS do
					local t = TINT_BY_CODE[string.sub(part, k, k)]
					if t and t > 1 then
						look[f] = t
					end
				end
			end
		end
	end
	return look
end

-- A piece's main and accent colours (`c`, `a`) under tint colour `t` (nil: its own colours).
local function tinted(c: string, a: string, t: string?): (string, string)
	if t == nil or t == c then
		return c, a
	elseif a == c then
		return t, t
	elseif TONES[c] == a then
		return t, SHADE_OF[t] or t
	elseif a == t then
		return t, c
	end
	return t, a
end

-- The palette key slot `slot`'s piece (or the apron) is tinted with in `look`, nil for its own colours.
local function tintOf(look: { [string]: any }, slot: string): string?
	local f = TINT_OF[slot]
	local t = if f then look[f] else nil
	local o = if type(t) == "number" and t > 1 then TINTS[t] else nil
	return if o then o.color else nil
end

-- The degrees what is in the hand is turned forward (Types.Look.turn).
local function turnOf(look: { [string]: any }): number
	local t = look.turn
	local o = if type(t) == "number" then TURNS[t] else nil
	return if o then tonumber(o.id) or 0 else 0
end

local function namesOf(list: { Option }): { string }
	local out: { string } = {}
	for i, o in list do
		out[i] = o.name
	end
	return out
end

return table.freeze({
	skin = SKIN,
	hair = HAIR,
	styles = STYLES,
	shirt = SHIRT,
	eyes = EYES,
	bangs = BANGS,
	aprons = APRONS,
	tints = TINTS,
	turns = TURNS,
	names = table.freeze({
		skin = SKIN_NAMES,
		hair = HAIR_NAMES,
		styles = STYLE_NAMES,
		shirt = SHIRT_NAMES,
		eyes = EYE_NAMES,
		bangs = namesOf(BANGS),
		aprons = namesOf(APRONS),
		tints = namesOf(TINTS),
		turns = namesOf(TURNS),
	}),
	worn = WORN,
	extra = EXTRA,
	extraDefault = EXTRA_DEFAULT,
	tintFields = TINT_FIELDS,
	tintField = TINT_OF,
	encode = encode,
	decode = decode,
	tinted = tinted,
	tintOf = tintOf,
	turnOf = turnOf,
})
