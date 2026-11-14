--!strict
-- The interface kit (docs/ARCHITECTURE.md 10; Random Bakery's look): pixel-art plates with stepped corners, the pixel
-- font, no borders, all on the world's pixel grid. Since the request of 2026-11-14 ("make the ui appear like this
-- instead, with a black transparent background and make it neater", with a picture of Random Bakery's HUD) every
-- card, panel, bar and notice is black see-through glass (UIKit.glass: flat, small stepped corners, no outline,
-- frame, bevel or shadow), an item in a list sits on a faint veil (UIKit.row), buttons are flat with a darker bottom
-- lip, and a neutral button is a dark glass one with white words. Every root's canvas is laid out in UI px, one UI px = one art
-- pixel = K screen px (UIScale K = PixelRenderer.pixelScale()), so the interface, the text and the world share one
-- grid. Labels are drawn by Pixel/PixelText when EditableImages work, else they stay native in Press Start 2P.
-- Conventions the sims rely on: a button is a TextButton whose child TextLabel holds its words; a disabled button has
-- AutoButtonColor false; buttons fire Activated; UIKit.openPanel(name, arg) opens a registered panel.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local PixelFont = require(ReplicatedStorage.Shared.Render.PixelFont)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local PixelText = require(script.Parent.Parent.Pixel.PixelText)
local Snapshot = require(script.Parent.Parent.Pixel.Snapshot)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local PixelSprites = require(script.Parent.PixelSprites)

local UIKit = {}
UIKit.Resized = Util.Signal() :: Types.Signal<Vector2>

local player = Players.LocalPlayer

------------------------------------------------------------------ colours
local colorCache: { [string]: Color3 } = {}
local function hexColor(hex: number): Color3
	return Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
end

-- A colour by key: the interface's own (Palette.ui) first, then the world's (Palette.colors), then the scores'.
function UIKit.color(key: string): Color3
	local cached = colorCache[key]
	if cached then
		return cached
	end
	local hex = Palette.ui[key] or Palette.colors[key] or Palette.axis[key] or Palette.match[key] or 0xFF00FF
	local c = hexColor(hex)
	colorCache[key] = c
	return c
end

function UIKit.hex(hex: number): Color3
	return hexColor(hex)
end

------------------------------------------------------------------ roots and canvases
type CanvasRec = { gui: ScreenGui, canvas: Frame, scaler: UIScale }
local roots: { [string]: ScreenGui } = {}
local recs: { [ScreenGui]: CanvasRec } = {}
local K = 2

local function playerGui(): PlayerGui
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function viewport(): Vector2
	local cam = Workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

local function insetTop(): number
	local ok, tl = pcall(function(): Vector2
		local a = GuiService:GetGuiInset()
		return a
	end)
	return if ok and typeof(tl) == "Vector2" then tl.Y else 0
end

-- Every canvas sits on the full screen's grid of K: its top-left on a multiple of K from the screen corner, its size
-- a whole number of UI px.
local function layoutCanvas(rec: CanvasRec)
	local gui = rec.gui
	local size = gui.AbsoluteSize
	local top = if gui.IgnoreGuiInset then 0 else insetTop()
	if size.X < 1 or size.Y < 1 then
		local vp = viewport()
		size = Vector2.new(vp.X, vp.Y - top)
	end
	local oy = top % K
	rec.scaler.Scale = K
	rec.canvas.Position = UDim2.fromOffset(0, if oy == 0 then 0 else K - oy)
	rec.canvas.Size = UDim2.fromOffset(math.max(1, math.floor(size.X / K)), math.max(1, math.floor((size.Y - (if oy == 0 then 0 else K - oy)) / K)))
end

-- A root's canvas changed size on its own (Roblox lays ScreenGuis out after the camera's ViewportSize event, and the
-- top bar's inset or a safe area can settle with no viewport change at all): tell the UI once this frame, so
-- everything laid out from the canvas's size (the HUD's bars and cards, Build mode's tray) is laid out again.
local resizePending = false
local function scheduleResized()
	if resizePending then
		return
	end
	resizePending = true
	task.defer(function()
		resizePending = false
		UIKit.Resized:Fire(UIKit.size())
	end)
end

local function makeRoot(name: string, order: number, fullScreen: boolean): ScreenGui
	local existing = roots[name]
	if existing then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.DisplayOrder = order
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = fullScreen
	if fullScreen then
		gui.ScreenInsets = Enum.ScreenInsets.None
	end
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	local sc = Instance.new("UIScale")
	sc.Parent = canvas
	canvas.Parent = gui
	local rec: CanvasRec = { gui = gui, canvas = canvas, scaler = sc }
	recs[gui] = rec
	roots[name] = gui
	layoutCanvas(rec)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local before = rec.canvas.Size
		layoutCanvas(rec)
		if rec.canvas.Size ~= before then
			scheduleResized()
		end
	end)
	gui.Parent = playerGui()
	return gui
end

