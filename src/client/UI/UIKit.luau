--!strict
-- The interface kit (docs/ARCHITECTURE.md 10; Random Bakery's look): pixel-art plates with stepped corners, the pixel
-- font, no borders, all on the world's pixel grid. Every root's canvas is laid out in UI px, one UI px = one art
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
local PixelFont = require(ReplicatedStorage.Shared.Render.PixelFont)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local PixelText = require(script.Parent.Parent.Pixel.PixelText)
local Snapshot = require(script.Parent.Parent.Pixel.Snapshot)
local Audio = require(script.Parent.Parent.Controllers.Audio)

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

-- The roots: World (popups over the office, full screen), Hud, Modal (panels), Popup (cards, notices).
function UIKit.root(name: string): ScreenGui
	if name == "World" then
		return makeRoot("World", 7, true)
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
-- A flat surface with stepped pixel corners (Random Bakery's UIKit.plate): rectangles named "Fill", no overlaps, so
-- a translucent plate stays even. Content goes in it at ZIndex >= 1.
function UIKit.plate(parent: Instance?, size: UDim2, pos: UDim2?, c: Color3?, alpha: number?, corner: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Plate"
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local k = math.clamp(math.floor(corner or 2), 0, 3)
	local col = c or UIKit.color("plate")
	local a = alpha or 0
	local function rect(x: UDim, y: UDim, w: UDim, h: UDim)
		local r = Instance.new("Frame")
		r.Name = "Fill"
		r.BorderSizePixel = 0
		r.BackgroundColor3 = col
		r.BackgroundTransparency = a
		r.Position = UDim2.new(x, y)
		r.Size = UDim2.new(w, h)
		r.ZIndex = 0
		r.Parent = f
	end
	local insets: { number } = if k == 1 then { 1 } elseif k == 2 then { 2, 1 } elseif k == 3 then { 3, 1, 1 } else {}
	local rows = #insets
	for i, inset in insets do
		local y = i - 1
		rect(UDim.new(0, inset), UDim.new(0, y), UDim.new(1, -2 * inset), UDim.new(0, 1))
		rect(UDim.new(0, inset), UDim.new(1, -y - 1), UDim.new(1, -2 * inset), UDim.new(0, 1))
	end
	rect(UDim.new(0, 0), UDim.new(0, rows), UDim.new(1, 0), UDim.new(1, -2 * rows))
	f.Parent = parent
	return f
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
export type ButtonOpts = { color: Color3?, textColor: Color3?, enabled: boolean?, name: string?, face: string? }

local buttonColor: { [GuiButton]: Color3 } = {}

-- The plate colour a button shows now: its own (lighter while hovered) or the disabled grey.
local hovered: { [GuiButton]: boolean } = {}
local function paintButton(b: GuiButton)
	local plate = b:FindFirstChild("Plate")
	if plate == nil then
		return
	end
	local c = if b.AutoButtonColor then (buttonColor[b] or UIKit.color("button")) else UIKit.color("button_off")
	if hovered[b] and b.AutoButtonColor then
		c = c:Lerp(Color3.new(1, 1, 1), 0.18)
	end
	UIKit.setPlate(plate, c)
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
	local plate = UIKit.plate(b, UDim2.fromScale(1, 1), nil, col, 0, 2)
	plate.ZIndex = 1
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
type PanelDef = { title: string, build: (body: Frame, arg: any?) -> (), pause: boolean?, w: number?, h: number? }
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
	local w = math.min(def.w or 300, s.X - 8)
	local h = math.min(def.h or 170, s.Y - 6)
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
	shade.BackgroundColor3 = UIKit.color("ink")
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 1
	local fx, fy = math.floor((s.X - sz.X) / 2), math.floor((s.Y - sz.Y) / 2)
	local frame = UIKit.plate(shade, UDim2.fromOffset(sz.X, sz.Y), UDim2.fromOffset(fx, fy + 10), UIKit.color("plate"), 0, 3)
	frame.Name = "Frame"
	frame.ZIndex = 2
	UIKit.text(frame, def.title, UDim2.new(1, -40, 0, 14), UDim2.fromOffset(6, 2), { color = UIKit.color("accent"), name = "Title" })
	-- the status line: notices while the panel is open land here instead of covering it
	local titleW = UIKit.textWidth(def.title) + 14
	UIKit.text(frame, "", UDim2.new(1, -(titleW + UIKit.buttonWidth("Close", 4) + 8), 0, 14), UDim2.fromOffset(titleW, 2), { color = UIKit.color("text"), name = "Status", x = "right" })
	UIKit.button(frame, "Close", UDim2.fromOffset(UIKit.buttonWidth("Close", 4), 12), UDim2.new(1, -UIKit.buttonWidth("Close", 4) - 3, 0, 3), function()
		Audio.play("close")
		UIKit.closePanel()
	end, { color = UIKit.color("plate_light"), name = "Close" })
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(math.floor((s.X - w) / 2), 24), UIKit.color("plate"), 0.08, 2)
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
		y += n.Size.Y.Offset + 2
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
function UIKit.portrait(parent: Instance, look: Types.Look, size: number, pos: UDim2): GuiObject
	local snap = nil
	if Snapshot.available() then
		local key = string.format("dev:%d.%d.%d.%d:%d", look.skin, look.hair, look.style, look.shirt, size)
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
	local Looks = require(ReplicatedStorage.Shared.Data.Looks)
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
			;(inst :: any)[k] = UDim2.new(
				lerp(from.X.Scale, target.X.Scale),
				math.floor(lerp(from.X.Offset, target.X.Offset) + 0.5),
				lerp(from.Y.Scale, target.Y.Scale),
				math.floor(lerp(from.Y.Offset, target.Y.Offset) + 0.5)
			)
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
