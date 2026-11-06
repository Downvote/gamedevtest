-- GUI layout for the fake engine (preview tool): makes AbsoluteSize / AbsolutePosition / AbsoluteContentSize /
-- TextBounds / AbsoluteCanvasSize / AbsoluteWindowSize behave like Roblox for the features the game uses, and fires
-- their GetPropertyChangedSignal once per frame when they change (Roblox runs scripts' layout reactions this way).
-- Supported: UDim2 size/position/anchor, UIScale (scales an object about its anchor and every offset below it),
-- UIPadding, UIListLayout (direction, alignment, padding, sort order, Wraps, flex Fill/Space*), UIFlexItem grow,
-- UIGridLayout, AutomaticSize (children and text), ScrollingFrame canvases (CanvasSize, AutomaticCanvasSize,
-- CanvasPosition), UIAspectRatioConstraint, UISizeConstraint, UITextSizeConstraint, TextScaled, TextWrapped, RichText
-- (b, font color/size/weight/face/transparency, stroke, uc/sc, br), ClipsDescendants, Folders (transparent).
-- Text is measured with fontmetrics.luau (the same advances topng.py draws with), so wrapping matches the PNGs.
-- Layout is recomputed per ScreenGui only after a layout-relevant property write or reparent inside it.
local E = require("./engine")
local I = require("./inst")
local FM = require("./fontmetrics")
local getD = I.getD
local isA = I.isA
local v2 = E.v2
local UDim2 = E.types.UDim2
local UDim = E.types.UDim

local G = {}
E.gui = G
G.stats = { layouts = 0, fires = 0 }

------------------------------------------------------------------ classes and defaults
local GUI_OBJ = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true, VideoFrame = true,
}
local TEXT_CLS = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGE_CLS = { ImageLabel = true, ImageButton = true }
G.GUI_OBJ, G.TEXT_CLS, G.IMAGE_CLS = GUI_OBJ, TEXT_CLS, IMAGE_CLS

local function u2(a, b, c, d)
	return UDim2.new(a, b, c, d)
end
local GREY = E.c3(163 / 255, 162 / 255, 165 / 255)
local INK = E.c3(27 / 255, 42 / 255, 53 / 255)
local DEF_COMMON = {
	Visible = true, Position = u2(0, 0, 0, 0), AnchorPoint = v2(0, 0), Rotation = 0, ZIndex = 1, LayoutOrder = 0,
	BackgroundColor3 = GREY, BackgroundTransparency = 0, BorderSizePixel = 1, BorderColor3 = INK, BorderMode = "Outline",
	ClipsDescendants = false, AutomaticSize = "None",
}
local DEF = {
	Frame = { Size = u2(0, 100, 0, 100) },
	ScrollingFrame = { Size = u2(0, 100, 0, 100), CanvasSize = u2(0, 0, 2, 0), CanvasPosition = v2(0, 0), AutomaticCanvasSize = "None", ScrollBarThickness = 12, ScrollingDirection = "XY", ClipsDescendants = true },
	TextLabel = { Size = u2(0, 200, 0, 50), Text = "Label" },
	TextButton = { Size = u2(0, 200, 0, 50), Text = "Button" },
	TextBox = { Size = u2(0, 200, 0, 50), Text = "", PlaceholderText = "" },
	ImageLabel = { Size = u2(0, 100, 0, 100) },
	ImageButton = { Size = u2(0, 100, 0, 100) },
	ViewportFrame = { Size = u2(0, 100, 0, 100) },
	CanvasGroup = { Size = u2(0, 100, 0, 100) },
	VideoFrame = { Size = u2(0, 100, 0, 100) },
	ScreenGui = { Enabled = true, DisplayOrder = 0, IgnoreGuiInset = false, ScreenInsets = "CoreUISafeInsets", ZIndexBehavior = "Sibling" },
	UIListLayout = { FillDirection = "Vertical", Padding = UDim.new(0, 0), SortOrder = "LayoutOrder", HorizontalAlignment = "Left", VerticalAlignment = "Top", Wraps = false, HorizontalFlex = "None", VerticalFlex = "None" },
	UIGridLayout = { CellSize = u2(0, 100, 0, 100), CellPadding = u2(0, 5, 0, 5), FillDirection = "Horizontal", FillDirectionMaxCells = 0, SortOrder = "LayoutOrder", StartCorner = "TopLeft", HorizontalAlignment = "Left", VerticalAlignment = "Top" },
	UIPadding = { PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0) },
	UIScale = { Scale = 1 },
	UIAspectRatioConstraint = { AspectRatio = 1, AspectType = "FitWithinMaxSize", DominantAxis = "Width" },
	UISizeConstraint = { MinSize = v2(0, 0), MaxSize = v2(math.huge, math.huge) },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	UIFlexItem = { FlexMode = "None", GrowRatio = 0, ShrinkRatio = 0 },
	UIStroke = { Thickness = 1, ApplyStrokeMode = "Contextual", Enabled = true, Transparency = 0 },
}
local TEXT_DEF = {
	TextSize = 14, Font = "Legacy", TextScaled = false, TextWrapped = false, TextXAlignment = "Center",
	TextYAlignment = "Center", RichText = false, TextTruncate = "None", LineHeight = 1, MaxVisibleGraphemes = -1,
	TextTransparency = 0, TextStrokeTransparency = 1,
}

local function P(d, k)
	local v = d.props[k]
	if v ~= nil then
		return v
	end
	local t = DEF[d.cls]
	if t then
		v = t[k]
		if v ~= nil then
			return v
		end
	end
	if TEXT_CLS[d.cls] then
		v = TEXT_DEF[k]
		if v ~= nil then
			return v
		end
	end
	if GUI_OBJ[d.cls] then
		return DEF_COMMON[k]
	end
	return nil
end
G.P = P
local function EN(d, k)
	local v = P(d, k)
	if type(v) == "table" then
		return rawget(v, "Name")
	end
	return v
end
G.EN = EN

