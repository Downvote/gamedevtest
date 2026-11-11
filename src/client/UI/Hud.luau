--!strict
-- The HUD (docs/ARCHITECTURE.md 10.3; GAME_DESIGN 3-9): the chips along the top (shells, food, wood, the day and its
-- clock), the menu bar along the bottom (Build, Villagers, Driftlings, Explore, Index, Looks), the island card on the
-- right (the lodge, villagers and beds, driftlings and nests, visitors, charm, what a day makes) with the expedition
-- card under it while one is under way, the tips banner, the loading curtain and the new day's banner. The camera fits
-- the island clear of the HUD's blocks (CameraController.setHudRects).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Menus = require(script.Parent.Menus)
local BuildUI = require(script.Parent.BuildUI)
local ExpeditionUI = require(script.Parent.ExpeditionUI)
local Voyage = require(script.Parent.Voyage)

local Hud = {}

local TOP_H = 13
local BAR_H = 15
-- the island's looks (GAME_DESIGN 2): the chips sit in thin frames of planks, the cards in thick ones, the menu bar on
-- a wooden dock; these are the room they take
local CHIP_Y = 5 -- a chip's top (its frame 3 px above)
local CARD_Y = TOP_H + 15 -- the cards' top (their frames 4 px above)
local DOCK = 6 -- the dock round the menu bar (3 px of board, 3 of frame)
local CARD_W = 124 -- the card's width (108 on phones)
local CARD_MAX_H = 120
local LINE_H = 11

local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local chipIcons: { [string]: GuiObject } = {}
local bar: Frame? = nil
local barW = 0
local card: Frame? = nil
local expCard: Frame? = nil
local tips: Frame? = nil
local homeButton: TextButton? = nil
local dayBar: Frame? = nil
local musicButton: GuiButton? = nil
local musicPref: string? = nil -- the music switch as last tapped (before the server's answer comes back)
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
local function hudRects()
	local s = UIKit.size("Hud")
	local K = UIKit.P()
	local o = UIKit.canvasOrigin("Hud")
	local function r(x0: number, y0: number, x1: number, y1: number): Raster.Rect
		return { x0 = o.X + x0 * K, y0 = o.Y + y0 * K, x1 = o.X + x1 * K, y1 = o.Y + y1 * K }
	end
	local half = math.floor(barW / 2) + 4
	local list: { Raster.Rect }
	if UIKit.phone() then
		-- a phone (Random Bakery's rule): only Roblox's top bar and the menu bar are kept clear
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y },
			r(math.floor(s.X / 2) - half - DOCK, s.Y - BAR_H - 2 * DOCK - 2, math.floor(s.X / 2) + half + DOCK, s.Y),
		}
	else
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (CHIP_Y + TOP_H + 4) * K },
			r(0, s.Y - BAR_H - 2 * DOCK - 2, s.X, s.Y),
			r(s.X - CARD_W - 9, CARD_Y - 5, s.X, CARD_Y + CARD_MAX_H + 6),
		}
	end
	CameraController.setHudRects(list)
end

------------------------------------------------------------------ chips
-- A chip: its 11 px icon, its value, on a carved board in a thin frame of planks.
local function chip(name: string, x: number, w: number, icon: string): number
	local canvas = UIKit.canvas("Hud")
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, TOP_H), UDim2.fromOffset(x, CHIP_Y), UIKit.color("plate"), 0.04, 2, { bevel = true, wood = 2 })
	f.Name = "Chip_" .. name
	chipIcons[name] = PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(1, 1), 3)
	chips[name] = UIKit.text(f, "", UDim2.new(1, -15, 1, 0), UDim2.fromOffset(13, 0), { name = "Value" })
	chipFrames[name] = f
	return x + w + 9
end