-- The roots: World (popups over the office, full screen), Hud, Modal (panels), Stage (a microgame's overlay, full
-- screen: its canvas is the world's art grid), Popup (cards, notices).
function UIKit.root(name: string): ScreenGui
	if name == "World" then
		return makeRoot("World", 7, true)
	elseif name == "Stage" then
		return makeRoot("Stage", 22, true)
	elseif name == "Modal" then
		return makeRoot("Modal", 20, false)
	elseif name == "Popup" then
		return makeRoot("Popup", 25, false)
	end
	return makeRoot("Hud", 10, false)
end

function UIKit.canvas(name: string): Frame
	return recs[UIKit.root(name)].canvas
end

-- The canvas size in UI px.
function UIKit.size(name: string?): Vector2
	local c = UIKit.canvas(name or "Hud")
	return Vector2.new(c.Size.X.Offset, c.Size.Y.Offset)
end

function UIKit.P(): number
	return K
end

-- A phone: a short side of 500 screen px or less (Roblox's touch-control rule).
function UIKit.phone(): boolean
	local vp = viewport()
	return math.min(vp.X, vp.Y) <= 500
end

-- The top-left of a root's canvas in full-screen px (the world's art grid starts at the screen's corner).
function UIKit.canvasOrigin(name: string): Vector2
	local gui = UIKit.root(name)
	local c = recs[gui].canvas
	local top = if gui.IgnoreGuiInset then 0 else insetTop()
	return Vector2.new(0, top + c.Position.Y.Offset)
end

local function relayoutAll()
	local k = PixelRenderer.pixelScale()
	K = math.max(1, math.floor(k))
	for _, rec in recs do
		layoutCanvas(rec)
	end
	scheduleResized()
end

------------------------------------------------------------------ text
export type TextOpts = {
	color: Color3?,
	x: string?, -- "left" | "center" | "right"
	y: string?, -- "top" | "center" | "bottom"
	wrap: boolean?,
	kind: string?, -- PixelText style: "shadow" (default) | "plain" | "outline" | "title"
	under: Color3?,
	face: string?, -- "small" | "big"
	z: number?,
	name: string?,
}

local XA = { left = Enum.TextXAlignment.Left, center = Enum.TextXAlignment.Center, right = Enum.TextXAlignment.Right }
local YA = { top = Enum.TextYAlignment.Top, center = Enum.TextYAlignment.Center, bottom = Enum.TextYAlignment.Bottom }

function UIKit.textWidth(text: string, face: string?): number
	return PixelFont.width(Lang.t(text), if face == "big" then PixelFont.BIG else PixelFont.SMALL)
end

-- How many lines `text` wraps to in w UI px (as a wrapped label breaks it: whole words, the small face unless "big").
function UIKit.lines(text: string, w: number, face: string?): number
	return #PixelFont.wrap(Lang.t(text), w, if face == "big" then PixelFont.BIG else PixelFont.SMALL)
end

function UIKit.lineHeight(face: string?): number
	return if face == "big" then 18 else 10
end

-- A label in UI px. Its Text stays readable by the sims and screen readers; the pixel font draws it.
function UIKit.text(parent: Instance?, text: string, size: UDim2, pos: UDim2?, opts: TextOpts?): TextLabel
	local o: TextOpts = opts or {}
	local l = Instance.new("TextLabel")
	l.Name = o.name or "Label"
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = size
	l.Position = pos or UDim2.new()
	l.Text = text
	l.TextColor3 = o.color or UIKit.color("text")
	l.TextXAlignment = XA[o.x or "left"] or Enum.TextXAlignment.Left
	l.TextYAlignment = YA[o.y or "center"] or Enum.TextYAlignment.Center
	l.TextWrapped = o.wrap == true
	l.ZIndex = o.z or 2
	l.Font = Enum.Font.Arcade
	l.TextSize = if o.face == "big" then 16 else 8
	l.LineHeight = 1.25
	if PixelText.available() then
		PixelText.bind(l, {
			kind = o.kind or "shadow",
			under = o.under or UIKit.color("ink"),
			face = o.face or "small",
			unit = 1,
		})
	end
	l.Parent = parent
	return l
end

function UIKit.setText(l: TextLabel, text: string)
	if l.Text ~= text then
		l.Text = text
	end
end

function UIKit.setTextColor(l: TextLabel, c: Color3)
	l.TextColor3 = c
	if PixelText.isBound(l) then
		PixelText.setColor(l, c)
	end
end

------------------------------------------------------------------ plates
-- A surface with stepped pixel corners and a 1 px ink outline that follows them (GAME_DESIGN 2: "use a 1 pixel
-- outline"): rectangles named "Fill" inside rectangles named "Edge", none overlapping, so a translucent plate stays
-- even. `style.edge = false` leaves the outline off (a flat swatch); `style.shadow` casts a 2 px drop shadow down
-- and to the right (panels, cards, the tray). The island's looks (GAME_DESIGN 2): `style.wood` (2 or 3) frames it in
-- planks of driftwood that many px wide outside its outline (and another ink outline round them: the plate takes
-- that much more room on every side), lit along the top and left, shaded along the bottom and right, seams between
-- the planks and a nail head in each corner; `style.bevel` lights the plate's top row and shades its bottom one (a
-- carved board: chips, rows). Content goes in it at ZIndex >= 1.
export type PlateStyle = { edge: boolean?, shadow: boolean?, edgeColor: Color3?, wood: number?, bevel: boolean?, glass: boolean?, row: boolean? }

-- The look since 2026-11-14 (Random Bakery's HUD): black glass this see-through (BackgroundTransparency) behind the
-- HUD's cards and bars, the panels, the tray and the notices; an item's veil over it (white, this see-through); a dark
-- button's face (the glass a step darker); the padding inside a glass plate.
UIKit.GLASS_ALPHA = 0.38
UIKit.PANEL_ALPHA = 0.16 -- a panel's glass (its lists and words over the world: denser)
UIKit.ROW_ALPHA = 0.9
UIKit.DARK_ALPHA = 0.3
UIKit.PAD = 4

-- The wooden frame round a plate (style.wood = t px of planks): a child behind the plate's own rectangles, `t + 1`
-- px out on every side. Its seams fall every PLANK px along the top and bottom (staggered) and down the sides.
local PLANK = 44
local function woodFrame(f: Frame, size: UDim2, k: number, t: number)
	local o = t + 1
	local back = Instance.new("Frame")
	back.Name = "Wood"
	back.BackgroundTransparency = 1
	back.BorderSizePixel = 0
	back.Position = UDim2.fromOffset(-o, -o)
	back.Size = UDim2.new(size.X.Scale, size.X.Offset + 2 * o, size.Y.Scale, size.Y.Offset + 2 * o)
	back.ZIndex = -1
	back.Parent = f
	-- the planks: an outlined board as big as the frame (the plate covers its middle), corners a step rounder
	local board = UIKit.plate(back, UDim2.fromScale(1, 1), nil, UIKit.color("frame"), 0, math.min(3, k + 1))
	board.Name = "Board"
	board.ZIndex = -2
	local c0 = math.min(3, k + 1) + 1 -- the bevel lines start clear of the board's rounded corners
	local function line(name: string, color: Color3, pos: UDim2, sz: UDim2)
		local q = Instance.new("Frame")
		q.Name = name
		q.BorderSizePixel = 0
		q.BackgroundColor3 = color
		q.Position = pos
		q.Size = sz
		q.ZIndex = -1
		q.Parent = back
	end
	local hi, lo, dark = UIKit.color("frame_hi"), UIKit.color("frame_lo"), UIKit.color("frame_dark")
	-- the outer row: lit along the top and left, shaded along the bottom and right
	line("Hi", hi, UDim2.fromOffset(c0, 1), UDim2.new(1, -2 * c0, 0, 1))
	line("Hi", hi, UDim2.fromOffset(1, c0), UDim2.new(0, 1, 1, -2 * c0))
	line("Lo", lo, UDim2.new(0, c0, 1, -2), UDim2.new(1, -2 * c0, 0, 1))
	line("Lo", lo, UDim2.new(1, -2, 0, c0), UDim2.new(0, 1, 1, -2 * c0))
	if t >= 3 then
		-- the inner row: the plate sits a little deeper (shaded along its top and left edge, lit along its bottom)
		line("Lo", lo, UDim2.fromOffset(t, t), UDim2.new(1, -2 * t, 0, 1))
		line("Lo", lo, UDim2.fromOffset(t, t), UDim2.new(0, 1, 1, -2 * t))
		line("Hi", hi, UDim2.new(0, t, 1, -t - 1), UDim2.new(1, -2 * t, 0, 1))
		line("Hi", hi, UDim2.new(1, -t - 1, 0, t), UDim2.new(0, 1, 1, -2 * t))
	end
	-- the seams between planks (only where the size is known in px)
	local w, h = size.X.Offset + 2 * o, size.Y.Offset + 2 * o
	if size.X.Scale == 0 then
		local x = 18
		while x < w - 14 do
			line("Seam", dark, UDim2.fromOffset(x, 1), UDim2.fromOffset(1, t))
			line("Seam", dark, UDim2.fromOffset(math.min(w - 12, x + math.floor(PLANK / 2)), h - 1 - t), UDim2.fromOffset(1, t))
			x += PLANK
		end
	end
	if size.Y.Scale == 0 then
		local y = 24
		while y < h - 18 do
			line("Seam", dark, UDim2.fromOffset(1, y), UDim2.fromOffset(t, 1))
			line("Seam", dark, UDim2.fromOffset(w - 1 - t, y + 12), UDim2.fromOffset(t, 1))
			y += PLANK
		end
	end
	-- a nail head in each corner of the frame: a lit pixel over a shaded one
	local nh, nl = UIKit.color("nail_hi"), UIKit.color("nail_lo")
	local n = math.floor((t + 1) / 2)
	for _, c in { { false, false }, { true, false }, { false, true }, { true, true } } do
		local px = if c[1] then UDim.new(1, -n - 2) else UDim.new(0, n)
		local py = if c[2] then UDim.new(1, -n - 2) else UDim.new(0, n)
		line("Nail", nh, UDim2.new(px, py), UDim2.fromOffset(1, 1))
		line("Nail", nl, UDim2.new(px + UDim.new(0, 1), py + UDim.new(0, 1)), UDim2.fromOffset(1, 1))
	end
end
local CORNER_INSETS: { [number]: { number } } = { [0] = {}, [1] = { 1 }, [2] = { 2, 1 }, [3] = { 3, 1, 1 } }

function UIKit.plate(parent: Instance?, size: UDim2, pos: UDim2?, c: Color3?, alpha: number?, corner: number?, style: PlateStyle?): Frame
	local f = Instance.new("Frame")
	f.Name = "Plate"
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local k = math.clamp(math.floor(corner or 2), 0, 3)
	local col = c or UIKit.color("plate")
	local a = alpha or 0
	local st: PlateStyle = style or {}
	local edged = st.edge ~= false
	local ink = st.edgeColor or UIKit.color("ink")
	if st.glass or (st.wood and st.wood > 0) then
		-- black see-through glass (the old frames of planks are gone: a `wood` plate is glass too): flat, its corners
		-- at most two steps, no outline, frame, bevel or shadow
		col = UIKit.color("glass")
		a = if st.glass and alpha then alpha else UIKit.GLASS_ALPHA
		k = math.min(k, 2)
		edged = false
		st = { edge = false }
	elseif st.row then
		-- an item's veil over the glass (or a tinted one: picked, ready)
		col = c or UIKit.color("veil")
		a = alpha or UIKit.ROW_ALPHA
		k = math.min(k, 1)
		edged = false
		st = { edge = false }
	end
	-- a rectangle from `l` px in on the left to `r` px in on the right, `y` px down (from the top or, bottom, up)
	local function rect(name: string, color: Color3, l: number, r: number, y: number, h: UDim, bottom: boolean?)
		local q = Instance.new("Frame")
		q.Name = name
		q.BorderSizePixel = 0
		q.BackgroundColor3 = color
		q.BackgroundTransparency = a
		q.Position = UDim2.new(UDim.new(0, l), if bottom then UDim.new(1, -y - 1) else UDim.new(0, y))
		q.Size = UDim2.new(UDim.new(1, -(l + r)), h)
		q.ZIndex = 0
		q.Parent = f
	end
	local insets = CORNER_INSETS[k]
	local rows = #insets
	local one = UDim.new(0, 1)
	if not edged then
		for i, inset in insets do
			rect("Fill", col, inset, inset, i - 1, one)
			rect("Fill", col, inset, inset, i - 1, one, true)
		end
		rect("Fill", col, 0, 0, rows, UDim.new(1, -2 * rows))
	else
		-- the outline is the shape less the shape shrunk by a pixel: row by row through the corners, then the sides
		local function outer(y: number): number
			if y < 0 then
				return math.huge
			end
			return if y < rows then insets[y + 1] else 0
		end
		-- a pixel-high run `w` px wide from `x` px in on the left (or, `right`, from x px in on the right)
		local function run(name: string, color: Color3, x: number, w: number, y: number, bottom: boolean, right: boolean)
			local q = Instance.new("Frame")
			q.Name = name
			q.BorderSizePixel = 0
			q.BackgroundColor3 = color
			q.BackgroundTransparency = a
			q.Position = UDim2.new(if right then UDim.new(1, -x - w) else UDim.new(0, x), if bottom then UDim.new(1, -y - 1) else UDim.new(0, y))
			q.Size = UDim2.fromOffset(w, 1)
			q.ZIndex = 0
			q.Parent = f
		end
		for y = 0, rows do
			local l = outer(y)
			local li = math.max(l + 1, outer(y - 1), outer(y + 1))
			for _, bottom in { false, true } do
				if li == math.huge then
					rect("Edge", ink, l, l, y, one, bottom)
				else
					run("Edge", ink, l, li - l, y, bottom, false)
					run("Edge", ink, l, li - l, y, bottom, true)
					rect("Fill", col, li, li, y, one, bottom)
				end
			end
		end
		-- the sides: an edge pixel each side of the fill
		local mid = UDim.new(1, -2 * (rows + 1))
		for _, right in { false, true } do
			local q = Instance.new("Frame")
			q.Name = "Edge"
			q.BorderSizePixel = 0
			q.BackgroundColor3 = ink
			q.BackgroundTransparency = a
			q.Position = UDim2.new(if right then 1 else 0, if right then -1 else 0, 0, rows + 1)
			q.Size = UDim2.new(UDim.new(0, 1), mid)
			q.ZIndex = 0
			q.Parent = f
		end
		rect("Fill", col, 1, 1, rows + 1, mid)
	end
	if st.bevel and edged then
		-- a carved board: its top row lit, its bottom row shaded (clear of the corners)
		local inset = k + 1
		local lit = Instance.new("Frame")
		lit.Name = "BevelHi"
		lit.BorderSizePixel = 0
		lit.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), 0.16)
		lit.BackgroundTransparency = a
		lit.Position = UDim2.fromOffset(inset, 1)
		lit.Size = UDim2.new(1, -2 * inset, 0, 1)
		lit.ZIndex = 0
		lit.Parent = f
		local dim = lit:Clone()
		dim.Name = "BevelLo"
		dim.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.22)
		dim.Position = UDim2.new(0, inset, 1, -2)
		dim.Parent = f
	end
	local o = 0
	if st.wood and st.wood > 0 then
		local t = math.clamp(math.floor(st.wood), 1, 4)
		woodFrame(f, size, k, t)
		o = t + 1
	end
	if st.shadow then
		-- a drop shadow: two strips outside the plate (or its frame), right and below (its bottom-right corner stepped)
		local function shade(px: UDim, py: UDim, sx: UDim, sy: UDim)
			local q = Instance.new("Frame")
			q.Name = "Shadow"
			q.BorderSizePixel = 0
			q.BackgroundColor3 = UIKit.color("ink")
			q.BackgroundTransparency = 0.55 + a * 0.45
			q.Position = UDim2.new(px, py)
			q.Size = UDim2.new(sx, sy)
			q.ZIndex = -2
			q.Parent = f
		end
		shade(UDim.new(1, o), UDim.new(0, k + 2 - o), UDim.new(0, 2), UDim.new(1, -(k + 2) + 2 * o))
		shade(UDim.new(0, k + 2 - o), UDim.new(1, o), UDim.new(1, -(k + 1) + 2 * o), UDim.new(0, 2))
	end
	f.Parent = parent
	return f
