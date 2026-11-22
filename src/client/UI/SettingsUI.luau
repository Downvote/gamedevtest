--!strict
-- The Settings panel (GAME_DESIGN 9; the request of 2026-11-14: "Add a settings tab, replacing the music button"): the
-- menu bar's Settings opens it, in place of the music note that sat in the top right corner.
--   Language  Auto / each language      settings.lang: Auto (the player's Roblox language when the game has it) or a
--                                       language by its own name, its words in its own letters (never translated);
--                                       the choices flow over lines of their own under the label (2026-11-20: "like
--                                       the bakery game, make translations for different languages")
--   Text      Pixel / Smooth            settings.text: the pixel font, or Roblox's own font for every word (2026-11-20:
--                                       "an option to turn off pixel text")
--   Music     On / Off                  settings.music: the background music
--   Sounds    On / Off                  settings.sfx: every one-shot sound and the island's loops (waves, birds, rain)
--   Pixel art High / Medium / Low       settings.pixel: the pixel filter's detail (no Off: the user asked for none, 2026-11-14)
--   Screen    Auto / 100% .. 200%       settings.screen: the display's own scale (Pixel/DisplayScale), so every art pixel
--                                       is a whole number of the screen's pixels (2026-11-20: the tree's outlines broken
--                                       on a screen at 125%); its choices on a line of their own under the label
--   View      - [ten notches] +         settings.zoom: the camera's zoom on the islands (the request of 2026-11-18: "make a
--                                       view slider for zooming the camera in and out, with 10 notches"); drag the knob,
--                                       tap a notch or the - and + at the ends
-- A tap takes effect on this client at once (Audio, PixelRenderer) and is kept with the profile (settings.set); until the
-- server's view says the same, the tap's value is the one used. The View slider moves at once and the camera follows
-- ZOOM_WAIT after the last notch, so a drag across several bakes the island once.
-- API: SettingsUI.init(), SettingsUI.value(k) -> string, SettingsUI.zoom() -> number, SettingsUI.setZoom(n) (as a drag
-- to notch n would: sims and previews), SettingsUI.apply() (Hud's heartbeat: music and sounds follow the settings),
-- SettingsUI.ROWS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local DisplayScale = require(script.Parent.Parent.Pixel.DisplayScale)
local UIKit = require(script.Parent.UIKit)

local SettingsUI = {}

type Opt = { v: string, text: string }
type Row = { k: string, label: string, opts: { Opt }, hint: string?, own: boolean?, flow: boolean? }
-- (the language row's choices: Auto, then each language by its own name, shown as written)
local LANG_OPTS: { Opt } = { { v = "auto", text = "Auto" } }
for _, info in Lang.LIST do
	table.insert(LANG_OPTS, { v = info.code, text = info.name })
end
local ROWS: { Row } = {
	{ k = "lang", label = "Language", opts = LANG_OPTS, own = true, flow = true },
	{
		k = "text",
		label = "Text",
		opts = { { v = "pixel", text = "Pixel" }, { v = "smooth", text = "Smooth" } },
		hint = "Smooth is easier to read on a small screen.",
	},
	{ k = "music", label = "Music", opts = { { v = "on", text = "On" }, { v = "off", text = "Off" } } },
	{ k = "sfx", label = "Sounds", opts = { { v = "on", text = "On" }, { v = "off", text = "Off" } } },
	{
		k = "pixel",
		label = "Pixel art",
		opts = { { v = "high", text = "High" }, { v = "medium", text = "Medium" }, { v = "low", text = "Low" } },
		hint = "Lower runs smoother on older phones.",
	},
	{
		k = "screen",
		label = "Screen",
		opts = {
			{ v = "auto", text = "Auto" },
			{ v = "100", text = "100%" },
			{ v = "125", text = "125%" },
			{ v = "150", text = "150%" },
			{ v = "175", text = "175%" },
			{ v = "200", text = "200%" },
		},
		hint = "Pixels look uneven? Pick your screen's scale.",
		own = true,
	},
}
SettingsUI.ROWS = ROWS

-- taps the server hasn't answered yet (key -> value)
local pending: { [string]: string } = {}

-- A setting's value now: a tap not answered yet, else the profile's (music and sounds "on" unless "off", the pixel
-- art "high" unless set).
function SettingsUI.value(k: string): string
	local v: Types.ClientView? = StateClient.view()
	local saved = if v then (v.settings :: any)[k] else nil
	local p = pending[k]
	if p ~= nil then
		if saved == p then
			pending[k] = nil
		end
		return p
	end
	if k == "pixel" then
		return if type(saved) == "string" then saved else "high"
	elseif k == "screen" then
		return if type(saved) == "string" and Tuning.ScreenScales[saved] ~= nil then saved else "auto"
	elseif k == "lang" then
		return if type(saved) == "string" and (saved == "auto" or Lang.byCode[saved] ~= nil) then saved else "auto"
	elseif k == "text" then
		return if saved == "smooth" then "smooth" else "pixel"
	end
	return if saved == "off" then "off" else "on"
end

-- Music and sounds as the settings say (Hud's heartbeat calls this every frame; cheap).
function SettingsUI.apply()
	Audio.setMusicOn(SettingsUI.value("music") ~= "off")
	Audio.setSoundsOn(SettingsUI.value("sfx") ~= "off")
	DisplayScale.setChoice(SettingsUI.value("screen"))
end

-- The language and the text as the settings say, a tap not answered yet included (Main.client on every view; UIKit
-- does nothing when they are on already).
function SettingsUI.applyLanguage()
	UIKit.applyLanguage(SettingsUI.value("lang"), SettingsUI.value("text") == "smooth")
end

local function set(k: string, val: string)
	if SettingsUI.value(k) == val then
		return
	end
	pending[k] = val
	if k == "pixel" then
		PixelRenderer.setTier(val)
	end
	SettingsUI.apply()
	if k == "lang" or k == "text" then
		SettingsUI.applyLanguage()
	end
	Audio.play("click")
	task.spawn(function()
		local res = StateClient.request("settings.set", { k = k, v = val })
		if not res.ok then
			pending[k] = nil
			UIKit.notice("Couldn't save that. Try again.", UIKit.color("bad"))
		end
		SettingsUI.apply()
		SettingsUI.applyLanguage()
		if UIKit.currentPanel() == "settings" then
			UIKit.refreshPanel()
		end
	end)
	UIKit.refreshPanel()
end

------------------------------------------------------------------ the View slider
local NOTCHES = #Tuning.CamZoomNotches
local ZOOM_WAIT = 0.3 -- seconds after the last notch before the camera follows and the notch is saved
local pendingZoom: number? = nil -- a notch the server hasn't kept yet
local zoomSeq = 0
local showZoom: ((n: number) -> ())? = nil -- the open panel's knob

-- The View slider's notch now: one not saved yet, else the profile's (the default until the view comes).
function SettingsUI.zoom(): number
	local v: Types.ClientView? = StateClient.view()
	local saved = if v and type(v.settings.zoom) == "number" then v.settings.zoom :: number else Tuning.CamZoomDefault
	local p = pendingZoom
	if p ~= nil then
		if saved == p then
			pendingZoom = nil
		end
		return p
	end
	return saved
end

-- The knob to notch n (clamped); the camera and the save follow ZOOM_WAIT after the last one.
function SettingsUI.setZoom(n: number)
	local z = math.clamp(math.floor(n + 0.5), 1, NOTCHES)
	if z == SettingsUI.zoom() then
		return
	end
	pendingZoom = z
	Audio.play("flip")
	local show = showZoom
	if show then
		show(z)
	end
	zoomSeq += 1
	local seq = zoomSeq
	task.delay(ZOOM_WAIT, function()
		if seq ~= zoomSeq then
			return -- (a later notch takes over)
		end
		CameraController.setZoom(z)
		local res = StateClient.request("settings.set", { k = "zoom", v = z })
		if seq ~= zoomSeq then
			return
		end
		if not res.ok then
			pendingZoom = nil
			CameraController.setZoom(SettingsUI.zoom())
			UIKit.notice("Couldn't save that. Try again.", UIKit.color("bad"))
			if UIKit.currentPanel() == "settings" then
				UIKit.refreshPanel()
			end
		end
	end)
end

local PAD = 6
local ROW_H = 22
local KNOB_W = 7
local TRACK_MIN = 110 -- UI px: a shorter track beside the label (a phone held upright) goes on a line of its own

-- Whether the View slider gets a line of its own in a body w UI px wide (its track beside the label would be short).
local function narrow(w: number): boolean
	return w - PAD - 14 - (PAD + 62 + 14) < TRACK_MIN
end

-- A row's hint lines in a body w wide (it wraps on a narrow panel).
local function hintLines(hint: string, w: number): number
	return math.max(1, UIKit.lines(hint, w - 2 * PAD))
end

-- The View row at y: the label, then - [the track, its ten notches and the knob] + across the rest of the row (on a
-- narrow panel, the label's own line and the slider under it, the body's whole width).
local function viewRow(body: Frame, w: number, y: number)
	UIKit.text(body, "View", UDim2.fromOffset(60, 12), UDim2.fromOffset(PAD, y + 2), { color = UIKit.color("text"), name = "Label_zoom" })
	local own = narrow(w)
	local BX0 = if own then PAD else PAD + 62
	local TX0 = BX0 + 14
	local TW = w - PAD - 14 - TX0
	local TY = if own then y + 15 else y + 1
	UIKit.button(body, "-", UDim2.fromOffset(12, 11), UDim2.fromOffset(BX0, TY), function()
		SettingsUI.setZoom(SettingsUI.zoom() - 1)
	end, { name = "ZoomOut" })
	UIKit.button(body, "+", UDim2.fromOffset(12, 11), UDim2.fromOffset(w - PAD - 12, TY), function()
		SettingsUI.setZoom(SettingsUI.zoom() + 1)
	end, { name = "ZoomIn" })
	-- the track: a frame round a groove (a darker step of the groove: selective outlining), filled up to the knob
	UIKit.rect(body, UDim2.fromOffset(TW, 5), UDim2.fromOffset(TX0, TY + 3), UIKit.inkOf(UIKit.color("plate")), 3)
	UIKit.rect(body, UDim2.fromOffset(TW - 2, 3), UDim2.fromOffset(TX0 + 1, TY + 4), UIKit.color("plate"), 4)
	local fill = UIKit.rect(body, UDim2.fromOffset(0, 3), UDim2.fromOffset(TX0 + 1, TY + 4), UIKit.color("accent"), 5)
	-- a notch's knob x (whole UI px along the track)
	local function knobX(i: number): number
		return math.floor((TW - KNOB_W) * (i - 1) / (NOTCHES - 1) + 0.5)
	end
	-- the ten notches: a tick under the track at each (1 x 3 px), the default's a pixel longer
	for i = 1, NOTCHES do
		local long = i == Tuning.CamZoomDefault
		UIKit.rect(body, UDim2.fromOffset(1, if long then 4 else 3), UDim2.fromOffset(TX0 + knobX(i) + 3, TY + 9), UIKit.color("text_dim"), 3).Name = "ZoomTick_" .. i
	end
	local knob = Instance.new("Frame")
	knob.Name = "ZoomKnob"
	knob.BackgroundTransparency = 1
	knob.Size = UDim2.fromOffset(KNOB_W, 11)
	knob.ZIndex = 6
	knob.Parent = body
	-- (its outline a darker step of its face)
	local knobEdge = UIKit.inkOf(UIKit.color("button_ok"))
	UIKit.rect(knob, UDim2.fromOffset(5, 11), UDim2.fromOffset(1, 0), knobEdge, 6)
	UIKit.rect(knob, UDim2.fromOffset(7, 9), UDim2.fromOffset(0, 1), knobEdge, 6)
	UIKit.rect(knob, UDim2.fromOffset(5, 9), UDim2.fromOffset(1, 1), UIKit.color("button_ok"), 7)
	UIKit.rect(knob, UDim2.fromOffset(1, 7), UDim2.fromOffset(1, 2), UIKit.color("paper"), 8)
	local function show(n: number)
		local x = knobX(n)
		knob.Position = UDim2.fromOffset(TX0 + x, TY)
		fill.Size = UDim2.fromOffset(math.max(0, x + 2), 3)
	end
	show(SettingsUI.zoom())
	showZoom = show
	-- dragging along the track, or a tap on it, picks the nearest notch (mouse or touch)
	local hit = Instance.new("TextButton")
	hit.Name = "ZoomSlider"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromOffset(TW, 15)
	hit.Position = UDim2.fromOffset(TX0, TY - 2)
	hit.ZIndex = 9
	hit.Parent = body
	local dragging = false
	local function at(px: number)
		local s = math.max(1e-6, hit.AbsoluteSize.X / TW) -- (screen px a UI px)
		local u = (px - hit.AbsolutePosition.X) / s - (KNOB_W - 1) / 2
		SettingsUI.setZoom(1 + u / (TW - KNOB_W) * (NOTCHES - 1))
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			at(input.Position.X)
		end
	end)
	local moved = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			at(input.Position.X)
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	hit.Destroying:Connect(function()
		moved:Disconnect()
		ended:Disconnect()
		if showZoom == show then
			showZoom = nil
		end
	end)
end

-- A flowing row's choices laid out in a body w wide: each button's x, y (from the row's first line) and width, and
-- how many lines they take (a choice's words as shown: a language's own name, never translated).
local function flowLayout(row: Row, w: number): ({ { x: number, y: number, w: number } }, number)
	local out: { { x: number, y: number, w: number } } = {}
	local x, line = PAD, 0
	for _, o in row.opts do
		local bw = math.max(26, (if o.v == "auto" then UIKit.textWidth(o.text) else UIKit.rawWidth(o.text)) + 12)
		if x > PAD and x + bw > w - PAD then
			x = PAD
			line += 1
		end
		table.insert(out, { x = x, y = line * 16, w = bw })
		x += bw + 3
	end
	return out, line + 1
end

local function build(sheet: Frame, _arg: any?)
	local bw = sheet:GetAttribute("W")
	local w = if type(bw) == "number" then bw else 228
	-- (the rows in a list that scrolls: on a phone the sheet is the screen and the rows ran on past its foot with the
	-- View slider last, out of reach; the request of 2026-11-22, "the view setting is hidden in mobile and other
	-- devices, you cant scroll down to see it")
	local body = UIKit.scroll(sheet, UDim2.fromOffset(w, UIKit.bodyHeight(sheet)), UDim2.new())
	body.Name = "List"
	local y = 4
	for _, row in ROWS do
		UIKit.text(body, row.label, UDim2.fromOffset(60, 12), UDim2.fromOffset(PAD, y + 2), { color = UIKit.color("text"), name = "Label_" .. row.k })
		if row.k == "screen" then
			-- (what Auto found, so a player can tell whether the game saw the screen's scale)
			local found = Lang.fmt("Found {n}%", { n = math.floor(DisplayScale.found() * 100 + 0.5) })
			UIKit.text(body, found, UDim2.fromOffset(w - 2 * PAD - 60, 12), UDim2.fromOffset(PAD + 60, y + 2), { color = UIKit.color("text_dim"), x = "right", name = "Found_screen" })
		end
		local cur = SettingsUI.value(row.k)
		if row.flow then
			-- (the choices flow over lines of their own under the label, from the left)
			local spots, n = flowLayout(row, w)
			y += 14
			for i, o in row.opts do
				local at = spots[i]
				UIKit.button(body, o.text, UDim2.fromOffset(at.w, 14), UDim2.fromOffset(at.x, y + at.y), function()
					set(row.k, o.v)
				end, { name = "Set_" .. row.k .. "_" .. o.v, color = if cur == o.v then UIKit.color("button") else UIKit.color("plate_light"), raw = o.v ~= "auto" })
			end
			y += 16 * n + 6
			continue
		end
		-- the choices to the right, each as wide as its word, the chosen one lit (a row of many on a line of its own
		-- under the label, from the left)
		local widths: { number } = {}
		local total = 0
		local minW = if row.own then 26 else 28
		for i, o in row.opts do
			widths[i] = math.max(minW, UIKit.buttonWidth(o.text, 6))
			total += widths[i] + 3
		end
		local x = w - PAD - total + 3
		if row.own then
			y += 14
			x = PAD
		end
		for i, o in row.opts do
			local on = cur == o.v
			UIKit.button(body, o.text, UDim2.fromOffset(widths[i], 14), UDim2.fromOffset(x, y), function()
				set(row.k, o.v)
			end, { name = "Set_" .. row.k .. "_" .. o.v, color = if on then UIKit.color("button") else UIKit.color("plate_light") })
			x += widths[i] + 3
		end
		y += ROW_H
		if row.hint then
			local n = hintLines(row.hint, w)
			UIKit.text(body, row.hint, UDim2.fromOffset(w - 2 * PAD, 10 * n), UDim2.fromOffset(PAD, y - 6), { color = UIKit.color("text_dim"), wrap = n > 1, name = "Hint_" .. row.k })
			y += 8 + 10 * (n - 1)
		end
	end
	viewRow(body :: any, w, y)
	-- (room under the slider's ticks at the list's foot)
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.fromOffset(1, 12)
	foot.Position = UDim2.fromOffset(0, y + (if narrow(w) then 30 else 16))
	foot.Parent = body
end

-- The panel's height for its width: the rows as build lays them out, a hint wrapping and the View slider on a line of
-- its own on a narrow panel.
local function heightFor(pw: number): number
	local w = pw - 8
	local y = 4
	for _, row in ROWS do
		if row.flow then
			local _, n = flowLayout(row, w)
			y += 14 + 16 * n + 6
			continue
		end
		y += ROW_H + (if row.own then 14 else 0)
		if row.hint then
			y += 8 + 10 * (hintLines(row.hint, w) - 1)
		end
	end
	return y + (if narrow(w) then 30 else 16) + 4 + 20
end

function SettingsUI.init()
	UIKit.registerPanel("settings", { title = "Settings", icon = "gear", w = 236, hFor = heightFor, build = build })
end

return SettingsUI