local function buildTop()
	local x = 6
	x = chip("shells", x, 56, "shell")
	x = chip("food", x, 52, "food")
	x = chip("wood", x, 50, "wood")
	x = chip("day", x, 50, "sun")
	-- the day's clock along the day chip's bottom edge
	local db = UIKit.rect(chipFrames.day, UDim2.fromOffset(0, 1), UDim2.new(0, 3, 1, -2), UIKit.color("accent"), 3)
	db.Name = "DayBar"
	dayBar = db
	-- Home: shown while the founder is off their own island (char.home sends them back to their path)
	local hb = UIKit.button(UIKit.canvas("Hud"), "Home", UDim2.fromOffset(UIKit.buttonWidth("Home", 5), TOP_H), UDim2.fromOffset(x - 3, CHIP_Y), function()
		local res = StateClient.request("char.home", {})
		if not res.ok and res.err ~= "cooldown" then
			UIKit.notice("You can't go home right now.", UIKit.color("bad"))
		end
	end, { name = "Home", color = UIKit.color("button_warn") })
	hb.Visible = false
	homeButton = hb
	-- the music switch: a note in the top right corner (settings.music, kept with the profile)
	local s = UIKit.size("Hud")
	local mb = UIKit.button(UIKit.canvas("Hud"), "", UDim2.fromOffset(15, TOP_H), UDim2.fromOffset(s.X - 19, CHIP_Y), function()
		local v = StateClient.view()
		local cur = musicPref or (if v and v.settings.music == "off" then "off" else "on")
		local want = if cur == "off" then "on" else "off"
		musicPref = want
		Audio.play("click")
		task.spawn(function()
			StateClient.request("settings.set", { k = "music", v = want })
		end)
	end, { name = "MusicToggle", color = UIKit.color("frame") })
	PixelSprites.image(mb, "mini_note", UDim2.fromOffset(2, 1), 6).Name = "Note"
	musicButton = mb
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
			UIKit.setText(l, Numbers.coins(x))
		end
	end, instant)
end

local function updateTop(v: Types.ClientView)
	showStore("shells", v.shells, last.shells == nil)
	showStore("food", v.food, last.food == nil)
	showStore("wood", v.wood, last.wood == nil)
	-- the food runs out: the chip goes red (everyone works at half speed and the shops close)
	local fl = chips.food
	if fl then
		UIKit.setTextColor(fl, if v.food <= 0 then UIKit.color("bad") else UIKit.color("text"))
	end
	local dl = chips.day
	if dl then
		UIKit.setText(dl, "Day " .. v.day)
	end
	local db, df = dayBar, chipFrames.day
	if db and df then
		db.Size = UDim2.fromOffset(math.floor((df.Size.X.Offset - 6) * math.clamp(v.dayFrac, 0, 1)), 1)
	end
end

------------------------------------------------------------------ the menu bar
local MENUS: { { text: string, panel: string, icon: string } } = {
	{ text = "Build", panel = "build", icon = "home" },
	{ text = "Villagers", panel = "folk", icon = "folk" },
	{ text = "Driftlings", panel = "pals", icon = "pal" },
	{ text = "Explore", panel = "explore", icon = "boat" },
	{ text = "Index", panel = "index", icon = "star" },
	{ text = "Looks", panel = "looks", icon = "visitor" },
}
local MENU_ICON = 12 -- a menu button's icon (11 px and a gap) before its words

local function buildBar()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	if bar then
		bar:Destroy()
	end
	local total = 0
	for _, m in MENUS do
		total += UIKit.buttonWidth(m.text, 5) + MENU_ICON + 3
	end
	total -= 3
	barW = total
	local f = Instance.new("Frame")
	f.Name = "MenuBar"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(total, BAR_H)
	-- pinned to the canvas's bottom edge (not a measured y: it stays on screen while the canvas settles)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, math.floor((s.X - total) / 2), 1, -(DOCK + 2))
	f.Parent = canvas
	-- the dock the buttons stand on: a dark board in a frame of planks, showing between them
	local dock = UIKit.plate(f, UDim2.fromOffset(total + 6, BAR_H + 6), UDim2.fromOffset(-3, -3), UIKit.color("frame_dark"), 0, 2, { bevel = true, wood = 2 })
	dock.Name = "Dock"
	dock.ZIndex = 1
	local x = 0
	for _, m in MENUS do
		local w = UIKit.buttonWidth(m.text, 5) + MENU_ICON
		local b = UIKit.button(f, m.text, UDim2.fromOffset(w, BAR_H), UDim2.fromOffset(x, 0), function()
			if m.panel == "build" then
				BuildUI.open()
			elseif m.panel == "explore" and ExpeditionUI.active() then
				ExpeditionUI.open()
			else
				UIKit.openPanel(m.panel)
			end
		end, {
			name = "Menu_" .. m.panel,
			color = if m.panel == "build" then UIKit.color("button_warn") elseif m.panel == "explore" then UIKit.color("button_ok") else nil,
		})
		b.ZIndex = 2
		PixelSprites.image(b, "mini_" .. m.icon, UDim2.fromOffset(3, 2), 6)
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(2 + MENU_ICON - 2, 0)
			words.Size = UDim2.new(1, -(4 + MENU_ICON - 2), 1, 0)
		end
		x += w + 3
	end
	bar = f
