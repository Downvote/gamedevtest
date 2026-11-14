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

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Quests = require(ReplicatedStorage.Shared.Data.Quests)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
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
local SettingsUI = require(script.Parent.SettingsUI)
local WelcomeUI = require(script.Parent.WelcomeUI)
local BuildUI = require(script.Parent.BuildUI)

local Hud = {}

local TOP_H = 14 -- the top bar's height
local BAR_H = 14 -- a menu button's height
local EDGE = 5 -- UI px between the HUD's blocks and the screen's edges
local CHIP_Y = 4 -- the top bar's top
local CARD_Y = CHIP_Y + TOP_H + 4 -- the cards' top (and the status panel's)
local GAP = 3 -- UI px between two blocks stacked in a column
local DOCK = 3 -- the glass round the menu bar's buttons
local PAD = UIKit.PAD -- inside a block
local CARD_W = 116 -- the right column's width (104 on phones)
local CARD_MAX_H = 150
local LINE_H = 11

local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local chipIcons: { [string]: GuiObject } = {}
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
	local hb = homeButton
	if hb and hb.Visible then
		right = math.max(right, hb.Position.X.Offset + hb.Size.X.Offset)
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
	if UIKit.phone() then
		-- a phone (Random Bakery's rule): only Roblox's top bar and the menu bar are kept clear
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y },
			r(math.floor(s.X / 2) - half, s.Y - BAR_H - 2 * DOCK - EDGE, math.floor(s.X / 2) + half, s.Y),
		}
	else
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (CHIP_Y + TOP_H + 2) * K },
			r(math.floor(s.X / 2) - half, s.Y - BAR_H - 2 * DOCK - EDGE, math.floor(s.X / 2) + half, s.Y),
			r(s.X - CARD_W - EDGE - 2, rightTop() - 2, s.X, rightTop() + CARD_MAX_H),
		}
	end
	CameraController.setHudRects(list)
end

------------------------------------------------------------------ the top bar
-- One glass strip of chips (Random Bakery's top bar): each chip its 11 px icon and its value; the day's chip has a
-- thin bar under its words for how far through the day it is.
local CHIP_GAP = 7
-- (the top bar is one line: the shells, then the season and the weather, Hud.topChip; the day count went from it on
-- 2026-11-14: "also, this can be compressed into one line. remove the "day 1" as well")
local CHIP_MIN: { [string]: number } = { shells = 40, season = 24, weather = 24 }
local CHIP_ORDER = { "shells", "season", "weather" }
-- Each chip as wide as its words need (never under its minimum), the strip round them, Home after it.
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
			local w = math.max(CHIP_MIN[name] or 40, 13 + UIKit.textWidth(words) + 1)
			f.Visible = true
			f.Position = UDim2.fromOffset(x, 0)
			f.Size = UDim2.fromOffset(w, TOP_H)
			x += w + CHIP_GAP
		elseif f then
			f.Visible = false
		end
	end
	local w = x - CHIP_GAP + PAD - 1
	if tb.Size.X.Offset ~= w then
		tb.Size = UDim2.fromOffset(w, TOP_H)
	end
	local hb = homeButton
	if hb then
		hb.Position = UDim2.fromOffset(EDGE + w + GAP, CHIP_Y)
	end
	-- (the top bar grew or shrank: the right-hand column may move between the top row and under it)
	local c = card
	if c and c.Position.Y.Offset ~= rightTop() then
		restackSoon()
	end
end
local function chip(name: string, x: number, w: number, icon: string): number
	local f = Instance.new("Frame")
	f.Name = "Chip_" .. name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(w, TOP_H)
	f.Position = UDim2.fromOffset(x, 0)
	f.ZIndex = 2
	f.Parent = topBar
	chipIcons[name] = PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(0, 1), 3)
	chips[name] = UIKit.text(f, "", UDim2.new(1, -13, 0, 10), UDim2.fromOffset(13, 2), { name = "Value", z = 3 })
	chipFrames[name] = f
	return x + w + CHIP_GAP
