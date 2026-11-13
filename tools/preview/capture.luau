-- Capture for the preview tool: a real pixel store behind the fake EditableImage, and dumps of what a client shows
-- (EditableImage pixels as hex rows, the PlayerGui tree with the raw GUI properties, the 3D parts of every visible
-- ViewportFrame, the workspace parts with the camera) printed to stdout between @@ markers for topng.py.
local E = require("./engine")
local I = require("./inst")
local R = require("./raycast")
local G = require("./guiengine")
local getD = I.getD
local IMPL = I.IMPL
local v2 = E.v2
local typeOf = E.typeof

local C = {}

------------------------------------------------------------------ EditableImage with pixels
local function imgState(self)
	local d = getD(self)
	if d.destroyed then
		error("EditableImage was destroyed", 3)
	end
	local size = d.props.Size
	if d.pix == nil then
		d.pix = buffer.create(size.X * size.Y * 4) -- transparent black, like a new EditableImage
		d.writes = 0
	end
	return d, size.X, size.Y
end

local function clipRect(W, H, x, y, w, h)
	local x0, y0 = math.max(0, x), math.max(0, y)
	local x1, y1 = math.min(W, x + w), math.min(H, y + h)
	return x0, y0, x1 - x0, y1 - y0
end

local function blendPixel(pix, o, r, g, b, a, mode)
	-- mode: "BlendSourceOver" (default) or "Overwrite"
	if mode == "Overwrite" or a >= 255 then
		buffer.writeu8(pix, o, r)
		buffer.writeu8(pix, o + 1, g)
		buffer.writeu8(pix, o + 2, b)
		buffer.writeu8(pix, o + 3, a)
		return
	end
	if a <= 0 then
		return
	end
	local sa = a / 255
	local da = buffer.readu8(pix, o + 3) / 255
	local oa = sa + da * (1 - sa)
	local function mix(sc, dc)
		if oa <= 0 then
			return 0
		end
		return math.floor((sc * sa + dc * da * (1 - sa)) / oa + 0.5)
	end
	buffer.writeu8(pix, o, mix(r, buffer.readu8(pix, o)))
	buffer.writeu8(pix, o + 1, mix(g, buffer.readu8(pix, o + 1)))
	buffer.writeu8(pix, o + 2, mix(b, buffer.readu8(pix, o + 2)))
	buffer.writeu8(pix, o + 3, math.floor(oa * 255 + 0.5))
end

local function enumName(v)
	if v == nil or v == false then
		return nil
	end
	if type(v) == "table" then
		return rawget(v, "Name")
	end
	return tostring(v)
end

local function colorBytes(c, transparency)
	local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	local a = math.clamp(math.floor((1 - (transparency or 0)) * 255 + 0.5), 0, 255)
	return r, g, b, a
end

