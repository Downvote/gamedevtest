--!strict
-- The HUD (docs/ARCHITECTURE.md 10.3; GAME_DESIGN 3-9): the top bar (shells, the day and its clock), the
-- status panel under it on the left (lines like the season and the weather: `Hud.statusLine`) with the questline's
-- card under that, the menu bar along the bottom (Build, Driftlings, Index, Looks), the island card on the right (the
-- island's name, driftlings in huts and their room, charm and what it adds, what it makes) with the Tree of Life's card under
-- it (the time to its next eggs, its best few eggs with their prices to hatch them), the tips banner, the new day's
-- banner and the alerts for a new lot of eggs (the loading card is src/first's). The camera fits the island clear of
-- the HUD's blocks (CameraController.setHudRects).
-- The look (the request of 2026-11-14: "make the ui appear like this instead, with a black transparent background and
-- make it neater", with a picture of Random Bakery's HUD): every block is black see-through glass (UIKit.glass) with
-- small stepped corners and no frame; the top bar is one strip of icon and number pairs; the cards line up on one
-- column each side, the same width, padding and line height, labels quiet, numbers right-aligned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Quests = require(ReplicatedStorage.Shared.Data.Quests)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local EggView = require(script.Parent.Parent.Controllers.EggView)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local AvatarView = require(script.Parent.Parent.Controllers.AvatarView)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Words = require(script.Parent.Words)
local Menus = require(script.Parent.Menus)
local StoreUI = require(script.Parent.StoreUI)
local FounderUI = require(script.Parent.FounderUI)
local RewardsUI = require(script.Parent.RewardsUI)
local TopUI = require(script.Parent.TopUI)
local SettingsUI = require(script.Parent.SettingsUI)
local VisitUI = require(script.Parent.VisitUI)
local WelcomeUI = require(script.Parent.WelcomeUI)
local BuildUI = require(script.Parent.BuildUI)
local HatchScene = require(script.Parent.HatchScene)

local Hud = {}

local TOP_H = 14 -- the top bar's height
local BAR_H = 20 -- a menu button's height (a desktop's toolbar: the big icons, GAME_DESIGN 2.1)
-- (on a phone the menu's buttons are icons only, square and taller, so the bar is short enough to stay clear of
-- Roblox's jump button at the bottom right: the request of 2026-11-19, "make mobile and tablet as responsive and
-- catered to as possible"; each still gets UIKit's fingertip pad)
local BAR_H_PHONE = 18
local BTN_PHONE = 20
local function barH(): number
	return if UIKit.phone() then BAR_H_PHONE else BAR_H
end
local EDGE = 5 -- UI px between the HUD's blocks and the screen's edges
local CHIP_Y = 4 -- the top bar's top
local CARD_Y = CHIP_Y + TOP_H + 4 -- the cards' top (and the status panel's)
local GAP = 3 -- UI px between two blocks stacked in a column
local DOCK = 3 -- the glass round the menu bar's buttons
local PAD = UIKit.PAD -- inside a block
local CARD_W = 116 -- the right column's width (104 on phones)
local CARD_MAX_H = 150
local LINE_H = 11

------------------------------------------------------------------ phones and tablets
-- The request of 2026-11-21, with a phone held sideways: "rearrange and redo the UI on mobile and tablet. Reference
-- other mobile tycoon games in landscape and replicate their UI design." What those games share (GAME_DESIGN 2.1):
-- the money in a pill at the top left with a "+" to the store; the menus as big square buttons down the left; the
-- store, the gifts and whatever runs on a timer as squares on the right, under the island's card; the main action
-- (here Build) a big button by the right thumb, beside Roblox's jump button; the bottom left kept free for the
-- thumbstick and nothing under the jump button; the cards fold away. A touch screen (UIKit.touch: no mouse) gets it: a
-- phone icon-only squares, a tablet bigger ones with their names under them. A desktop keeps the menu bar.
local function mobile(): boolean
	return UIKit.touch()
end
local SQ_PHONE, SQ_TABLET = 22, 28 -- a square's side (22 UI px: 44 screen px, a fingertip, at a phone's pixel size)
local LABEL_H = 9 -- a tablet square's name under it
local function sq(): number
	return if UIKit.phone() then SQ_PHONE else SQ_TABLET
end
local function labelled(): boolean
	return not UIKit.phone()
end
local cellW = SQ_PHONE -- the left grid's column (a tablet's as wide as its longest name)
local cellR = SQ_PHONE -- the right row's (a third of the island card's width)
local menuSide: Frame? = nil -- the right row's Gifts and Store (the Eggs square is the tree's card)
local buildBox: Frame? = nil -- Build by the jump button
local buildBtn: TextButton? = nil -- Build, the menu bar's or the touch screen's own
local plusButton: TextButton? = nil -- the coins' "+"
-- (the island card folded to its name and coins a minute, or open: nil till tapped, a phone starting folded and a
-- tablet open; the quest's card folded to its title)
local cardOpen: boolean? = nil
local questOpen = true
local function cardFolded(): boolean
	if cardOpen == nil then
		return mobile() and UIKit.phone()
	end
	return not cardOpen
end
-- Roblox's jump button in the HUD canvas's UI px, x0, y0, x1, y1 (its TouchJump: 70 px at 95 px from the right and 90
-- from the bottom on a screen whose short side is 500 px or less, else 120 px at 170 and 210; inside the safe area
-- and down to the screen's bottom, as the HUD's canvas is)
local function jumpRect(): (number, number, number, number)
	local s = UIKit.size("Hud")
	local K = UIKit.P()
	local small = math.min(s.X, s.Y) * K <= 500
	local size = if small then 70 else 120
	local x0 = s.X - (if small then 95 else 170) / K
	local y0 = s.Y - (if small then 90 else 210) / K
	return x0, y0, x0 + size / K, y0 + size / K
end

local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local chipIcons: { [string]: GuiObject } = {}
-- what each chip set from outside (Hud.topChip) shows, put back when a resize builds the top bar again: the season's
-- and the weather's chips came back empty and stayed so until their words next changed, up to a minute later
local chipSaid: { [string]: { icon: string?, text: string, color: Color3? } } = {}
local bar: Frame? = nil
local barW = 0
local card: Frame? = nil
local treeCard: Frame? = nil -- the Tree of Life's card (GAME_DESIGN 6)
local tips: Frame? = nil
local quest: Frame? = nil -- the questline's card (GAME_DESIGN 9)
local QUEST_W = 150
local topBar: Frame? = nil -- the top bar: one glass strip of chips
local status: Frame? = nil -- the status panel under the top bar (Hud.statusLine)
local statusLines: { [string]: Frame } = {}
local statusOrder: { string } = {}
local homeButton: TextButton? = nil
local visitButton: TextButton? = nil -- (Visit: beside the top bar while the founder is home and someone else is here)
local visitLook = 0 -- (when the other islands were last counted for it)
-- (the HUD's blocks laid out again: set once `stack` is defined below; the top bar and Home call it when the
-- right-hand column may move between the top row and under the top bar)
local restackSoon: () -> () = function() end
local banner: Frame? = nil
local lastKey = ""

------------------------------------------------------------------ smooth numbers
-- Values the HUD shows ease toward their targets (the shells count up); `apply` draws a value.
type Ease = { cur: number, target: number, apply: (number) -> () }
local eases: { [string]: Ease } = {}
local function easeTo(key: string, target: number, apply: (number) -> (), instant: boolean?)
	local e = eases[key]
	if e == nil or instant then
		eases[key] = { cur = target, target = target, apply = apply }
		apply(target)
		return
	end
	e.target = target
	e.apply = apply
end
local function stepEases(dt: number)
	local k = math.min(1, dt * 7)
	for _, e in eases do
		if e.cur ~= e.target then
			local d = e.target - e.cur
			e.cur = if math.abs(d) < math.max(0.5, math.abs(e.target) * 0.002) then e.target else e.cur + d * k
			e.apply(e.cur)
		end
	end
end
local chipBump: { [string]: number } = {}

------------------------------------------------------------------ layout
-- The right-hand column's top (the island card, the tree's card on a desktop, the store's offers): up in the top row
-- beside the top bar, where the music note was (the request of 2026-11-14: "Add a settings tab, replacing the music
-- button, then move the right side tab up"), when the row has room for both; on a screen too narrow for that (the top
-- bar's words, or Home beside it, reaching the column) it waits under the top bar as before.
local function rightTop(): number
	local s = UIKit.size("Hud")
	local right = EDGE
	local tb = topBar
	if tb then
		right = EDGE + tb.Size.X.Offset
	end
	for _, b in { homeButton, visitButton } :: { TextButton? } do
		if b and b.Visible then
			right = math.max(right, b.Position.X.Offset + b.Size.X.Offset)
		end
	end
	return if right + GAP <= s.X - CARD_W - EDGE then CHIP_Y else CARD_Y
end

local function hudRects()
	local s = UIKit.size("Hud")
	local K = UIKit.P()
	local o = UIKit.canvasOrigin("Hud")
	local function r(x0: number, y0: number, x1: number, y1: number): Raster.Rect
		return { x0 = o.X + x0 * K, y0 = o.Y + y0 * K, x1 = o.X + x1 * K, y1 = o.Y + y1 * K }
	end
	local half = math.floor(barW / 2) + DOCK + 1
	local list: { Raster.Rect }
	if mobile() then
		-- a touch screen: nothing along the bottom any more (the squares keep to the sides), so a phone keeps only
		-- Roblox's top bar clear, the founder in the middle of what's left; a tablet the top bar's row and the right
		-- column too, as a desktop does
		if UIKit.phone() then
			list = { { x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y } }
		else
			list = {
				{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (CHIP_Y + TOP_H + 2) * K },
				r(s.X - CARD_W - EDGE - 2, rightTop() - 2, s.X, rightTop() + CARD_MAX_H),
			}
		end
	elseif UIKit.phone() then
		-- a phone (Random Bakery's rule): only Roblox's top bar and the menu bar are kept clear
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y },
			r(math.floor(s.X / 2) - half, s.Y - barH() - 2 * DOCK - EDGE, math.floor(s.X / 2) + half, s.Y),
		}
	else
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (CHIP_Y + TOP_H + 2) * K },
			r(math.floor(s.X / 2) - half, s.Y - barH() - 2 * DOCK - EDGE, math.floor(s.X / 2) + half, s.Y),
			r(s.X - CARD_W - EDGE - 2, rightTop() - 2, s.X, rightTop() + CARD_MAX_H),
		}
	end
	CameraController.setHudRects(list)
