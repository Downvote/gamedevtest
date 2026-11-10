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
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Menus = require(script.Parent.Menus)
local BuildUI = require(script.Parent.BuildUI)
local ExpeditionUI = require(script.Parent.ExpeditionUI)

local Hud = {}

local TOP_H = 13
local BAR_H = 15
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
			r(math.floor(s.X / 2) - half, s.Y - BAR_H - 3, math.floor(s.X / 2) + half, s.Y),
		}
	else
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (TOP_H + 3) * K },
			r(0, s.Y - BAR_H - 3, s.X, s.Y),
			r(s.X - CARD_W - 3, TOP_H + 2, s.X, TOP_H + 4 + CARD_MAX_H),
		}
	end
	CameraController.setHudRects(list)
end

------------------------------------------------------------------ chips
-- A chip: its 11 px icon, its value; `color` the thin band under the value.
local function chip(name: string, x: number, w: number, icon: string): number
	local canvas = UIKit.canvas("Hud")
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, TOP_H), UDim2.fromOffset(x, 2), UIKit.color("plate"), 0.08, 2)
	f.Name = "Chip_" .. name
	chipIcons[name] = PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(1, 1), 3)
	chips[name] = UIKit.text(f, "", UDim2.new(1, -15, 1, 0), UDim2.fromOffset(13, 0), { name = "Value" })
	chipFrames[name] = f
	return x + w + 3
end

local function buildTop()
	local x = 3
	x = chip("shells", x, 56, "shell")
	x = chip("food", x, 52, "food")
	x = chip("wood", x, 50, "wood")
	x = chip("day", x, 50, "sun")
	-- the day's clock along the day chip's bottom edge
	local db = UIKit.rect(chipFrames.day, UDim2.fromOffset(0, 1), UDim2.new(0, 3, 1, -2), UIKit.color("accent"), 3)
	db.Name = "DayBar"
	dayBar = db
	-- Home: shown while the founder is off their own island (char.home sends them back to their path)
	local hb = UIKit.button(UIKit.canvas("Hud"), "Home", UDim2.fromOffset(UIKit.buttonWidth("Home", 5), TOP_H), UDim2.fromOffset(x, 2), function()
		local res = StateClient.request("char.home", {})
		if not res.ok and res.err ~= "cooldown" then
			UIKit.notice("You can't go home right now.", UIKit.color("bad"))
		end
	end, { name = "Home", color = UIKit.color("button_warn") })
	hb.Visible = false
	homeButton = hb
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
local MENUS: { { text: string, panel: string } } = {
	{ text = "Build", panel = "build" },
	{ text = "Villagers", panel = "folk" },
	{ text = "Driftlings", panel = "pals" },
	{ text = "Explore", panel = "explore" },
	{ text = "Index", panel = "index" },
	{ text = "Looks", panel = "looks" },
}