local old = IMPL.EditableImage
IMPL.EditableImage = {
	WritePixelsBuffer = function(self, pos, size, buf)
		local d, W, H = imgState(self)
		if typeOf(pos) ~= "Vector2" or typeOf(size) ~= "Vector2" or type(buf) ~= "buffer" then
			error("WritePixelsBuffer: (Vector2, Vector2, buffer) expected", 2)
		end
		local px, py, sw, sh = math.floor(pos.X), math.floor(pos.Y), math.floor(size.X), math.floor(size.Y)
		if px < 0 or py < 0 or px + sw > W or py + sh > H then
			error("WritePixelsBuffer: region out of bounds", 2)
		end
		if buffer.len(buf) ~= sw * sh * 4 then
			error(string.format("WritePixelsBuffer: buffer length %d does not match %dx%dx4", buffer.len(buf), sw, sh), 2)
		end
		local pix = d.pix
		if px == 0 and sw == W then
			buffer.copy(pix, py * W * 4, buf, 0, sw * sh * 4)
		else
			for row = 0, sh - 1 do
				buffer.copy(pix, ((py + row) * W + px) * 4, buf, row * sw * 4, sw * 4)
			end
		end
		d.writes += 1
		d.lastWrite = E.frame
		E.imageWrites += 1
		C.pixelsWritten = (C.pixelsWritten or 0) + sw * sh
	end,
	ReadPixelsBuffer = function(self, pos, size)
		local d, W, H = imgState(self)
		local px, py, sw, sh = math.floor(pos.X), math.floor(pos.Y), math.floor(size.X), math.floor(size.Y)
		if px < 0 or py < 0 or px + sw > W or py + sh > H then
			error("ReadPixelsBuffer: region out of bounds", 2)
		end
		local out = buffer.create(sw * sh * 4)
		for row = 0, sh - 1 do
			buffer.copy(out, row * sw * 4, d.pix, ((py + row) * W + px) * 4, sw * 4)
		end
		return out
	end,
	WritePixels = function(self, pos, size, arr)
		local d, W = imgState(self)
		local px, py, sw, sh = math.floor(pos.X), math.floor(pos.Y), math.floor(size.X), math.floor(size.Y)
		local k = 1
		for row = 0, sh - 1 do
			for col = 0, sw - 1 do
				local o = ((py + row) * W + px + col) * 4
				for ch = 0, 3 do
					buffer.writeu8(d.pix, o + ch, math.clamp(math.floor((arr[k] or 0) * 255 + 0.5), 0, 255))
					k += 1
				end
			end
		end
		d.writes += 1
		E.imageWrites += 1
	end,
	ReadPixels = function(self, pos, size)
		local d, W = imgState(self)
		local out = {}
		local px, py, sw, sh = math.floor(pos.X), math.floor(pos.Y), math.floor(size.X), math.floor(size.Y)
		for row = 0, sh - 1 do
			for col = 0, sw - 1 do
				local o = ((py + row) * W + px + col) * 4
				for ch = 0, 3 do
					table.insert(out, buffer.readu8(d.pix, o + ch) / 255)
				end
			end
		end
		return out
	end,
	DrawRectangle = function(self, pos, size, color, transparency, combine)
		local d, W, H = imgState(self)
		local x0, y0, w, h = clipRect(W, H, math.floor(pos.X), math.floor(pos.Y), math.floor(size.X), math.floor(size.Y))
		local r, g, b, a = colorBytes(color, transparency)
		local mode = enumName(combine) or "BlendSourceOver"
		for y = y0, y0 + h - 1 do
			for x = x0, x0 + w - 1 do
				blendPixel(d.pix, (y * W + x) * 4, r, g, b, a, mode)
			end
		end
		d.writes += 1
		E.imageWrites += 1
	end,
	DrawCircle = function(self, center, radius, color, transparency, combine)
		local d, W, H = imgState(self)
		local r, g, b, a = colorBytes(color, transparency)
		local mode = enumName(combine) or "BlendSourceOver"
		local cx, cy = center.X, center.Y
		for y = math.max(0, math.floor(cy - radius)), math.min(H - 1, math.ceil(cy + radius)) do
			for x = math.max(0, math.floor(cx - radius)), math.min(W - 1, math.ceil(cx + radius)) do
				if (x - cx) ^ 2 + (y - cy) ^ 2 <= radius * radius then
					blendPixel(d.pix, (y * W + x) * 4, r, g, b, a, mode)
				end
			end
		end
		d.writes += 1
		E.imageWrites += 1
	end,
	DrawLine = function(self, p0, p1, color, transparency, combine)
		local d, W, H = imgState(self)
		local r, g, b, a = colorBytes(color, transparency)
		local mode = enumName(combine) or "BlendSourceOver"
		local x0, y0, x1, y1 = math.floor(p0.X), math.floor(p0.Y), math.floor(p1.X), math.floor(p1.Y)
		local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
		for i = 0, n do
			local x = math.floor(x0 + (x1 - x0) * i / n + 0.5)
			local y = math.floor(y0 + (y1 - y0) * i / n + 0.5)
			if x >= 0 and y >= 0 and x < W and y < H then
				blendPixel(d.pix, (y * W + x) * 4, r, g, b, a, mode)
			end
		end
		d.writes += 1
		E.imageWrites += 1
	end,
	DrawImage = function(self, pos, img, combine)
		local d, W, H = imgState(self)
		local sd, SW, SH = imgState(img)
		local mode = enumName(combine) or "BlendSourceOver"
		local px, py = math.floor(pos.X), math.floor(pos.Y)
		for y = 0, SH - 1 do
			for x = 0, SW - 1 do
				local tx, ty = px + x, py + y
				if tx >= 0 and ty >= 0 and tx < W and ty < H then
					local so = (y * SW + x) * 4
					blendPixel(d.pix, (ty * W + tx) * 4, buffer.readu8(sd.pix, so), buffer.readu8(sd.pix, so + 1), buffer.readu8(sd.pix, so + 2), buffer.readu8(sd.pix, so + 3), mode)
				end
			end
		end
		d.writes += 1
		E.imageWrites += 1
	end,
	Destroy = function(self)
		local d = getD(self)
		d.destroyed = true
		d.pix = nil
	end,
}
for k, f in old do
	if IMPL.EditableImage[k] == nil then
		IMPL.EditableImage[k] = f
	end