end

local function buildTop()
	local canvas = UIKit.canvas("Hud")
	local widths = CHIP_MIN
	local w = PAD + widths.shells + PAD - 1
	local tb = UIKit.glass(canvas, UDim2.fromOffset(w, TOP_H), UDim2.fromOffset(EDGE, CHIP_Y), 2)
	tb.Name = "TopBar"
	topBar = tb
	local x = PAD
	x = chip("shells", x, widths.shells, "shell")
	x = chip("season", x, widths.season, "sun")
	x = chip("weather", x, widths.weather, "sun")
	layoutTop()
	-- Home: shown while the founder is off their own island (char.home sends them back to their plaza)
	local hb = UIKit.button(canvas, "Home", UDim2.fromOffset(UIKit.buttonWidth("Home", 5), TOP_H), UDim2.fromOffset(EDGE + w + GAP, CHIP_Y), function()
		local res = StateClient.request("char.home", {})
		if not res.ok and res.err ~= "cooldown" then
			UIKit.notice("You can't go home right now.", UIKit.color("bad"))
		end
	end, { name = "Home", color = UIKit.color("button_warn") })
	hb.Visible = false
	homeButton = hb
	-- (the music switch that sat in the top right corner moved into the Settings panel: UI/SettingsUI, the menu bar's
	-- Settings, 2026-11-14)
end

------------------------------------------------------------------ the status panel
-- Under the top bar on the left, glass like it: one line each (an 11 px icon and words), the season and the weather
-- and the like, from other modules: `Hud.statusLine(name, icon, text, color?)` adds or changes a line, a nil `text`
-- takes it away. It hides while it has no lines; the quest's card sits under it.
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
			y += LINE_H
		end
	end
	st.Size = UDim2.fromOffset(STATUS_W, y + 1)
	st.Visible = #statusOrder > 0
end

function Hud.statusLine(name: string, icon: string?, text: string?, color: Color3?)
	local st = status
	if st == nil then
		return
	end
	local old = statusLines[name]
	if text == nil then
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
	local ic = line:FindFirstChild("Icon")
	if ic then
		ic:Destroy()
	end
	if icon then
		PixelSprites.image(line, "mini_" .. icon, UDim2.fromOffset(0, 0), 3).Name = "Icon"
	end
	local t = line:FindFirstChild("Text")
	if t and t:IsA("TextLabel") then
		UIKit.setText(t, text)
		UIKit.setTextColor(t, color or UIKit.color("text"))
	else
		UIKit.text(line, text, UDim2.new(1, -13, 0, 10), UDim2.fromOffset(13, 1), { color = color or UIKit.color("text"), name = "Text", z = 3 })
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
end

-- A chip on the top bar's line after the shells (UI/WeatherChip: "season", "weather"): its icon, its words and their
-- colour; nil words take it away.
function Hud.topChip(name: string, icon: string?, text: string?, color: Color3?)
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
	{ text = "Looks", panel = "looks", icon = "visitor" },
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