end

------------------------------------------------------------------ the island card
local function line(parent: Instance, icon: string, text: string, y: number, w: number, color: Color3?, right: string?, rightColor: Color3?, name: string?)
	PixelSprites.image(parent, "mini_" .. icon, UDim2.fromOffset(3, y), 4)
	UIKit.text(parent, text, UDim2.fromOffset(w - 18, 10), UDim2.fromOffset(16, y + 1), { color = color or UIKit.color("text"), z = 4, name = name })
	if right then
		UIKit.text(parent, right, UDim2.fromOffset(w - 20, 10), UDim2.fromOffset(16, y + 1), { x = "right", color = rightColor or UIKit.color("text_dim"), z = 4, name = if name then name .. "R" else nil })
	end
end

local function cardKey(v: Types.ClientView): string
	return string.format("%d|%d/%d|%d/%d|%.1f|%d|%d|%d|%d", v.tier, #v.folk, v.beds, #v.pals, v.nests, v.visitors, v.charm, math.floor(v.rates.food + 0.5), math.floor(v.rates.wood + 0.5), math.floor(v.rates.shells + 0.5))
		.. (if v.food <= 0 then "|hungry" else "")
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
	local h = 3 + 12 + 4 * LINE_H + 4 + 3 * LINE_H + 3
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - 7, CARD_Y), UIKit.color("plate"), 0.04, 3, { shadow = true, wood = 3 })
	f.Name = "IslandCard"
	local plan = Office.plans[v.tier]
	-- the island's name on a plank across the top
	UIKit.plank(f, 11, 3)
	UIKit.text(f, if plan then plan.name else "Your island", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("paper"), kind = "shadow", z = 4, name = "Title" })
	local y = 15
	local full = #v.folk >= v.beds
	line(f, "folk", "Villagers", y, w, nil, string.format("%d/%d", #v.folk, v.beds), if full then UIKit.color("orange") else nil, "Folk")
	y += LINE_H
	line(f, "pal", "Driftlings", y, w, nil, string.format("%d/%d", #v.pals, v.nests), if #v.pals >= v.nests and v.nests > 0 then UIKit.color("orange") else nil, "Pals")
	y += LINE_H
	line(f, "visitor", "Visitors", y, w, nil, string.format("%.1f", v.visitors), nil, "Visitors")
	y += LINE_H
	line(f, "charm", "Charm", y, w, nil, tostring(v.charm), UIKit.color("pink"), "Charm")
	y += LINE_H
	-- a carved groove between the island and what it makes
	UIKit.rect(f, UDim2.fromOffset(w - 8, 1), UDim2.fromOffset(4, y + 1), UIKit.color("ink"), 4)
	UIKit.rect(f, UDim2.fromOffset(w - 8, 1), UDim2.fromOffset(4, y + 2), UIKit.color("plate_light"), 4)
	y += 4
	local function rate(icon: string, n: number, label: string)
		local c = if n < -0.05 then UIKit.color("bad") elseif n > 0.05 then UIKit.color("good") else UIKit.color("text_dim")
		line(f, icon, label, y, w, nil, Numbers.perMin(n * 60 / Tuning.TurnSeconds), c, "Rate_" .. icon)
		y += LINE_H
	end
	rate("food", v.rates.food, if v.food <= 0 then "Hungry!" else "Food")
	rate("wood", v.rates.wood, "Wood")
	rate("shell", v.rates.shells, "Shells")
	f:SetAttribute("Key", key)
	f.Visible = not BuildUI.isOpen() and not ExpeditionUI.isOpen()
	card = f
end

------------------------------------------------------------------ the expedition card
-- Under the island card while an expedition is under way (the player closed its screen): where, how far, Continue.
local function updateExp(v: Types.ClientView)
	local e = v.exp
	local key = if e then string.format("%d:%d:%s:%s", e.isle.seed, e.node, tostring(e.battle ~= nil), tostring(e.over)) else ""
	if expCard and expCard:GetAttribute("Key") == key then
		return
	end
	if expCard then
		expCard:Destroy()
		expCard = nil
	end
	if e == nil then
		return
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local w = CARD_W
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, 43), UDim2.fromOffset(s.X - w - 7, CARD_Y), UIKit.color("plate"), 0.04, 3, { shadow = true, wood = 3 })
	f.Name = "ExpCard"
	UIKit.plank(f, 11, 3)
	PixelSprites.image(f, "mini_boat", UDim2.fromOffset(3, 1), 4)
	UIKit.text(f, e.isle.name, UDim2.fromOffset(w - 20, 10), UDim2.fromOffset(16, 1), { color = UIKit.color("paper"), kind = "shadow", z = 4, name = "Islet" })
	local state = if e.battle then "In a battle!" else string.format("Stage %d", math.max(0, e.node - 1))
	UIKit.text(f, state, UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 14), { color = if e.battle then UIKit.color("bad") else UIKit.color("text_dim"), z = 4, name = "State" })
	local b = UIKit.button(f, "Continue", UDim2.fromOffset(w - 8, 13), UDim2.fromOffset(4, 26), function()
		ExpeditionUI.open()
	end, { name = "ExpContinue", color = UIKit.color("button_ok") })
	b:SetAttribute("Pulse", true)
	f:SetAttribute("Key", key)
	expCard = f
end

-- The cards stack down the right edge (on a phone the expedition card sits on the left, clear of the jump button).
local function stack()
	local s = UIKit.size("Hud")
	local c, e = card, expCard
	-- (the sea chart's wide panel covers the cards but a sliver: they step aside for it too)
	local hide = BuildUI.isOpen() or ExpeditionUI.isOpen() or UIKit.currentPanel() == "explore"
	if c then
		c.Visible = not hide
	end
	if e then
		e.Visible = not hide
		if UIKit.phone() then
			e.Position = UDim2.fromOffset(7, CARD_Y)
		else
			local y = if c then c.Position.Y.Offset + c.Size.Y.Offset + 11 else CARD_Y
			e.Position = UDim2.fromOffset(s.X - CARD_W - 7, y)
		end
	end
end

------------------------------------------------------------------ tips
local TIPS: { [number]: string } = {
	[1] = "Food: tap Build, place a Veggie Patch. It grows food; everyone eats it.",
	[2] = "Wood: place a Lumber Camp. It chops wood for bigger buildings.",
	[3] = "Shells: place a Snack Stall. It sells food to visitors for shells.",
	[4] = "Now a Tent: a castaway moves in at once, to work and to sail with you.",
	[5] = "Build a Driftling Nest, then tap Explore: your villager sails with you!",
	[6] = "Set sail from Explore: on the islands your party fights by itself.",
	[7] = "Catch a driftling: in a battle, tap Snack and throw one at a hurt wild one.",
	[8] = "A new friend! Islands give food, wood, shells and friends: sail often.",
}
-- (on an expedition under way, with its screen closed)
local TIPS_AWAY: { [number]: string } = {
	[6] = "Your party is on its first island: tap Continue to watch it fight.",
	[7] = "Tap Continue: in a battle, throw a snack at a hurt wild one to catch it.",
}
-- in Build mode (the tray already on the right tab, the building pulsing)
local TIPS_BUILD: { [number]: string } = {
	[1] = "Food: place a Veggie Patch. It grows food; everyone eats it.",
	[5] = "Place a Driftling Nest, then tap Done and Explore to set sail!",
}

-- The tip's banner sits over the menu bar, or over the build tray in Build mode (the tips show there too).
local function tipsLift(): number
	return if BuildUI.isOpen() then BuildUI.TRAY_H + 12 else BAR_H + 2 * DOCK + 8
end

local function updateTips(v: Types.ClientView)
	local text = (if BuildUI.isOpen() then TIPS_BUILD[v.tut] else nil) or (if v.exp then TIPS_AWAY[v.tut] else nil) or TIPS[v.tut]
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
	local ok = v.tut == 8
	-- a parchment note in a thin frame of planks; on a phone it keeps to the room left of the island card (two lines
	-- if it must), so it never covers the card
	local room = if UIKit.phone() then s.X - CARD_W - 24 else s.X - 20
	local want = UIKit.textWidth(text) + (if ok then 40 else 12)
	local w = math.min(want, room)
	local lines = if want > w then 2 else 1
	local h = 4 + 10 * lines
	local left = if UIKit.phone() then math.floor((s.X - CARD_W - 12 - w) / 2) else math.floor((s.X - w) / 2)
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.new(0, left, 1, -tipsLift()), UIKit.color("paper"), 0, 2, { shadow = true, wood = 2 })
	f.AnchorPoint = Vector2.new(0, 1)
	f.Name = "Tips"
	local l = UIKit.text(f, text, UDim2.new(1, if ok then -36 else -8, 1, 0), UDim2.fromOffset(5, 0), { color = UIKit.color("text_ink"), kind = "plain", name = "Words", wrap = lines > 1 })
	l:SetAttribute("Source", text)
	if ok then
		UIKit.button(f, "OK", UDim2.fromOffset(24, 10), UDim2.new(1, -27, 0, 2), function()
			StateClient.request("tut.next", {})
		end, { name = "TipsOk" })
	end
	f.Visible = not ExpeditionUI.isOpen()
	tips = f
	-- a new tip bounces in
	f.Position = UDim2.new(0, left, 1, -(tipsLift() - 4))
	UIKit.tween(f, 0.18, { Position = UDim2.new(0, left, 1, -tipsLift()) })
end

------------------------------------------------------------------ the loading curtain
local function buildCurtain()
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local f = Instance.new("Frame")
	f.Name = "Curtain"
	-- the open sea at night (GAME_DESIGN 2: the island's looks): deep blue, a few wave crests, the title, and the
	-- loading bar in a thin frame of planks
	f.BackgroundColor3 = UIKit.color("sea_shade")
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 1, 40)
	f.Position = UDim2.fromOffset(0, -40)
	f.ZIndex = 20
	f.Parent = canvas
	local crest = UIKit.color("sea_shade"):Lerp(UIKit.color("button"), 0.28)
	local rng = Random.new(7)
	for _ = 1, 26 do
		local cx, cy = rng:NextInteger(4, math.max(5, s.X - 16)), rng:NextInteger(44, math.max(45, s.Y + 30))
		local cw = rng:NextInteger(5, 12)
		UIKit.rect(f, UDim2.fromOffset(cw, 1), UDim2.fromOffset(cx, cy), crest, 20).Name = "Crest"
		UIKit.rect(f, UDim2.fromOffset(math.max(2, cw - 4), 1), UDim2.fromOffset(cx + 2, cy - 1), crest, 20).Name = "Crest"
	end
	local title = UIKit.text(f, "Driftling Isle", UDim2.fromOffset(s.X, 18), UDim2.new(0, 0, 0.5, 4), { x = "center", face = "big", color = UIKit.color("accent"), kind = "title", z = 21 })
	title.AnchorPoint = Vector2.new(0, 1)
	UIKit.text(f, "Waking up your island...", UDim2.fromOffset(s.X, 10), UDim2.new(0, 0, 0.5, 26), { x = "center", color = UIKit.color("text_dim"), z = 21 })
	local holder = UIKit.plate(f, UDim2.fromOffset(124, 7), UDim2.new(0.5, -62, 0.5, 40), UIKit.color("plate"), 0, 1, { wood = 2 })
	holder.ZIndex = 21
	local _, set = UIKit.bar(holder, UDim2.fromOffset(120, 3), UDim2.fromOffset(2, 2), UIKit.color("accent"), UIKit.color("plate_light"))
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local done, progress = PixelRenderer.firstPicture()
			set(progress)
			if done or os.clock() - t0 > 30 then
				break
			end
			task.wait(0.05)
		end
		UIKit.tween(f, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.3)
		f:Destroy()
	end)
