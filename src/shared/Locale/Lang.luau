--!strict
-- Lang: the game's words in the player's language (docs/LOCALIZATION.md; the bakery's own module, Random Bakery's
-- Locale/Lang, ported 2026-11-20 for the request "like the bakery game, make translations for different languages").
-- Pure (no Instances).
--
-- The game is written in English and stays English everywhere it is decided (code, the server, saves, the sims); a
-- client shows it in its player's language: every word goes through Lang.t where it is put on screen or measured
-- (UIKit.text and the label writes, UIKit.textWidth / lines, Pixel/PixelText as a safety net, the world's tags). The
-- language is the player's choice in Settings ("auto": their Roblox language when the game has it, else English).
--
-- A language is a generated table (Locale/<code>, scripts/gen_locale.py from locale/<code>.json) of English -> its
-- words. A key is a whole string as the game shows it, or a template: "{1} of {2} bought", whose {n} stand for what
-- changes (numbers, names, a smaller sentence); a translation may move them ("Comprados: {1} de {2}"). Lang.t(s):
--   1. the exact string; words in capitals as the table has them; words with spaces round them (the spaces kept);
--   2. a count, a rank or a number around a known name ("2x {name}", "{name} ★3", "{name} 0.5%");
--   3. else the most specific template that matches it (the one with the most fixed letters), each part a {n} took
--      translated in turn (a name, a number left as it is, a smaller sentence); a short template ("Your {1}", "{1} and
--      {2}") only around words that translate, or numbers;
--   4. else the same affixes round any words that translate; a text of several lines or sentences, each on its own
--      (when one of them is known); a name made of known names, each translated;
--   5. else s as it is (English).
-- Results are cached; what Lang.t returns is never translated again (a label's words measured twice, a word that is
-- the same in both languages).
--
-- API
--   Lang.LIST                     { { code, name, pixel } } English first, then by players (docs/LOCALIZATION.md 1)
--   Lang.byCode[code]             that entry; `pixel`: drawn in the pixel font (false: the native font, for scripts
--                                 the pixel font has no letters for)
--   Lang.code(): string           the language on show ("en" ...)
--   Lang.pixel(): boolean         whether it is drawn in the pixel font
--   Lang.set(code, words?): boolean  shows `code` (unknown codes: English); true when it changed. `words` stands in
--                                 for its table (the specs)
--   Lang.resolve(choice, localeId): string   a Settings choice ("auto" or a code) and the player's Roblox LocaleId
--                                 ("es-es", "pt-br", "zh-cn" ...) -> the code to show
--   Lang.t(s): string             s in the language on show. A key may carry a context after "@@" ("Back@@slot",
--                                 the Looks screen's back slot, apart from the Back button): English shows the words
--                                 before it, a language its own key for it (else the words before it, translated)
--   Lang.f(template, ...): string the template's translation with {1}, {2} ... filled in with the values as they are
--                                 (names; a value to translate goes through t first), never translated again
--   Lang.fmt(template, { key = value }): string   the same with named slots ({name}, {a})
--   Lang.an(anTpl, aTpl, name, ...): string   an English sentence whose article goes with a name ("An {1} egg ...",
--                                 "A {1} egg ..."): the template for the name's first letter, {1} the name in lower case
--                                 in English and translated in any other language (each has both keys), more values
--                                 for {2} ... as they are
--   Lang.list(items): string     items already in the language on show as one list ("a, b and c" with the language's
--                                 own comma and "and": the keys ", @@list" and " and @@list"), kept
--   Lang.produced(s): boolean     s is a translation t gave (a label's words already in the language on show)
--   Lang.keep(s): string          s, marked as already in the language on show (a piece of a translation, such as
--                                 the letters typed so far): never translated again
--   Lang.needsScript(s): boolean  s has letters the pixel font cannot draw (Thai, Arabic, Chinese ...)
--   Lang.estimateWidth(s, em)     about how wide a line is in a native font em px tall
--   Lang.Changed                  Signal(code) after a change
--   Lang.seen                     nil, or a table that collects every string asked for (the string catalog's capture,
--                                 docs/LOCALIZATION.md 4: harness only)
local Types = require(script.Parent.Parent.Types)
local Util = require(script.Parent.Parent.Logic.Util)

export type Info = { code: string, name: string, pixel: boolean }

local Lang = {}

Lang.LIST = {
	{ code = "en", name = "English", pixel = true },
	{ code = "id", name = "Bahasa Indonesia", pixel = true },
	{ code = "es", name = "Español", pixel = true },
	{ code = "th", name = "ไทย", pixel = false },
	{ code = "pt", name = "Português", pixel = true },
	{ code = "ar", name = "العربية", pixel = false },
	{ code = "ru", name = "Русский", pixel = true },
	{ code = "fr", name = "Français", pixel = true },
	{ code = "zh", name = "简体中文", pixel = false },
	{ code = "it", name = "Italiano", pixel = true },
} :: { Info }

local byCode: { [string]: Info } = {}
for _, info in Lang.LIST do
	byCode[info.code] = info
end
Lang.byCode = byCode

Lang.Changed = Util.Signal() :: Types.Signal<string>
Lang.seen = nil :: { [string]: boolean }?

type Template = {
	key: string,
	out: string,
	pattern: string,
	anchor: string, -- its longest fixed piece (a plain find before the pattern)
	letters: number, -- fixed letters (and a little for each fixed mark): the most specific template wins
	slots: { number }, -- the placeholder number of each capture, in order
	name: boolean, -- a name template (NAME_TEMPLATES): its capture must be a name the table knows (nameOf)
	lines: boolean, -- the key has line breaks (else no {n} of it takes one: a line is matched on its own)
	weak: boolean, -- under 5 fixed letters ("Your {1}", "{1} and {2}"): only around known words (or numbers)
}

local current = "en"
local exact: { [string]: string } = {}
local templates: { Template } = {}
-- trigram (the anchor's first 3 bytes) -> the templates with that anchor, most specific first
local index: { [string]: { Template } } = {}
local namePrefixes: { [string]: Template } = {} -- "Golden " -> the "Golden {1}" template
local cache: { [string]: string } = {}
local cached = 0
local done: { [string]: boolean } = {} -- what t returned: never translated again
local produced: { [string]: boolean } = {} -- what t returned in place of something else (a translation)
local CACHE_MAX = 6000
local SHORT = "\0short" -- the index key of the templates whose anchor is under three letters
-- a name template ("Golden {1}": a word before a name, only ever around a name that translates). None in this game
-- (a driftling's mutations are listed apart from its name); the bakery's mechanism kept for one that needs it.
local NAME_TEMPLATES: { [string]: boolean } = {}
local DEPTH_MAX = 3

local function escape(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function compile(key: string, out: string): Template?
	local pieces: { string } = {}
	local slots: { number } = {}
	local pos = 1
	while true do
		local a, b, n = string.find(key, "{(%d+)}", pos)
		if a == nil or b == nil then
			break
		end
		table.insert(pieces, string.sub(key, pos, a - 1))
		table.insert(slots, tonumber(n) or 1)
		pos = b + 1
	end
	if #slots == 0 then
		return nil
	end
	table.insert(pieces, string.sub(key, pos))
	-- a {n} glued to a letter ("Lv{1}", "{1}st", "{1}x", "{1}K") was a number: it only ever takes one
	local pattern = "^" .. escape(pieces[1])
	for i = 1, #slots do
		local tight = string.find(pieces[i], "%a$") ~= nil or string.find(pieces[i + 1], "^%a") ~= nil
		pattern ..= (if tight then "(%d[%d%.,:]*)" else "(.-)") .. escape(pieces[i + 1])
	end
	pattern ..= "$"
	local anchor, letters, marks = "", 0, 0
	for _, p in pieces do
		if #p > #anchor then
			anchor = p
		end
		local _, n = string.gsub(p, "%a", "")
		local _, m = string.gsub(p, "%p", "")
		letters += n
		marks += m
	end
	-- a template needs words of its own (not "{1}: {2}"), and an anchor to find it by (two letters will do: "Lv{1}",
	-- the island level, is kept on a short list every lookup reads)
	if letters < 2 or #anchor < 2 then
		return nil
	end
	return {
		key = key,
		out = out,
		pattern = pattern,
		anchor = anchor,
		letters = letters + marks * 0.1 + #anchor * 0.001,
		slots = slots,
		name = NAME_TEMPLATES[key] == true,
		weak = letters < 5,
		lines = string.find(key, "\n", 1, true) ~= nil,
	}
end

local function load(code: string): { [string]: string }
	if code == "en" then
		return {}
	end
	local ok, data = pcall(function(): any
		local mod = (script :: any).Parent:FindFirstChild(code)
		return if mod and mod:IsA("ModuleScript") then (require :: any)(mod) else nil
	end)
	return if ok and type(data) == "table" then data :: any else {}
end

function Lang.code(): string
	return current
end

function Lang.pixel(): boolean
	local info = byCode[current]
	return info == nil or info.pixel
end

function Lang.set(code: string, words: { [string]: string }?): boolean
	local c = if byCode[code] then code else "en"
	if c == current and words == nil then
		return false
	end
	current = c
	exact = {}
	templates = {}
	index = {}
	namePrefixes = {}
	cache = {}
	cached = 0
	done = {}
	produced = {}
	for key, out in words or load(c) do
		if type(key) == "string" and type(out) == "string" then
			local tpl = if string.find(key, "{%d+}") then compile(key, out) else nil
			if tpl then
				table.insert(templates, tpl)
				if tpl.name then
					namePrefixes[string.sub(key, 1, -4)] = tpl
				end
			else
				exact[key] = out
			end
		end
	end
	table.sort(templates, function(a: Template, b: Template): boolean
		if a.letters ~= b.letters then
			return a.letters > b.letters
		end
		return a.key < b.key
	end)
	for _, tpl in templates do
		local tri = if #tpl.anchor < 3 then SHORT else string.sub(tpl.anchor, 1, 3)
		local list = index[tri]
		if list == nil then
			list = {}
			index[tri] = list
		end
		table.insert(list, tpl)
	end
	Lang.Changed:Fire(c)
	return true
end

-- The language a Settings choice shows: a code as it is, "auto" (or nothing) the player's Roblox language when the
-- game has it (any Chinese is shown in Simplified Chinese), else English.
function Lang.resolve(choice: string?, localeId: string?): string
	if choice and choice ~= "auto" and byCode[choice] then
		return choice
	end
	local loc = string.lower(localeId or "")
	local base = string.match(loc, "^(%a%a)") or ""
	return if byCode[base] then base else "en"
end

local translate: (s: string, depth: number) -> string

-- A name the table knows (a building's, a piece's, a rarity's), with any name templates before it, in the language on
-- show; nil when s is anything else.
local function nameOf(s: string, depth: number): string?
	local hit = exact[s]
	if hit or depth > 4 then
		return hit
	end
	for prefix, tpl in namePrefixes do
		if string.sub(s, 1, #prefix) == prefix then
			local inner = nameOf(string.sub(s, #prefix + 1), depth + 1)
			if inner then
				return (string.gsub(tpl.out, "{1}", (string.gsub(inner, "%%", "%%%%"))))
			end
		end
	end
	return nil
end

local function viaTemplate(s: string, depth: number): string?
	-- the candidate templates: those whose anchor starts at one of s's trigrams, most specific first
	local seenList: { [{ Template }]: boolean } = {}
	local best: Template? = nil
	local bestCaps: { string }? = nil
	for i = 0, #s - 2 do
		local list = if i == 0 then index[SHORT] else index[string.sub(s, i, i + 2)]
		if list and not seenList[list] then
			seenList[list] = true
			for _, tpl in list do
				if best and tpl.letters <= best.letters then
					break
				end
				if string.find(s, tpl.anchor, 1, true) then
					local caps = table.pack(string.match(s, tpl.pattern))
					local ok = caps.n > 0 and caps[1] ~= nil
					if ok and not tpl.lines then
						for i = 1, caps.n do
							if string.find(caps[i], "\n", 1, true) then
								ok = false
								break
							end
						end
					end
					if ok and tpl.name then
						ok = nameOf(caps[1], 0) ~= nil
					elseif ok and tpl.weak then
						-- so "Your {1}" is "Your Lumber Camp", never the start of any sentence ("Your island ...")
						for i = 1, caps.n do
							local cap = caps[i]
							if not string.find(cap, "^[%d%s%p]*$") and exact[cap] == nil and translate(cap, depth + 1) == cap then
								ok = false
								break
							end
						end
					end
					if ok then
						best = tpl
						bestCaps = caps :: any
						break
					end
				end
			end
		end
	end
	if best == nil or bestCaps == nil then
		return nil
	end
	local vals: { [number]: string } = {}
	for i, slot in best.slots do
		local cap = bestCaps[i] or ""
		vals[slot] = if depth < DEPTH_MAX then translate(cap, depth + 1) else cap
	end
	return (string.gsub(best.out, "{(%d+)}", function(n: string): string
		return vals[tonumber(n) or 0] or ("{" .. n .. "}")
	end))
end

-- A count, a rank or a number around a name ("2x Veggie Patch", "#3 Coin Baron", "+10% Charm", "3/10 eggs",
-- "Goldtouched ★3", "Legendary 0.5%", "Rain 4:19", "Lumber Camp x3"): the name translated, the rest as it is.
local HEADS = { "^([%d,%.]+x )(.+)$", "^(#%d+ )(.+)$", "^([+%-]?[%d,%.]+%%? )(.+)$", "^(%d+/%d+ )(.+)$" }
local TAILS = { "^(.-)( ★%d+)$", "^(.-)( [+%-]?[%d,%.:/]+[%%x]?)$", "^(.-)( x[%d%.]+)$" }
local function viaAffix(s: string, depth: number, strict: boolean): string?
	if depth >= DEPTH_MAX then
		return nil
	end
	-- the head and the tail at once, so the name in between is translated whole ("2x Golden Apple ★3")
	local head: string?, body = nil, s
	for _, p in HEADS do
		local h, rest = string.match(s, p)
		if h and rest then
			head, body = h, rest
			break
		end
	end
	local name, tail: string? = body, nil
	for _, p in TAILS do
		local base, t = string.match(body, p)
		if base and t and base ~= "" then
			name, tail = base, t
			break
		end
	end
	-- a name starts with a capital ("Volume", "Éclair"), never a word of a sentence ("1 in 7")
	if (head == nil and tail == nil) or not string.find(name, "^[%u\195-\244]") then
		return nil
	end
	-- strict (before the templates): only around a known name, so "Coin Baron ★3" is never a template's
	local t = if strict then nameOf(name, 0) else translate(name, depth + 1)
	if t == nil or t == name then
		return nil
	end
	return (head or "") .. t .. (tail or "")
end

-- A capital letter's twin of a lower-case one (Latin-1, Latin Extended-A's œ, Cyrillic): string.upper only knows ASCII.
local function upper(s: string): string
	local out: { string } = {}
	for _, c in utf8.codes(s) do
		if c >= 0x61 and c <= 0x7A then
			c -= 0x20
		elseif (c >= 0xE0 and c <= 0xFE and c ~= 0xF7) or (c >= 0x430 and c <= 0x44F) then
			c -= 0x20
		elseif c >= 0x450 and c <= 0x45F then
			c -= 0x50
		elseif c == 0xFF then
			c = 0x178
		elseif c == 0x153 then
			c = 0x152
		end
		table.insert(out, utf8.char(c))
	end
	return table.concat(out)
end

-- Words in capitals ("COMMON", "NEW!"): the words as the tables have them (Title Case, then a capital first),
-- translated, in capitals.
local function viaCaps(s: string, depth: number): string?
	if depth >= DEPTH_MAX or string.find(s, "%l") or not string.find(s, "%u.*%u") or utf8.len(s) == nil then
		return nil
	end
	local lower = string.lower(s)
	local title = (string.gsub(lower, "%S+", function(w: string): string
		return string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2)
	end))
	local first = string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
	for _, c in { title, first } do
		-- (words with no letters %l sees, Cyrillic, come back as they were: not capitals to look up again)
		if c ~= s then
			local t = translate(c, depth + 1)
			if t ~= c then
				return upper(t)
			end
		end
	end
	return nil
end

-- Words with spaces around them ("Autumn ", a piece measured before more is put after it): the words translated, the
-- spaces kept.
local function viaTrim(s: string, depth: number): string?
	local a, core, b = string.match(s, "^(%s*)(.-)(%s*)$")
	if a == nil or core == nil or b == nil or (a == "" and b == "") or core == "" then
		return nil
	end
	local t = translate(core, depth)
	return if t ~= core then a .. t .. b else nil
end

-- A name made of names ("Rare Egg": a rarity's and a word's), each translated; the language's own joiner (none in
-- Chinese and Thai, a space elsewhere). Only when every piece is known.
local NO_SPACES: { [string]: boolean } = { zh = true, th = true }
local function viaNames(s: string): string?
	local words = string.split(s, " ")
	if #words < 2 or #words > 8 then
		return nil
	end
	-- names are capitalised word by word ("Rare Egg"); a sentence is not ("Gift in 4")
	for _, w in words do
		if not string.find(w, "^%u") then
			return nil
		end
	end
	local out: { string } = {}
	local i = 1
	while i <= #words do
		local found: string? = nil
		local j = #words
		while j >= i do
			local phrase = table.concat(words, " ", i, j)
			local t = exact[phrase]
			if t and (j > i or i < #words or #out > 0) then
				found = t
				break
			end
			j -= 1
		end
		if found == nil then
			return nil
		end
		table.insert(out, found)
		i = j + 1
	end
	return if #out >= 2 then table.concat(out, if NO_SPACES[current] then "" else " ") else nil
end

-- A text of several lines, or sentences, each on its own (only when one of them is known); last, a list's items
-- ("Goldtouched, Sunkissed", "Rain · 4:19").
local SPLITS = { "\n", ". ", "; ", " · ", " - ", " + ", ", " }
local function viaParts(s: string, depth: number): string?
	if depth >= DEPTH_MAX then
		return nil
	end
	for _, sep in SPLITS do
		if string.find(s, sep, 1, true) then
			local parts = string.split(s, sep)
			if #parts >= 2 then
				local changed = false
				for i, p in parts do
					-- a sentence keeps its full stop for the lookup ("Sold out." not "Sold out")
					local key = if sep == ". " and i < #parts then p .. "." else p
					local out = translate(key, depth + 1)
					if out ~= key then
						changed = true
						parts[i] = if sep == ". " and i < #parts and string.sub(out, -1) == "." then string.sub(out, 1, -2) else out
					end
				end
				if changed then
					return table.concat(parts, sep)
				end
			end
		end
	end
	return nil
end

translate = function(s: string, depth: number): string
	if s == "" or done[s] then
		return s
	end
	local hit = cache[s]
	if hit then
		return hit
	end
	local out: string? = exact[s]
	-- (a context: its own key, else the words before it)
	if out == nil and string.find(s, "@@", 1, true) then
		local base = string.match(s, "^(.-)@@%w+$")
		if base then
			out = translate(base, depth)
		end
	end
	if out == nil and not string.find(s, "^[%d%s%p]*$") then
		out = viaCaps(s, depth)
			or viaTrim(s, depth)
			or viaAffix(s, depth, true)
			or viaTemplate(s, depth)
			or viaAffix(s, depth, false)
			or viaParts(s, depth)
			or viaNames(s)
	end
	local res: string = out or s
	if cached >= CACHE_MAX then
		cache = {}
		cached = 0
	end
	cache[s] = res
	cached += 1
	done[res] = true
	if res ~= s then
		produced[res] = true
	end
	return res
end

-- Whether `s` is a translation Lang.t gave (so not English to translate, nor to keep as a label's English).
function Lang.produced(s: string): boolean
	return produced[s] == true
end

function Lang.keep(s: string): string
	done[s] = true
	produced[s] = true
	return s
end

function Lang.t(s: string): string
	local seen = Lang.seen
	if seen and type(s) == "string" then
		seen[s] = true
	end
	if type(s) ~= "string" then
		return s
	end
	if current == "en" then
		-- (a context after "@@" is never shown)
		return if string.find(s, "@@", 1, true) then (string.match(s, "^(.-)@@%w+$") or s) else s
	end
	return translate(s, 0)
end

-- Whether `s` has letters of a script the pixel font cannot draw (Hebrew and Arabic, Thai, Korean, Chinese and
-- Japanese ...): such words are drawn in a native font even where everything else is in the pixel font.
function Lang.needsScript(s: string): boolean
	if not string.find(s, "[\214-\255]") then
		return false
	end
	for _, cp in utf8.codes(s) do
		if (cp >= 0x0590 and cp <= 0x08FF) or (cp >= 0x0E00 and cp <= 0x0E7F) or (cp >= 0x1100 and cp <= 0x11FF)
			or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0xF900 and cp <= 0xFAFF)
			or (cp >= 0xFF00 and cp <= 0xFFEF) then
			return true
		end
	end
	return false
end

-- About how wide a line of `s` is in a native font `em` px tall (where the real measure is not to hand): an ideograph
-- a whole em, a space a quarter, Thai and Latin letters a bit over half, Arabic a bit under, combining marks nothing.
function Lang.estimateWidth(s: string, em: number): number
	local sum = 0
	for _, cp in utf8.codes(s) do
		if (cp >= 0x2E80 and cp <= 0x9FFF) or (cp >= 0xAC00 and cp <= 0xD7AF) or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFF00 and cp <= 0xFFEF) then
			sum += em
		elseif cp == 0x0E31 or (cp >= 0x0E34 and cp <= 0x0E3A) or (cp >= 0x0E47 and cp <= 0x0E4E) or (cp >= 0x064B and cp <= 0x065F) or cp == 0x0670 then
			sum += 0
		elseif cp == 32 then
			sum += em * 0.25
		elseif cp >= 0x0600 and cp <= 0x06FF then
			sum += em * 0.55
		else
			sum += em * 0.58
		end
	end
	return math.ceil(sum)
end

function Lang.f(template: string, ...: any): string
	local args = table.pack(...)
	local out = (string.gsub(Lang.t(template), "{(%d+)}", function(n: string): string
		local v = args[tonumber(n) or 0]
		return if v == nil then "" else tostring(v)
	end))
	return Lang.keep(out)
end

function Lang.an(anTpl: string, aTpl: string, name: string, ...: any): string
	local vowel = string.find(string.lower(name), "^[aeiou]") ~= nil
	local word = if current == "en" then string.lower(name) else Lang.t(name)
	return Lang.f(if vowel then anTpl else aTpl, word, ...)
end

-- Lang.fmt("Wearing: {name}", { name = "Bucket Hat" }) -> the template's translation, each {key} filled with its
-- value as it is (a value to translate goes through t first), never translated again.
-- Items already in the language on show joined as one list ("a, b and c"), with the language's own comma and "and".
function Lang.list(items: { string }): string
	if #items == 0 then
		return ""
	end
	local comma, andWord = Lang.t(", @@list"), Lang.t(" and @@list")
	local out = items[1]
	for i = 2, #items do
		out ..= (if i == #items then andWord else comma) .. items[i]
	end
	return Lang.keep(out)
end

function Lang.fmt(s: string, args: { [string]: string | number }): string
	return Lang.keep((string.gsub(Lang.t(s), "{(%w+)}", function(k: string): string
		local v = args[k]
		return if v ~= nil then tostring(v) else "{" .. k .. "}"
	end)))
end

return Lang