end

------------------------------------------------------------------ JSON
local HEX = {}
for i = 0, 255 do
	HEX[i] = string.format("%02x", i)
end
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function jstr(s)
	s = string.gsub(s, '[%c"\\]', function(ch)
		return ESC[ch] or string.format("\\u%04x", string.byte(ch))
	end)
	return '"' .. s .. '"'
end
local function jnum(n)
	if n ~= n or n == math.huge or n == -math.huge then
		return "null"
	end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.6g", n)
end

local function idOf(inst)
	return getD(inst).id
end

-- Serialises one property value (Roblox datatypes as arrays / tagged objects).
local function jval(v)
	local t = typeOf(v)
	if v == nil then
		return "null"
	elseif t == "number" then
		return jnum(v)
	elseif t == "boolean" then
		return if v then "true" else "false"
	elseif t == "string" then
		return jstr(v)
	elseif t == "Vector2" then
		return "[" .. jnum(v.X) .. "," .. jnum(v.Y) .. "]"
	elseif t == "Vector3" then
		return "[" .. jnum(v.X) .. "," .. jnum(v.Y) .. "," .. jnum(v.Z) .. "]"
	elseif t == "UDim2" then
		return "[" .. jnum(v.X.Scale) .. "," .. jnum(v.X.Offset) .. "," .. jnum(v.Y.Scale) .. "," .. jnum(v.Y.Offset) .. "]"
	elseif t == "UDim" then
		return "[" .. jnum(v.Scale) .. "," .. jnum(v.Offset) .. "]"
	elseif t == "Color3" then
		return "[" .. jnum(v.R) .. "," .. jnum(v.G) .. "," .. jnum(v.B) .. "]"
	elseif t == "EnumItem" then
		return jstr(rawget(v, "Name"))
	elseif t == "Instance" then
		return '{"inst":' .. jnum(idOf(v)) .. ',"cls":' .. jstr(getD(v).cls) .. "}"
	elseif t == "CFrame" then
		local parts = { v:GetComponents() }
		for i, x in parts do
			parts[i] = jnum(x)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	elseif t == "ColorSequence" then
		local out = {}
		for _, kp in v.Keypoints do
			table.insert(out, "[" .. jnum(kp.Time) .. "," .. jnum(kp.Value.R) .. "," .. jnum(kp.Value.G) .. "," .. jnum(kp.Value.B) .. "]")
		end
		return '{"cs":[' .. table.concat(out, ",") .. "]}"
	elseif t == "NumberSequence" then
		local out = {}
		for _, kp in v.Keypoints do
			table.insert(out, "[" .. jnum(kp.Time) .. "," .. jnum(kp.Value) .. "," .. jnum(kp.Envelope or 0) .. "]")
		end
		return '{"ns":[' .. table.concat(out, ",") .. "]}"
	elseif t == "Font" then
		return '{"family":' .. jstr(tostring(v.Family)) .. ',"weight":' .. jstr(enumName(v.Weight) or "Regular") .. ',"style":' .. jstr(enumName(v.Style) or "Normal") .. "}"
	elseif t == "Content" then
		local st = v.SourceType
		if st == "Object" and v.Object then
			return '{"src":"Object","inst":' .. jnum(idOf(v.Object)) .. ',"cls":' .. jstr(getD(v.Object).cls) .. "}"
		elseif st == "Uri" then
			return '{"src":"Uri","uri":' .. jstr(tostring(v.Uri)) .. "}"
		end
		return "null"
	elseif t == "Rect" then
		return "[" .. jnum(v.Min.X) .. "," .. jnum(v.Min.Y) .. "," .. jnum(v.Max.X) .. "," .. jnum(v.Max.Y) .. "]"
	elseif t == "NumberRange" then
		return "[" .. jnum(v.Min) .. "," .. jnum(v.Max) .. "]"
	end
	return jstr(tostring(v))
