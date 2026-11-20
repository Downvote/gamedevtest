-- Lang spec (docs/LOCALIZATION.md; the bakery's own, ported 2026-11-20): the language a Settings choice and a Roblox
-- locale pick, a word or sentence found as it is, templates (their {n} moved by the translation, each part translated
-- in turn, the most specific winning), lines and sentences one by one, English left as it is, and what t returns never
-- translated again. Every language table: a translation for each key, the same {n} and rich-text tags as its key.
-- Every word the game can show (scripts/locale_strings.py, written by scripts/check.sh) has its words in every
-- language (docs/LOCALIZATION.md 6).
local T = require("../TestKit")
local Lang = require("../../build/luautest/shared/Locale/Lang")

local WORDS = {
	["Save"] = "Guardar",
	["Lumber Camp"] = "Aserradero",
	["Not enough coins."] = "No tienes monedas.",
	["Try again soon."] = "Prueba pronto.",
	["Hatches in {1}"] = "Eclosiona en {1}",
	["Sold a {1} for {2} coins."] = "Vendiste {1} por {2} monedas.",
	["Sell {1}"] = "Vender {1}",
	["Rare"] = "Raro",
	["Egg"] = "Huevo",
	["Common"] = "Común",
	["Charm"] = "Encanto",
	["Autumn"] = "Otoño",
	["Coin Baron"] = "Barón de Monedas",
	["Lv{1}"] = "Nv{1}",
	["{1} coins"] = "{1} monedas",
	["Needs {1}"] = "Requiere {1}",
	["Gift"] = "Regalo",
	["Your {1}"] = "Tu {1}",
	["{1} and {2}"] = "{1} y {2}",
	["Wearing: {name}"] = "Llevas: {name}",
	["Veggie Patch"] = "Huerto",
}

return function()
	T.it("resolve: a Settings choice, else the Roblox language the game has, else English", function()
		T.eq(Lang.resolve("es", "ru-ru"), "es", "a choice wins")
		T.eq(Lang.resolve("auto", "pt-br"), "pt", "Brazilian Portuguese")
		T.eq(Lang.resolve(nil, "zh-cn"), "zh", "Chinese")
		T.eq(Lang.resolve("auto", "zh-tw"), "zh", "any Chinese in Simplified")
		T.eq(Lang.resolve("auto", "de-de"), "en", "a language the game does not have")
		T.eq(Lang.resolve("xx", nil), "en", "junk")
		T.eq(#Lang.LIST, 10)
		T.eq(Lang.LIST[1].code, "en")
	end)

	T.it("English is the game's own words", function()
		Lang.set("en")
		T.eq(Lang.code(), "en")
		T.eq(Lang.t("Save"), "Save")
		T.eq(Lang.fmt("Wearing: {name}", { name = "Beret" }), "Wearing: Beret", "named slots")
		T.truthy(Lang.pixel())
	end)

	T.it("words, templates, parts", function()
		Lang.set("es", WORDS)
		T.eq(Lang.code(), "es")
		T.eq(Lang.t("Save"), "Guardar", "a word")
		T.eq(Lang.t("Hatches in 4:30"), "Eclosiona en 4:30", "numbers pass through")
		T.eq(Lang.t("Sold a Lumber Camp for 55 coins."), "Vendiste Aserradero por 55 monedas.", "a part is translated in turn")
		T.eq(Lang.t("Sell Lumber Camp"), "Vender Aserradero")
		T.eq(Lang.t("Not enough coins. Try again soon."), "No tienes monedas. Prueba pronto.", "sentence by sentence")
		T.eq(Lang.t("Save\nLumber Camp"), "Guardar\nAserradero", "line by line")
		T.eq(Lang.t("Something new"), "Something new", "unknown words stay English")
		T.eq(Lang.t("2x Lumber Camp"), "2x Aserradero", "a count before a name")
		T.eq(Lang.t("Coin Baron ★3"), "Barón de Monedas ★3", "a star after a name")
		T.eq(Lang.t("Rare Egg"), "Raro Huevo", "a name made of names")
		T.eq(Lang.t("Rare Pudding"), "Rare Pudding", "only when every piece is known")
		T.eq(Lang.t("1,200"), "1,200", "numbers alone")
		T.eq(Lang.t(Lang.t("Save")), "Guardar", "never translated twice")
		T.truthy(Lang.produced("Guardar") and not Lang.produced("Save") and not Lang.produced("Something new"))
		T.eq(Lang.f("Sold a {1} for {2} coins.", "Huerto", 40), "Vendiste Huerto por 40 monedas.", "f fills a template")
		T.eq(Lang.fmt("Wearing: {name}", { name = "Boina" }), "Llevas: Boina", "fmt fills named slots")
		Lang.set("th", {})
		T.truthy(not Lang.pixel(), "Thai is drawn natively")
		Lang.set("en")
	end)

	T.it("what a template may take", function()
		Lang.set("es", WORDS)
		T.eq(Lang.t("Lv12"), "Nv12", "a {n} glued to letters takes a number")
		T.eq(Lang.t("Lvx"), "Lvx", "and only a number")
		T.eq(Lang.t("Lumber Camp\n+5 coins"), "Aserradero\n+5 monedas", "a template takes no line break")
		T.eq(Lang.t("Needs Lumber Camp + Veggie Patch"), "Requiere Aserradero + Huerto", "a list's items")
		T.eq(Lang.t("Common, 1 in 7"), "Común, 1 in 7")
		T.eq(Lang.t("Lumber Camp x3"), "Aserradero x3", "a multiplier after a name")
		T.eq(Lang.t("+10% Charm"), "+10% Encanto", "a number before a name")
		T.eq(Lang.t("COMMON"), "COMÚN", "capitals")
		T.eq(Lang.t("Autumn "), "Otoño ", "spaces kept")
		T.eq(Lang.t("Gift in 4"), "Gift in 4", "a sentence is not a name of names")
		T.eq(Lang.t("Your Lumber Camp"), "Tu Aserradero", "a short template around words that translate")
		T.eq(Lang.t("Your island is growing"), "Your island is growing", "never the start of any sentence")
		T.eq(Lang.t("Veggie Patch and Lumber Camp"), "Huerto y Aserradero")
		T.eq(Lang.t("Bo and Lumber Camp"), "Bo and Lumber Camp", "a short template's words all translate")
		local typed = Lang.keep("Pastel")
		T.eq(Lang.t(typed), "Pastel", "kept words are never translated")
		Lang.set("en")
	end)

	T.it("scripts the pixel font cannot draw", function()
		T.truthy(Lang.needsScript("ภาษาไทย") and Lang.needsScript("简体中文") and Lang.needsScript("العربية"))
		T.truthy(not Lang.needsScript("Русский") and not Lang.needsScript("Español ★ → …"))
		T.truthy(Lang.estimateWidth("简体", 8) == 16 and Lang.estimateWidth("ab", 8) > 0)
	end)

	T.it("every word the game can show is in every language", function()
		local ok, list = pcall(require, "../../build/luautest/LocaleStrings")
		T.truthy(ok and type(list) == "table", "build/luautest/LocaleStrings is missing: run scripts/check.sh")
		if not ok or type(list) ~= "table" then
			return
		end
		for _, info in Lang.LIST do
			if info.code ~= "en" then
				local okW, words = pcall(require, "../../build/luautest/shared/Locale/" .. info.code)
				T.truthy(okW and type(words) == "table", "no table for " .. info.code .. ": run python3 scripts/gen_locale.py")
				if okW and type(words) == "table" then
					Lang.set(info.code, words)
					local missing = {}
					for _, e in list do
						-- a key of the table (its words may be the English ones), or a string the table's keys and
						-- templates translate ({n} filled with a number)
						local trimmed = string.match(e.s, "^%s*(.-)%s*$") or e.s
						local sample = (string.gsub(e.s, "{%d+}", "7"))
						if words[e.s] == nil and words[trimmed] == nil and Lang.t(sample) == sample then
							table.insert(missing, string.format("%q (%s)", e.s, e.at))
						end
					end
					T.truthy(
						#missing == 0,
						string.format(
							"%s has no words for %d strings the game can show: add each to every locale/<code>.json and run "
								.. "python3 scripts/gen_locale.py (a string never shown goes in locale/ignore.txt):\n    %s",
							info.code,
							#missing,
							table.concat(missing, "\n    ", 1, math.min(#missing, 30))
						)
					)
				end
			end
		end
		Lang.set("en")
	end)

	T.it("words already in another language never break a lookup", function()
		-- a label can hold another language's words for a moment (a change of language; the PixelText safety net
		-- translates what it draws): Lang.t must give something back, never error (the bakery's capitals that read
		-- the same in Title Case once recursed until the stack overflowed)
		Lang.set("fr")
		T.eq(Lang.t("E O"), "E O")
		local tables = {}
		for _, info in Lang.LIST do
			if info.code ~= "en" then
				local ok, words = pcall(require, "../../build/luautest/shared/Locale/" .. info.code)
				if ok and type(words) == "table" then
					tables[info.code] = words
				end
			end
		end
		for code, own in tables do
			Lang.set(code, own)
			for other, words in tables do
				if other ~= code then
					for _, out in words do
						local ok, err = pcall(Lang.t, out)
						T.truthy(ok, code .. " reading " .. other .. " '" .. out .. "': " .. tostring(err))
					end
				end
			end
		end
		Lang.set("en")
	end)

	T.it("every language table keeps its keys' {n} and tags", function()
		for _, info in Lang.LIST do
			if info.code ~= "en" then
				local ok, words = pcall(require, "../../build/luautest/shared/Locale/" .. info.code)
				if ok and type(words) == "table" then
					local n = 0
					for key, out in words do
						n += 1
						T.truthy(type(out) == "string" and out ~= "", info.code .. ": " .. key .. " has no translation")
						local function marks(s: string): string
							local list = {}
							for m in string.gmatch(s, "{%w+}") do
								table.insert(list, m)
							end
							for m in string.gmatch(s, "</?font[^>]*>") do
								table.insert(list, (string.gsub(m, "%s", "")))
							end
							table.sort(list)
							return table.concat(list, ",")
						end
						T.eq(marks(out), marks(key), info.code .. ": " .. key)
					end
					T.truthy(n > 0, info.code .. " is empty")
				end
			end
		end
	end)
end