------------------------------------------------------------------ tree helpers
local function comps(d)
	local c = d.compCache
	if c and c.ver == d.layStamp then
		return c
	end
	c = { ver = d.layStamp }
	for _, ch in d.children do
		local cd = getD(ch)
		if not GUI_OBJ[cd.cls] and cd.cls ~= "Folder" and c[cd.cls] == nil then
			c[cd.cls] = cd
		end
	end
	d.compCache = c
	return c
end
local function guiKids(d, out)
	out = out or {}
	for _, ch in d.children do
		local cd = getD(ch)
		if GUI_OBJ[cd.cls] then
			table.insert(out, cd)
		elseif cd.cls == "Folder" then
			guiKids(cd, out)
		end
	end
	return out
end
G.guiKids = guiKids
local function visible(d)
	return P(d, "Visible") ~= false
end

local function ud(u, size, k)
	return u.Scale * size + u.Offset * k
end

------------------------------------------------------------------ text
local FONT_OF = {
	Arcade = "arcade",
	GothamBlack = "body800", FredokaOne = "body800", LuckiestGuy = "body800", Bangers = "body800",
	GothamBold = "body700", SourceSansBold = "body700", ArialBold = "body700", RobotoBold = "body700",
	GothamSemibold = "body700", GothamMedium = "body700", SourceSansSemibold = "body700",
	Code = "mono", RobotoMono = "mono",
}
local function fontKey(d)
	local ff = d.props.FontFace
	if ff ~= nil and E.typeof(ff) == "Font" then
		local fam = tostring(ff.Family or "")
		local w = ff.Weight
		local wn = if type(w) == "table" then rawget(w, "Name") else tostring(w or "Regular")
		if string.find(fam, "PressStart", 1, true) or string.find(fam, "Arcade", 1, true) then
			return "arcade"
		elseif string.find(fam, "Mono", 1, true) or string.find(fam, "Code", 1, true) then
			return "mono"
		elseif wn == "Heavy" or wn == "ExtraBold" or wn == "Black" then
			return "body800"
		elseif wn == "Bold" or wn == "SemiBold" then
			return "body700"
		end
		return "body500"
	end
	local name = EN(d, "Font") or "Legacy"
	local k = FONT_OF[name]
	if k then
		return k
	end
	return if string.find(name, "Bold", 1, true) then "body700" else "body500"
end
G.fontKey = fontKey
local BOLDER = { body500 = "body700", body700 = "body800" }

local FALLBACK = FM.fallback.adv
local function glyphKey(key, cp)
	if FM[key].adv[cp] ~= nil then
		return key
	end
	return "fallback"
end
G.glyphKey = glyphKey
local function codes(s)
	local ok, list = pcall(function()
		local out = {}
		for _, cp in utf8.codes(s) do
			table.insert(out, cp)
		end
		return out
	end)
	if ok then
		return list
	end
	local out = {}
	for i = 1, #s do
		out[i] = string.byte(s, i)
	end
	return out
end
local function textWidth(s, key, size)
	local adv = FM[key].adv
	local w = 0
	for _, cp in codes(s) do
		w += adv[cp] or FALLBACK[cp] or 600
	end
	return w * size / 1000
end
G.textWidth = textWidth

local ENT = { ["&lt;"] = "<", ["&gt;"] = ">", ["&amp;"] = "&", ["&quot;"] = '"', ["&apos;"] = "'" }
local function unescape(s)
	return (string.gsub(s, "&%a+;", function(e)
		return ENT[e] or e
	end))
end
local function parseColor(s)
	s = string.gsub(s, "^%s*[\"']?(.-)[\"']?%s*$", "%1")
	local h = string.match(s, "^#?(%x%x%x%x%x%x)$")
	if h then
		return { tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255, tonumber(string.sub(h, 5, 6), 16) / 255 }
	end
	local r, g, b = string.match(s, "^rgb%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)$")
	if r then
		return { tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255 }
	end
	return nil
end
local function attrs(body)
	local out = {}
	for k, q, v in string.gmatch(body, "(%w+)%s*=%s*([\"'])(.-)%2") do
		out[string.lower(k)] = v
	end
	return out