end
C.jval = jval
C.jstr = jstr

------------------------------------------------------------------ GUI tree dump
-- Only explicitly-set properties are written (the Python side applies Roblox's real defaults).
local GUI_PROPS = {
	"Visible", "Size", "Position", "AnchorPoint", "Rotation", "ZIndex", "LayoutOrder", "BackgroundColor3",
	"BackgroundTransparency", "BorderSizePixel", "BorderColor3", "BorderMode", "ClipsDescendants", "AutomaticSize",
	-- text
	"Text", "TextSize", "TextColor3", "TextTransparency", "Font", "FontFace", "TextScaled", "TextWrapped",
	"TextXAlignment", "TextYAlignment", "RichText", "TextStrokeColor3", "TextStrokeTransparency", "TextTruncate",
	"LineHeight", "MaxVisibleGraphemes", "PlaceholderText", "PlaceholderColor3",
	-- image
	"Image", "ImageContent", "ImageColor3", "ImageTransparency", "ResampleMode", "ScaleType", "SliceCenter",
	"ImageRectOffset", "ImageRectSize", "TileSize",
	-- scrolling
	"CanvasSize", "CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness", "ScrollBarImageColor3",
	"ScrollBarImageTransparency", "ScrollingDirection", "VerticalScrollBarInset", "HorizontalScrollBarInset",
	-- viewport / canvas group
	"Ambient", "LightColor", "LightDirection", "CurrentCamera", "GroupTransparency", "GroupColor3",
	-- layer collectors
	"Enabled", "DisplayOrder", "IgnoreGuiInset", "ScreenInsets", "ZIndexBehavior",
	-- layouts / components
	"FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "Wraps", "HorizontalFlex",
	"VerticalFlex", "ItemLineAlignment", "CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "Scale", "Thickness", "Color", "Transparency",
	"ApplyStrokeMode", "LineJoinMode", "CornerRadius", "Offset", "AspectRatio", "AspectType", "DominantAxis",
	"MinSize", "MaxSize", "MinTextSize", "MaxTextSize", "FlexMode", "GrowRatio", "ShrinkRatio",
}

local function isGuiNode(cls)
	return I.isA(cls, "GuiBase2d") or I.isA(cls, "UIComponent") or cls == "Folder"
end

local function propsJson(inst, d)
	local parts = {}
	for _, k in GUI_PROPS do
		local v = d.props[k]
		if v ~= nil and I.memberOf(d.cls, k) then
			table.insert(parts, jstr(k) .. ":" .. jval(v))
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function partJson(p)
	local d = getD(p)
	local props = d.props
	local shape = R.shapeOf(d)
	local names = { "block", "ball", "cylinder", "wedge", "cornerwedge" }
	local cf = props.CFrame or E.cf.identity
	local size = props.Size or E.v3(4, 1, 2)
	local color = props.Color or E.c3(163 / 255, 162 / 255, 165 / 255)
	local pc = d.attrs.PixelColor
	return '{"id":' .. jnum(d.id) .. ',"shape":"' .. names[shape] .. '","cf":' .. jval(cf) .. ',"size":' .. jval(size)
		.. ',"color":' .. jval(if typeOf(pc) == "Color3" then pc else color) .. ',"tr":' .. jnum(props.Transparency or 0)
		.. ',"mat":' .. jstr(enumName(props.Material) or "Plastic") .. ',"name":' .. jstr(props.Name or "") .. "}"
end
C.partJson = partJson

local function partsUnder(root, out, skip)
	for _, x in getD(root).children do
		local d = getD(x)
		if not (skip and skip[x]) then
			if I.isA(d.cls, "BasePart") and (d.props.Transparency or 0) < 0.999 then
				table.insert(out, partJson(x))
			end
			partsUnder(x, out, skip)
		end
	end
	return out
end

local function cameraJson(cam)
	if cam == nil then
		return "null"
	end
	local d = getD(cam)
	return '{"cf":' .. jval(d.props.CFrame or E.cf.identity) .. ',"fov":' .. jnum(d.props.FieldOfView or 70) .. "}"
end

local function viewportJson(vf)
	local d = getD(vf)
	local cam = d.props.CurrentCamera
	local parts = partsUnder(vf, {})
	return '{"camera":' .. cameraJson(cam) .. ',"parts":[' .. table.concat(parts, ",") .. "]}"
end

local function layoutJson(d)
	local L = d.lay
	if L == nil or L.x == nil or not (G.GUI_OBJ[d.cls] or I.isA(d.cls, "LayerCollector")) then
		return ""
	end
	local parts = { ',"r":[' .. jnum(L.x) .. "," .. jnum(L.y) .. "," .. jnum(L.w) .. "," .. jnum(L.h) .. '],"sk":' .. jnum(L.k or 1) }
	if L.clip then
		table.insert(parts, ',"cl":[' .. jnum(L.clip[1]) .. "," .. jnum(L.clip[2]) .. "," .. jnum(L.clip[3]) .. "," .. jnum(L.clip[4]) .. "]")
	end
	if d.cls == "ScrollingFrame" and L.cw then
		table.insert(parts, ',"cv":[' .. jnum(L.cw) .. "," .. jnum(L.ch) .. "]")
	end
	if G.TEXT_CLS[d.cls] then
		local ok, tl = pcall(G.textLayout, d)
		if ok and tl then
			local lines = {}
			for i, ln in tl.lines do
				local segs = {}
				for _, seg in ln do
					local st = seg[5]
					local col = if st.color then "[" .. jnum(st.color[1]) .. "," .. jnum(st.color[2]) .. "," .. jnum(st.color[3]) .. "]" else "null"
					local stroke = "null"
					if st.stroke then
						local sk = st.stroke
						stroke = "[" .. jnum(sk[1]) .. "," .. jnum(sk[2]) .. "," .. jnum(sk[3]) .. "," .. jnum(sk[4]) .. "," .. jnum(sk[5]) .. "]"
					end
					table.insert(segs, "[" .. jstr(seg[1]) .. "," .. jstr(seg[2]) .. "," .. jnum(seg[3]) .. "," .. jnum(seg[4]) .. "," .. col .. "," .. (if st.transp then jnum(st.transp) else "null") .. "," .. stroke .. "]")
				end
				table.insert(lines, '{"w":' .. jnum(tl.widths[i]) .. ',"h":' .. jnum(tl.heights[i]) .. ',"s":[' .. table.concat(segs, ",") .. "]}")
			end
			table.insert(parts, ',"tx":{"pad":[' .. jnum(tl.pad[1]) .. "," .. jnum(tl.pad[2]) .. "," .. jnum(tl.pad[3]) .. "," .. jnum(tl.pad[4]) .. '],"size":' .. jnum(tl.size) .. ',"ph":' .. (if tl.placeholder then "true" else "false") .. ',"lines":[' .. table.concat(lines, ",") .. "]}")
		end
	end
	return table.concat(parts)
end

local function nodeJson(inst, out)
	local d = getD(inst)
	if I.isA(d.cls, "LayerCollector") then
		G.ensure(d)
	end
	table.insert(out, '{"id":' .. jnum(d.id) .. ',"c":' .. jstr(d.cls) .. ',"n":' .. jstr(d.props.Name or "") .. ',"p":' .. propsJson(inst, d) .. layoutJson(d))
	if d.cls == "ViewportFrame" then
		table.insert(out, ',"vp":' .. viewportJson(inst))
	end
	local kids = {}
	for _, ch in d.children do
		if isGuiNode(getD(ch).cls) then
			table.insert(kids, ch)
		end
	end
	if #kids > 0 then
		table.insert(out, ',"k":[')
		for i, ch in kids do
			if i > 1 then
				table.insert(out, ",")
			end
			nodeJson(ch, out)
		end
		table.insert(out, "]")
	end
	table.insert(out, "}")
end

local function guiJson(player)
	local pg = player:FindFirstChild("PlayerGui")
	local out = { "[" }
	local first = true
	for _, g in getD(pg).children do
		local gd = getD(g)
		if gd.cls == "ScreenGui" then
			if not first then
				table.insert(out, ",")
			end
			first = false
			nodeJson(g, out)
		end
	end
	table.insert(out, "]")
	return table.concat(out)
end

------------------------------------------------------------------ images
local function emitImage(img)
	local d = getD(img)
	local size = d.props.Size
	local W, H = size.X, size.Y
	print(string.format("@@IMAGE %d %d %d %d", d.id, W, H, d.writes or 0))
	local pix = d.pix or buffer.create(W * H * 4)
	local row = table.create(W * 4)
	for y = 0, H - 1 do
		local base = y * W * 4
		for i = 0, W * 4 - 1 do
			row[i + 1] = HEX[buffer.readu8(pix, base + i)]
		end
		print(table.concat(row))
	end
end

-- Every EditableImage some visible ImageLabel shows.
local function imagesShown(player)
	local found, list = {}, {}
	for _, x in I.descendants(player:FindFirstChild("PlayerGui"), {}) do
		local d = getD(x)
		local c = d.props.ImageContent
		if c ~= nil and typeOf(c) == "Content" and c.SourceType == "Object" and c.Object and not found[c.Object] then
			local od = getD(c.Object)
			if od.cls == "EditableImage" and not od.destroyed then
				found[c.Object] = true
				table.insert(list, c.Object)
			end
		end
	end
	return list
end
C.imagesShown = imagesShown

------------------------------------------------------------------ frame dump
-- Dumps everything the player's client shows right now.
function C.dump(player, label, extra)
	local vp = E.viewport
	local UIS = E.services.UserInputService
	local touch = getD(UIS).props.TouchEnabled == true
	local gs = E.services.GuiService
	local touchControls = not (gs and getD(gs).props.TouchControlsEnabled == false)
	-- (Roblox hides the phone's jump button while the character can't jump: JumpHeight 0, as in Build mode)
	local jump = true
	pcall(function()
		local char = player and player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.JumpHeight ~= nil and hum.JumpHeight <= 0 then
			jump = false
		end
	end)
	print("@@FRAME " .. label)
	print(string.format('@@META {"w":%d,"h":%d,"inset":%d,"touch":%s,"touchControls":%s,"jump":%s,"t":%s,"label":%s%s}', vp.X, vp.Y, E.inset, if touch then "true" else "false", if touchControls then "true" else "false", if jump then "true" else "false", jnum(E.SIM.now - E.t0), jstr(label), extra or ""))
	for _, img in imagesShown(player) do
		emitImage(img)
	end
	print("@@GUI " .. guiJson(player))
	-- the 3D world under the GUI (classic look / before the pixel image covers the screen)
	local skip = {}
	local cam = getD(E.workspace).props.CurrentCamera
	local parts = partsUnder(E.workspace, {}, skip)
	print('@@WORLD {"camera":' .. cameraJson(cam) .. ',"parts":[' .. table.concat(parts, ",") .. "]}")
	print("@@ENDFRAME " .. label)
end

return C