local function buildBar()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	if bar then
		bar:Destroy()
	end
	local total = 0
	for _, m in menus() do
		total += UIKit.buttonWidth(m.text, 4) + MENU_ICON + 2
	end
	total -= 2
	barW = total
	local f = Instance.new("Frame")
	f.Name = "MenuBar"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(total, BAR_H)
	-- pinned to the canvas's bottom edge (not a measured y: it stays on screen while the canvas settles)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, math.floor((s.X - total) / 2), 1, -(DOCK + EDGE - 1))
	f.Parent = canvas
	-- one glass strip under the buttons (Random Bakery's bar): each button shows only its icon and words until the
	-- mouse is over it; Build's words in the accent
	local dock = UIKit.glass(f, UDim2.fromOffset(total + 2 * DOCK, BAR_H + 2 * DOCK), UDim2.fromOffset(-DOCK, -DOCK), 2)
	dock.Name = "Dock"
	dock.ZIndex = 1
	local x = 0
	for _, m in menus() do
		local w = UIKit.buttonWidth(m.text, 4) + MENU_ICON
		local b = UIKit.button(f, m.text, UDim2.fromOffset(w, BAR_H), UDim2.fromOffset(x, 0), function()
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
		PixelSprites.image(b, "mini_" .. m.icon, UDim2.fromOffset(3, 2), 6)
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(MENU_ICON + 1, 0)
			words.Size = UDim2.new(1, -(MENU_ICON + 4), 1, 0)
		end
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

local function cardKey(v: Types.ClientView): string
	return string.format("%d|%d/%d|%d|%d|%d", v.tier, housedOf(v), v.nests, math.floor(v.charm), math.round((v.charmBonus or 0) * 100), math.floor(v.rates.shells + 0.5))
end

local function updateCard(v: Types.ClientView)
	local key = cardKey(v)
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
	local h = 15 + 3 * LINE_H + 4 + LINE_H + 2
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - EDGE, rightTop()), 2)
	f.Name = "IslandCard"
	local plan = Office.plans[v.tier]
	-- the island's name, a faint rule under it
	UIKit.plank(f, 11)
	UIKit.text(f, if plan then plan.name else "Your island", UDim2.fromOffset(w - 2 * PAD, 10), UDim2.fromOffset(PAD, 2), { color = UIKit.color("accent"), kind = "shadow", z = 4, name = "Title" })
	local y = 15
	local housed = housedOf(v)
	line(f, "pal", "In huts", y, w, nil, string.format("%d/%d", housed, v.nests), if housed >= v.nests and v.nests > 0 then UIKit.color("orange") else nil, "Pals")
	y += LINE_H
	line(f, "charm", "Charm", y, w, nil, Numbers.int(math.floor(v.charm)), UIKit.color("pink"), "Charm")
	y += LINE_H
	-- what the charm adds to every shell (Logic/Island.charmBonus: the visitors went on 2026-11-14)
	line(f, "shell", "Charm bonus", y, w, nil, string.format("+%d%%", math.round((v.charmBonus or 0) * 100)), UIKit.color("pink"), "CharmBonus")
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
	rate("shell", v.rates.shells, "Shells")
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
local function updateTree(v: Types.ClientView)
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
		PixelSprites.image(price, "mini_shell", UDim2.new(1, 2, 0, 0), 5).Name = "PriceIcon"
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
local function stack()
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
			for _, it in { { "shells", "shells" } } do
				local n = tonumber(d[it[1]]) or 0
				if n > 0 then
					table.insert(parts, string.format("+%s %s", Numbers.coins(n), it[2]))
				end
			end
			Audio.play("reward")
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
	local key = if q then string.format("%s:%d:%d", q.id, have, need) else ""
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
	local done = have >= need
	local canvas = UIKit.canvas("Hud")
	local w = QUEST_W
	local textW = w - 10
	local lines = math.clamp(math.ceil(UIKit.textWidth(q.text) / textW), 1, 3)
	local h = 16 + lines * 10 + 16
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(EDGE, CARD_Y), 2)
	f.Name = "Quest"
	f:SetAttribute("Key", key)
	PixelSprites.image(f, "mini_" .. q.icon, UDim2.fromOffset(3, 2), 3)
	UIKit.text(f, q.title, UDim2.fromOffset(w - 44, 10), UDim2.fromOffset(16, 2), { color = UIKit.color("accent"), name = "Title", z = 3 })
	local which = string.format("%d/%d", i, #Quests.list)
	UIKit.text(f, which, UDim2.fromOffset(26, 10), UDim2.fromOffset(w - 30, 2), { x = "right", color = UIKit.color("text_dim"), name = "Which", z = 3 })
	UIKit.text(f, q.text, UDim2.fromOffset(textW, lines * 10), UDim2.fromOffset(5, 14), { color = UIKit.color("text"), wrap = lines > 1, name = "Words", z = 3 })
	local y = 15 + lines * 10 + 1
	if done then
		-- its reward, and Claim
		local x = 5
		for _, it in { { "shells", "shell" } } do
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
	-- a new quest slides in from the left
	f.Position = UDim2.fromOffset(-w - 8, CARD_Y)
	stack()
	local to = f.Position
	f.Position = UDim2.fromOffset(-w - 8, to.Y.Offset)
	UIKit.tween(f, 0.22, { Position = to })
end

------------------------------------------------------------------ tips
local TIPS: { [number]: string } = {
	[1] = "Shells pay for everything. Tap Build and place a Lumber Camp. It sells the wood it cuts.",
	[2] = "Shells hatch eggs. Place a Veggie Patch. It sells what it grows.",
	[3] = "Driftlings need somewhere to live. Place a Driftling Hut.",
	[4] = "The Tree of Life laid eggs round its roots. Tap the tree to pick one to hatch.",
	[5] = "A Snack Stall sells snacks for shells too. Place one by the path.",
	[6] = "The tree lays new eggs every few minutes. When the huts are full, swap a weak one for a better one.",
}
-- in Build mode (the tray already on the right tab, the building pulsing)
local TIPS_BUILD: { [number]: string } = {
	[1] = "Place a Lumber Camp. It sells the wood it cuts for shells.",
	[2] = "Place a Veggie Patch. It sells its veggies for shells.",
	[3] = "Place a Driftling Hut. Driftlings live there and go to work.",
	[5] = "Place a Snack Stall. It sells snacks for shells.",
}

-- The tip's banner sits over the menu bar, or over the build tray in Build mode (the tips show there too).
local function tipsLift(): number
	return if BuildUI.isOpen() then BuildUI.trayHeight() + 12 else BAR_H + 2 * DOCK + EDGE + 4
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
	local ok = v.tut == 6
	-- a glass note; on a phone it keeps to the room left of the island card (two lines if it must), so it never
	-- covers the card
	local room = if UIKit.phone() then s.X - CARD_W - 24 else s.X - 20
	local want = UIKit.textWidth(text) + (if ok then 40 else 12)
	local w = math.min(want, room)
	local lines = if want > w then 2 else 1
	local h = 5 + 10 * lines
	local left = if UIKit.phone() then math.floor((s.X - CARD_W - 12 - w) / 2) else math.floor((s.X - w) / 2)
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
	-- a new tip bounces in
	f.Position = UDim2.new(0, left, 1, -(tipsLift() - 4))
	UIKit.tween(f, 0.18, { Position = UDim2.new(0, left, 1, -tipsLift()) })
end

------------------------------------------------------------------ a new day
-- A banner drops in at the top: the day, or what hatched. Under a panel or in Build mode: a notice.
-- A new calendar day ("Day 12": every few hours) or a turn's news (an egg hatched).
local function onDay(msg: { [string]: any })
	local isDay = msg.kind == "day"
	local day = tonumber(msg.day) or 0
	local lines: { string } = {}
	-- an egg hatched at the Hatchery (Logic/Breed): its kind (and what it was born with)
	-- (a kind the player never had before gets "New!" in front: the turn's `fresh`)
	local hatched = 0
	local fresh: { [string]: boolean } = {}
	if type(msg.fresh) == "table" then
		for _, sp in msg.fresh do
			if type(sp) == "string" then
				fresh[sp] = true
			end
		end
	end
	if type(msg.hatched) == "table" then
		for _, x in msg.hatched do
			local d = if type(x) == "table" and type(x.sp) == "string" then Creatures.byId[x.sp] else nil
			if d then
				hatched += 1
				table.insert(lines, (if fresh[d.id] then "New! " else "") .. d.name .. " hatched!")
				fresh[d.id] = nil
			end
		end
	end
	if not isDay and hatched == 0 then
		return
	end
	local title = if isDay then "Day " .. day else "An egg hatched!"
	-- (a hatchling the friend's chimes, a plain new day a small ding)
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
	local w = 140
	for _, l in lines do
		w = math.max(w, UIKit.textWidth(l) + 16)
	end
	w = math.min(w, s.X - 16)
	local h = 22 + #lines * 10
	local x = math.floor((s.X - w) / 2)
	local f = UIKit.glass(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, -h - 10), 2)
	f.Name = "DayBanner"
	f.ZIndex = 8
	PixelSprites.image(f, if isDay then "mini_sun" else "mini_pal", UDim2.fromOffset(6, 6), 9)
	UIKit.text(f, title, UDim2.fromOffset(w - 24, 16), UDim2.fromOffset(20, 3), { face = "big", kind = "title", color = UIKit.color("accent"), z = 9, name = "Day" })
	for i, l in lines do
		UIKit.text(f, l, UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 10 + i * 10), { color = UIKit.color("good"), z = 9, name = "Line" .. i })
	end
	banner = f
	UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, 30) })
	if #lines > 0 then
		task.delay(0.3, function()
			if f.Parent then
				UIKit.burst(f, math.floor(w / 2), 10, { "accent", "good", "white" }, 14, 40)
			end
		end)
	end
	task.delay(2.6 + #lines * 0.5, function()
		if f.Parent then
			UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, -h - 10) })
			task.wait(0.3)
			f:Destroy()
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
		local a = if turned == 2 or turned == 4 then "An" else "A"
		UIKit.notice(string.format("%s %s egg is waiting under the tree.", a, string.lower(rar.name)), UIKit.color(rar.color), 5)
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
	local more = tonumber(msg.more) or 0
	if best >= 4 then
		local rar = Traits.RARITY[best] or Traits.RARITY[1]
		local a = if best == 4 then "An" else "A"
		UIKit.notice(string.format("%s %s egg is waiting under the tree.", a, string.lower(rar.name)), UIKit.color(rar.color), 5)
		Audio.play("grow")
		local tc = treeCard
		if tc and tc.Parent and tc.Visible then
			UIKit.burstOn(tc, { rar.color, "accent", "white" }, 18, 40)
		end
	elseif more > 0 then
		UIKit.notice(string.format("The tree laid %d more %s.", more, if more == 1 then "egg" else "eggs"), UIKit.color("good"), 3)
		Audio.play("rare")
	else
		UIKit.notice("The Tree of Life has new eggs!", UIKit.color("good"), 3)
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
	for _, f in { card, treeCard, tips, quest, homeButton, topBar, offers } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	offers, offerKey = nil, nil
	card, treeCard, tips, quest, homeButton, topBar = nil, nil, nil, nil, nil, nil
	CARD_W = if UIKit.phone() then 104 else 116
	buildTop()
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
	Menus.init()
	StoreUI.init()
	SettingsUI.init()
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
			local text = "New eggs in " .. clock(left)
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
		-- jumping on the island: held while the build tray or a panel is up (the phone's jump button hides with it,
		-- clear of the tray's and the panels' buttons) and while swimming; in the sea the founder swims slower
		local char = Players.LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			local swimming = AvatarView.swimming()
			local want = if BuildUI.isOpen() or UIKit.currentPanel() ~= nil or swimming then 0 else Tuning.JumpHeight
			if hum.JumpHeight ~= want then
				hum.JumpHeight = want
			end
			local pace = if swimming then Tuning.SwimSpeed else Tuning.WalkSpeed
			if hum.WalkSpeed ~= pace then
				hum.WalkSpeed = pace
			end
		end
		local hb = homeButton
		if hb then
			local show = not atHome() and not BuildUI.isOpen()
			if hb.Visible ~= show then
				hb.Visible = show
				restackSoon()
			end
		end
	end)
end

return Hud
