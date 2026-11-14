--!strict
-- The Settings panel (GAME_DESIGN 9; the request of 2026-11-14: "Add a settings tab, replacing the music button"): the
-- menu bar's Settings opens it, in place of the music note that sat in the top right corner.
--   Music     On / Off                  settings.music: the background music
--   Sounds    On / Off                  settings.sfx: every one-shot sound and the island's loops (waves, birds, rain)
--   Pixel art High / Medium / Low       settings.pixel: the pixel filter's detail (no Off: the user asked for none, 2026-11-14)
-- A tap takes effect on this client at once (Audio, PixelRenderer) and is kept with the profile (settings.set); until the
-- server's view says the same, the tap's value is the one used.
-- API: SettingsUI.init(), SettingsUI.value(k) -> string, SettingsUI.apply() (Hud's heartbeat: music and sounds follow the
-- settings), SettingsUI.ROWS.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)

local SettingsUI = {}

type Opt = { v: string, text: string }
type Row = { k: string, label: string, opts: { Opt }, hint: string? }
local ROWS: { Row } = {
	{ k = "music", label = "Music", opts = { { v = "on", text = "On" }, { v = "off", text = "Off" } } },
	{ k = "sfx", label = "Sounds", opts = { { v = "on", text = "On" }, { v = "off", text = "Off" } } },
	{
		k = "pixel",
		label = "Pixel art",
		opts = { { v = "high", text = "High" }, { v = "medium", text = "Medium" }, { v = "low", text = "Low" } },
		hint = "Less detail runs smoother on older phones.",
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
	end
	return if saved == "off" then "off" else "on"
end

-- Music and sounds as the settings say (Hud's heartbeat calls this every frame; cheap).
function SettingsUI.apply()
	Audio.setMusicOn(SettingsUI.value("music") ~= "off")
	Audio.setSoundsOn(SettingsUI.value("sfx") ~= "off")
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
	Audio.play("click")
	task.spawn(function()
		local res = StateClient.request("settings.set", { k = k, v = val })
		if not res.ok then
			pending[k] = nil
			UIKit.notice("That setting couldn't be saved. Try again in a moment.", UIKit.color("bad"))
		end
		SettingsUI.apply()
		if UIKit.currentPanel() == "settings" then
			UIKit.refreshPanel()
		end
	end)
	UIKit.refreshPanel()
end

local PAD = 6
local ROW_H = 22

local function build(body: Frame, _arg: any?)
	local bw = body:GetAttribute("W")
	local w = if type(bw) == "number" then bw else 228
	local y = 4
	for _, row in ROWS do
		UIKit.text(body, row.label, UDim2.fromOffset(60, 12), UDim2.fromOffset(PAD, y + 2), { color = UIKit.color("text"), name = "Label_" .. row.k })
		local cur = SettingsUI.value(row.k)
		-- the choices to the right, each as wide as its word, the chosen one lit
		local widths: { number } = {}
		local total = 0
		for i, o in row.opts do
			widths[i] = math.max(28, UIKit.buttonWidth(o.text, 6))
			total += widths[i] + 3
		end
		local x = w - PAD - total + 3
		for i, o in row.opts do
			local on = cur == o.v
			UIKit.button(body, o.text, UDim2.fromOffset(widths[i], 14), UDim2.fromOffset(x, y), function()
				set(row.k, o.v)
			end, { name = "Set_" .. row.k .. "_" .. o.v, color = if on then UIKit.color("button") else UIKit.color("plate_light") })
			x += widths[i] + 3
		end
		y += ROW_H
		if row.hint then
			UIKit.text(body, row.hint, UDim2.fromOffset(w - 2 * PAD, 10), UDim2.fromOffset(PAD, y - 6), { color = UIKit.color("text_dim"), name = "Hint_" .. row.k })
			y += 8
		end
	end
end

function SettingsUI.init()
	UIKit.registerPanel("settings", { title = "Settings", icon = "gear", w = 236, h = 104, build = build })
end

return SettingsUI