end

-- The rule under a card's or panel's title row (the title planks went with the frames on 2026-11-14): a faint line
-- `UIKit.PAD` px in from each side, `h + 1` px down. (`k`, the old plank's corner, is not used.)
function UIKit.plank(frame: Frame, h: number, _k: number?)
	local r = UIKit.rect(frame, UDim2.new(1, -2 * UIKit.PAD, 0, 1), UDim2.fromOffset(UIKit.PAD, h + 1), UIKit.color("rule"), 1)
	r.BackgroundTransparency = 0.84
	r.Name = "TitleRule"
end

-- Black see-through glass (the look since 2026-11-14): every card, panel, bar and notice. `corner` 1 or 2 steps.
function UIKit.glass(parent: Instance?, size: UDim2, pos: UDim2?, corner: number?): Frame
	return UIKit.plate(parent, size, pos, nil, nil, corner or 2, { glass = true })
end

-- An item's veil over the glass (a row, a card in a list): white, faint; `c` tints it (picked, ready), `alpha` its
-- see-through (UIKit.ROW_ALPHA by default).
function UIKit.row(parent: Instance?, size: UDim2, pos: UDim2?, c: Color3?, alpha: number?): Frame
	return UIKit.plate(parent, size, pos, c, alpha, 1, { row = true })
end

function UIKit.setPlate(plate: Instance, c: Color3?, alpha: number?)
	for _, r in plate:GetChildren() do
		if r:IsA("Frame") and r.Name == "Fill" then
			if c then
				r.BackgroundColor3 = c
			end
			if alpha then
				r.BackgroundTransparency = alpha
			end
		end
	end
end

-- A one-UI-px rectangle-filled frame (bars, swatches, separators).
function UIKit.rect(parent: Instance?, size: UDim2, pos: UDim2?, c: Color3, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Rect"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = c
	f.Size = size
	f.Position = pos or UDim2.new()
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

------------------------------------------------------------------ buttons
export type ButtonOpts = { color: Color3?, textColor: Color3?, enabled: boolean?, name: string?, face: string?, ghost: boolean? }

local buttonColor: { [GuiButton]: Color3 } = {}

-- The plate a button shows now. A coloured button is flat in its colour with a darker lip along its bottom (lighter
-- while hovered; the disabled grey). A neutral one (the old wooden colours: plate, plate_light, frame) is a dark glass
-- button: the glass a step darker, white words, a faint veil while hovered. A ghost (opts.ghost: the menu bar's) shows
-- no surface until the mouse is over it.
local hovered: { [GuiButton]: boolean } = {}
local neutralSet: { [string]: boolean }? = nil
local function isNeutral(c: Color3): boolean
	local set = neutralSet
	if set == nil then
		local n: { [string]: boolean } = {}
		for _, key in { "plate", "plate_light", "frame", "frame_dark", "glass" } do
			n[UIKit.color(key):ToHex()] = true
		end
		neutralSet = n
		set = n
	end
	return (set :: { [string]: boolean })[c:ToHex()] == true
end
UIKit.isNeutral = isNeutral
local function paintButton(b: GuiButton)
	local plate = b:FindFirstChild("Plate")
	if plate == nil then
		return
	end
	local base = buttonColor[b] or UIKit.color("button")
	local on = b.AutoButtonColor
	local hot = hovered[b] == true and on
	local c, a, lipA = base, 0, 0
	if b:GetAttribute("Ghost") then
		c, a, lipA = UIKit.color("veil"), if hot then 0.84 else 1, 1
	elseif isNeutral(base) then
		c = if hot then UIKit.color("glass"):Lerp(Color3.new(1, 1, 1), 0.2) else UIKit.color("glass")
		a = if on then UIKit.DARK_ALPHA else 0.55
		lipA = 1
	elseif not on then
		c = UIKit.color("button_off")
	elseif hot then
		c = base:Lerp(Color3.new(1, 1, 1), 0.18)
	end
	UIKit.setPlate(plate, c, a)
	-- the lip along the bottom: the face a shade darker (none on a dark or ghost button)
	local lip = plate:FindFirstChild("Lip")
	if lip and lip:IsA("Frame") then
		lip.BackgroundColor3 = c:Lerp(Color3.new(0, 0, 0), 0.28)
		lip.BackgroundTransparency = lipA
	end
end

-- Pressed: the plate and its words sink one UI px (and come back up on release).
local function pressButton(b: GuiButton, down: boolean)
	local plate = b:FindFirstChild("Plate")
	local words = b:FindFirstChild("Words")
	local dy = if down and b.AutoButtonColor then 1 else 0
	if plate and plate:IsA("GuiObject") then
		plate.Position = UDim2.fromOffset(0, dy)
	end
	if words and words:IsA("GuiObject") then
		words.Position = UDim2.fromOffset(words.Position.X.Offset, dy)
	end
end

-- A plate button with its words in a child label. It lightens under the mouse, sinks a pixel while pressed and
-- clicks (or buzzes, disabled).
function UIKit.button(parent: Instance?, text: string, size: UDim2, pos: UDim2?, onClick: () -> (), opts: ButtonOpts?): TextButton
	local o: ButtonOpts = opts or {}
	local b = Instance.new("TextButton")
	b.Name = o.name or "Button"
	b.Text = ""
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Size = size
	b.Position = pos or UDim2.new()
	b.AutoButtonColor = true
	b.ZIndex = 2
	local col = o.color or UIKit.color("button")
	buttonColor[b] = col
	if o.ghost then
		b:SetAttribute("Ghost", true)
	end
	-- flat, its corners stepped, no outline; a darker lip along the bottom (pressed, the button sinks a pixel)
	local plate = UIKit.plate(b, UDim2.fromScale(1, 1), nil, col, 0, 2, { edge = false })
	plate.ZIndex = 1
	local lip = UIKit.rect(plate, UDim2.new(1, -4, 0, 1), UDim2.new(0, 2, 1, -1), col:Lerp(Color3.new(0, 0, 0), 0.28), 1)
	lip.Name = "Lip"
	local l = UIKit.text(b, text, UDim2.new(1, -4, 1, 0), UDim2.fromOffset(2, 0), {
		x = "center",
		color = o.textColor or UIKit.color("text"),
		kind = "shadow",
		under = UIKit.color("ink"),
		face = o.face,
		z = 3,
		name = "Words",
	})
	l.Active = false
	b.Activated:Connect(function()
		if b.AutoButtonColor then
			Audio.play("click")
			onClick()
		else
			Audio.play("deny")
		end
	end)
	b.MouseEnter:Connect(function()
		hovered[b] = true
		paintButton(b)
	end)
	b.MouseLeave:Connect(function()
		hovered[b] = nil
		paintButton(b)
		pressButton(b, false)
	end)
	b.MouseButton1Down:Connect(function()
		pressButton(b, true)
	end)
	b.MouseButton1Up:Connect(function()
		pressButton(b, false)
	end)
	b.Destroying:Connect(function()
		buttonColor[b] = nil
		hovered[b] = nil
	end)
	b.Parent = parent
	if o.enabled == false then
		UIKit.setEnabled(b, false)
	else
		paintButton(b)
	end
	return b
end

function UIKit.setEnabled(b: GuiButton, on: boolean)
	if b.AutoButtonColor == on and b:GetAttribute("Painted") then
		return
	end
	b:SetAttribute("Painted", true)
	b.AutoButtonColor = on
	paintButton(b)
	local words = b:FindFirstChild("Words")
	if words and words:IsA("TextLabel") then
		UIKit.setTextColor(words, if on then UIKit.color("text") else UIKit.color("text_dim"))
	end
end

function UIKit.setButtonText(b: GuiButton, text: string)
	local words = b:FindFirstChild("Words")
	if words and words:IsA("TextLabel") then
		UIKit.setText(words, text)
	end
end

function UIKit.setButtonColor(b: GuiButton, c: Color3)
	buttonColor[b] = c
	if b.AutoButtonColor then
		paintButton(b)
	end
end

-- A button sized to its words.
function UIKit.buttonWidth(text: string, pad: number?): number
	return UIKit.textWidth(text) + 2 * (pad or 6)
end

------------------------------------------------------------------ bars
-- A progress bar: back plate and a fill; returns the frame and a setter (0..1).
function UIKit.bar(parent: Instance?, size: UDim2, pos: UDim2?, fill: Color3, back: Color3?): (Frame, (number) -> ())
	local f = Instance.new("Frame")
	f.Name = "Bar"
	f.BackgroundTransparency = 1
	f.Size = size
	f.Position = pos or UDim2.new()
	f.ZIndex = 2
	local bg = UIKit.rect(f, UDim2.fromScale(1, 1), nil, back or UIKit.color("ink"), 2)
	bg.Name = "Back"
	local fg = UIKit.rect(f, UDim2.fromScale(0, 1), nil, fill, 3)
	fg.Name = "Fill"
	f.Parent = parent
	local function set(frac: number)
		local w = f.AbsoluteSize.X / math.max(1, K)
		local width = if w >= 1 then w else size.X.Offset
		local px = math.floor(math.clamp(frac, 0, 1) * width + 0.5)
		fg.Size = UDim2.new(0, px, 1, 0)
	end
	return f, set
end

------------------------------------------------------------------ helpers
function UIKit.clear(parent: Instance)
	for _, c in parent:GetChildren() do
		if not c:IsA("UIScale") then
			c:Destroy()
		end
	end
end

function UIKit.vlist(parent: GuiObject, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or 2)
	l.Parent = parent
	return l
end

function UIKit.hlist(parent: GuiObject, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, gap or 2)
	l.Parent = parent
	return l
end

-- A scrolling list frame (UI px) whose canvas follows its content.
function UIKit.scroll(parent: Instance?, size: UDim2, pos: UDim2?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = "List"
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = size
	s.Position = pos or UDim2.new()
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = UIKit.color("text_dim")
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ZIndex = 2
	s.Parent = parent
	return s
end

------------------------------------------------------------------ panels
-- The notices on screen (UIKit.notice); a panel that opens clears them so none sits over it.
local noticeList: { Frame } = {}
function UIKit.clearNotices()
	for _, n in noticeList do
		n:Destroy()
	end
	table.clear(noticeList)
end

-- Registered panels (Hud's menus): build(body, arg) fills the panel's body; UIKit.openPanel shows one at a time.
type PanelDef = { title: string, build: (body: Frame, arg: any?) -> (), pause: boolean?, w: number?, h: number?, icon: string? }
local panels: { [string]: PanelDef } = {}
local openName: string? = nil
local openFrame: Frame? = nil
UIKit.PanelChanged = Util.Signal() :: Types.Signal<string?>

function UIKit.registerPanel(name: string, def: PanelDef)
	panels[name] = def
end

function UIKit.closePanel()
	local f = openFrame
	local name = openName
	openFrame, openName = nil, nil
	if f then
		f:Destroy()
	end
	if name then
		UIKit.PanelChanged:Fire(nil)
	end
end

function UIKit.currentPanel(): string?
	return openName
end

-- The panel's size for the screen: as big as its def asks, never past the canvas less a margin.
local function panelSize(def: PanelDef): Vector2
	local s = UIKit.size("Modal")
	-- (its frame of planks takes 4 px more on every side: it still fits the screen)
	local w = math.min(def.w or 300, s.X - 10)
	local h = math.min(def.h or 170, s.Y - 10)
	return Vector2.new(w, h)
end

function UIKit.openPanel(name: string, arg: any?)
	local def = panels[name]
	if def == nil then
		return
	end
	UIKit.closePanel()
	UIKit.clearNotices()
	local canvas = UIKit.canvas("Modal")
	local sz = panelSize(def)
	local s = UIKit.size("Modal")
	local shade = Instance.new("TextButton")
	shade.Name = "Panel_" .. name
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = UIKit.color("sea_shade")
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 1
	local fx, fy = math.floor((s.X - sz.X) / 2), math.floor((s.Y - sz.Y) / 2)
	-- black see-through glass (the look since 2026-11-14), the world dimmed behind it
	local frame = UIKit.plate(shade, UDim2.fromOffset(sz.X, sz.Y), UDim2.fromOffset(fx, fy + 10), nil, UIKit.PANEL_ALPHA, 2, { glass = true })
	frame.Name = "Frame"
	frame.ZIndex = 2
	-- the title row: its icon and words, a faint rule under it
	UIKit.plank(frame, 15)
	local tx = UIKit.PAD + 1
	if def.icon then
		PixelSprites.image(frame, "mini_" .. def.icon, UDim2.fromOffset(UIKit.PAD + 1, 3), 3)
		tx = UIKit.PAD + 14
	end
	UIKit.text(frame, def.title, UDim2.new(1, -40, 0, 14), UDim2.fromOffset(tx, 2), { color = UIKit.color("text"), kind = "shadow", under = UIKit.color("ink"), name = "Title", z = 3 })
	-- the status line: notices while the panel is open land here instead of covering it
	local titleW = UIKit.textWidth(def.title) + tx + 8
	UIKit.text(frame, "", UDim2.new(1, -(titleW + UIKit.buttonWidth("Close", 4) + 8), 0, 14), UDim2.fromOffset(titleW, 2), { color = UIKit.color("text"), name = "Status", x = "right" })
	UIKit.button(frame, "Close", UDim2.fromOffset(UIKit.buttonWidth("Close", 4), 12), UDim2.new(1, -UIKit.buttonWidth("Close", 4) - 3, 0, 3), function()
		Audio.play("close")
		UIKit.closePanel()
	end, { color = UIKit.color("button_close"), name = "Close" })
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -8, 1, -20)
	body.Position = UDim2.fromOffset(4, 17)
	body.ZIndex = 2
	body:SetAttribute("W", sz.X - 8)
	body:SetAttribute("H", sz.Y - 20)
	body.Parent = frame
	shade.Parent = canvas
	openFrame = shade :: any
	openName = name
	UIKit.tween(shade, 0.15, { BackgroundTransparency = 0.45 })
	UIKit.tween(frame, 0.15, { Position = UDim2.fromOffset(fx, fy) })
	Audio.play("open")
	local ok, err = pcall(function()
		def.build(body, arg)
	end)
	if not ok then
		warn("[UIKit] panel " .. name .. " failed: " .. tostring(err))
	end
	UIKit.PanelChanged:Fire(name)
end

-- Rebuild the open panel's body (after the view changed), keeping its argument.
local openArg: any? = nil
local rawOpen = UIKit.openPanel
UIKit.openPanel = function(name: string, arg: any?)
	openArg = arg
	rawOpen(name, arg)
end
function UIKit.refreshPanel()
	local name = openName
	local f = openFrame
	if name == nil or f == nil then
		return
	end
	local def = panels[name]
	local body = f:FindFirstChild("Frame") and (f :: any).Frame:FindFirstChild("Body")
	if def and body then
		local list = body:FindFirstChild("List")
		local pos = if list and list:IsA("ScrollingFrame") then list.CanvasPosition else nil
		UIKit.clear(body)
		local ok, err = pcall(function()
			def.build(body :: Frame, openArg)
		end)
		if not ok then
			warn("[UIKit] panel " .. name .. " failed: " .. tostring(err))
		end
		local nl = body:FindFirstChild("List")
		if pos and nl and nl:IsA("ScrollingFrame") then
			nl.CanvasPosition = pos
		end
	end
end

-- A panel body's size in UI px (set when the panel opens).
function UIKit.bodyWidth(body: Instance): number
	local w = body:GetAttribute("W")
	return if type(w) == "number" then w else 200
end
function UIKit.bodyHeight(body: Instance): number
	local h = body:GetAttribute("H")
	return if type(h) == "number" then h else 120
end

------------------------------------------------------------------ notices

-- A small notice that fades by itself (top centre, newest at the bottom of the stack, at most 3). While a panel is
-- open it is the panel's status line instead (next to its title), so it never covers the panel.
local statusSeq = 0
function UIKit.notice(text: string, color: Color3?, seconds: number?)
	local open = openFrame
	local status = if open then open:FindFirstChild("Status", true) else nil
	if status and status:IsA("TextLabel") then
		statusSeq += 1
		local mine = statusSeq
		UIKit.setText(status, text)
		UIKit.setTextColor(status, color or UIKit.color("text"))
		task.delay(seconds or 3.5, function()
			if statusSeq == mine and status.Parent then
				UIKit.setText(status, "")
			end
		end)
		return
	end
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local w = math.min(UIKit.textWidth(text) + 14, s.X - 16)
	local lines = if UIKit.textWidth(text) + 14 > w then 2 else 1
	local h = 6 + 10 * lines
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(math.floor((s.X - w) / 2), 24), 2)
	f.Name = "Notice"
	UIKit.rect(f, UDim2.new(0, 2, 1, -4), UDim2.fromOffset(2, 2), color or UIKit.color("accent"), 1)
	local words = UIKit.text(f, text, UDim2.new(1, -12, 1, -2), UDim2.fromOffset(7, 1), { wrap = true, name = "Words" })
	table.insert(noticeList, f)
	while #noticeList > 3 do
		local old = table.remove(noticeList, 1)
		if old then
			old:Destroy()
		end
	end
	local y = 24
	for _, n in noticeList do
		if n == f then
			-- the new one slides down into its place
			n.Position = UDim2.fromOffset(n.Position.X.Offset, y - 8)
			UIKit.tween(n, 0.18, { Position = UDim2.fromOffset(n.Position.X.Offset, y) })
		else
			n.Position = UDim2.fromOffset(n.Position.X.Offset, y)
		end
		y += n.Size.Y.Offset + 8
	end
	task.delay(seconds or 3.5, function()
		if f.Parent == nil then
			return
		end
		-- fade away, then go
		for _, r in f:GetDescendants() do
			if r:IsA("Frame") and r.BackgroundTransparency < 1 then
				UIKit.tween(r, 0.25, { BackgroundTransparency = 1 })
			end
		end
		if PixelText.isBound(words) then
			local t0 = os.clock()
			local conn: RBXScriptConnection? = nil
			conn = RunService.Heartbeat:Connect(function()
				local a = math.clamp((os.clock() - t0) / 0.25, 0, 1)
				if words.Parent == nil or a >= 1 then
					if conn then
						conn:Disconnect()
					end
					return
				end
				PixelText.setTransparency(words, a)
			end)
		else
			UIKit.tween(words, 0.25, { TextTransparency = 1 })
		end
		task.wait(0.25)
		local i = table.find(noticeList, f)
		if i then
			table.remove(noticeList, i)
		end
		f:Destroy()
	end)
end

------------------------------------------------------------------ world popups
-- A popup that floats up from a world point and fades (the crew's "+12"): on the World root, at the art pixel the
-- renderer shows that point.
function UIKit.floatText(world: Vector3, text: string, color: Color3, big: boolean?)
	local i, j, on = PixelRenderer.projectPixel(world)
	if not on then
		return
	end
	local canvas = UIKit.canvas("World")
	local face = if big then "big" else "small"
	local w = UIKit.textWidth(text, face) + 4
	local h = UIKit.lineHeight(face)
	local l = UIKit.text(canvas, text, UDim2.fromOffset(w, h), UDim2.fromOffset(i - math.floor(w / 2), j - h), {
		color = color,
		x = "center",
		kind = "outline",
		under = UIKit.color("ink"),
		face = face,
		name = "Pop",
	})
	local t0 = os.clock()
	local x0, y0 = i - math.floor(w / 2), j - h
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 1.4 or l.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			l:Destroy()
			return
		end
		l.Position = UDim2.fromOffset(x0, y0 - math.floor(math.min(t, 0.8) * 14))
		if t > 0.9 then
			local a = (t - 0.9) / 0.5
			l.TextTransparency = a
			if PixelText.isBound(l) then
				PixelText.setTransparency(l, a)
			end
		end
	end)
end

------------------------------------------------------------------ bits over the world
-- 1 px bits flying out of a world point on the World canvas (its UI px are the world's art px): dust from a
-- founder's feet, sparkles round a head with a new idea. They arc, fall and go. One Heartbeat runs them all.
type WorldBit = { f: Frame, x: number, y: number, vx: number, vy: number, grav: number, t0: number, life: number }
local worldBits: { WorldBit } = {}
local worldConn: RBXScriptConnection? = nil
function UIKit.bitsAt(world: Vector3, colors: { string }, n: number, speed: number?, grav: number?)
	local i, j, on = PixelRenderer.projectPixel(world)
	if not on then
		return
	end
	local canvas = UIKit.canvas("World")
	local sp = speed or 30
	for k = 1, n do
		local r = UIKit.rect(canvas, UDim2.fromOffset(1, 1), UDim2.fromOffset(i, j), UIKit.color(colors[(k - 1) % #colors + 1]), 3)
		r.Name = "Bit"
		r.Active = false
		local a = math.random() * math.pi * 2
		local v = sp * (0.4 + 0.6 * math.random())
		table.insert(worldBits, { f = r, x = i, y = j, vx = math.cos(a) * v, vy = math.sin(a) * v * 0.6 - sp * 0.5, grav = grav or 90, t0 = os.clock(), life = 0.35 + math.random() * 0.35 })
	end
	if worldConn == nil then
		local last = os.clock()
		worldConn = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			local dt = math.min(0.05, now - last)
			last = now
			for idx = #worldBits, 1, -1 do
				local b = worldBits[idx]
				if now - b.t0 > b.life or b.f.Parent == nil then
					b.f:Destroy()
					table.remove(worldBits, idx)
				else
					b.vy += b.grav * dt
					b.x += b.vx * dt
					b.y += b.vy * dt
					b.f.Position = UDim2.fromOffset(math.floor(b.x + 0.5), math.floor(b.y + 0.5))
				end
			end
			if #worldBits == 0 and worldConn then
				worldConn:Disconnect()
				worldConn = nil
			end
		end)
	end
end

------------------------------------------------------------------ UI effects: bits, rising words, a shine
-- Bits of 1 px flying out of a point of a frame (UI px), rising words that fade, and a light band sweeping across a
-- button: the interface's juice (a purchase, a new idea, money coming in). One Heartbeat runs every bit and word.
type UiBit = { f: GuiObject, x: number, y: number, vx: number, vy: number, grav: number, t0: number, life: number, fade: boolean }
local uiBits: { UiBit } = {}
local uiConn: RBXScriptConnection? = nil
local function runUiBits()
	if uiConn then
		return
	end
	local last = os.clock()
	uiConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.05, now - last)
		last = now
		for idx = #uiBits, 1, -1 do
			local b = uiBits[idx]
			local age = now - b.t0
			if age > b.life or b.f.Parent == nil then
				b.f:Destroy()
				table.remove(uiBits, idx)
			else
				b.vy += b.grav * dt
				b.x += b.vx * dt
				b.y += b.vy * dt
				b.f.Position = UDim2.fromOffset(math.floor(b.x + 0.5), math.floor(b.y + 0.5))
				if b.fade and age > b.life * 0.6 and b.f:IsA("TextLabel") then
					local a = (age - b.life * 0.6) / (b.life * 0.4)
					local l = b.f :: TextLabel
					l.TextTransparency = a
					if PixelText.isBound(l) then
						PixelText.setTransparency(l, a)
					end
				end
			end
		end
		if #uiBits == 0 and uiConn then
			uiConn:Disconnect()
			uiConn = nil
		end
	end)
end

function UIKit.burst(parent: Instance, x: number, y: number, colors: { string }, n: number?, speed: number?)
	local sp = speed or 45
	for k = 1, n or 8 do
		local r = UIKit.rect(parent, UDim2.fromOffset(1, 1), UDim2.fromOffset(math.floor(x), math.floor(y)), UIKit.color(colors[(k - 1) % #colors + 1]), 30)
		r.Name = "Bit"
		r.Active = false
		local a = math.random() * math.pi * 2
		local v = sp * (0.4 + 0.6 * math.random())
		local g: GuiObject = r
		table.insert(uiBits, { f = g, x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - sp * 0.4, grav = 140, t0 = os.clock(), life = 0.35 + math.random() * 0.3, fade = false })
	end
	runUiBits()
end

-- The canvas a GUI object sits on, and its middle there (UI px).
local function onCanvas(gui: GuiObject): (Frame?, number, number)
	local c: Instance? = gui.Parent
	while c and not (c:IsA("Frame") and c.Name == "Canvas") do
		c = c.Parent
	end
	if c == nil or not c:IsA("Frame") then
		return nil, 0, 0
	end
	local canvasF = c :: Frame
	local kk = math.max(1, K)
	local x = (gui.AbsolutePosition.X - canvasF.AbsolutePosition.X + gui.AbsoluteSize.X / 2) / kk
	local y = (gui.AbsolutePosition.Y - canvasF.AbsolutePosition.Y + gui.AbsoluteSize.Y / 2) / kk
	return canvasF, x, y
end

-- A burst from the middle of a GUI object, on its canvas (it outlives the object: a panel rebuilt).
function UIKit.burstOn(gui: GuiObject, colors: { string }, n: number?, speed: number?)
	local canvasF, x, y = onCanvas(gui)
	if canvasF then
		UIKit.burst(canvasF, x, y, colors, n, speed)
	end
end

-- A word rising from a point of a frame and fading (money coming in).
function UIKit.popText(parent: Instance, x: number, y: number, text: string, color: Color3)
	local w = UIKit.textWidth(text) + 4
	local l = UIKit.text(parent, text, UDim2.fromOffset(w, 10), UDim2.fromOffset(math.floor(x - w / 2), math.floor(y)), { x = "center", color = color, kind = "outline", z = 30, name = "PopText" })
	l.Active = false
	local g: GuiObject = l
	table.insert(uiBits, { f = g, x = math.floor(x - w / 2), y = math.floor(y), vx = 0, vy = -16, grav = 0, t0 = os.clock(), life = 0.9, fade = true })
	runUiBits()
end

-- A light band (2 px, clear of the stepped corners) sweeping across a button's plate.
function UIKit.shine(b: GuiObject)
	local plate = b:FindFirstChild("Plate")
	if plate == nil or not plate:IsA("Frame") or b.AbsoluteSize.X < 4 then
		return
	end
	local w = b.Size.X.Offset
	local h = b.Size.Y.Offset
	if w < 8 or h < 6 then
		return
	end
	plate.ClipsDescendants = true
	local band = UIKit.rect(plate, UDim2.fromOffset(2, h - 4), UDim2.fromOffset(-2, 2), Color3.new(1, 1, 1), 2)
	band.Name = "Shine"
	band.BackgroundTransparency = 0.55
	band.Active = false
	local band2 = UIKit.rect(band, UDim2.fromOffset(1, h - 4), UDim2.fromOffset(3, 0), Color3.new(1, 1, 1), 2)
	band2.BackgroundTransparency = 0.3
	UIKit.tween(band, 0.45, { Position = UDim2.fromOffset(w, 2) })
	task.delay(0.5, function()
		band:Destroy()
	end)
end

------------------------------------------------------------------ confetti
-- A burst of confetti over a frame (a Hall of Fame game, an award, a perfect minigame): little rects that fly up,
-- tumble down, sway and fade, then go.
function UIKit.confetti(parent: GuiObject, n: number?, colors: { string }?)
	local w = parent.AbsoluteSize.X / math.max(1, K)
	local h = parent.AbsoluteSize.Y / math.max(1, K)
	if w < 4 then
		w, h = parent.Size.X.Offset, parent.Size.Y.Offset
	end
	local keys = colors or { "accent", "fun", "ideas", "graphics", "sound", "white" }
	type Bit = { f: Frame, x: number, y: number, vx: number, vy: number, ph: number }
	local bits: { Bit } = {}
	for i = 1, n or 40 do
		local c = UIKit.color(keys[(i - 1) % #keys + 1])
		-- 1 px pieces and short sticks (never a 2 x 2 block: that would read as one big pixel)
		local shape = i % 4
		local r = UIKit.rect(parent, UDim2.fromOffset(if shape == 1 then 2 else 1, if shape == 2 then 2 else 1), UDim2.fromOffset(0, 0), c, 20)
		r.Name = "Confetti"
		table.insert(bits, { f = r, x = w * (0.2 + 0.6 * math.random()), y = h * 0.45, vx = (math.random() - 0.5) * 140, vy = -60 - math.random() * 90, ph = math.random() * 6 })
	end
	local t0 = os.clock()
	local last = t0
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local t, dt = now - t0, math.min(0.05, now - last)
		last = now
		if t > 2.2 or parent.Parent == nil then
			for _, b in bits do
				b.f:Destroy()
			end
			if conn then
				conn:Disconnect()
			end
			return
		end
		for _, b in bits do
			b.vy = math.min(b.vy + 160 * dt, 50)
			b.vx *= 0.98
			b.x += (b.vx + math.sin(t * 6 + b.ph) * 12) * dt
			b.y += b.vy * dt
			b.f.Position = UDim2.fromOffset(math.floor(b.x), math.floor(b.y))
			if t > 1.6 then
				b.f.BackgroundTransparency = (t - 1.6) / 0.6
			end
		end
	end)
end

------------------------------------------------------------------ portraits
-- A developer's portrait: their rig drawn by Pixel/Snapshot like the world (2:1, toon bands, ink outline), cached by
-- look. Without EditableImages a plain swatch of their shirt colour stands in.
-- (the seated rig wears the hat, face, neck, back and top pieces of the look: Models/CharacterModels)
function UIKit.portrait(parent: Instance, look: Types.Look, size: number, pos: UDim2): GuiObject
	local snap = nil
	if Snapshot.available() then
		-- (keyed by the whole look, the pieces worn too: Data/Looks.encode)
		local key = "dev:" .. Looks.encode(look :: any) .. ":" .. size
		snap = Snapshot.get(key, function(): Instance?
			-- head and shoulders, turned to face the viewer (the world's camera looks from +X +Z: yaw 45)
			local rig = CharacterModels.build(look, "Portrait", 0)
			CharacterModels.pose(rig, CFrame.new(), 0, "idle")
			for _, n in { "LegL", "LegR", "ShinL", "ShinR", "ArmL", "ArmR", "HandL", "HandR" } do
				local part = rig.parts[n]
				if part then
					part:Destroy()
				end
			end
			return rig.model
		end, { size = size, priority = 1, yaw = 45 })
	end
	if snap then
		local l = Snapshot.label(snap, parent, true)
		l.Name = "Portrait"
		l.Position = pos
		l.ZIndex = 3
		return l
	end
	local f = UIKit.plate(parent, UDim2.fromOffset(size, size), pos, UIKit.color(Looks.shirt[look.shirt] or "blue"), 0, 2)
	f.Name = "Portrait"
	return f
end

------------------------------------------------------------------ lifecycle
function UIKit.init()
	K = math.max(1, math.floor(PixelRenderer.pixelScale()))
	UIKit.root("World")
	UIKit.root("Hud")
	UIKit.root("Modal")
	UIKit.root("Popup")
	PixelRenderer.Changed:Connect(relayoutAll)
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(relayoutAll)
		end)
	end
	-- K follows the renderer's layer (it can change with the tier or the screen)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local k = math.max(1, math.floor(PixelRenderer.pixelScale()))
			if k ~= K then
				relayoutAll()
			end
		end
	end)
end

-- Tween helper (UI px offsets only).
-- Tween helper. Positions and sizes (UDim2) move on the pixel grid: every frame their offsets are whole UI px (a
-- Quad ease-out, snapped), so nothing is ever drawn between art pixels; anything else (transparencies, colours) is a
-- TweenService tween.
local gridTweens: { [Instance]: { [string]: number } } = {}
function UIKit.tween(inst: Instance, time: number, props: { [string]: any })
	local rest: { [string]: any } = {}
	local grid: { [string]: UDim2 } = {}
	for k, v in props do
		if typeof(v) == "UDim2" then
			grid[k] = v
		else
			rest[k] = v
		end
	end
	if next(rest) ~= nil then
		local tw = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), rest)
		tw:Play()
	end
	for k, target in grid do
		local from = (inst :: any)[k] :: UDim2
		local mine = (gridTweens[inst] and gridTweens[inst][k] or 0) + 1
		gridTweens[inst] = gridTweens[inst] or {}
		gridTweens[inst][k] = mine
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			local p = if time <= 0 then 1 else math.clamp((os.clock() - t0) / time, 0, 1)
			local mapping = gridTweens[inst]
			if inst.Parent == nil or mapping == nil or mapping[k] ~= mine then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local e = 1 - (1 - p) * (1 - p)
			local function lerp(a: number, b: number): number
				return a + (b - a) * e
			end
			local at = UDim2.new(lerp(from.X.Scale, target.X.Scale), math.floor(lerp(from.X.Offset, target.X.Offset) + 0.5), lerp(from.Y.Scale, target.Y.Scale), math.floor(lerp(from.Y.Offset, target.Y.Offset) + 0.5))
			local obj: any = inst
			obj[k] = at
			if p >= 1 then
				mapping[k] = nil
				if next(mapping) == nil then
					gridTweens[inst] = nil
				end
				if conn then
					conn:Disconnect()
				end
			end
		end)
	end
end

return UIKit