local function buildBar()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	if bar then
		bar:Destroy()
	end
	local total = 0
	for _, m in MENUS do
		total += UIKit.buttonWidth(m.text, 5) + 3
	end
	total -= 3
	barW = total
	local f = Instance.new("Frame")
	f.Name = "MenuBar"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(total, BAR_H)
	-- pinned to the canvas's bottom edge (not a measured y: it stays on screen while the canvas settles)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Position = UDim2.new(0, math.floor((s.X - total) / 2), 1, -2)
	f.Parent = canvas
	local x = 0
	for _, m in MENUS do
		local w = UIKit.buttonWidth(m.text, 5)
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
	local h = 2 + 11 + 4 * LINE_H + 3 + 3 * LINE_H + 3
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
	f.Name = "IslandCard"
	local plan = Office.plans[v.tier]
	UIKit.text(f, if plan then plan.name else "Your island", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent"), z = 4, name = "Title" })
	local y = 13
	local full = #v.folk >= v.beds
	line(f, "folk", "Villagers", y, w, nil, string.format("%d/%d", #v.folk, v.beds), if full then UIKit.color("orange") else nil, "Folk")
	y += LINE_H
	line(f, "pal", "Driftlings", y, w, nil, string.format("%d/%d", #v.pals, v.nests), if #v.pals >= v.nests and v.nests > 0 then UIKit.color("orange") else nil, "Pals")
	y += LINE_H
	line(f, "visitor", "Visitors", y, w, nil, string.format("%.1f", v.visitors), nil, "Visitors")
	y += LINE_H
	line(f, "charm", "Charm", y, w, nil, tostring(v.charm), UIKit.color("pink"), "Charm")
	y += LINE_H
	UIKit.rect(f, UDim2.fromOffset(w - 8, 1), UDim2.fromOffset(4, y + 1), UIKit.color("plate_light"), 4)
	y += 3
	local function rate(icon: string, n: number, label: string)
		local c = if n < -0.05 then UIKit.color("bad") elseif n > 0.05 then UIKit.color("good") else UIKit.color("text_dim")
		line(f, icon, label, y, w, nil, Numbers.perDay(n), c, "Rate_" .. icon)
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, 40), UDim2.fromOffset(s.X - w - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
	f.Name = "ExpCard"
	PixelSprites.image(f, "mini_boat", UDim2.fromOffset(3, 2), 4)
	UIKit.text(f, e.isle.name, UDim2.fromOffset(w - 20, 10), UDim2.fromOffset(16, 3), { color = UIKit.color("accent"), z = 4, name = "Islet" })
	local state = if e.battle then "In a battle!" else string.format("Stop %d of %d", e.node, #e.nodes)
	UIKit.text(f, state, UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 13), { color = if e.battle then UIKit.color("bad") else UIKit.color("text_dim"), z = 4, name = "State" })
	local b = UIKit.button(f, "Continue", UDim2.fromOffset(w - 8, 13), UDim2.fromOffset(4, 24), function()
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
	local hide = BuildUI.isOpen() or ExpeditionUI.isOpen()
	if c then
		c.Visible = not hide
	end
	if e then
		e.Visible = not hide
		if UIKit.phone() then
			e.Position = UDim2.fromOffset(3, TOP_H + 4)
		else
			local y = if c then c.Position.Y.Offset + c.Size.Y.Offset + 3 else TOP_H + 4
			e.Position = UDim2.fromOffset(s.X - CARD_W - 3, y)
		end
	end
end

------------------------------------------------------------------ tips
local TIPS: { [number]: string } = {
	[1] = "Food first: tap Build and place a Veggie Patch.",
	[2] = "Now a Tent: a castaway may move in at dawn and work for you.",
	[3] = "Build a Driftling Nest, then tap Explore and set sail to a new island!",
	[4] = "In battle, Treat a hurt wild driftling with food to befriend it.",
}

local function updateTips(v: Types.ClientView)
	local text = TIPS[v.tut]
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
	local ok = v.tut == 4
	local w = math.min(UIKit.textWidth(text) + (if ok then 40 else 12), s.X - 20)
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, 14), UDim2.new(0, math.floor((s.X - w) / 2), 1, -(BAR_H + 5)), UIKit.color("paper"), 0, 2)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Name = "Tips"
	local l = UIKit.text(f, text, UDim2.new(1, if ok then -36 else -8, 1, 0), UDim2.fromOffset(5, 0), { color = UIKit.color("text_ink"), kind = "plain", name = "Words" })
	l:SetAttribute("Source", text)
	if ok then
		UIKit.button(f, "OK", UDim2.fromOffset(24, 10), UDim2.new(1, -27, 0, 2), function()
			StateClient.request("tut.next", {})
		end, { name = "TipsOk" })
	end
	f.Visible = not BuildUI.isOpen()
	tips = f
	-- a new tip bounces in
	f.Position = UDim2.new(0, math.floor((s.X - w) / 2), 1, -(BAR_H + 1))
	UIKit.tween(f, 0.18, { Position = UDim2.new(0, math.floor((s.X - w) / 2), 1, -(BAR_H + 5)) })
end

------------------------------------------------------------------ the loading curtain
local function buildCurtain()
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local f = Instance.new("Frame")
	f.Name = "Curtain"
	f.BackgroundColor3 = UIKit.color("plate")
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 1, 40)
	f.Position = UDim2.fromOffset(0, -40)
	f.ZIndex = 20
	f.Parent = canvas
	local title = UIKit.text(f, "Driftling Isle", UDim2.fromOffset(s.X, 18), UDim2.new(0, 0, 0.5, 4), { x = "center", face = "big", color = UIKit.color("accent"), kind = "title", z = 21 })
	title.AnchorPoint = Vector2.new(0, 1)
	UIKit.text(f, "Waking up your island...", UDim2.fromOffset(s.X, 10), UDim2.new(0, 0, 0.5, 26), { x = "center", color = UIKit.color("text_dim"), z = 21 })
	local _, set = UIKit.bar(f, UDim2.fromOffset(120, 3), UDim2.new(0.5, -60, 0.5, 42), UIKit.color("accent"), UIKit.color("plate_light"))
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
local function onDay(msg: { [string]: any })
	local day = tonumber(msg.day) or 0
	local lines: { string } = {}
	local who = msg.movedIn
	if type(who) == "table" and type(who.name) == "string" then
		table.insert(lines, who.name .. " moved in!")
	end
	local trained = if type(msg.trained) == "number" then msg.trained else 0
	if trained > 0 then
		table.insert(lines, string.format("%d trained at the yard", trained))
	end
	Audio.play(if #lines > 0 then "fanfare" else "ding")
	chipBump.day = os.clock()
	if UIKit.currentPanel() ~= nil or ExpeditionUI.isOpen() or BuildUI.isOpen() then
		UIKit.notice("Day " .. day .. (if #lines > 0 then ": " .. table.concat(lines, ", ") else ""), UIKit.color("accent"), 4)
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, -h - 6), UIKit.color("plate"), 0, 3)
	f.Name = "DayBanner"
	f.ZIndex = 8
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), UIKit.color("accent"), 9)
	PixelSprites.image(f, "mini_sun", UDim2.fromOffset(6, 6), 9)
	UIKit.text(f, "Day " .. day, UDim2.fromOffset(w - 24, 16), UDim2.fromOffset(20, 3), { face = "big", kind = "title", color = UIKit.color("accent"), z = 9, name = "Day" })
	for i, l in lines do
		UIKit.text(f, l, UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 10 + i * 10), { color = UIKit.color("good"), z = 9, name = "Line" .. i })
	end
	banner = f
	UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, 22) })
	if #lines > 0 then
		task.delay(0.3, function()
			if f.Parent then
				UIKit.burst(f, math.floor(w / 2), 10, { "accent", "good", "white" }, 14, 40)
			end
		end)
	end
	task.delay(2.6 + #lines * 0.5, function()
		if f.Parent then
			UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(x, -h - 6) })
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
	for _, f in { card, expCard, tips, homeButton } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	card, expCard, tips, homeButton, dayBar = nil, nil, nil, nil, nil
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
			UIKit.popText(UIKit.canvas("Hud"), cf.Position.X.Offset + cf.Size.X.Offset / 2, TOP_H + 4, "+" .. Numbers.coins(gained), UIKit.color("accent"))
			gained = 0
		end
	end)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "day" then
			onDay(msg)
		end
	end)
	UIKit.Resized:Connect(function()
		rebuild()
	end)
	-- Build mode has its own tray, an expedition the whole screen: the menu bar, the cards and the tips step aside
	local function aside()
		local on = BuildUI.isOpen() or ExpeditionUI.isOpen()
		for _, f in { bar, tips } :: { GuiObject? } do
			if f then
				f.Visible = not on
			end
		end
		stack()
	end
	BuildUI.Changed:Connect(aside)
	ExpeditionUI.Changed:Connect(aside)
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
