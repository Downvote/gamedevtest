-- tests/specs/PixelFont.spec.luau: the pixel font (Render/PixelFont + the generated PixelFontData): every ASCII glyph
-- and every character the game's strings use is drawn, glyph bit masks stay inside their widths and the em, the
-- advances follow the TTF (SMALL as drawn; BIG the small face doubled), the big face keeps to the 1 px grid (no two
-- of its pixels touch only at a corner: every diagonal is a 1 px stair) and its title layer's anti-aliasing sits in
-- the elbows of its steps, measuring, word wrap, clipping, rich-text colour runs, and golden masks of sample strings
-- (face, drop shadow, bold outline, the big face).
local T = require("../TestKit")
local PF = require("../../build/luautest/shared/Render/PixelFont")

local function rows(m: PF.Mask): { string }
	local out = {}
	for y = 0, m.h - 1 do
		local s = ""
		for x = 0, m.w - 1 do
			local v = buffer.readu8(m.px, y * m.w + x)
			s ..= if v == 0 then "." else tostring(v)
		end
		table.insert(out, s)
	end
	return out
end

-- every non-ASCII character in the game's Luau strings (grep -P '[^\x00-\x7F]' src, comments left out)
local GAME_CHARS = { "·", "é", "è", "ê", "â", "û", "À", "°", "★" }