end

------------------------------------------------------------------ a new day
-- A banner drops in at the top: the day, who moved in, who trained. Under a panel or an expedition: a notice.
-- A new calendar day ("Day 12": every few hours) or a turn's news (a newcomer, the yard's training).
local function onDay(msg: { [string]: any })
	local isDay = msg.kind == "day"
	local day = tonumber(msg.day) or 0
	local lines: { string } = {}
	local who = msg.movedIn
	if type(who) == "table" and type(who.name) == "string" then
		table.insert(lines, who.name .. " moved in!")
	end
	-- an egg hatched at the Hatchery (Logic/Breed): its kind (and what it was born with)
	local hatched = 0
	if type(msg.hatched) == "table" then
		for _, x in msg.hatched do
			local d = if type(x) == "table" and type(x.sp) == "string" then Creatures.byId[x.sp] else nil
			if d then
				hatched += 1
				table.insert(lines, d.name .. " hatched!")
			end
		end
	end
	local trained = if type(msg.trained) == "number" then msg.trained else 0
	if trained > 0 then
		table.insert(lines, string.format("%d trained at the yard", trained))
	end
	if not isDay and msg.movedIn == nil and hatched == 0 then
		-- only the yard's training: a quiet word
		if #lines > 0 then
			UIKit.notice(lines[1], UIKit.color("good"), 3)
		end
		return
	end
	local title = if isDay then "Day " .. day elseif msg.movedIn == nil then "An egg hatched!" else "A newcomer!"
	Audio.play(if #lines > 0 then "fanfare" else "ding")
	if isDay then
		chipBump.day = os.clock()
	end
	if UIKit.currentPanel() ~= nil or ExpeditionUI.isOpen() or BuildUI.isOpen() then
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, -h - 10), UIKit.color("plate"), 0, 3, { shadow = true, wood = 3 })
	f.Name = "DayBanner"
	f.ZIndex = 8
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), UIKit.color("accent"), 9)
	PixelSprites.image(f, if isDay then "mini_sun" else "mini_folk", UDim2.fromOffset(6, 6), 9)
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
local function refresh(v: Types.ClientView)
	updateTop(v)
	updateCard(v)
	updateExp(v)
	stack()
	updateTips(v)
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
	for _, f in { card, expCard, tips, homeButton, musicButton } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	card, expCard, tips, homeButton, dayBar, musicButton = nil, nil, nil, nil, nil, nil
	CARD_W = if UIKit.phone() then 108 else 124
	buildTop()
	buildBar()
	local v = StateClient.view()
	if v then
		lastKey = ""
		refresh(v)
	end
	hudRects()