end
-- (text, style) runs; style: { bold, color, size, transp, stroke = {r,g,b,thick,transp}, upper, face }
local function richRuns(text, rich)
	if not rich then
		return { { text, {} } }
	end
	local runs = {}
	local stack = { {} }
	local i = 1
	local n = #text
	while i <= n do
		local a = string.find(text, "<", i, true)
		local b = a and string.find(text, ">", a + 1, true)
		local nextLt = a and string.find(text, "<", a + 1, true)
		if a and b and (nextLt == nil or nextLt > b) then
			if a > i then
				table.insert(runs, { unescape(string.sub(text, i, a - 1)), stack[#stack] })
			end
			local body = string.gsub(string.sub(text, a + 1, b - 1), "^%s*(.-)%s*$", "%1")
			local low = string.lower(body)
			if string.sub(low, 1, 1) == "/" then
				if #stack > 1 then
					table.remove(stack)
				end
			elseif string.sub(low, 1, 2) == "br" then
				table.insert(runs, { "\n", stack[#stack] })
			else
				local name = string.match(low, "^(%w+)") or ""
				local st = table.clone(stack[#stack])
				local at = attrs(body)
				local known = true
				if name == "b" then
					st.bold = true
				elseif name == "font" then
					if at.color then
						st.color = parseColor(at.color) or st.color
					end
					if at.size and tonumber(at.size) then
						st.size = tonumber(at.size)
					end
					if at.weight then
						local w = string.lower(at.weight)
						if w == "bold" or w == "heavy" or w == "extrabold" or w == "semibold" or (tonumber(w) and tonumber(w) >= 600) then
							st.bold = true
						end
					end
					if at.transparency and tonumber(at.transparency) then
						st.transp = tonumber(at.transparency)
					end
					if at.face and string.find(string.lower(at.face), "arcade", 1, true) then
						st.face = "arcade"
					end
				elseif name == "stroke" then
					local c = parseColor(at.color or "#000000") or { 0, 0, 0 }
					st.stroke = { c[1], c[2], c[3], tonumber(at.thickness or "1") or 1, tonumber(at.transparency or "0") or 0 }
				elseif name == "uc" or name == "uppercase" or name == "sc" or name == "smallcaps" then
					st.upper = true
				elseif name == "i" or name == "u" or name == "s" or name == "mark" then
					-- no visual change in the preview
				else
					known = false
				end
				if known then
					if string.sub(body, -1) ~= "/" then
						table.insert(stack, st)
					end
				else
					table.insert(runs, { string.sub(text, a, b), stack[#stack] })
				end
			end
			i = b + 1
		else
			table.insert(runs, { unescape(string.sub(text, i)), stack[#stack] })
			break
		end
	end
	return runs
end

-- Visible text after MaxVisibleGraphemes (TextBox placeholder when empty). Returns text, isPlaceholder.
local function shownText(d)
	local text = P(d, "Text") or ""
	if d.cls == "TextBox" and text == "" then
		return P(d, "PlaceholderText") or "", true
	end
	local mvg = P(d, "MaxVisibleGraphemes")
	if type(mvg) == "number" and mvg >= 0 then
		if P(d, "RichText") then
			local out, cnt = {}, 0
			local i = 1
			while i <= #text do
				local a = string.find(text, "<", i, true)
				local b = a and string.find(text, ">", a, true)
				local plain = string.sub(text, i, (a or #text + 1) - 1)
				local cps = codes(unescape(plain))
				local take = math.max(0, math.min(#cps, mvg - cnt))
				local kept = {}
				for j = 1, take do
					table.insert(kept, utf8.char(cps[j]))
				end
				cnt += #cps
				table.insert(out, (string.gsub(table.concat(kept), "[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" })))
				if a and b then
					table.insert(out, string.sub(text, a, b))
					i = b + 1
				else
					break
				end
			end
			text = table.concat(out)
		else
			local cps = codes(text)
			local kept = {}
			for j = 1, math.min(#cps, mvg) do
				table.insert(kept, utf8.char(cps[j]))
			end
			text = table.concat(kept)
		end
	end
	return text, false
end
G.shownText = shownText

local function isSpace(s)
	return string.match(s, "^ +$") ~= nil
end

-- Lines of segments { text, fontKey, size, width, style } with widths and heights; maxw = nil: no wrapping.
local function setText(d, text, size, maxw, k)
	local baseKey = fontKey(d)
	local lineH = P(d, "LineHeight") or 1
	local tokens = {}
	for _, run in richRuns(text, P(d, "RichText") == true) do
		local t, st = run[1], run[2]
		if st.upper then
			t = string.upper(t)
		end
		local i = 1
		while i <= #t do
			local a, b = string.find(t, "\n", i, true)
			local s1, s2 = string.find(t, " +", i)
			local cut, cutEnd
			if a and (not s1 or a < s1) then
				cut, cutEnd = a, a
			elseif s1 then
				cut, cutEnd = s1, s2
			end
			if cut == nil then
				table.insert(tokens, { string.sub(t, i), st })
				break
			end
			if cut > i then
				table.insert(tokens, { string.sub(t, i, cut - 1), st })
			end
			table.insert(tokens, { string.sub(t, cut, cutEnd), st })
			i = cutEnd + 1
		end
	end
	local lines = { {} }
	local widths = { 0 }
	local function segFont(st)
		local key = st.face or baseKey
		if st.bold then
			key = BOLDER[key] or key
		end
		local fs = if st.size then st.size * k else size
		return key, fs
	end
	for _, tok in tokens do
		local t, st = tok[1], tok[2]
		if t == "\n" then
			table.insert(lines, {})
			table.insert(widths, 0)
			continue
		end
		local key, fs = segFont(st)
		local w = textWidth(t, key, fs)
		local space = isSpace(t)
		local cur = lines[#lines]
		if maxw ~= nil and widths[#widths] + w > maxw + 0.5 and #cur > 0 and not space then
			while #cur > 0 and isSpace(cur[#cur][1]) do
				widths[#widths] -= cur[#cur][4]
				table.remove(cur)
			end
			table.insert(lines, {})
			table.insert(widths, 0)
			cur = lines[#lines]
		end
		if maxw ~= nil and w > maxw + 0.5 and not space then
			local chunk = ""
			for _, cp in codes(t) do
				local ch = utf8.char(cp)
				local cw = textWidth(chunk .. ch, key, fs)
				if widths[#widths] + cw > maxw + 0.5 and (chunk ~= "" or #lines[#lines] > 0) then
					if chunk ~= "" then
						local chw = textWidth(chunk, key, fs)
						table.insert(lines[#lines], { chunk, key, fs, chw, st })
						widths[#widths] += chw
					end
					table.insert(lines, {})
					table.insert(widths, 0)
					chunk = ch
				else
					chunk ..= ch
				end
			end
			if chunk ~= "" then
				local chw = textWidth(chunk, key, fs)
				table.insert(lines[#lines], { chunk, key, fs, chw, st })
				widths[#widths] += chw
			end
			continue
		end
		if space and #lines[#lines] == 0 and maxw ~= nil and #lines > 1 then
			continue
		end
		table.insert(lines[#lines], { t, key, fs, w, st })
		widths[#widths] += w
	end
	local heights = {}
	for i, ln in lines do
		local m = size
		if #ln > 0 then
			m = 0
			for _, seg in ln do
				m = math.max(m, seg[3])
			end
		end
		heights[i] = m * lineH
	end
	return lines, widths, heights
end
G.setText = setText

local function textBounds(d, size, maxw, k)
	local text = shownText(d)
	local _, widths, heights = setText(d, text, size, maxw, k)
	local w, h = 0, 0
	for i, lw in widths do
		w = math.max(w, lw)
		h += heights[i]
	end
	return w, h
end

-- Font size the object draws with (TextScaled: the largest size whose wrapped text fits its box).
local function drawSize(d, k, w, h)
	if P(d, "TextScaled") ~= true then
		return (P(d, "TextSize") or 14) * k
	end
	local c = comps(d).UITextSizeConstraint
	local lo = if c then (P(c, "MinTextSize") or 1) * k else 1
	local hi = if c then math.min(100 * k, (P(c, "MaxTextSize") or 100) * k) else 100 * k
	local a, b = math.max(1, math.floor(lo)), math.max(1, math.floor(hi))
	local best = a
	while a <= b do
		local mid = (a + b) // 2
		local bw, bh = textBounds(d, mid, math.max(1, w), k)
		if bw <= w + 0.5 and bh <= h + 0.5 then
			best = mid
			a = mid + 1
		else
			b = mid - 1
		end
	end
	return best
end
G.drawSize = drawSize

------------------------------------------------------------------ measure / place
local measure, measureChildren, place

local function ownScale(d)
	local sc = comps(d).UIScale
	return if sc then (P(sc, "Scale") or 1) else 1
end
local function padding(d, w, h, k)
	local p = comps(d).UIPadding
	if not p then
		return 0, 0, 0, 0
	end
	return ud(P(p, "PaddingLeft"), w, k), ud(P(p, "PaddingTop"), h, k), ud(P(p, "PaddingRight"), w, k), ud(P(p, "PaddingBottom"), h, k)
end
local function constrain(d, w, h, pk)
	local c = comps(d)
	local sc = c.UISizeConstraint
	if sc then
		local mn, mx = P(sc, "MinSize"), P(sc, "MaxSize")
		w = math.min(math.max(w, mn.X * pk), mx.X * pk)
		h = math.min(math.max(h, mn.Y * pk), mx.Y * pk)
	end
	local ar = c.UIAspectRatioConstraint
	if ar then
		local ratio = P(ar, "AspectRatio") or 1
		if ratio > 0 then
			if EN(ar, "AspectType") == "ScaleWithParentSize" then
				if EN(ar, "DominantAxis") == "Height" then
					w = h * ratio
				else
					h = w / ratio
				end
			elseif w / math.max(h, 1e-9) > ratio then
				w = h * ratio
			else
				h = w / ratio
			end
		end
	end
	return w, h
end
local function layoutOf(d)
	local c = comps(d)
	return c.UIListLayout or c.UIGridLayout
end
local function sortedKids(lay, kids)
	local list = table.clone(kids)
	if EN(lay, "SortOrder") == "Name" then
		table.sort(list, function(a, b)
			return (a.props.Name or "") < (b.props.Name or "")
		end)
	else
		for i, kd in list do
			kd.layIdx = i
		end
		table.sort(list, function(a, b)
			local la, lb = P(a, "LayoutOrder") or 0, P(b, "LayoutOrder") or 0
			if la ~= lb then
				return la < lb
			end
			return a.layIdx < b.layIdx
		end)
	end
	return list
end
local function wrapLines(kids, horiz, pad, limit)
	local lines = {}
	local cur, used, thick = {}, 0, 0
	for _, c in kids do
		local L = c.lay
		local m = if horiz then L.w else L.h
		local cr = if horiz then L.h else L.w
		local add = if #cur == 0 then m else pad + m
		if #cur > 0 and used + add > limit + 0.5 then
			table.insert(lines, { cur, used, thick })
			cur, used, thick = {}, 0, 0
			add = m
		end
		table.insert(cur, c)
		used += add
		thick = math.max(thick, cr)
	end
	if #cur > 0 then
		table.insert(lines, { cur, used, thick })
	end
	return lines
end
local function listContent(lay, kids, cw, ch, k)
	local horiz = EN(lay, "FillDirection") == "Horizontal"
	local pad = ud(P(lay, "Padding"), if horiz then cw else ch, k)
	local main, cross = 0, 0
	if P(lay, "Wraps") == true then
		local lines = wrapLines(kids, horiz, pad, if horiz then cw else ch)
		for i, ln in lines do
			main = math.max(main, ln[2])
			cross += ln[3] + (if i > 1 then pad else 0)
		end
	else
		for i, c in kids do
			main += (if horiz then c.lay.w else c.lay.h) + (if i > 1 then pad else 0)
			cross = math.max(cross, if horiz then c.lay.h else c.lay.w)
		end
	end
	if horiz then
		return main, cross
	end
	return cross, main
end
local function gridDims(grid, n, cw, ch, k)
	local cell, cpad = P(grid, "CellSize"), P(grid, "CellPadding")
	local cwid, chei = ud(cell.X, cw, k), ud(cell.Y, ch, k)
	local px, py = ud(cpad.X, cw, k), ud(cpad.Y, ch, k)
	local vertical = EN(grid, "FillDirection") == "Vertical"
	local per
	if vertical then
		per = math.max(1, math.floor((ch + py) / math.max(1e-6, chei + py)))
	else
		per = math.max(1, math.floor((cw + px) / math.max(1e-6, cwid + px)))
	end
	local mx = P(grid, "FillDirectionMaxCells") or 0
	if mx > 0 then
		per = math.min(per, mx)
	end
	local cols, rows
	if vertical then
		cols, rows = math.ceil(n / per), math.min(n, per)
	else
		rows, cols = math.ceil(n / per), math.min(n, per)
	end
	return cwid, chei, px, py, per, cols, rows, vertical
end
local function gridContent(grid, n, cw, ch, k)
	if n == 0 then
		return 0, 0
	end
	local cwid, chei, px, py, _, cols, rows = gridDims(grid, n, cw, ch, k)
	return cols * cwid + (cols - 1) * px, rows * chei + (rows - 1) * py
end

local function visibleKids(d)
	local out = {}
	for _, c in guiKids(d) do
		if visible(c) then
			table.insert(out, c)
		end
	end
	return out
end

local function contentExtent(d, w, h, k, auto)
	local pl, pt, pr, pb = padding(d, w, h, k)
	local cw, ch = 0, 0
	if TEXT_CLS[d.cls] then
		local wrapw = nil
		if auto == "Y" and (P(d, "TextWrapped") == true or P(d, "TextScaled") == true) then
			wrapw = math.max(1, w - pl - pr)
		end
		local tw, th = textBounds(d, (P(d, "TextSize") or 14) * k, wrapw, k)
		cw, ch = tw + pl + pr, th + pt + pb
	end
	local innerW, innerH = math.max(0, w - pl - pr), math.max(0, h - pt - pb)
	local kids = visibleKids(d)
	if #kids > 0 then
		for _, c in kids do
			measure(c, innerW, innerH, k)
		end
		local lay = layoutOf(d)
		if lay and lay.cls == "UIListLayout" then
			local lw, lh = listContent(lay, kids, innerW, innerH, k)
			cw, ch = math.max(cw, lw + pl + pr), math.max(ch, lh + pt + pb)
		elseif lay and lay.cls == "UIGridLayout" then
			local gw, gh = gridContent(lay, #kids, innerW, innerH, k)
			cw, ch = math.max(cw, gw + pl + pr), math.max(ch, gh + pt + pb)
		else
			for _, c in kids do
				local pos, ap = P(c, "Position"), P(c, "AnchorPoint")
				local ex = pos.X.Scale * innerW + pos.X.Offset * k - ap.X * c.lay.w + c.lay.w
				local ey = pos.Y.Scale * innerH + pos.Y.Offset * k - ap.Y * c.lay.h + c.lay.h
				cw, ch = math.max(cw, ex + pl + pr), math.max(ch, ey + pt + pb)
			end
		end
	end
	return cw, ch
end

local function kidsExtent(d, kids, cw, ch, k)
	local pl, pt, pr, pb = padding(d, cw, ch, k)
	local lay = layoutOf(d)
	if lay and lay.cls == "UIListLayout" then
		local lw, lh = listContent(lay, kids, cw - pl - pr, ch - pt - pb, k)
		return lw + pl + pr, lh + pt + pb
	elseif lay and lay.cls == "UIGridLayout" then
		local gw, gh = gridContent(lay, #kids, cw - pl - pr, ch - pt - pb, k)
		return gw + pl + pr, gh + pt + pb
	end
	local ew, eh = 0, 0
	for _, c in kids do
		local pos, ap = P(c, "Position"), P(c, "AnchorPoint")
		ew = math.max(ew, pos.X.Offset * k + pos.X.Scale * cw - ap.X * c.lay.w + c.lay.w + pl + pr)
		eh = math.max(eh, pos.Y.Offset * k + pos.Y.Scale * ch - ap.Y * c.lay.h + c.lay.h + pt + pb)
	end
	return ew, eh
end

local function lay(d)
	local L = d.lay
	if L == nil then
		L = {}
		d.lay = L
	end
	return L
end

local pass = 0
function measure(d, pw, ph, pk)
	local L = lay(d)
	if L.pass == pass and L.pw == pw and L.ph == ph and L.pk == pk then
		return L.w, L.h -- already measured with the same inputs in this layout pass
	end
	L.pass, L.pw, L.ph, L.pk = pass, pw, ph, pk
	local s = ownScale(d)
	local size = P(d, "Size")
	local w = ud(size.X, pw, pk)
	local h = ud(size.Y, ph, pk)
	w, h = constrain(d, w, h, pk)
	w, h = w * s, h * s
	local k = pk * s
	L.k = k
	local auto = EN(d, "AutomaticSize") or "None"
	if auto ~= "None" then
		local cw, ch = contentExtent(d, w, h, k, auto)
		if auto == "X" or auto == "XY" then
			w = math.max(w, cw)
		end
		if auto == "Y" or auto == "XY" then
			h = math.max(h, ch)
		end
	end
	L.w, L.h = math.max(0, w), math.max(0, h)
	measureChildren(d)
	return L.w, L.h
end

function measureChildren(d)
	local L = d.lay
	local w, h, k = L.w, L.h, L.k
	local kids = guiKids(d)
	if d.cls == "ScrollingFrame" then
		-- the canvas is never smaller than the window; a shown scroll bar with an inset narrows the window
		local cs = P(d, "CanvasSize")
		local auto = EN(d, "AutomaticCanvasSize") or "None"
		local thick = (P(d, "ScrollBarThickness") or 12) * k
		local dir = EN(d, "ScrollingDirection") or "XY"
		local vin, hin = EN(d, "VerticalScrollBarInset") or "None", EN(d, "HorizontalScrollBarInset") or "None"
		local function canvasFor(winW, winH)
			local cw, ch = math.max(ud(cs.X, w, k), winW), math.max(ud(cs.Y, h, k), winH)
			local ipl, ipt, ipr, ipb = padding(d, cw, ch, k)
			for _, c in kids do
				measure(c, math.max(0, cw - ipl - ipr), math.max(0, ch - ipt - ipb), k)
			end
			if auto ~= "None" then
				local vk = {}
				for _, c in kids do
					if visible(c) then
						table.insert(vk, c)
					end
				end
				local ew, eh = kidsExtent(d, vk, cw, ch, k)
				if auto == "X" or auto == "XY" then
					cw = math.max(cw, ew)
				end
				if auto == "Y" or auto == "XY" then
					ch = math.max(ch, eh)
				end
			end
			return cw, ch
		end
		local winW, winH = w, h
		local cw, ch = canvasFor(winW, winH)
		local vbar = (dir == "XY" or dir == "Y") and ch > winH + 0.5
		local hbar = (dir == "XY" or dir == "X") and cw > winW + 0.5
		local nw = if vin == "Always" or (vin == "ScrollBar" and vbar) then w - thick else w
		local nh = if hin == "Always" or (hin == "ScrollBar" and hbar) then h - thick else h
		if nw ~= winW or nh ~= winH then
			cw, ch = canvasFor(math.max(0, nw), math.max(0, nh))
		end
		L.cw, L.ch = cw, ch
		return
	end
	local pl, pt, pr, pb = padding(d, w, h, k)
	local innerW, innerH = math.max(0, w - pl - pr), math.max(0, h - pt - pb)
	local lyt = layoutOf(d)
	local grid = lyt and lyt.cls == "UIGridLayout"
	for _, c in kids do
		if grid and visible(c) then
			local cell = P(lyt, "CellSize")
			local CL = lay(c)
			CL.k = k * ownScale(c)
			CL.w, CL.h = ud(cell.X, innerW, k), ud(cell.Y, innerH, k)
			measureChildren(c)
		else
			measure(c, innerW, innerH, k)
		end
	end
end

local function placeList(lyt, kids, cx, cy, cw, ch, k, clip)
	local horiz = EN(lyt, "FillDirection") == "Horizontal"
	local pad = ud(P(lyt, "Padding"), if horiz then cw else ch, k)
	local ha, va = EN(lyt, "HorizontalAlignment"), EN(lyt, "VerticalAlignment")
	local limit = if horiz then cw else ch
	local flex = if horiz then EN(lyt, "HorizontalFlex") else EN(lyt, "VerticalFlex")
	local lines
	if P(lyt, "Wraps") == true then
		lines = wrapLines(kids, horiz, pad, limit)
	else
		local used, thick = 0, 0
		for i, c in kids do
			used += (if horiz then c.lay.w else c.lay.h) + (if i > 1 then pad else 0)
			thick = math.max(thick, if horiz then c.lay.h else c.lay.w)
		end
		lines = { { kids, used, thick } }
	end
	local cpos = 0
	if #lines > 1 then
		local total = 0
		for i, ln in lines do
			total += ln[3] + (if i > 1 then pad else 0)
		end
		local crossAvail = if horiz then ch else cw
		local ca = if horiz then va else ha
		if ca == "Center" then
			cpos = (crossAvail - total) / 2
		elseif ca == "Bottom" or ca == "Right" then
			cpos = crossAvail - total
		end
	end
	for _, ln in lines do
		local line, used, thick = ln[1], ln[2], ln[3]
		local free = limit - used
		local gap, start = pad, 0
		local grew = false
		if flex == "Fill" and free > 0 then
			local share = free / math.max(1, #line)
			for _, c in line do
				if horiz then
					c.lay.w += share
				else
					c.lay.h += share
				end
				measureChildren(c)
			end
			free, grew = 0, true
		else
			local growers = {}
			for _, c in line do
				local fi = comps(c).UIFlexItem
				local fm = fi and EN(fi, "FlexMode")
				if fm == "Grow" or fm == "Fill" or fm == "Custom" then
					table.insert(growers, c)
				end
			end
			if #growers > 0 and free > 0 then
				local share = free / #growers
				for _, c in growers do
					if horiz then
						c.lay.w += share
					else
						c.lay.h += share
					end
					measureChildren(c)
				end
				free, grew = 0, true
			end
		end
		if not grew and flex == "SpaceBetween" and #line > 1 and free > 0 then
			gap = pad + free / (#line - 1)
		elseif not grew and flex == "SpaceAround" and free > 0 then
			gap = pad + free / #line
			start = free / #line / 2
		elseif not grew and flex == "SpaceEvenly" and free > 0 then
			gap = pad + free / (#line + 1)
			start = free / (#line + 1)
		else
			local ma = if horiz then ha else va
			if ma == "Center" then
				start = free / 2
			elseif ma == "Right" or ma == "Bottom" then
				start = free
			end
		end
		local m = start
		for _, c in line do
			local L = c.lay
			if horiz then
				local yy
				if #lines > 1 then
					yy = if va == "Center" then cpos + (thick - L.h) / 2 elseif va == "Bottom" then cpos + thick - L.h else cpos
				else
					yy = if va == "Center" then (ch - L.h) / 2 elseif va == "Bottom" then ch - L.h else 0
				end
				place(c, cx + m, cy + yy, clip)
				m += L.w + gap
			else
				local xx
				if #lines > 1 then
					xx = if ha == "Center" then cpos + (thick - L.w) / 2 elseif ha == "Right" then cpos + thick - L.w else cpos
				else
					xx = if ha == "Center" then (cw - L.w) / 2 elseif ha == "Right" then cw - L.w else 0
				end
				place(c, cx + xx, cy + m, clip)
				m += L.h + gap
			end
		end
		cpos += thick + pad
	end
	local cwT, chT = listContent(lyt, kids, cw, ch, k)
	local LL = lay(lyt)
	LL.cw, LL.ch = cwT, chT
end

local function placeGrid(grid, kids, cx, cy, cw, ch, k, clip)
	local n = #kids
	local cwid, chei, px, py, per, cols, rows, vertical = gridDims(grid, n, cw, ch, k)
	local gw = cols * cwid + math.max(0, cols - 1) * px
	local gh = rows * chei + math.max(0, rows - 1) * py
	local ha, va = EN(grid, "HorizontalAlignment"), EN(grid, "VerticalAlignment")
	local ox = if ha == "Center" then (cw - gw) / 2 elseif ha == "Right" then cw - gw else 0
	local oy = if va == "Center" then (ch - gh) / 2 elseif va == "Bottom" then ch - gh else 0
	local corner = EN(grid, "StartCorner") or "TopLeft"
	for i, c in kids do
		local idx = i - 1
		local col, row
		if vertical then
			col, row = idx // per, idx % per
		else
			row, col = idx // per, idx % per
		end
		if string.find(corner, "Right", 1, true) then
			col = cols - 1 - col
		end
		if string.find(corner, "Bottom", 1, true) then
			row = rows - 1 - row
		end
		c.lay.w, c.lay.h = cwid, chei
		measureChildren(c)
		place(c, cx + ox + col * (cwid + px), cy + oy + row * (chei + py), clip)
	end
	local LL = lay(grid)
	LL.cw, LL.ch = (if n > 0 then gw else 0), (if n > 0 then gh else 0)
end

local function placeKids(d, kids, cx, cy, cw, ch, k, clip)
	local lyt = layoutOf(d)
	if lyt then
		local vis, hidden = {}, {}
		for _, c in kids do
			if visible(c) then
				table.insert(vis, c)
			else
				table.insert(hidden, c)
			end
		end
		vis = sortedKids(lyt, vis)
		if lyt.cls == "UIGridLayout" then
			placeGrid(lyt, vis, cx, cy, cw, ch, k, clip)
		else
			placeList(lyt, vis, cx, cy, cw, ch, k, clip)
		end
		kids = hidden
	end
	for _, c in kids do
		local L = c.lay
		local pos, ap = P(c, "Position"), P(c, "AnchorPoint")
		place(c, cx + pos.X.Scale * cw + pos.X.Offset * k - ap.X * L.w, cy + pos.Y.Scale * ch + pos.Y.Offset * k - ap.Y * L.h, clip)
	end
end

function place(d, x, y, clip)
	local L = d.lay
	L.x, L.y = x, y
	L.clip = clip
	local w, h, k = L.w, L.h, L.k
	local myclip = clip
	if d.cls == "ScrollingFrame" or P(d, "ClipsDescendants") == true then
		local r = { x, y, x + w, y + h }
		if clip then
			r = { math.max(clip[1], r[1]), math.max(clip[2], r[2]), math.min(clip[3], r[3]), math.min(clip[4], r[4]) }
		end
		myclip = r
	end
	local kids = guiKids(d)
	if #kids == 0 then
		return
	end
	if d.cls == "ScrollingFrame" then
		local cw, ch = L.cw or w, L.ch or h
		local cp = P(d, "CanvasPosition") or v2(0, 0)
		local pl, pt, pr, pb = padding(d, cw, ch, k)
		placeKids(d, kids, x - cp.X + pl, y - cp.Y + pt, cw - pl - pr, ch - pt - pb, k, myclip)
		return
	end
	local pl, pt, pr, pb = padding(d, w, h, k)
	placeKids(d, kids, x + pl, y + pt, w - pl - pr, h - pt - pb, k, myclip)
end

------------------------------------------------------------------ roots and caching
local function rootRect(d)
	-- E.guiViewport: the GUI still laid out for an earlier screen (Roblox lays ScreenGuis out after the camera's
	-- ViewportSize changes; the scenario "shelflate" holds that moment)
	local vp = E.guiViewport or E.viewport
	if d.cls == "ScreenGui" then
		local full = P(d, "IgnoreGuiInset") == true or EN(d, "ScreenInsets") == "None"
		if full then
			return 0, 0, vp.X, vp.Y
		end
		return 0, E.inset, vp.X, vp.Y - E.inset
	end
	-- BillboardGui / SurfaceGui: their own pixel size
	local s = d.props.Size
	if s and E.typeof(s) == "UDim2" then
		return 0, 0, s.X.Offset, s.Y.Offset
	end
	return 0, 0, 0, 0
end

local function layoutRoot(d)
	G.stats.layouts += 1
	pass += 1
	local x, y, w, h = rootRect(d)
	local L = lay(d)
	L.x, L.y, L.w, L.h, L.k = x, y, w, h, 1
	L.clip = nil
	for _, c in guiKids(d) do
		measure(c, w, h, 1)
		local CL = c.lay
		local pos, ap = P(c, "Position"), P(c, "AnchorPoint")
		place(c, x + pos.X.Scale * w + pos.X.Offset - ap.X * CL.w, y + pos.Y.Scale * h + pos.Y.Offset - ap.Y * CL.h, nil)
	end
end

local function rootOf(d)
	local cur = d
	local guard = 0
	while cur and guard < 200 do
		guard += 1
		if isA(cur.cls, "LayerCollector") then
			return cur
		end
		local p = cur.props.Parent
		cur = p and getD(p)
	end
	return nil
end
G.rootOf = rootOf

local function vpKey()
	local vp = E.guiViewport or E.viewport
	return vp.X .. "x" .. vp.Y .. "/" .. E.inset
end

-- Lays out the root of d when needed; returns d.lay (nil when d is not under a LayerCollector).
local function ensure(d)
	local root = rootOf(d)
	if not root then
		return nil
	end
	local key = vpKey()
	if root.layDone ~= (root.guiVer or 0) or root.layVp ~= key then
		root.layDone = root.guiVer or 0
		root.layVp = key
		layoutRoot(root)
	end
	local L = d.lay
	if L == nil or L.x == nil then
		-- not reached by the layout (e.g. a GuiObject under a non-GUI parent inside the root)
		return nil
	end
	return L
end
G.ensure = ensure

------------------------------------------------------------------ invalidation
local VISUAL_ONLY = {
	BackgroundColor3 = true, BackgroundTransparency = true, TextColor3 = true, TextTransparency = true,
	ImageColor3 = true, ImageTransparency = true, BorderColor3 = true, TextStrokeColor3 = true,
	TextStrokeTransparency = true, Color = true, Transparency = true, Rotation = true, ZIndex = true,
	AutoButtonColor = true, Active = true, Selectable = true, GroupTransparency = true, GroupColor3 = true,
	Image = true, ImageContent = true, ResampleMode = true, CurrentCamera = true, Ambient = true, LightColor = true,
	LightDirection = true, ScrollBarImageColor3 = true, ScrollBarImageTransparency = true, Interactable = true,
	PlaceholderColor3 = true, ZIndexBehavior = true, DisplayOrder = true, Offset = true, Enabled = true,
	ResetOnSpawn = true, SelectionImageObject = true, Modal = true, ClearTextOnFocus = true, TextEditable = true,
	ApplyStrokeMode = false, LineJoinMode = true, ScrollingEnabled = true, ElasticBehavior = true,
}
local function bump(d)
	local root = rootOf(d)
	if root then
		root.guiVer = (root.guiVer or 0) + 1
	end
end
G.bump = bump
local function guiRelevant(cls)
	return GUI_OBJ[cls] or isA(cls, "UIComponent") or isA(cls, "LayerCollector") or cls == "Folder"
end
local prevWrite = I.onPropWrite
I.onPropWrite = function(self, d, k)
	if prevWrite then
		prevWrite(self, d, k)
	end
	if VISUAL_ONLY[k] == true then
		return
	end
	if guiRelevant(d.cls) then
		d.layStamp = (d.layStamp or 0) + 1
		bump(d)
	end
end
local prevReparent = I.onReparent
I.onReparent = function(subtree, old, new)
	if prevReparent then
		prevReparent(subtree, old, new)
	end
	local top = subtree[1]
	local td = getD(top)
	if not guiRelevant(td.cls) then
		return
	end
	if old then
		local od = getD(old)
		od.layStamp = (od.layStamp or 0) + 1
		bump(od)
	end
	if new then
		local nd = getD(new)
		nd.layStamp = (nd.layStamp or 0) + 1
		bump(nd)
	end
	bump(td)
end

------------------------------------------------------------------ engine properties
local GET = I.GET
local fallbackAbs = I.guiAbs
local function absOf(self)
	local d = getD(self)
	local L = ensure(d)
	if L then
		return L
	end
	return nil
end
GET.GuiBase2d = GET.GuiBase2d or {}
GET.GuiBase2d.AbsoluteSize = function(self)
	local L = absOf(self)
	if L then
		return v2(L.w, L.h)
	end
	if isA(getD(self).cls, "LayerCollector") then
		return v2(0, 0)
	end
	return v2(0, 0)
end
GET.GuiBase2d.AbsolutePosition = function(self)
	local L = absOf(self)
	if L then
		-- AbsolutePosition is in inset-excluded screen space (y = 0 under the top bar)
		return v2(L.x, L.y - E.inset)
	end
	return v2(0, 0)
end
GET.GuiBase2d.AbsoluteRotation = function(self)
	local total, cur = 0, self
	while cur do
		local d = getD(cur)
		if GUI_OBJ[d.cls] then
			total += P(d, "Rotation") or 0
		end
		if isA(d.cls, "LayerCollector") then
			break
		end
		cur = d.props.Parent
	end
	return total
end
local function textBox(d, L)
	local pl, pt, pr, pb = padding(d, L.w, L.h, L.k)
	return pl, pt, math.max(0, L.w - pl - pr), math.max(0, L.h - pt - pb), pr, pb
end
local function textGet(self, d)
	local L = ensure(d)
	if not L then
		return v2(0, 0)
	end
	local _, _, bw, bh = textBox(d, L)
	local wrap = if P(d, "TextWrapped") == true or P(d, "TextScaled") == true then math.max(1, bw) else nil
	local size = drawSize(d, L.k, bw, bh)
	local w, h = textBounds(d, size, wrap, L.k)
	return v2(w, h)
end
GET.TextLabel = GET.TextLabel or {}
GET.TextLabel.TextBounds = textGet
GET.TextLabel.TextFits = function(self, d)
	local L = ensure(d)
	if not L then
		return true
	end
	local b = textGet(self, d)
	return b.X <= L.w + 0.5 and b.Y <= L.h + 0.5
end
GET.TextButton = GET.TextLabel
GET.TextBox = GET.TextLabel
GET.ScrollingFrame = GET.ScrollingFrame or {}
GET.ScrollingFrame.AbsoluteCanvasSize = function(self, d)
	local L = ensure(d)
	if not L then
		return v2(0, 0)
	end
	return v2(L.cw or L.w, L.ch or L.h)
end
GET.ScrollingFrame.AbsoluteWindowSize = function(self, d)
	local L = ensure(d)
	if not L then
		return v2(0, 0)
	end
	return v2(L.w, L.h)
end
GET.UIGridStyleLayout = GET.UIGridStyleLayout or {}
GET.UIGridStyleLayout.AbsoluteContentSize = function(self, d)
	local parent = d.props.Parent
	if parent == nil then
		return v2(0, 0)
	end
	local pd = getD(parent)
	local L = ensure(pd)
	if not L then
		return v2(0, 0)
	end
	local LL = d.lay
	if LL and LL.cw then
		return v2(LL.cw, LL.ch)
	end
	-- the layout is not the active one (a second layout object) or nothing is visible: measure the visible kids
	local kids = visibleKids(pd)
	local k = L.k or 1
	local pl, pt, pr, pb = padding(pd, L.w, L.h, k)
	if d.cls == "UIGridLayout" then
		local gw, gh = gridContent(d, #kids, L.w - pl - pr, L.h - pt - pb, k)
		return v2(gw, gh)
	end
	local cw, ch = listContent(d, kids, L.w - pl - pr, L.h - pt - pb, k)
	return v2(cw, ch)
end

------------------------------------------------------------------ change signals (once per frame)
local WATCHED = { AbsoluteSize = true, AbsolutePosition = true, AbsoluteContentSize = true, TextBounds = true, AbsoluteCanvasSize = true, AbsoluteWindowSize = true, TextFits = true }
local watched = setmetatable({}, { __mode = "k" }) -- inst -> { [prop] = lastValue | false }
local prevGPCS = I.IMPL.Object.GetPropertyChangedSignal
I.IMPL.Object.GetPropertyChangedSignal = function(self, prop)
	local sig = prevGPCS(self, prop)
	if WATCHED[prop] then
		local w = watched[self]
		if not w then
			w = {}
			watched[self] = w
		end
		if w[prop] == nil then
			w[prop] = false -- fires once at the next check (Roblox fires when the first layout assigns it)
		end
	end
	return sig
end
function G.fireChanges()
	for inst, props in watched do
		local d = getD(inst)
		if d.destroyed then
			watched[inst] = nil
			continue
		end
		local ps = d.propSigs
		for prop, last in props do
			local sig = ps[prop]
			if sig and #sig.conns > 0 then
				local ok, cur = pcall(function()
					return inst[prop]
				end)
				if ok then
					local key = tostring(cur)
					if key ~= last then
						props[prop] = key
						G.stats.fires += 1
						I.fire(sig)
					end
				end
			end
		end
	end
end

-- hook the frame loop: layout reactions run after Heartbeat, like Roblox's GUI update before the next render
local step = E.step
E.step = function(dt)
	step(dt)
	local t0 = os.clock()
	G.fireChanges()
	E.flushDeferred()
	if E.coTime then
		E.coTime["<gui layout>"] = (E.coTime["<gui layout>"] or 0) + (os.clock() - t0)
	end
end

------------------------------------------------------------------ dump support
-- Text layout for drawing: the font size and the lines of segments.
function G.textLayout(d)
	local L = ensure(d)
	if not L then
		return nil
	end
	local text, placeholder = shownText(d)
	if text == "" then
		return nil
	end
	local pl, pt, bw, bh, pr, pb = textBox(d, L)
	local wrap = if P(d, "TextWrapped") == true or P(d, "TextScaled") == true then math.max(1, bw) else nil
	local size = drawSize(d, L.k, bw, bh)
	local lines, widths, heights = setText(d, text, size, wrap, L.k)
	return { size = size, lines = lines, widths = widths, heights = heights, placeholder = placeholder, pad = { pl, pt, pr, pb } }
end

return G