return function()
	T.it("draws every printable ASCII character in both faces", function()
		for cp = 32, 126 do
			local ch = string.char(cp)
			T.truthy(PF.has(PF.SMALL, ch), "SMALL lacks " .. ch)
			T.truthy(PF.has(PF.BIG, ch), "BIG lacks " .. ch)
			T.truthy(PF.glyph(PF.SMALL, ch) ~= PF.SMALL.box, "SMALL draws " .. ch .. " as the box")
		end
	end)

	T.it("draws every non-ASCII character the game's strings use", function()
		for _, ch in GAME_CHARS do
			T.truthy(PF.has(PF.SMALL, ch), "SMALL lacks " .. ch)
		end
		-- curly quotes, a no-break space and the minus sign borrow ASCII glyphs; anything else is the box
		T.eq(PF.glyph(PF.SMALL, "\u{2019}"), PF.glyph(PF.SMALL, "'"))
		T.eq(PF.glyph(PF.SMALL, "\u{00A0}"), PF.glyph(PF.SMALL, " "))
		T.eq(PF.glyph(PF.SMALL, "\u{4E2D}"), PF.SMALL.box)
		T.eq(PF.width("\u{4E2D}"), PF.SMALL.box.adv)
	end)

	T.it("keeps glyph masks inside their width and the line", function()
		for ch, g in PF.SMALL.glyphs do
			T.truthy(g.adv == (if ch == " " then PF.SMALL.space else g.w + 1), "SMALL advance of " .. ch)
			T.truthy(g.top >= -3 and g.top + #g.rows <= 8, "SMALL rows of " .. ch .. " leave -3..7")
			for _, bits in g.rows do
				T.truthy(bits < 2 ^ g.w, "SMALL " .. ch .. " has pixels past its width")
			end
			if string.match(ch, "^[%w]$") then
				local ink = false
				for _, bits in g.rows do
					ink = ink or bits ~= 0
				end
				T.truthy(ink, "SMALL " .. ch .. " is blank")
			end
		end
		for ch, g in PF.BIG.glyphs do
			T.truthy(g.top + #g.rows <= 16 and g.top >= -6, "BIG " .. ch .. " leaves the em (accents 6 px above it)")
			for _, bits in g.rows do
				T.truthy(bits < 2 ^ g.w, "BIG " .. ch .. " has pixels past its advance")
			end
		end
	end)

	T.it("keeps the big face on the 1 px grid (no step is a 2 px block)", function()
		-- a plain 2x copy of the small face would have its diagonals touch only at the corners of 2 x 2 blocks
		local function ink(rows: { number }, x: number, y: number): boolean
			local r = rows[y + 1]
			return r ~= nil and bit32.band(r, bit32.lshift(1, x)) ~= 0
		end
		for ch, g in PF.BIG.glyphs do
			local bad = 0
			for y = 0, #g.rows - 2 do
				for x = 0, g.w - 2 do
					local a, b, c, d = ink(g.rows, x, y), ink(g.rows, x + 1, y), ink(g.rows, x, y + 1), ink(g.rows, x + 1, y + 1)
					if (a and d and not b and not c) or (b and c and not a and not d) then
						bad += 1
					end
				end
			end
			T.eq(bad, 0, "BIG " .. ch .. " has pixels touching only at a corner")
		end
		T.truthy(#PF.glyph(PF.BIG, "W").rows == 14, "BIG caps are 14 px")
	end)

	T.it("follows the TTF's advances (SMALL: as drawn; BIG: twice SMALL)", function()
		for ch, g in PF.SMALL.glyphs do
			T.eq(PF.glyph(PF.BIG, ch).adv, 2 * g.adv, "BIG advance of " .. ch)
		end
		local small = { A = 6, H = 6, O = 7, I = 4, i = 2, l = 2, m = 8, a = 6, e = 5, [" "] = 3, ["."] = 2 }
		for ch, adv in small do
			T.eq(PF.glyph(PF.SMALL, ch).adv, adv, "SMALL advance of " .. ch)
		end
		-- tabular digits: numbers keep their width as they count
		for d = 0, 9 do
			T.eq(PF.glyph(PF.SMALL, tostring(d)).adv, 5, "SMALL advance of " .. d)
		end
		T.eq(PF.SMALL.em, 8)
		T.eq(PF.BIG.em, 16)
		T.eq(PF.pitch(1.25), 10)
		T.eq(PF.pitch(1), 8)
	end)

	T.it("measures pen widths", function()
		T.eq(PF.width(""), 0)
		T.eq(PF.width("Hi"), 6 + 2)
		T.eq(PF.width("Hello"), 6 + 5 + 2 + 2 + 5)
		T.eq(PF.width("a b"), 6 + 3 + 6)
		T.eq(PF.width("Hi\nHello"), PF.width("Hello"))
		T.eq(PF.width("Crème"), PF.width("Creme"))
		T.eq(PF.width("MYTHIC", PF.BIG), 2 * PF.width("MYTHIC"))
		-- narrower than Press Start 2P's 8 px per character
		T.truthy(PF.width("Strawberry Sponge Cake") < 8 * #"Strawberry Sponge Cake")
	end)

	T.it("wraps at spaces within the width and breaks long words", function()
		local text = "The quick brown fox jumps over the lazy dog"
		for _, w in { 20, 33, 40, 57, 80, 200 } do
			local lines = PF.wrap(text, w)
			for _, l in lines do
				T.truthy(PF.width(l) <= w, string.format("line '%s' wider than %d", l, w))
				T.truthy(string.sub(l, 1, 1) ~= " " and string.sub(l, -1) ~= " ", "line '" .. l .. "' keeps a break space")
			end
			if w >= PF.width("quick") then
				T.eq(table.concat(lines, " "), text, "wrapping at " .. w .. " lost words")
			else
				T.eq(string.gsub(table.concat(lines), " ", ""), (string.gsub(text, " ", "")), "breaking at " .. w .. " lost letters")
			end
			T.eq(PF.lineCount(text, w), #lines)
			-- greedy: the next line's first word did not fit
			for i = 1, if w >= PF.width("quick") then #lines - 1 else 0 do
				local nextWord = string.match(lines[i + 1], "^(%S+)") :: string
				T.truthy(PF.width(lines[i] .. " " .. nextWord) > w, "line " .. i .. " could have taken '" .. nextWord .. "'")
			end
		end
		T.deepEq(PF.wrap("one\ntwo three", 200), { "one", "two three" })
		T.deepEq(PF.wrap("a\n\nb", 200), { "a", "", "b" })
		local long = PF.wrap("Supercalifragilistic", 30)
		T.truthy(#long > 1, "a long word breaks")
		T.eq(table.concat(long), "Supercalifragilistic")
		for _, l in long do
			T.truthy(PF.width(l) <= 30, "piece '" .. l .. "' too wide")
		end
		T.eq(PF.lineCount("", 50), 1)
		T.eq(PF.lineCount("Make 4", PF.width("Make 4")), 1)
		T.eq(PF.lineCount("Make 4", PF.width("Make 4") - 1), 2)
	end)

	T.it("clips one line with ...", function()
		T.eq(PF.clip("Cake", 100), "Cake")
		local c = PF.clip("Strawberry Sponge Cake", 50)
		T.eq(string.sub(c, -3), "...")
		T.truthy(PF.width(c) <= 50, "clipped line too wide: " .. c)
		T.eq(PF.clip("Strawberry Sponge Cake", PF.width("Strawberry...")), "Strawberry...")
		T.eq(PF.clip("Strawberry Sponge", PF.width("Strawberry...") + 3), "Strawberry...")
	end)

	T.it("parses rich-text colour runs and keeps them through wrapping", function()
		local plain, colors, rgbs = PF.rich('Adding Jam: <font color="#9BE38E">+3</font> Volume, <font color="#FF7C8C">-2</font> kcal')
		T.eq(plain, "Adding Jam: +3 Volume, -2 kcal")
		T.eq(#colors, #plain)
		T.deepEq(rgbs, { 0x9BE38E, 0xFF7C8C })
		T.eq(colors[string.find(plain, "+", 1, true) :: number], 1)
		T.eq(colors[string.find(plain, "-", 1, true) :: number], 2)
		T.eq(colors[1], 0)
		local lines = PF.wrap(plain, 60)
		local lc = PF.lineColors(lines, plain, colors)
		T.eq(#lc, #lines)
		local seen = {}
		for i, l in lines do
			for j, ch in PF.graphemes(l) do
				if ch == "+" or ch == "3" then
					T.eq(lc[i][j], 1, "colour of " .. ch)
				elseif ch == "-" or ch == "2" then
					T.eq(lc[i][j], 2, "colour of " .. ch)
				elseif ch ~= " " then
					T.eq(lc[i][j], 0, "colour of " .. ch)
				end
				seen[ch] = true
			end
		end
		T.truthy(seen["+"] and seen["-"], "both runs survive wrapping")
		local p2 = PF.rich("a<br/>b &lt;3")
		T.eq(p2, "a\nb <3")
	end)

	T.it("rasterises golden masks", function()
		local m = PF.mask({ "Hi! Crème" })
		T.eq(m.blockW, PF.width("Hi! Crème"))
		T.eq(m.blockH, 8)
		T.eq(m.oy, -1) -- the grave accent reaches one row above the em
		T.deepEq(rows(m), {
			"..........................1................",
			"1...1.1.1.....1111.........1...............",
			"1...1...1....1....1........................",
			"1...1.1.1....1......1.11..11..111.11...11..",
			"11111.1.1....1......11...1..1.1..1..1.1..1.",
			"1...1.1.1....1......1....1111.1..1..1.1111.",
			"1...1.1......1....1.1....1....1..1..1.1....",
			"1...1.1.1.....1111..1.....111.1..1..1..111.",
			"...........................................",
		})
		local sh = PF.under(PF.mask({ "Hi" }), "shadow")
		T.eq(sh.w, PF.width("Hi") + 1)
		T.deepEq(rows(sh), {
			".........",
			".1...1.1.",
			".1...1...",
			".1...1.1.",
			".11111.1.",
			".1...1.1.",
			".1...1.1.",
			".1...1.1.",
			".........",
		})
		local ol = PF.under(PF.mask({ "i" }), "outline")
		T.eq(ol.ox, -1)
		T.eq(ol.oy, -1)
		T.deepEq(rows(ol), { ".1..", "1.1.", ".11.", "111.", "111.", "111.", "111.", "111.", ".11.", "...." })
		-- the title layer: the outline and 2 px of depth (the big words)
		local ti = PF.under(PF.mask({ "i" }), "title")
		T.eq(ti.w, 4)
		T.eq(ti.h, 8 + 4)
		T.deepEq({ ti.ox, ti.oy }, { -1, -1 })
		T.deepEq(rows(ti)[10], "111.")
		T.deepEq(rows(ti)[11], ".1..")
		-- pixel-art anti-aliasing (2s) in the elbows of the big face's steps: none in an L's square inside corner,
		-- some round an O's corners, never under the face, nothing else changed
		local function aa(text: string): (number, boolean)
			local face = PF.mask({ text }, { face = PF.BIG })
			local under = PF.under(face, "title")
			local sm = PF.smooth(face, under)
			local n, clean = 0, true
			for y = 0, sm.h - 1 do
				for x = 0, sm.w - 1 do
					local v = buffer.readu8(sm.px, y * sm.w + x)
					local u = buffer.readu8(under.px, y * sm.w + x)
					if v == 2 then
						n += 1
						local fx, fy = x + sm.ox - face.ox, y + sm.oy - face.oy
						if u == 0 or (fx >= 0 and fy >= 0 and fx < face.w and fy < face.h and buffer.readu8(face.px, fy * face.w + fx) ~= 0) then
							clean = false
						end
					elseif v ~= u then
						clean = false
					end
				end
			end
			return n, clean
		end
		local nL, okL = aa("L")
		T.eq(nL, 0, "an L's square corners are left sharp")
		T.truthy(okL)
		local nO, okO = aa("O")
		T.truthy(nO >= 4, "an O's rounded corners are anti-aliased: " .. nO)
		T.truthy(okO, "anti-aliasing only on outline pixels, everything else as it was")
		local nV, okV = aa("V")
		T.truthy(nV > 0 and okV, "a V's diagonals are anti-aliased at their ends")
		-- centred lines, a second line one pitch lower
		local two = PF.mask({ "ab", "a" }, { align = "Center" })
		T.eq(two.blockH, 18)
		T.eq(two.h, 18)
		T.deepEq(rows(two)[13], "...1111.....")
		-- colour indices
		local col = PF.mask({ "+3" }, { colors = { { 1, 0 } } })
		T.deepEq(rows(col)[4], "22222...1..")
		-- the big face: the small one doubled
		local big = PF.mask({ "HI" }, { face = PF.BIG })
		T.eq(big.w, 12 + 8)
		T.eq(rows(big)[1], "11......11..111111..")
		T.eq(rows(big)[6], "11......11....11....")
		T.eq(rows(big)[7], "1111111111....11....")
	end)
end