end

function Hud.start()
	buildCurtain()
	Menus.init()
	ExpeditionUI.init()
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
		if gained >= 1 and now - popAt >= 2 and cf and cf.Parent and not ExpeditionUI.isOpen() then
			popAt = now
			UIKit.popText(UIKit.canvas("Hud"), cf.Position.X.Offset + cf.Size.X.Offset / 2, CHIP_Y + TOP_H + 4, "+" .. Numbers.coins(gained), UIKit.color("accent"))
			gained = 0
		end
	end)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "day" or msg.kind == "turn" then
			onDay(msg)
		end
	end)
	UIKit.Resized:Connect(function()
		rebuild()
	end)
	-- Build mode has its own tray, an expedition the whole screen: the menu bar and the cards step aside; the tips
	-- stay in Build mode (lifted over the tray) and step aside for an expedition
	local function aside()
		local b = bar
		if b then
			b.Visible = not (BuildUI.isOpen() or ExpeditionUI.isOpen())
		end
		local v = StateClient.view()
		if v then
			updateTips(v)
		end
		local t = tips
		if t then
			t.Visible = not ExpeditionUI.isOpen()
			t.Position = UDim2.new(t.Position.X.Scale, t.Position.X.Offset, 1, -tipsLift())
		end
		stack()
	end
	BuildUI.Changed:Connect(aside)
	ExpeditionUI.Changed:Connect(aside)
	UIKit.PanelChanged:Connect(function()
		stack()
	end)
	local lastBeat = os.clock()
	local nextShine = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - lastBeat)
		lastBeat = now
		stepEases(dt)
		-- the day's clock creeps along between the server's ticks; the sun sets into the moon for the evening
		local v = StateClient.view()
		if v then
			local db, df = dayBar, chipFrames.day
			if db and df then
				db.Size = UDim2.fromOffset(math.floor((df.Size.X.Offset - 6) * math.clamp(v.dayFrac, 0, 1)), 1)
			end
			local icon = chipIcons.day
			local night = v.dayFrac >= 0.75
			if icon and icon:GetAttribute("Night") ~= night and df then
				icon:Destroy()
				local ni = PixelSprites.image(df, if night then "mini_moon" else "mini_sun", UDim2.fromOffset(1, 1), 3)
				ni:SetAttribute("Night", night)
				chipIcons.day = ni
			end
		end
		-- a chip whose value changed flashes for a moment
		for name, at in chipBump do
			local f = chipFrames[name]
			local k = 1 - (now - at) / 0.45
			if f then
				UIKit.setPlate(f, UIKit.color("plate"):Lerp(UIKit.color("plate_light"), math.max(0, k)))
			end
			if k <= 0 then
				chipBump[name] = nil
			end
		end
		-- the food chip blinks while the island is hungry
		local ff = chipFrames.food
		if v and ff and v.food <= 0 and chipBump.food == nil then
			local on = math.floor(now * 2) % 2 == 0
			UIKit.setPlate(ff, if on then UIKit.color("plate"):Lerp(UIKit.color("bad"), 0.35) else UIKit.color("plate"))
		end
		-- the expedition card's Continue pulses
		local e = expCard
		if e then
			local pulse = (math.sin(now * 5) + 1) / 2
			local shineNow = now >= nextShine
			if shineNow then
				nextShine = now + 2.2
			end
			for _, b in e:GetChildren() do
				if b:IsA("TextButton") and b:GetAttribute("Pulse") == true and b.AutoButtonColor then
					UIKit.setButtonColor(b, UIKit.color("button_ok"):Lerp(UIKit.color("button_warn"), pulse * 0.7))
					if shineNow then
						UIKit.shine(b)
					end
				end
			end
		end
		-- the background music: easygoing island tunes by day, softer ones from the twilight, an adventure at sea
		-- (an islet's screen, a voyage); the note in the corner switches it off and on
		local f = DayLight.frac()
		Audio.music(if ExpeditionUI.isOpen() or Voyage.isPlaying() then "sea" elseif f >= 0.74 or f < 0.02 then "night" else "day")
		local vw = StateClient.view()
		local on = (musicPref or (if vw and vw.settings.music == "off" then "off" else "on")) ~= "off"
		Audio.setMusicOn(on)
		local mb = musicButton
		if mb then
			local note = mb:FindFirstChild("Note")
			if note and note:IsA("ImageLabel") then
				local c = if on then Color3.new(1, 1, 1) else Color3.fromRGB(120, 110, 130)
				if note.ImageColor3 ~= c then
					note.ImageColor3 = c
				end
			end
		end
		-- jumping on the island: held while the build tray, a panel, an islet's screen or a voyage is up (the phone's
		-- jump button hides with it, clear of the tray, the panels' and the battle's buttons)
		local char = Players.LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			local want = if BuildUI.isOpen() or ExpeditionUI.isOpen() or Voyage.isPlaying() or UIKit.currentPanel() ~= nil then 0 else Tuning.JumpHeight
			if hum.JumpHeight ~= want then
				hum.JumpHeight = want
			end
		end
		local hb = homeButton
		if hb then
			local show = not atHome() and not BuildUI.isOpen() and not ExpeditionUI.isOpen()
			if hb.Visible ~= show then
				hb.Visible = show
			end
		end
	end)
end

return Hud