end

------------------------------------------------------------------ the top bar
-- One glass strip of chips (Random Bakery's top bar): each chip its 11 px icon and its value; the day's chip has a
-- thin bar under its words for how far through the day it is.
local CHIP_GAP = 7
local PLUS_W = 12 -- (a touch screen's "+" at the end of the coins chip: the Store)
-- (the top bar is one line: the shells, then the season and the weather, Hud.topChip; the day count went from it on
-- 2026-11-14: "also, this can be compressed into one line. remove the "day 1" as well")
local CHIP_MIN: { [string]: number } = { shells = 40, season = 24, weather = 24, rate = 0, isle = 30, charm = 20 }
-- (a desktop's resource bar also has the coins a minute after the coins, and at its right end the island's name and
-- level and its charm: the PC builders' bar across the top, GAME_DESIGN 2.1; the chips a screen lacks are skipped)
local CHIP_ORDER = { "shells", "rate", "season", "weather" }
local CHIP_RIGHT = { "isle", "charm" }
local function chipWidth(name: string, words: string): number
	local icon = (chipIcons :: { [string]: GuiObject? })[name] ~= nil
	return math.max(CHIP_MIN[name] or 40, (if icon then 13 else 0) + UIKit.textWidth(words) + 1)
end
-- Each chip as wide as its words need (never under its minimum), the strip round them, Home after it. A desktop's
-- strip runs the screen's width, the right chips at its far end.
local function layoutTop()
	local tb = topBar
	if tb == nil then
		return
	end
	local x = PAD
	for _, name in CHIP_ORDER do
		local f = chipFrames[name]
		local l = chips[name]
		local words = if l then tostring(l:GetAttribute("Source") or l.Text) else ""
		-- (a chip with nothing to say yet takes no room)
		if f and l and words ~= "" then
			local w = chipWidth(name, words)
			-- (a touch screen's coins chip ends in its "+")
			local pb = plusButton
			if name == "shells" and pb then
				w += PLUS_W + 2
				pb.Position = UDim2.fromOffset(w - PLUS_W, 1)
			end
			f.Visible = true
			f.Position = UDim2.fromOffset(x, 0)
			f.Size = UDim2.fromOffset(w, TOP_H)
			x += w + (if name == "shells" and chipFrames.rate then 3 else CHIP_GAP)
		elseif f then
			f.Visible = false
		end
	end
	local w = x - CHIP_GAP + PAD - 1
	local leftW = w
	if not mobile() then
		w = UIKit.size("Hud").X - 2 * EDGE
		local rx = w - PAD + 1
		for i = #CHIP_RIGHT, 1, -1 do
			local name = CHIP_RIGHT[i]
			local f, l = chipFrames[name], chips[name]
			local words = if l then tostring(l:GetAttribute("Source") or l.Text) else ""
			if f and l and words ~= "" then
				local cw = chipWidth(name, words)
				rx -= cw
				-- (never over the left chips: a narrow window drops the island's chips first)
				f.Visible = rx > leftW + 8
				f.Position = UDim2.fromOffset(rx, 0)
				f.Size = UDim2.fromOffset(cw, TOP_H)
				rx -= CHIP_GAP
			elseif f then
				f.Visible = false
			end
		end
	end
	if tb.Size.X.Offset ~= w then
		tb.Size = UDim2.fromOffset(w, TOP_H)
	end
	for _, b in { homeButton, visitButton } :: { TextButton? } do
		if b then
			-- (in the desktop's strip after the left chips; beside a touch screen's)
			b.Position = UDim2.fromOffset(EDGE + leftW + GAP, CHIP_Y)
			b.ZIndex = 4
		end
	end
	-- (the top bar grew or shrank: the right-hand column may move between the top row and under it)
	local c = card
	if c and c.Position.Y.Offset ~= rightTop() then
		restackSoon()
	end
end
local function chip(name: string, x: number, w: number, icon: string?): number
	local f = Instance.new("Frame")
	f.Name = "Chip_" .. name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(w, TOP_H)
	f.Position = UDim2.fromOffset(x, 0)
	f.ZIndex = 2
	f.Parent = topBar
	local ox = 0
	if icon then
		chipIcons[name] = PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(0, 1), 3)
		ox = 13
	end
	chips[name] = UIKit.text(f, "", UDim2.new(1, -ox, 0, 10), UDim2.fromOffset(ox, 2), { name = "Value", z = 3 })
	chipFrames[name] = f
	return x + w + CHIP_GAP
end
-- A chip's words and their colour (the desktop's coins a minute, island and charm: updateTop).
local function setChip(name: string, words: string, color: Color3?)
	local l = (chips :: { [string]: TextLabel? })[name]
	if l == nil then
		return
	end
	if l:GetAttribute("Source") ~= words then
		l:SetAttribute("Source", words)
		UIKit.setText(l, words)
		layoutTop()
	end
	UIKit.setTextColor(l, color or UIKit.color("text"))
end

local function buildTop()
	local canvas = UIKit.canvas("Hud")
	local widths = CHIP_MIN
	local w = PAD + widths.shells + PAD - 1
	local tb = UIKit.glass(canvas, UDim2.fromOffset(w, TOP_H), UDim2.fromOffset(EDGE, CHIP_Y), 2)
	tb.Name = "TopBar"
	topBar = tb
	local x = PAD
	x = chip("shells", x, widths.shells, "coin")
	if not mobile() then
		-- (a desktop's resource bar: the coins a minute in green after the coins, the island and its charm at the right)
		x = chip("rate", x, 20, nil)
		chip("isle", 0, widths.isle, "tree")
		chip("charm", 0, widths.charm, "charm")
	end
	x = chip("season", x, widths.season, "sun")
	x = chip("weather", x, widths.weather, "sun")
	-- the coins' "+" (a touch screen: the mobile games' pill, a tap to the Store), a white cross drawn on mint, its
	-- shadow the mint's ink; the coins' words make room for it
	if mobile() then
		local cf = chipFrames.shells
		local pb = UIKit.button(cf, "", UDim2.fromOffset(PLUS_W, PLUS_W), UDim2.fromOffset(widths.shells - PLUS_W, 1), function()
			UIKit.openPanel("store")
		end, { name = "CoinsPlus", color = UIKit.color("button_ok") })
		pb.ZIndex = 4
		local ink = UIKit.inkOf(UIKit.color("button_ok"))
		for _, r in { { 3, 6, 6, 2 }, { 5, 4, 2, 6 } } do
			UIKit.rect(pb, UDim2.fromOffset(r[3], r[4]), UDim2.fromOffset(r[1], r[2]), ink, 5).Name = "Shade"
		end
		for _, r in { { 3, 5, 6, 2 }, { 5, 3, 2, 6 } } do
			UIKit.rect(pb, UDim2.fromOffset(r[3], r[4]), UDim2.fromOffset(r[1], r[2]), UIKit.color("text"), 6).Name = "Cross"
		end
		plusButton = pb
		local l = chips.shells
		if l then
			l.Size = UDim2.new(1, -(13 + PLUS_W + 2), 0, 10)
		end
	end
	layoutTop()
	-- Home: shown while the founder is off their own island (char.home sends them back to their tree)
	local hb = UIKit.button(canvas, "Home", UDim2.fromOffset(UIKit.buttonWidth("Home", 5), TOP_H), UDim2.fromOffset(EDGE + w + GAP, CHIP_Y), function()
		local res = StateClient.request("char.home", {})
		if not res.ok and res.err ~= "cooldown" then
			UIKit.notice("Can't go home right now.", UIKit.color("bad"))
		end
	end, { name = "Home", color = UIKit.color("button_warn") })
	hb.Visible = false
	homeButton = hb
	-- Visit: shown in its place while the founder is home and another player's island is here (the islands float
	-- apart in the sky since 2026-11-20: UI/VisitUI lists them, each with a way over)
	local vb = UIKit.button(canvas, "Visit", UDim2.fromOffset(UIKit.buttonWidth("Visit", 5), TOP_H), UDim2.fromOffset(EDGE + w + GAP, CHIP_Y), function()
		UIKit.openPanel("visit")
	end, { name = "Visit", color = UIKit.color("button") })
	vb.Visible = false
	visitButton = vb
	-- (the music switch that sat in the top right corner moved into the Settings panel: UI/SettingsUI, the menu bar's
	-- Settings, 2026-11-14)
end

------------------------------------------------------------------ the status panel
-- Under the top bar on the left, glass like it: one line each (an 11 px icon and words), the season and the weather
-- and the like, from other modules: `Hud.statusLine(name, icon, text, color?, onTap?)` adds or changes a line, a nil
-- `text` takes it away. A line given `onTap` is a ghost button (a faint veil under the mouse; a tap calls it: the gift's
-- line opens the Rewards sheet). It hides while it has no lines; the quest's card sits under it.
local STATUS_W = QUEST_W
-- (the blocks under it move when a line comes or goes: `stack`, set once it is defined below)
local restack: () -> () = function() end
local function layoutStatus()
	local st = status
	if st == nil then
		return
	end
	local y = 2
	for _, name in statusOrder do
		local l = statusLines[name]
		if l then
			l.Position = UDim2.fromOffset(PAD - 1, y)
			l.Size = UDim2.fromOffset(STATUS_W - 2 * PAD + 2, LINE_H)
			y += LINE_H
		end
	end
	st.Size = UDim2.fromOffset(STATUS_W, y + 1)
	-- (stepping aside for Build mode and any panel, as `stack` has it: the lines change a few times a second, and each
	-- change set it showing again over the panel)
	st.Visible = #statusOrder > 0 and not (BuildUI.isOpen() or UIKit.currentPanel() ~= nil)
end

local statusTaps: { [string]: () -> () } = {}
function Hud.statusLine(name: string, icon: string?, text: string?, color: Color3?, onTap: (() -> ())?)
	local st = status
	if st == nil then
		return
	end
	local old = statusLines[name]
	if text == nil then
		statusTaps[name] = nil
		if old then
			old:Destroy()
			statusLines[name] = nil
			local i = table.find(statusOrder, name)
			if i then
				table.remove(statusOrder, i)
			end
			layoutStatus()
			restack()
		end
		return
	end
	local l: Frame? = old
	local added = l == nil
	if not l then
		local nf = Instance.new("Frame")
		nf.Name = "Status_" .. name
		nf.BackgroundTransparency = 1
		nf.Size = UDim2.fromOffset(STATUS_W - 2 * PAD + 2, LINE_H)
		nf.ZIndex = 2
		nf.Parent = st
		statusLines[name] = nf
		table.insert(statusOrder, name)
		l = nf
	end
	local line = l :: Frame
	-- (its icon made again only when it changes: the gift's line is set four times a second)
	if line:GetAttribute("Icon") ~= (icon or "") then
		line:SetAttribute("Icon", icon or "")
		local ic = line:FindFirstChild("Icon")
		if ic then
			ic:Destroy()
		end
		if icon then
			PixelSprites.image(line, "mini_" .. icon, UDim2.fromOffset(0, 0), 3).Name = "Icon"
		end
	end
	local t = line:FindFirstChild("Text")
	if t and t:IsA("TextLabel") then
		UIKit.setText(t, text)
		UIKit.setTextColor(t, color or UIKit.color("text"))
	else
		UIKit.text(line, text, UDim2.new(1, -13, 0, 10), UDim2.fromOffset(13, 1), { color = color or UIKit.color("text"), name = "Text", z = 3 })
	end
	-- (the button under the icon and the words, made once: the line is set again four times a second, the latest
	-- `onTap` kept by name)
	if onTap then
		statusTaps[name] = onTap
	else
		statusTaps[name] = nil
	end
	local tap = line:FindFirstChild("StatusTap_" .. name)
	if onTap and tap == nil then
		UIKit.button(line, "", UDim2.new(1, 2, 1, 0), UDim2.fromOffset(-1, 0), function()
			local f = statusTaps[name]
			if f then
				f()
			end
		end, { name = "StatusTap_" .. name, ghost = true }).ZIndex = 1
	elseif onTap == nil and tap then
		tap:Destroy()
	end
	layoutStatus()
	if added then
		restack()
	end
end

-- Whether the founder stands on their own island.
local function atHome(): boolean
	local v = StateClient.view()
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if v == nil or root == nil or not root:IsA("BasePart") then
		return true
	end
	return Street.plotAt(root.Position.X, root.Position.Z) == v.plot
end

local last: { [string]: number } = {}
local function showStore(key: string, value: number, instant: boolean?)
	local was = last[key]
	if was ~= nil and math.floor(was) ~= math.floor(value) then
		chipBump[key] = os.clock()
	end
	last[key] = value
	easeTo(key, value, function(x: number)
		local l = chips[key]
		if l then
			local t = Numbers.coins(x)
			if l:GetAttribute("Source") ~= t then
				l:SetAttribute("Source", t)
				UIKit.setText(l, t)
				layoutTop()
			end
		end
	end, instant)
end

local function updateTop(v: Types.ClientView)
	showStore("shells", v.shells, last.shells == nil)
	if chips.rate then
		local n = v.rates.shells
		setChip("rate", Numbers.perMin(n * 60 / Tuning.TurnSeconds), if n < -0.05 then UIKit.color("bad") elseif n > 0.05 then UIKit.color("good") else UIKit.color("text_dim"))
		local plan = Office.plans[v.tier]
		local name = if plan then plan.name else "Your island"
		setChip("isle", Lang.keep(Lang.t(name) .. " · " .. Lang.f("Level {1}/{2}", v.tier, #Office.plans)), UIKit.color("accent"))
		setChip("charm", Numbers.int(math.floor(v.charm)), UIKit.color("pink"))
	end
end

-- A chip on the top bar's line after the shells (UI/WeatherChip: "season", "weather"): its icon, its words and their
-- colour; nil words take it away.
function Hud.topChip(name: string, icon: string?, text: string?, color: Color3?)
	if text then
		chipSaid[name] = { icon = icon, text = text, color = color }
	else
		chipSaid[name] = nil
	end
	local f: Frame?, l: TextLabel? = chipFrames[name], chips[name]
	if not f or not l then
		return
	end
	local words = text or ""
	if icon and f:GetAttribute("Icon") ~= icon then
		f:SetAttribute("Icon", icon)
		local old = chipIcons[name]
		if old then
			old:Destroy()
		end
		chipIcons[name] = PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(0, 1), 3)
	end
	if l:GetAttribute("Source") ~= words then
		l:SetAttribute("Source", words)
		UIKit.setText(l, words)
	end
	UIKit.setTextColor(l, color or UIKit.color("text"))
	layoutTop()
end

------------------------------------------------------------------ the menu bar
type Menu = { text: string, panel: string, icon: string }
local MENUS: { Menu } = {
	{ text = "Build", panel = "build", icon = "home" },
	{ text = "Driftlings", panel = "pals", icon = "pal" },
	{ text = "Index", panel = "index", icon = "star" },
	-- the My founder screen (UI/FounderUI, 2026-11-20: Random Bakery's customization screen)
	{ text = "Looks", panel = "looks", icon = "visitor" },
	-- the rewards for coming back and playing (UI/RewardsUI, 2026-11-19): a red dot while something waits
	{ text = "Gifts", panel = "rewards", icon = "gift" },
	-- the leaderboards and the friends (UI/TopUI, 2026-11-21: "Make a leaderboard system, along with friend invite
	-- bonuses")
	{ text = "Top@@board", panel = "top", icon = "trophy" },
	-- the store (GAME_DESIGN 14, 2026-11-14): passes, products, the rotating shop and the pass track
	{ text = "Store", panel = "store", icon = "store" },
	-- the settings (UI/SettingsUI, 2026-11-14: "Add a settings tab, replacing the music button"): music, sounds, pixel art
	{ text = "Settings", panel = "settings", icon = "gear" },
}
-- the Hatchery's button after Driftlings, once the island reaches the Hatchery's tier (the request of 2026-11-14:
-- "add a hatchery tab once it is unlocked too")
local HATCH_MENU: Menu = { text = "Hatchery", panel = "hatch", icon = "egg" }
local hatchShown = false
local function menus(): { Menu }
	if not hatchShown then
		return MENUS
	end
	local out = table.clone(MENUS)
	table.insert(out, 3, HATCH_MENU)
	return out
end
local MENU_ICON = 13 -- a menu button's icon (11 px and a gap) before its words
local giftDot: Frame? = nil
-- The desktop's shortcuts, one key a menu (letters clear of Roblox's own: W A S D, I and O for the zoom, Space, Tab,
-- the slash for chat), shown on the toolbar's key caps and in the tooltips; E opens the tree's panel.
local KEYS: { [string]: string } = { build = "B", pals = "P", hatch = "H", index = "N", looks = "L", rewards = "G", top = "T", store = "M", settings = "K", tree = "E" }
-- What each menu opens, a line in its tooltip (a desktop's on hover, a touch screen's on a held finger).
local MENU_TIPS: { [string]: string } = {
	build = "Place huts, work spots and decor.",
	pals = "Your driftlings: where they live and work.",
	hatch = "Pair two driftlings for an egg.",
	index = "Every kind you have found so far.",
	looks = "Change how your founder looks.",
	rewards = "Daily gifts, tasks, the spin and codes.",
	top = "Leaderboards and your friends.",
	store = "Passes, eggs and the shop.",
	settings = "Sound, view, text and language.",
	tree = "Hatch the eggs under the tree.",
}

local function openMenu(m: Menu)
	if m.panel == "build" then
		BuildUI.open()
	else
		UIKit.openPanel(m.panel)
	end
end
local function menuOf(panel: string): Menu?
	for _, m in menus() do
		if m.panel == panel then
			return m
		end
	end
	return nil
end
-- the red dot over the gift while something waits (RewardsUI.ready; Hud's second shows and hides it)
local function makeGiftDot(b: GuiObject, x: number)
	local dot = UIKit.rect(b, UDim2.fromOffset(5, 5), UDim2.fromOffset(x, 0), UIKit.inkOf(UIKit.color("bad")), 7)
	dot.Name = "Dot"
	UIKit.rect(dot, UDim2.fromOffset(3, 3), UDim2.fromOffset(1, 1), UIKit.color("bad"), 8)
	dot.Visible = false
	giftDot = dot
end

-- A touch screen's square: dark glass (UIKit's neutral button), the menu's big icon in the middle (UI/PixelSprites:
-- the 15 px `big_` set drawn for the touch screens, the 11 px one where none is drawn), centred in a cell `cw` wide;
-- on a tablet its name under it.
local function bigIcon(icon: string): (string, number)
	if PixelSprites.has("big_" .. icon) then
		return "big_" .. icon, 15
	end
	return "mini_" .. icon, 11
end
local function square(parent: Instance, m: Menu, x: number, y: number, cw: number): TextButton
	local n = sq()
	local b = UIKit.button(parent, "", UDim2.fromOffset(n, n), UDim2.fromOffset(x + math.floor((cw - n) / 2), y), function()
		openMenu(m)
	end, { name = "Menu_" .. m.panel, color = UIKit.color("glass") })
	local name, size = bigIcon(m.icon)
	PixelSprites.image(b, name, UDim2.fromOffset(math.floor((n - size) / 2), math.floor((n - size) / 2)), 6).Name = "Icon"
	if labelled() then
		UIKit.text(parent, m.text, UDim2.fromOffset(cw, LABEL_H), UDim2.fromOffset(x, y + n + 1), { x = "center", name = "Label_" .. m.panel, z = 3 })
	end
	-- (a held finger shows its name and what it opens: a phone's squares have no names under them)
	UIKit.tooltip(b, m.text, MENU_TIPS[m.panel])
	if m.panel == "rewards" then
		makeGiftDot(b, n - 6)
	end
	return b
end

-- The touch screen's menus: the left grid (two columns of squares under the top bar: Driftlings, the Hatchery once
-- it's open, Index, Looks, Top, Settings), the right row's Gifts and Store (`stack` sets it beside the Eggs square
-- under the island card) and Build, a big mint button by the jump button.
local LEFT_MENUS = { "pals", "hatch", "index", "looks", "top", "settings" }
local function buildSquares()
	local canvas = UIKit.canvas("Hud")
	local n = sq()
	cellW = n
	if labelled() then
		for _, id in LEFT_MENUS do
			local m = menuOf(id)
			if m then
				cellW = math.max(cellW, UIKit.textWidth(m.text) + 4)
			end
		end
		cellW = math.min(cellW, 60)
	end
	cellR = math.max(n, math.floor((CARD_W - 2 * GAP) / 3))
	local rh = n + (if labelled() then LABEL_H + 1 else 0)
	local list: { Menu } = {}
	for _, id in LEFT_MENUS do
		local m = menuOf(id)
		if m then
			table.insert(list, m)
		end
	end
	local rows = math.ceil(#list / 2)
	local f = Instance.new("Frame")
	f.Name = "MenuBar"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(2 * cellW + GAP, rows * rh + (rows - 1) * GAP)
	f.Parent = canvas
	for i, m in list do
		square(f, m, ((i - 1) % 2) * (cellW + GAP), ((i - 1) // 2) * (rh + GAP), cellW)
	end
	bar = f
	barW = 0
	local side = Instance.new("Frame")
	side.Name = "MenuSide"
	side.BackgroundTransparency = 1
	side.Size = UDim2.fromOffset(2 * cellR + GAP, rh)
	side.Parent = canvas
	local x = 0
	for _, id in { "rewards", "store" } do
		local m = menuOf(id)
		if m then
			square(side, m, x, 0, cellR)
			x += cellR + GAP
		end
	end
	menuSide = side
	local bm = menuOf("build")
	if bm then
		local bw = math.max(2 * n, UIKit.buttonWidth(bm.text, 5) + MENU_ICON + 3)
		local box = Instance.new("Frame")
		box.Name = "BuildBox"
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(bw, n)
		box.Parent = canvas
		local b = UIKit.button(box, bm.text, UDim2.fromOffset(bw, n), UDim2.new(), function()
			BuildUI.open()
		end, { name = "Menu_build", color = UIKit.color("button_ok") })
		b.ZIndex = 2
		local name, size = bigIcon(bm.icon)
		PixelSprites.image(b, name, UDim2.fromOffset(4, math.floor((n - size) / 2)), 6).Name = "Icon"
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(size + 5, 0)
			words.Size = UDim2.new(1, -(size + 7), 1, 0)
		end
		buildBox = box
		buildBtn = b
	end
end

local function buildBar()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	for _, f in { bar, menuSide, buildBox } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	bar, menuSide, buildBox, buildBtn, giftDot = nil, nil, nil, nil, nil
	if mobile() then
		buildSquares()
		return
	end
	-- A desktop's toolbar (the PC builders' row of named buttons along the bottom, GAME_DESIGN 2.1): each button its
	-- big icon and its name, its shortcut on a key cap at its top right corner, a tooltip with what it opens.
	local phone = UIKit.phone()
	local bh = barH()
	local ICON_W = 19
	local function widthOf(m: Menu): number
		return if phone then BTN_PHONE else UIKit.buttonWidth(m.text, 4) + ICON_W + 3
	end
	local total = 0
	for _, m in menus() do
		total += widthOf(m) + 2
	end
	total -= 2
	barW = total
	local f = Instance.new("Frame")
	f.Name = "MenuBar"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(total, bh)
	-- pinned to the canvas's bottom edge (not a measured y: it stays on screen while the canvas settles)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, math.floor((s.X - total) / 2), 1, -(DOCK + EDGE - 1))
	f.Parent = canvas
	-- one glass strip under the buttons (Random Bakery's bar): each button shows only its icon and words until the
	-- mouse is over it; Build's words in the accent
	local dock = UIKit.glass(f, UDim2.fromOffset(total + 2 * DOCK, bh + 2 * DOCK), UDim2.fromOffset(-DOCK, -DOCK), 2)
	dock.Name = "Dock"
	dock.ZIndex = 1
	local x = 0
	for _, m in menus() do
		local w = widthOf(m)
		local b = UIKit.button(f, if phone then "" else m.text, UDim2.fromOffset(w, bh), UDim2.fromOffset(x, 0), function()
			if m.panel == "build" then
				BuildUI.open()
			else
				UIKit.openPanel(m.panel)
			end
		end, {
			name = "Menu_" .. m.panel,
			ghost = true,
			textColor = if m.panel == "build" then UIKit.color("accent") else nil,
		})
		b.ZIndex = 2
		local icon, isz = bigIcon(m.icon)
		PixelSprites.image(b, icon, if phone then UDim2.fromOffset(math.floor((w - isz) / 2), math.floor((bh - isz) / 2)) else UDim2.fromOffset(3, math.floor((bh - isz) / 2)), 6).Name = "Icon"
		if m.panel == "rewards" then
			makeGiftDot(b, isz - 1)
		elseif m.panel == "build" then
			buildBtn = b
		end
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(ICON_W + 1, 0)
			words.Size = UDim2.new(1, -(ICON_W + 4), 1, 0)
		end
		local key = KEYS[m.panel]
		if key and not phone then
			UIKit.keyCap(b, key, UDim2.fromOffset(w - 8, -5), 7)
		end
		UIKit.tooltip(b, m.text, MENU_TIPS[m.panel], key)
		x += w + 2
	end
	bar = f
end

------------------------------------------------------------------ the island card
-- One line of a card: its 11 px icon, its label (quiet), its number on the right (white unless it says something).
local function line(parent: Instance, icon: string, text: string, y: number, w: number, color: Color3?, right: string?, rightColor: Color3?, name: string?)
	PixelSprites.image(parent, "mini_" .. icon, UDim2.fromOffset(PAD - 1, y), 4)
	UIKit.text(parent, text, UDim2.fromOffset(w - 2 * PAD - 13, 10), UDim2.fromOffset(PAD + 12, y + 1), { color = color or UIKit.color("text_dim"), z = 4, name = name })
	if right then
		UIKit.text(parent, right, UDim2.fromOffset(w - 2 * PAD - 13, 10), UDim2.fromOffset(PAD + 12, y + 1), { x = "right", color = rightColor or UIKit.color("text"), z = 4, name = if name then name .. "R" else nil })
	end
end

-- how many driftlings live in huts (the view holds every one of them, and only the pen's best)
local function housedOf(v: Types.ClientView): number
	local n = 0
	for _, x in v.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end

-- how many driftlings are at work (a job at a farm, camp or shop)
local function workingOf(v: Types.ClientView): number
	local n = 0
	for _, x in v.pals do
		if x.work ~= 0 then
			n += 1
		end
	end
	return n
end

local function cardKey(v: Types.ClientView): string
	return string.format("%d|%d/%d|%d/%d|%d|%d|%d", v.tier, housedOf(v), v.nests, workingOf(v), Island.jobPlaces(v.pieces), math.floor(v.charm), math.round((v.charmBonus or 0) * 100), math.floor(v.rates.shells + 0.5))
end

local restackCard: () -> () = function() end
local function updateCard(v: Types.ClientView)
	-- (a touch screen's card folds to its name and the coins a minute: a tap on it folds or opens it)
	local folded = cardFolded()
	local key = cardKey(v) .. (if folded then "|f" else "|o")
	if card and card:GetAttribute("Key") == key then
		return
	end
	if card then
		card:Destroy()
		card = nil
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local w = CARD_W
	local h = if folded then 15 + LINE_H + 2 else 15 + 4 * LINE_H + 4 + LINE_H + 2
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - EDGE, rightTop()), 2)
	f.Name = "IslandCard"
	local plan = Office.plans[v.tier]
	-- the island's name, a faint rule under it
	UIKit.plank(f, 11)
	UIKit.text(f, if plan then plan.name else "Your island", UDim2.fromOffset(w - 2 * PAD - 9, 10), UDim2.fromOffset(PAD, 2), { color = UIKit.color("accent"), kind = "shadow", z = 4, name = "Title" })
	-- (it folds on every screen, a docked panel as the PC builders' are: a click or tap on its title, or anywhere on it
	-- while folded)
	do
		PixelSprites.image(f, if folded then "arrow_down_t" else "arrow_up_t", UDim2.fromOffset(w - PAD - 7, 3), 5).Name = "Fold"
		local tap = UIKit.button(f, "", if folded then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 0, 13), UDim2.new(), function()
			cardOpen = folded
			local cv = StateClient.view()
			if cv then
				updateCard(cv)
				restackCard()
			end
		end, { name = "CardFold", ghost = true })
		tap.ZIndex = 6
	end
	local y = 15
	if folded then
		local n = v.rates.shells
		local c = if n < -0.05 then UIKit.color("bad") elseif n > 0.05 then UIKit.color("good") else UIKit.color("text_dim")
		line(f, "coin", "Coins", y, w, nil, Numbers.perMin(n * 60 / Tuning.TurnSeconds), c, "Rate_coin")
		f:SetAttribute("Key", key)
		f.Visible = not BuildUI.isOpen()
		card = f
		return
	end
	local housed = housedOf(v)
	line(f, "pal", "In huts", y, w, nil, string.format("%d/%d", housed, v.nests), if housed >= v.nests and v.nests > 0 then UIKit.color("orange") else nil, "Pals")
	y += LINE_H
	-- the driftlings at work out of the places at work (Island.jobPlaces; the requests of 2026-11-16, "can you make
	-- another detail to show creatures working, with x/y", and 2026-11-17, "for working, make it x/y, where x is
	-- amount of creatures working and y being the amount of work spaces available")
	line(f, "work", "Working", y, w, nil, string.format("%d/%d", workingOf(v), Island.jobPlaces(v.pieces)), nil, "Working")
	y += LINE_H
	line(f, "charm", "Charm", y, w, nil, Numbers.int(math.floor(v.charm)), UIKit.color("pink"), "Charm")
	y += LINE_H
	-- what the charm adds to every shell (Logic/Island.charmBonus: the visitors went on 2026-11-14)
	line(f, "coin", "Charm bonus", y, w, nil, string.format("+%d%%", math.round((v.charmBonus or 0) * 100)), UIKit.color("pink"), "CharmBonus")
	y += LINE_H
	-- a faint rule between the island and what it makes
	local rule = UIKit.rect(f, UDim2.fromOffset(w - 2 * PAD, 1), UDim2.fromOffset(PAD, y + 1), UIKit.color("rule"), 4)
	rule.BackgroundTransparency = 0.84
	y += 4
	local function rate(icon: string, n: number, label: string)
		local c = if n < -0.05 then UIKit.color("bad") elseif n > 0.05 then UIKit.color("good") else UIKit.color("text_dim")
		line(f, icon, label, y, w, nil, Numbers.perMin(n * 60 / Tuning.TurnSeconds), c, "Rate_" .. icon)
		y += LINE_H
	end
	rate("coin", v.rates.shells, "Coins")
	f:SetAttribute("Key", key)
	f.Visible = not BuildUI.isOpen()
	card = f
end

------------------------------------------------------------------ the tree's card
-- Under the island card (GAME_DESIGN 6): the Tree of Life's name and Open (its panel), how long till it lays its next
-- eggs (a bar running down: Heartbeat runs it on from StateClient.clutchLeft), then its best few eggs (EggView.best:
-- the rarest, and one the shells cover if none of those is): each one's egg, its rarity's name in its colour and its
-- price (green when the shells are there). The eggs are bought in the tree's panel only, so a tap anywhere on the card
-- opens it (the request of 2026-11-13: "the eggs should be buyable only after the player clicks on the tree or enters
-- the tree menu"). On a phone no egg rows at all (2026-11-14): the name, Open and the time to the next eggs.
local TREE_ROW = 15
local treeBar: Frame? = nil
local treeTime: TextLabel? = nil
local function clock(secs: number): string
	local s = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", s // 60, s % 60)
end
-- A touch screen's Eggs square: the tree's big icon over a bar running down to the next eggs, the time under it; a tap
-- opens the tree's panel. (The egg rows went from phones on 2026-11-14: "for mobile, remove the egg list in the tree
-- tab".)
local function treeSquare()
	local key = sq() * 1000 + cellR -- (its size: made again when the screen changes)
	if treeCard and treeCard:GetAttribute("Key") == key then
		return
	end
	if treeCard then
		treeCard:Destroy()
		treeCard = nil
	end
	local n = sq()
	local f = Instance.new("Frame")
	f.Name = "TreeCard"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(cellR, n + LABEL_H + 1)
	f.Parent = UIKit.canvas("Hud")
	local b = UIKit.button(f, "", UDim2.fromOffset(n, n), UDim2.fromOffset(math.floor((cellR - n) / 2), 0), function()
		UIKit.openPanel("tree")
	end, { name = "TreeOpen", color = UIKit.color("glass") })
	local name, size = bigIcon("tree")
	PixelSprites.image(b, name, UDim2.fromOffset(math.floor((n - size) / 2), math.floor((n - size - 4) / 2)), 6).Name = "Icon"
	local back = UIKit.rect(b, UDim2.fromOffset(n - 8, 3), UDim2.fromOffset(4, n - 5), UIKit.color("glass"), 6)
	back.BackgroundTransparency = 0.1
	back.Name = "TreeBar"
	treeBar = UIKit.rect(back, UDim2.fromOffset(n - 10, 1), UDim2.fromOffset(1, 1), UIKit.color("good"), 7)
	UIKit.tooltip(b, "Eggs", MENU_TIPS.tree)
	local t = UIKit.text(f, "", UDim2.fromOffset(cellR, LABEL_H), UDim2.fromOffset(0, n + 1), { x = "center", raw = true, color = UIKit.color("text"), z = 3, name = "TreeNext" })
	t:SetAttribute("Short", true)
	treeTime = t
	f:SetAttribute("Key", key)
	treeCard = f
end

local function updateTree(v: Types.ClientView)
	if mobile() then
		treeSquare()
		return
	end
	-- (on a phone no egg rows: just the card's name, Open and the time to the next eggs; the request of 2026-11-14:
	-- "for mobile, remove the egg list in the tree tab")
	local phone = UIKit.phone()
	local shown: { Types.Laid } = if phone then {} else EggView.best(v, 3)
	local parts: { string } = {}
	for _, e in shown do
		table.insert(parts, string.format("%d:%d:%s", e.id, e.cost or 0, if v.shells >= (e.cost or 0) then "y" else "n"))
	end
	local key = table.concat(parts, ",") .. ":" .. #v.clutch
	if treeCard and treeCard:GetAttribute("Key") == key then
		return
	end
	if treeCard then
		treeCard:Destroy()
		treeCard = nil
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local w = CARD_W
	local rows = if phone then 0 else math.max(1, #shown)
	local h = 27 + rows * TREE_ROW + (if phone then 4 else 1)
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - EDGE, rightTop()), 2)
	f.Name = "TreeCard"
	UIKit.plank(f, 11)
	PixelSprites.image(f, "mini_tree", UDim2.fromOffset(PAD - 1, 1), 4)
	UIKit.text(f, if UIKit.phone() then "Eggs" else "Tree of Life", UDim2.fromOffset(w - 56, 10), UDim2.fromOffset(PAD + 12, 2), { color = UIKit.color("accent"), kind = "shadow", z = 4, name = "Title" })
	UIKit.button(f, "Open", UDim2.fromOffset(30, 10), UDim2.fromOffset(w - 30 - PAD + 1, 1), function()
		UIKit.openPanel("tree")
	end, { name = "TreeOpen", color = UIKit.color("button_ok") }).ZIndex = 5
	-- (how long till the next eggs: the time and a bar running down)
	treeTime = UIKit.text(f, "New eggs in 0:00", UDim2.fromOffset(w - 2 * PAD, 10), UDim2.fromOffset(PAD, 15), { color = UIKit.color("text_dim"), z = 4, name = "TreeNext" })
	local back = UIKit.rect(f, UDim2.fromOffset(w - 2 * PAD, 3), UDim2.fromOffset(PAD, 25), UIKit.color("glass"), 4)
	back.BackgroundTransparency = 0.2
	back.Name = "TreeBar"
	treeBar = UIKit.rect(back, UDim2.fromOffset(w - 2 * PAD - 2, 1), UDim2.fromOffset(1, 1), UIKit.color("good"), 5)
	if #shown == 0 and not phone then
		UIKit.text(f, "No eggs right now", UDim2.fromOffset(w - 2 * PAD, 10), UDim2.fromOffset(PAD, 30), { color = UIKit.color("text_dim"), z = 4 })
	end
	for i, e in shown do
		local rar = Traits.RARITY[e.r] or Traits.RARITY[1]
		local y = 29 + (i - 1) * TREE_ROW
		local cost = e.cost or 0
		local text = Numbers.coins(cost)
		local bw = math.max(34, UIKit.textWidth(text) + 18)
		-- (the small egg, 9 x 11, in line with the name: the big one is taller than a row. The request of 2026-11-14:
		-- "the egg icons seem to overlap each other and the bottom one exceeds the border. could you make egg sprite
		-- icons smaller?")
		PixelSprites.image(f, "mini_egg_" .. math.clamp(e.r, 1, Traits.RMAX), UDim2.fromOffset(PAD, y + 1), 4).Name = "EggIcon_" .. e.id
		UIKit.text(f, rar.name, UDim2.fromOffset(w - bw - 21, 10), UDim2.fromOffset(PAD + 12, y + 2), { color = UIKit.color(rar.color), z = 4, name = "EggName_" .. e.id })
		local can = v.shells >= cost
		local price = UIKit.text(f, text, UDim2.fromOffset(bw - 14, 10), UDim2.fromOffset(w - bw - PAD + 1, y + 2), { x = "right", color = if can then UIKit.color("good") else UIKit.color("text_dim"), z = 4, name = "CardPrice_" .. e.id })
		PixelSprites.image(price, "mini_coin", UDim2.new(1, 2, 0, 0), 5).Name = "PriceIcon"
	end
	-- (the whole card under the title opens the panel: the eggs are bought there)
	local tap = Instance.new("TextButton")
	tap.Name = "TreeCardTap"
	tap.Text = ""
	tap.AutoButtonColor = true -- (an enabled button: see-through, so the press shows nothing)
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.new(1, 0, 1, -12)
	tap.Position = UDim2.fromOffset(0, 12)
	tap.ZIndex = 6
	tap.Parent = f
	tap.Activated:Connect(function()
		Audio.play("click")
		UIKit.openPanel("tree")
	end)
	f:SetAttribute("Key", key)
	treeCard = f
end

-- The cards stack down the right edge, GAP apart (on a phone the tree's card sits on the left, clear of the jump
-- button); down the left, the status panel and the quest's card under it.
local offers: Frame? = nil -- the store's offers (UI/StoreUI.offers: the Starter Pack, VIP's gift)

-- A touch screen's blocks: the grid of squares down the left under the top bar; the island card at the top right, the
-- row of squares under it (Eggs, Gifts, Store) and the offers under that, slid left of the jump button when they would
-- reach it; Build beside the jump button, level with it; the status panel and the quest's card right of the grid (or
-- under everything on a screen too narrow for that). Nothing goes in the bottom left, where the thumbstick is.
local function stackTouch()
	local s = UIKit.size("Hud")
	local hide = BuildUI.isOpen() or UIKit.currentPanel() ~= nil
	local gridR, gridB = EDGE, CARD_Y
	local b = bar
	if b then
		b.Visible = not hide
		b.Position = UDim2.fromOffset(EDGE, CARD_Y)
		gridR, gridB = EDGE + b.Size.X.Offset, CARD_Y + b.Size.Y.Offset
	end
	local colX = s.X - CARD_W - EDGE
	local y = rightTop()
	local c = card
	if c then
		c.Visible = not hide
		c.Position = UDim2.fromOffset(colX, y)
		y += c.Size.Y.Offset + GAP
	end
	local e, side = treeCard, menuSide
	local x = colX
	local rowB = y
	if e then
		e.Visible = not hide
		e.Position = UDim2.fromOffset(x, y)
		x += cellR + GAP
		rowB = math.max(rowB, y + e.Size.Y.Offset)
	end
	if side then
		side.Visible = not hide
		side.Position = UDim2.fromOffset(x, y)
		rowB = math.max(rowB, y + side.Size.Y.Offset)
	end
	local colB = rowB
	local jx0, jy0, _, jy1 = jumpRect()
	local of = offers
	if of then
		of.Visible = not hide
		local oy = rowB + GAP
		local ox = colX
		if oy + of.Size.Y.Offset > jy0 - GAP and colX + CARD_W > jx0 then
			ox = math.floor(jx0) - GAP - CARD_W
		end
		of.Position = UDim2.fromOffset(ox, oy)
		colB = oy + of.Size.Y.Offset
	end
	local bb = buildBox
	if bb then
		bb.Visible = not hide
		bb.Position = UDim2.fromOffset(math.floor(jx0) - GAP - bb.Size.X.Offset, math.floor((jy0 + jy1 - bb.Size.Y.Offset) / 2))
	end
	local lx, ly = gridR + GAP, CARD_Y
	if lx + STATUS_W > colX - GAP then
		lx, ly = EDGE, math.max(gridB, colB) + GAP
	end
	local st = status
	if st then
		layoutStatus()
		st.Position = UDim2.fromOffset(lx, ly)
		if st.Visible then
			st.Visible = not hide
			ly += st.Size.Y.Offset + GAP
		end
	end
	local qf = quest
	if qf then
		qf.Visible = not hide
		qf.Position = UDim2.fromOffset(lx, ly)
	end
end

local function stack()
	if mobile() then
		stackTouch()
		return
	end
	local s = UIKit.size("Hud")
	local c, e = card, treeCard
	-- (they step aside for Build mode and for any panel: the panel's glass would show them through it)
	local hide = BuildUI.isOpen() or UIKit.currentPanel() ~= nil
	local top = rightTop()
	if c then
		c.Visible = not hide
		c.Position = UDim2.fromOffset(s.X - CARD_W - EDGE, top)
	end
	local leftY = CARD_Y
	local st = status
	if st then
		layoutStatus()
		st.Position = UDim2.fromOffset(EDGE, leftY)
		if st.Visible then
			st.Visible = not (BuildUI.isOpen() or UIKit.currentPanel() ~= nil)
			leftY += st.Size.Y.Offset + GAP
		end
	end
	if e then
		e.Visible = not hide
		if UIKit.phone() then
			e.Position = UDim2.fromOffset(EDGE, leftY)
		else
			local y = if c then c.Position.Y.Offset + c.Size.Y.Offset + GAP else top
			e.Position = UDim2.fromOffset(s.X - CARD_W - EDGE, y)
		end
	end
	-- the store's offers under the right-hand column (the island card, and the tree's card on a desktop)
	local of = offers
	if of then
		of.Visible = not hide
		local y = if c then c.Position.Y.Offset + c.Size.Y.Offset + GAP else top
		if not UIKit.phone() and e and e.Visible then
			y = e.Position.Y.Offset + e.Size.Y.Offset + GAP
		end
		of.Position = UDim2.fromOffset(s.X - CARD_W - EDGE, y)
	end
	-- the quest's card down the left (under the tree's card on a phone); it steps aside for a panel
	local qf = quest
	if qf then
		qf.Visible = not (BuildUI.isOpen() or UIKit.currentPanel() ~= nil)
		local y = leftY
		if UIKit.phone() and e and e.Visible then
			y = e.Position.Y.Offset + e.Size.Y.Offset + GAP
		end
		qf.Position = UDim2.fromOffset(EDGE, y)
	end
end
-- (a status line came or went: the quest's card slides to its new place, taking over from its own slide in)
restack = function()
	local qf = quest
	local from = if qf then qf.Position else nil
	stack()
	if qf and from and qf.Parent then
		local to = qf.Position
		qf.Position = from
		UIKit.tween(qf, 0.18, { Position = to })
	end
end
restackSoon = function()
	stack()
	hudRects()
end
restackCard = restackSoon

------------------------------------------------------------------ the questline
-- Where a quest's Go takes the player (Data/Quests' `go`): a panel (the tree's too) or Build mode on a tab.
local function goTo(where: string)
	if string.sub(where, 1, 5) == "build" then
		BuildUI.open(string.match(where, "^build:(%a+)$"))
	else
		UIKit.openPanel(where)
	end
end

local function claimQuest()
	task.spawn(function()
		local res = StateClient.request("quest.claim", {})
		if res.ok and type(res.data) == "table" then
			local d = res.data :: { [string]: any }
			local parts: { string } = {}
			for _, it in { { "shells", "coins" } } do
				local n = tonumber(d[it[1]]) or 0
				if n > 0 then
					table.insert(parts, string.format("+%s %s", Numbers.coins(n), it[2]))
				end
			end
			Audio.play("reward")
			AvatarView.cheer()
			UIKit.notice("Quest done. " .. table.concat(parts, ", "), UIKit.color("good"), 3)
		else
			Audio.play("deny")
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		end
	end)
end

-- The questline's card (GAME_DESIGN 9): the quest on the go once the tips are over, its icon and title and which of
-- them it is, what to do and where, then its progress and Go (to the place it needs), or once done its reward and
-- Claim (shining).
local function updateQuest(v: Types.ClientView)
	local q, i = Quest.current(v.tut, v.quest or 1)
	local have, need = 0, 0
	if q then
		local facts: Quest.Facts = { pals = v.pals, pieces = v.pieces, tier = v.tier, seen = v.seen, stats = v.stats }
		have, need = Quest.progress(facts, q)
	end
	-- (a touch screen's card folds away to its title and progress at a tap on its title; a quest done always shows
	-- its Claim)
	local done = have >= need
	local folded = not questOpen and not done
	local key = if q then string.format("%s:%d:%d:%s:%d", q.id, have, need, if folded then "f" else "o", QUEST_W) else ""
	local was = quest
	local same = was ~= nil and q ~= nil and string.split(tostring(was:GetAttribute("Key") or ""), ":")[1] == q.id
	if quest and quest:GetAttribute("Key") == key then
		return
	end
	if quest then
		quest:Destroy()
		quest = nil
	end
	if q == nil then
		return
	end
	local canvas = UIKit.canvas("Hud")
	local w = QUEST_W
	local textW = w - 10
	-- (up to four lines: "Three at work" says what three need, beds and work buildings)
	local lines = math.clamp(math.ceil(UIKit.textWidth(q.text) / textW), 1, 4)
	-- (a title too long for its line wraps onto a second one rather than run under the count: "Discover 12 unique
	-- creatures", 2026-11-14)
	local titleW = w - 44 - (if not done then 9 else 0)
	local tl = if folded then 1 else math.clamp(UIKit.lines(q.title, titleW), 1, 2)
	local dy = (tl - 1) * 10
	local h = if folded then 14 else 16 + lines * 10 + 16 + dy
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(EDGE, CARD_Y), 2)
	f.Name = "Quest"
	f:SetAttribute("Key", key)
	if not done then
		PixelSprites.image(f, if folded then "arrow_down_t" else "arrow_up_t", UDim2.fromOffset(w - 10, 3), 5).Name = "Fold"
		local tap = UIKit.button(f, "", UDim2.new(1, 0, 0, 13), UDim2.new(), function()
			questOpen = folded
			local cv = StateClient.view()
			if cv then
				updateQuest(cv)
			end
		end, { name = "QuestFold", ghost = true })
		tap.ZIndex = 6
	end
	if folded then
		PixelSprites.image(f, "mini_" .. q.icon, UDim2.fromOffset(3, 2), 3)
		UIKit.text(f, q.title, UDim2.fromOffset(w - 50, 10), UDim2.fromOffset(16, 2), { color = UIKit.color("accent"), name = "Title", z = 3 })
		UIKit.text(f, string.format("%d/%d", have, need), UDim2.fromOffset(28, 10), UDim2.fromOffset(w - 42, 2), { x = "right", color = UIKit.color("text_dim"), name = "Progress", z = 3 })
		quest = f
		stack()
		return
	end
	PixelSprites.image(f, "mini_" .. q.icon, UDim2.fromOffset(3, 2), 3)
	UIKit.text(f, q.title, UDim2.fromOffset(titleW, tl * 10), UDim2.fromOffset(16, 2), { color = UIKit.color("accent"), name = "Title", z = 3, wrap = tl > 1, y = "top" })
	local which = string.format("%d/%d", i, #Quests.list)
	UIKit.text(f, which, UDim2.fromOffset(26, 10), UDim2.fromOffset(w - 30 - (if not done then 9 else 0), 2), { x = "right", color = UIKit.color("text_dim"), name = "Which", z = 3 })
	UIKit.text(f, q.text, UDim2.fromOffset(textW, lines * 10), UDim2.fromOffset(5, 14 + dy), { color = UIKit.color("text"), wrap = lines > 1, name = "Words", z = 3 })
	local y = 15 + lines * 10 + 1 + dy
	if done then
		-- its reward, and Claim
		local x = 5
		for _, it in { { "shells", "coin" } } do
			local n = (q.reward :: { [string]: number? })[it[1]] or 0
			if n > 0 then
				PixelSprites.image(f, "mini_" .. it[2], UDim2.fromOffset(x, y), 3)
				local t = Numbers.coins(n)
				UIKit.text(f, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 12, y + 1), { color = UIKit.color("text"), name = "Reward_" .. it[1], z = 3 })
				x += 16 + UIKit.textWidth(t)
			end
		end
		local b = UIKit.button(f, "Claim", UDim2.fromOffset(40, 12), UDim2.fromOffset(w - 44, y), claimQuest, { name = "QuestClaim", color = UIKit.color("button_ok") })
		b.ZIndex = 4
		task.delay(0.3, function()
			if b.Parent then
				UIKit.shine(b)
			end
		end)
	else
		-- how far, and Go
		local bw = w - 10 - 44 - 32
		local back = UIKit.rect(f, UDim2.fromOffset(bw, 4), UDim2.fromOffset(5, y + 4), UIKit.color("glass"), 3)
		back.BackgroundTransparency = 0.2
		back.Name = "Bar"
		UIKit.rect(back, UDim2.fromOffset(math.floor((bw - 2) * have / math.max(1, need)), 2), UDim2.fromOffset(1, 1), UIKit.color("good"), 4).Name = "Fill"
		UIKit.text(f, string.format("%d/%d", have, need), UDim2.fromOffset(30, 10), UDim2.fromOffset(5 + bw + 3, y + 1), { color = UIKit.color("text_dim"), name = "Progress", z = 3 })
		local b = UIKit.button(f, "Go", UDim2.fromOffset(40, 12), UDim2.fromOffset(w - 44, y), function()
			goTo(q.go)
		end, { name = "QuestGo" })
		b.ZIndex = 4
	end
	quest = f
	-- a new quest slides in from the left (one only folded or opened stays put)
	f.Position = UDim2.fromOffset(-w - 8, CARD_Y)
	stack()
	if same then
		return
	end
	local to = f.Position
	f.Position = UDim2.fromOffset(-w - 8, to.Y.Offset)
	UIKit.tween(f, 0.22, { Position = to })
end

------------------------------------------------------------------ tips
-- (the request of 2026-11-21: "Guide the player to put down a hut "Make a place for your driftlings to live in!" >
-- Guide the player to hatch a driftling: "You got your first driftling! Now, put down a work space for it to earn coins
-- in. > Guide the player to put down a workspace, the best one > "Great! You can hatch more driftlings from the tree,
-- which refreshes with eggs every few minutes."": the user's own words. While a tip asks for something built and Build
-- mode is shut, the menu bar's Build button pulses yellow)
local TIPS: { [number]: string } = {
	[Plot.TIP_HUT] = "Make a place for your driftlings to live in!",
	[Plot.TIP_HATCH] = "There are new eggs under the tree! Tap it to hatch one.",
	[Plot.TIP_WORK] = "You got your first driftling! Now, put down a work space for it to earn coins in.",
	[Plot.TIP_LAST] = "Great! You can hatch more driftlings from the tree, which refreshes with eggs every few minutes.",
}
-- in Build mode (the tray already on the right tab, the building pulsing): the same words but for these
local TIPS_BUILD: { [number]: string } = {}

-- The tip's banner sits over the menu bar, or over the build tray in Build mode (the tips show there too), above the
-- Free Decor tab on the tray's corner while that shows (a phone held upright: the tip runs that far across)
local function tipsLift(): number
	if BuildUI.isOpen() then
		local v = StateClient.view()
		local chip = v ~= nil and not (v.passes and v.passes.FreeDecor)
		return BuildUI.trayHeight() + (if chip then 18 else 12)
	end
	-- (a touch screen has no menu bar along the bottom: the note sits on the bottom edge)
	if mobile() then
		return EDGE + 2
	end
	return barH() + 2 * DOCK + EDGE + 4
end
-- A touch screen's note keeps left of Build and the jump button: centred on the screen when it fits, else pushed left.
local function tipsRoom(): number
	local jx0 = jumpRect()
	local bb = buildBox
	return math.floor(jx0) - GAP - (if bb then bb.Size.X.Offset + GAP else 0)
end

local function updateTips(v: Types.ClientView)
	local text = (if BuildUI.isOpen() then TIPS_BUILD[v.tut] else nil) or TIPS[v.tut]
	if tips then
		local words = tips:FindFirstChild("Words")
		if text and words and words:IsA("TextLabel") and words:GetAttribute("Source") == text then
			return
		end
		tips:Destroy()
		tips = nil
	end
	if text == nil then
		return
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local ok = v.tut == Plot.TIP_LAST
	-- a glass note; on a phone held sideways it keeps to the room left of the island card, which runs down the right
	-- side there, so it never covers the card; on one held upright the card sits at the top, and the note takes the
	-- width up to the jump button (it had the room left of the card there too, 59 px, and cut its words off after two
	-- lines: "Shells pay / for..."). As many lines as its words need
	local portrait = UIKit.phone() and s.Y > s.X
	local touch = mobile() and not BuildUI.isOpen()
	local right = if touch then tipsRoom() else s.X
	local room = if touch then right - EDGE elseif portrait then s.X - 64 elseif UIKit.phone() then s.X - CARD_W - 24 else s.X - 20
	local want = UIKit.textWidth(text) + (if ok then 40 else 12)
	local w = math.min(want, room)
	local lines = math.max(1, UIKit.lines(text, w - (if ok then 36 else 2 * PAD)))
	local h = 5 + 10 * lines
	local left = if touch then (if math.floor((s.X + w) / 2) <= right then math.floor((s.X - w) / 2) else math.max(EDGE, right - w))
		elseif portrait then 10
		elseif UIKit.phone() then math.floor((s.X - CARD_W - 12 - w) / 2)
		else math.floor((s.X - w) / 2)
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.new(0, left, 1, -tipsLift()), 2)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Name = "Tips"
	local l = UIKit.text(f, text, UDim2.new(1, if ok then -36 else -(2 * PAD), 1, 0), UDim2.fromOffset(PAD + 1, 0), { color = UIKit.color("text"), name = "Words", wrap = lines > 1 })
	l:SetAttribute("Source", text)
	if ok then
		UIKit.button(f, "OK", UDim2.fromOffset(24, 10), UDim2.new(1, -27, 0, 2), function()
			StateClient.request("tut.next", {})
		end, { name = "TipsOk" })
	end
	tips = f
	-- a new tip bounces in (the Heartbeat keeps it on the tray once it has)
	f.Position = UDim2.new(0, left, 1, -(tipsLift() - 4))
	f:SetAttribute("Settled", os.clock() + 0.2)
	UIKit.tween(f, 0.18, { Position = UDim2.new(0, left, 1, -tipsLift()) })
end

------------------------------------------------------------------ a new day
-- A banner drops in at the top: the day, or a Hatchery egg ready. Under a panel or in Build mode: a notice.
-- A new calendar day ("Day 12": every few hours) or a turn's news (a Hatchery's egg ready to hatch).
local function onDay(msg: { [string]: any })
	local isDay = msg.kind == "day"
	local day = tonumber(msg.day) or 0
	local lines: { string } = {}
	-- a Hatchery's egg ready (Logic/Breed.turn): a tap on the Hatchery hatches it (the request of 2026-11-20)
	local hatched = 0
	if type(msg.ready) == "table" then
		for _, x in msg.ready do
			if type(x) == "table" and type(x.sp) == "string" and Creatures.byId[x.sp] then
				hatched += 1
			end
		end
	end
	if hatched > 0 then
		table.insert(lines, if hatched == 1 then "Tap the Hatchery to hatch it." else "Tap the Hatcheries to hatch them.")
	end
	if not isDay and hatched == 0 then
		return
	end
	local title = if isDay then "Day " .. day elseif hatched == 1 then "An egg is ready" else "Eggs are ready"
	-- (an egg ready the friend's chimes, a plain new day a small ding)
	Audio.play(if hatched > 0 then "friend" else "ding")
	if isDay then
		chipBump.day = os.clock()
	end
	if UIKit.currentPanel() ~= nil or BuildUI.isOpen() then
		UIKit.notice(title .. (if #lines > 0 then ": " .. table.concat(lines, ", ") else ""), UIKit.color("accent"), 4)
		return
	end
	if banner then
		banner:Destroy()
		banner = nil
	end
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	-- (wide enough for the title in the big font after the icon, and for each line: the title went unmeasured and
	-- "An egg hatched!" (142 px) showed as "An egg hat...", the request of 2026-11-19: "it seems like the text gets cut
	-- off for some alerts")
	local w = math.max(140, UIKit.textWidth(title, "big") + 28)
	for _, l in lines do
		w = math.max(w, UIKit.textWidth(l) + 16)
	end
	w = math.min(w, s.X - 16)
	local h = 22 + #lines * 10
	local x = math.floor((s.X - w) / 2)
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, -h - 10), 2)
	f.Name = "DayBanner"
	f.ZIndex = 8
	PixelSprites.image(f, if isDay then "mini_sun" else "mini_egg", UDim2.fromOffset(6, 6), 9)
	UIKit.text(f, title, UDim2.fromOffset(w - 24, 16), UDim2.fromOffset(20, 3), { face = "big", kind = "title", color = UIKit.color("accent"), z = 9, name = "Day" })
	for i, l in lines do
		UIKit.text(f, l, UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 10 + i * 10), { color = UIKit.color("good"), z = 9, name = "Line" .. i })
	end
	banner = f
	UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, 30) })
	-- (the notices make way below it while it shows: they share the top of the screen)
	UIKit.setNoticeTop(30 + h + 6)
	if #lines > 0 then
		task.delay(0.3, function()
			if f.Parent then
				UIKit.burst(f, math.floor(w / 2), 10, { "accent", "good", "white" }, 14, 40)
			end
		end)
	end
	task.delay(2.6 + #lines * 0.5, function()
		-- (the notices' spot given back even when the banner went with its canvas: a rebuild of the HUD)
		if banner == f then
			UIKit.setNoticeTop(nil)
		end
		if f.Parent then
			UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, -h - 10) })
			task.wait(0.3)
			f:Destroy()
		end
		if banner == f then
			banner = nil
		end
	end)
end

------------------------------------------------------------------ lifecycle
-- A new lot of eggs under the tree (Fx "eggs"): a short notice, a chime, and if an epic or legendary egg is among them
-- it's named (its rarity's colour, a burst on the tree's card). An egg turned for the quest on the go (`turned`,
-- Logic/Tree.ensure) is named the same way.
local function onEggs(msg: { [string]: any })
	if type(msg.laid) ~= "table" then
		return
	end
	local turned = tonumber(msg.turned)
	if turned and Traits.RARITY[turned] then
		local rar = Traits.RARITY[turned]
		UIKit.notice(Lang.an("An {1} egg waits at the tree.", "A {1} egg waits at the tree.", rar.name), UIKit.color(rar.color), 5)
		Audio.play("grow")
		local tc = treeCard
		if tc and tc.Parent and tc.Visible then
			UIKit.burstOn(tc, { rar.color, "accent", "white" }, 18, 40)
		end
		return
	end
	local best = 1
	for _, x in msg.laid do
		if type(x) == "table" and type(x.r) == "number" then
			best = math.max(best, x.r)
		end
	end
	if best >= 4 then
		local rar = Traits.RARITY[best] or Traits.RARITY[1]
		-- ("An" before an epic, an ancient or an eternal egg; whole sentences, so a language has its own words round the
		-- rarity: Locale/Lang.an)
		UIKit.notice(Lang.an("An {1} egg waits at the tree.", "A {1} egg waits at the tree.", rar.name), UIKit.color(rar.color), 5)
		Audio.play("grow")
		local tc = treeCard
		if tc and tc.Parent and tc.Visible then
			UIKit.burstOn(tc, { rar.color, "accent", "white" }, 18, 40)
		end
	else
		-- (new eggs, a fresh lot or the extra ones an expansion brings: the same words either way, the request of
		-- 2026-11-21: "For all mentions of the tree "laying" eggs, just say "There are new eggs under the tree!"")
		UIKit.notice("There are new eggs under the tree!", UIKit.color("good"), 3)
		Audio.play("rare")
	end
end

local offerKey: string? = nil
local function updateOffers(v: Types.ClientView)
	local key = StoreUI.offerKey(v)
	if key == offerKey and (offers == nil or (offers :: Frame).Parent ~= nil) then
		return
	end
	offerKey = key
	if offers then
		(offers :: Frame):Destroy()
	end
	offers = StoreUI.offers(UIKit.canvas("Hud"), v, CARD_W)
end

local function refresh(v: Types.ClientView)
	updateTop(v)
	local hatch = Buildings.byId.hatchery
	local want = hatch ~= nil and v.tier >= hatch.tier
	if want ~= hatchShown then
		hatchShown = want
		buildBar()
	end
	updateCard(v)
	updateTree(v)
	updateOffers(v)
	stack()
	updateTips(v)
	updateQuest(v)
	local key = string.format("%d", v.tier)
	if key ~= lastKey then
		lastKey = key
		hudRects()
	end
	if UIKit.currentPanel() ~= nil then
		UIKit.refreshPanel()
	end
end

local function rebuild()
	for _, f in chipFrames do
		f:Destroy()
	end
	table.clear(chips)
	table.clear(chipFrames)
	table.clear(chipIcons)
	table.clear(last)
	for _, f in { card, treeCard, tips, quest, homeButton, visitButton, topBar, offers } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	offers, offerKey = nil, nil
	card, treeCard, tips, quest, homeButton, visitButton, topBar, plusButton = nil, nil, nil, nil, nil, nil, nil, nil
	treeBar, treeTime = nil, nil
	CARD_W = if UIKit.phone() then 104 else 116
	-- (a phone's left column narrower: right of the grid of squares it keeps clear of the founder in the middle)
	QUEST_W = if mobile() and UIKit.phone() then 136 else 150
	STATUS_W = QUEST_W
	buildTop()
	for name, said in chipSaid do
		Hud.topChip(name, said.icon, said.text, said.color)
	end
	-- the status panel keeps its lines across a rebuild (they come from other modules)
	if status == nil then
		local st = UIKit.glass(UIKit.canvas("Hud"), UDim2.fromOffset(QUEST_W, 4), UDim2.fromOffset(EDGE, CARD_Y), 2)
		st.Name = "Status"
		st.Visible = false
		status = st
	end
	buildBar()
	local v = StateClient.view()
	if v then
		lastKey = ""
		refresh(v)
	end
	hudRects()
end

function Hud.start()
	-- (each window shows its desktop shortcut, the key that shuts it again)
	UIKit.setPanelKeys(KEYS)
	Menus.init()
	StoreUI.init()
	FounderUI.init()
	RewardsUI.init()
	TopUI.init()
	SettingsUI.init()
	VisitUI.init()
	WelcomeUI.init()
	rebuild()
	StateClient.Changed:Connect(refresh)
	-- the stores every second: the chips count, shells coming in rise from their chip ("+12") at most every 2 s
	local popShells: number? = nil
	local gained, popAt = 0, 0
	StateClient.Tick:Connect(function(v: Types.ClientView)
		if popShells ~= nil and v.shells > (popShells :: number) then
			gained += v.shells - (popShells :: number)
		end
		popShells = v.shells
		updateTop(v)
		local now = os.clock()
		local cf = chipFrames.shells
		if gained >= 1 and now - popAt >= 2 and cf and cf.Parent then
			popAt = now
			UIKit.popText(UIKit.canvas("Hud"), cf.Position.X.Offset + cf.Size.X.Offset / 2, CHIP_Y + TOP_H + 4, "+" .. Numbers.coins(gained), UIKit.color("accent"))
			gained = 0
		end
	end)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "day" or msg.kind == "turn" then
			onDay(msg)
		elseif msg.kind == "eggs" then
			onEggs(msg)
		end
	end)
	UIKit.Resized:Connect(function()
		rebuild()
	end)
	-- the desktop's shortcuts (KEYS, on the toolbar's key caps): a menu's key opens it, or shuts it when it's the one
	-- open; never while typing (the chat, a code), in Build mode (its own keys), during a hatch or on a touch screen
	UserInputService.InputBegan:Connect(function(input: InputObject, done: boolean)
		if done or input.UserInputType ~= Enum.UserInputType.Keyboard or UIKit.touch() or BuildUI.isOpen() or HatchScene.isOpen() then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		for panel, key in KEYS do
			if input.KeyCode == (Enum.KeyCode :: any)[key] then
				if panel == "hatch" and not hatchShown then
					return
				end
				Audio.play("click")
				if panel == "build" then
					UIKit.closePanel()
					BuildUI.open()
				elseif UIKit.currentPanel() == panel then
					UIKit.closePanel()
				else
					UIKit.openPanel(panel)
				end
				return
			end
		end
	end)
	-- Build mode has its own tray: the menu bar and the cards step aside; the tips stay (lifted over the tray)
	local function aside()
		local b = bar
		if b then
			b.Visible = not BuildUI.isOpen()
		end
		local v = StateClient.view()
		if v then
			updateTips(v)
		end
		local t = tips
		if t then
			t.Position = UDim2.new(t.Position.X.Scale, t.Position.X.Offset, 1, -tipsLift())
		end
		stack()
	end
	BuildUI.Changed:Connect(aside)
	UIKit.PanelChanged:Connect(function()
		stack()
	end)
	local lastBeat = os.clock()
	local rewardsAt = 0
	local nextBuildShine = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - lastBeat)
		lastBeat = now
		stepEases(dt)
		-- the calendar day creeps along between the server's ticks (no night: "remove the day night cycle", 2026-11-14;
		-- the sun stays on the chip)
		-- a chip whose value changed flashes its number in the accent for a moment
		for name, at in chipBump do
			local l = chips[name]
			local k = 1 - (now - at) / 0.45
			if l then
				UIKit.setTextColor(l, UIKit.color("text"):Lerp(UIKit.color("accent"), math.max(0, k)))
			end
			if k <= 0 then
				chipBump[name] = nil
			end
		end
		-- the tip's banner rides on the menu bar or the build tray: the tray grows and shrinks with no word to the HUD
		-- (a piece picked or let go, the next tip's tab once something is built), and a banner left at the old height
		-- went under the tray's tabs (the user's report of 2026-11-14, "the tutorial tooltip sometimes gets hidden by
		-- the build menu after something is built")
		local tp = tips
		if tp and now >= ((tp:GetAttribute("Settled") :: number?) or 0) then
			local y = -tipsLift()
			if tp.Position.Y.Offset ~= y or tp.Position.Y.Scale ~= 1 then
				tp.Position = UDim2.new(tp.Position.X.Scale, tp.Position.X.Offset, 1, y)
			end
		end
		-- the menu bar's Build button pulses yellow (a shine across it now and then, its words white on it) while a tip
		-- asks for something built and Build mode is shut: the hut's tip and the workplace's (the tips of 2026-11-21:
		-- "Guide the player to put down a hut", "Guide the player to put down a workspace")
		local bb = buildBtn
		if bb and bb.Parent then
			local tv = StateClient.view()
			local want = tv ~= nil and (tv.tut == Plot.TIP_HUT or tv.tut == Plot.TIP_WORK) and not BuildUI.isOpen() and UIKit.currentPanel() == nil
			local plate = bb:FindFirstChild("Plate")
			local words = bb:FindFirstChild("Words")
			if want and plate then
				local k = (math.sin(now * 5) + 1) / 2
				UIKit.setPlate(plate, UIKit.color("accent"):Lerp(Color3.new(1, 1, 1), 0.35 * k), 0)
				if words and words:IsA("TextLabel") and not bb:GetAttribute("TipPulse") then
					UIKit.setTextColor(words, UIKit.color("text"))
				end
				if now >= nextBuildShine then
					nextBuildShine = now + 1.2
					UIKit.shine(bb)
				end
				bb:SetAttribute("TipPulse", true)
			elseif bb:GetAttribute("TipPulse") then
				bb:SetAttribute("TipPulse", nil)
				local own = buildBox ~= nil -- (a touch screen's own Build: mint, its words white)
				UIKit.setButtonColor(bb, UIKit.color(if own then "button_ok" else "button"))
				if words and words:IsA("TextLabel") then
					UIKit.setTextColor(words, UIKit.color(if own then "text" else "accent"))
				end
			end
		end
		-- the tree's card: the time to its next eggs runs down
		local tb, tt = treeBar, treeTime
		if tb and tb.Parent and tt then
			local left, secs = StateClient.clutchLeft()
			local back = tb.Parent :: GuiObject
			local fw = back.Size.X.Offset - 2
			local w = math.floor(fw * math.clamp(left / math.max(1, secs), 0, 1) + 0.5)
			if tb.Size.X.Offset ~= w then
				tb.Size = UDim2.fromOffset(w, 1)
			end
			local text = if tt:GetAttribute("Short") then clock(left) else "New eggs in " .. clock(left)
			if tt.Text ~= text then
				tt.Text = text
			end
		end
		-- the background music: the easygoing island tunes (always day now); the Settings panel switches it and the
		-- sounds off and on (UI/SettingsUI)
		Audio.music("day")
		SettingsUI.apply()
		-- the welcome-back card, once a report, when nothing else is up (GAME_DESIGN 14.3)
		WelcomeUI.step()
		-- the rewards (UI/RewardsUI): the Gifts button's dot, the next gift's and the timed boosts' lines, a few times a
		-- second
		if now - rewardsAt >= 0.25 then
			rewardsAt = now
			local rv = StateClient.view()
			local dot = giftDot
			if dot and dot.Parent then
				local want = RewardsUI.ready(rv) > 0
				if dot.Visible ~= want then
					dot.Visible = want
				end
			end
			RewardsUI.status(rv, Hud.statusLine)
			TopUI.status(rv, Hud.statusLine)
		end
		-- jumping on the island: held while the build tray or a panel is up (the phone's jump button hides with it,
		-- clear of the tray's and the panels' buttons)
		local char = Players.LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			local want = if BuildUI.isOpen() or UIKit.currentPanel() ~= nil then 0 else Tuning.JumpHeight
			if hum.JumpHeight ~= want then
				hum.JumpHeight = want
			end
			local pace = Tuning.WalkSpeed
			if hum.WalkSpeed ~= pace then
				hum.WalkSpeed = pace
			end
		end
		local hb = homeButton
		local home = atHome()
		if hb then
			local show = not home and not BuildUI.isOpen()
			if hb.Visible ~= show then
				hb.Visible = show
				restackSoon()
			end
		end
		local vb = visitButton
		if vb then
			local show = vb.Visible
			if os.clock() - visitLook >= 0.5 then
				visitLook = os.clock()
				show = home and not BuildUI.isOpen() and #VisitUI.islands() > 0
			elseif not home or BuildUI.isOpen() then
				show = false
			end
			if vb.Visible ~= show then
				vb.Visible = show
				restackSoon()
			end
		end
	end)
end

return Hud
