--!strict
-- The HUD (docs/ARCHITECTURE.md 10.3; GAME_DESIGN 2-7): the chips along the top (coins, the income, the next idea's
-- timer, the idea board's count), the menu bar along the bottom (Ideas, Index, Upgrades, Games, Looks, Build), the
-- card on the right (the game being made, or the newest ideas on the board), the tips banner, the loading curtain, and
-- the big reveal for a rare idea. The camera fits the office clear of the HUD's blocks (CameraController.setHudRects).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local IdeasData = require(ReplicatedStorage.Shared.Data.Ideas)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Ideas = require(ReplicatedStorage.Shared.Logic.Ideas)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local WorldView = require(script.Parent.Parent.Controllers.WorldView)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Menus = require(script.Parent.Menus)
local BuildUI = require(script.Parent.BuildUI)
local MicroUI = require(script.Parent.MicroUI)
local Words = require(script.Parent.Words)

local Hud = {}

local TOP_H = 13
local BAR_H = 15
local CARD_W = 124 -- the card's width (104 on phones)
local CARD_MAX_H = 104

local function cardWidth(): number
	return if UIKit.phone() then 104 else 124
end

local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local bar: Frame? = nil
local card: Frame? = nil
local tips: Frame? = nil
local homeButton: TextButton? = nil
local ideaBar: Frame? = nil
local reveal: Frame? = nil
local lastKey = ""

------------------------------------------------------------------ smooth numbers
-- Values the HUD shows ease toward their targets (the coins count up); `apply` draws a value.
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
local rollClock = 0 -- seconds since the last idea (the timer chip's bar)

------------------------------------------------------------------ layout
local function hudRects()
	local s = UIKit.size("Hud")
	local K = UIKit.P()
	local o = UIKit.canvasOrigin("Hud")
	local function r(x0: number, y0: number, x1: number, y1: number): Raster.Rect
		return { x0 = o.X + x0 * K, y0 = o.Y + y0 * K, x1 = o.X + x1 * K, y1 = o.Y + y1 * K }
	end
	local list: { Raster.Rect }
	if UIKit.phone() then
		-- a phone (Random Bakery's rule): only Roblox's top bar and the menu bar are kept clear
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y },
			r(math.floor(s.X / 2) - 140, s.Y - BAR_H - 3, math.floor(s.X / 2) + 140, s.Y),
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
local function chip(name: string, x: number, w: number, color: Color3): number
	local canvas = UIKit.canvas("Hud")
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, TOP_H), UDim2.fromOffset(x, 2), UIKit.color("plate"), 0.08, 2)
	f.Name = "Chip_" .. name
	UIKit.rect(f, UDim2.fromOffset(3, TOP_H - 6), UDim2.fromOffset(3, 3), color, 1)
	chips[name] = UIKit.text(f, "", UDim2.new(1, -9, 1, 0), UDim2.fromOffset(8, 0), { name = "Value" })
	chipFrames[name] = f
	return x + w + 3
end

local function buildTop()
	local x = 3
	x = chip("coins", x, 62, UIKit.color("accent"))
	x = chip("rate", x, 54, UIKit.color("good"))
	x = chip("idea", x, 72, UIKit.color("ideas"))
	-- the next idea's progress along the idea chip's bottom edge
	local ib = UIKit.rect(chipFrames.idea, UDim2.fromOffset(0, 1), UDim2.new(0, 3, 1, -2), UIKit.color("ideas"), 3)
	ib.Name = "IdeaBar"
	ideaBar = ib
	x = chip("board", x, 66, UIKit.color("text_dim"))
	-- Home: shown while the founder is off their own lot (char.home sends them back to their footpath)
	local hb = UIKit.button(UIKit.canvas("Hud"), "Home", UDim2.fromOffset(UIKit.buttonWidth("Home", 5), TOP_H), UDim2.fromOffset(x, 2), function()
		local res = StateClient.request("char.home", {})
		if not res.ok and res.err ~= "cooldown" then
			UIKit.notice("You can't go home right now.", UIKit.color("bad"))
		end
	end, { name = "Home", color = UIKit.color("button_warn") })
	hb.Visible = false
	homeButton = hb
end

-- Whether the founder stands on their own lot.
local function atHome(): boolean
	local v = StateClient.view()
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if v == nil or root == nil or not root:IsA("BasePart") then
		return true
	end
	return Street.plotAt(root.Position.X, root.Position.Z) == v.plot
end

local lastCoins: number? = nil
local function showCoins(coins: number, instant: boolean?)
	if lastCoins ~= nil and lastCoins ~= coins then
		chipBump.coins = os.clock()
	end
	lastCoins = coins
	easeTo("coins", coins, function(x: number)
		local l = chips.coins
		if l then
			UIKit.setText(l, Numbers.coins(x) .. " coins")
		end
	end, instant)
end

local function updateTop(v: Types.ClientView)
	showCoins(v.coins, lastCoins == nil)
	UIKit.setText(chips.rate, Numbers.rate(v.rate))
	UIKit.setText(chips.board, string.format("Board %d/%d", #v.ideas, Tuning.BoardSize))
	UIKit.setTextColor(chips.board, if #v.ideas >= Tuning.BoardSize then UIKit.color("accent") else UIKit.color("text"))
end

------------------------------------------------------------------ the menu bar
local MENUS: { { text: string, panel: string } } = {
	{ text = "Ideas", panel = "ideas" },
	{ text = "Index", panel = "index" },
	{ text = "Upgrades", panel = "upgrades" },
	{ text = "Games", panel = "games" },
	{ text = "Looks", panel = "looks" },
	{ text = "Build", panel = "build" },
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
			else
				UIKit.openPanel(m.panel)
			end
		end, {
			name = "Menu_" .. m.panel,
			color = if m.panel == "ideas" then UIKit.color("button_ok") elseif m.panel == "build" then UIKit.color("button_warn") else nil,
		})
		b.ZIndex = 2
		x += w + 3
	end
	bar = f
end

------------------------------------------------------------------ the card
-- A small idea line (LINE_H apart): its 11 px icon, its name in its tier's colour.
local LINE_H = 11
local function ideaLine(parent: Instance, c: Types.Card, y: number, w: number, extra: string?): TextLabel
	local def = IdeasData.byId[c.id]
	if def then
		PixelSprites.image(parent, "mini_" .. c.id, UDim2.fromOffset(3, y), 3)
	end
	local tier = Ideas.tier(c)
	local l = UIKit.text(parent, Ideas.name(c), UDim2.fromOffset(w - 18 - (if extra then 26 else 0), 10), UDim2.fromOffset(16, y + 1), { color = UIKit.color(Ideas.tierColor(tier)), name = "Idea" })
	if extra then
		UIKit.text(parent, extra, UDim2.fromOffset(24, 10), UDim2.fromOffset(w - 28, y + 1), { x = "right", color = UIKit.color("text"), name = "Mark" })
	end
	return l
end

local function updateCard(v: Types.ClientView)
	local proj = v.project
	local key = if proj then "p:" .. proj.title .. table.concat(proj.won, ",") else "b:" .. #v.ideas .. (if #v.ideas > 0 then Ideas.key(v.ideas[#v.ideas]) else "")
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
	local f: Frame
	if proj then
		f = UIKit.plate(canvas, UDim2.fromOffset(w, 88), UDim2.fromOffset(s.X - w - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
		f.Name = "ProjectCard"
		UIKit.text(f, "Making", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("text_dim") })
		UIKit.text(f, proj.title, UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 11), { color = UIKit.color("accent"), name = "Title" })
		local played = true
		for i, c in proj.ideas do
			local won = proj.won[i]
			played = played and won >= 0
			local mark = if won == 1 then "WIN" elseif won == 0 then "lose" else "-"
			local l = ideaLine(f, c, 10 + i * LINE_H, w, mark)
			l.Name = "Idea_" .. i
		end
		local wins = 0
		for _, x in proj.won do
			if x == 1 then
				wins += 1
			end
		end
		UIKit.text(f, string.format("Sales x%.2f", 1 + Tuning.WinBoost * wins), UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 59), { color = UIKit.color("good"), name = "Boost" })
		local b = UIKit.button(f, if played then "Launch!" else "Play!", UDim2.fromOffset(w - 8, 13), UDim2.fromOffset(4, 71), function()
			MicroUI.open()
		end, { name = if played then "CardLaunch" else "CardPlay", color = if played then UIKit.color("button_ok") else UIKit.color("accent"), textColor = if played then nil else UIKit.color("ink") })
		b:SetAttribute("Pulse", true)
	else
		local shown = math.min(#v.ideas, 4)
		local h = 40 + math.max(1, shown) * LINE_H
		f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
		f.Name = "BoardCard"
		UIKit.text(f, "Idea board", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent") })
		if shown == 0 then
			UIKit.text(f, "Your team is thinking...", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 13), { color = UIKit.color("text_dim") })
		end
		for i = 1, shown do
			ideaLine(f, v.ideas[#v.ideas - i + 1], 2 + i * LINE_H, w)
		end
		local ready = #v.ideas >= 3
		local b = UIKit.button(f, if ready then "Make a game!" else string.format("%d/3 ideas", #v.ideas), UDim2.fromOffset(w - 8, 13), UDim2.fromOffset(4, h - 16), function()
			UIKit.openPanel("ideas")
		end, { name = "MakeGame", color = if ready then UIKit.color("button_ok") else nil, enabled = ready })
		b:SetAttribute("Pulse", ready)
	end
	f:SetAttribute("Key", key)
	f.Visible = not BuildUI.isOpen()
	card = f
end

------------------------------------------------------------------ tips
local TIPS: { [number]: string } = {
	[1] = "Your idea team is thinking up ideas. Collect three, then make a game!",
	[2] = "Play the game's three minigames: every win boosts its sales!",
	[3] = "Your game earns coins for good. Spend them in Upgrades!",
}

local function updateTips(v: Types.ClientView)
	local text = TIPS[v.tut]
	if tips then
		local words = tips:FindFirstChild("Words")
		if text and words and words:IsA("TextLabel") and words.Text == text then
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
	local w = math.min(UIKit.textWidth(text) + 40, s.X - 20)
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, 14), UDim2.new(0, math.floor((s.X - w) / 2), 1, -(BAR_H + 5)), UIKit.color("paper"), 0, 2)
	f.AnchorPoint = Vector2.new(0, 1)
	f.Name = "Tips"
	UIKit.text(f, text, UDim2.new(1, -36, 1, 0), UDim2.fromOffset(5, 0), { color = UIKit.color("text_ink"), kind = "plain", name = "Words" })
	UIKit.button(f, "OK", UDim2.fromOffset(24, 10), UDim2.new(1, -27, 0, 2), function()
		StateClient.request("tut.next", {})
	end, { name = "TipsOk" })
	f.Visible = not BuildUI.isOpen()
	tips = f
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
	local title = UIKit.text(f, "Byte-Size Studio", UDim2.fromOffset(s.X, 18), UDim2.new(0, 0, 0.5, 4), { x = "center", face = "big", color = UIKit.color("accent"), kind = "title", z = 21 })
	title.AnchorPoint = Vector2.new(0, 1)
	UIKit.text(f, "Opening your studio...", UDim2.fromOffset(s.X, 10), UDim2.new(0, 0, 0.5, 26), { x = "center", color = UIKit.color("text_dim"), z = 21 })
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

------------------------------------------------------------------ a new idea
-- Rare and up: a banner drops in at the top (the tier, the idea, its 1 in N, "New!" the first time), with a sound to
-- match and confetti from Epic. Every idea restarts the timer chip's bar.
local function onIdea(msg: { [string]: any })
	rollClock = 0
	local c = msg.card
	if type(c) ~= "table" or not Ideas.valid(c) then
		return
	end
	local tier = if type(msg.tier) == "number" then msg.tier else 1
	if tier < Tuning.RevealTier then
		Audio.play("pop", { volume = 0.5, pitch = 1.2 })
		return
	end
	-- over a panel or the making card the banner would hide it: a line in the status bar (or a toast) instead
	if UIKit.currentPanel() ~= nil or MicroUI.isOpen() then
		UIKit.notice(string.format("%s idea: %s (%s)!", Ideas.tierName(tier), Ideas.name(c), Numbers.oneIn(if type(msg.oneIn) == "number" then msg.oneIn else Ideas.oneIn(c))), UIKit.color(Ideas.tierColor(tier)), 4)
		Audio.play(if tier >= 5 then "rare_fanfare" elseif tier >= 4 then "fanfare" else "sparkle")
		return
	end
	if reveal then
		reveal:Destroy()
		reveal = nil
	end
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local col = UIKit.color(Ideas.tierColor(tier))
	local w = math.min(200, s.X - 16)
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, 44), UDim2.fromOffset(math.floor((s.X - w) / 2), -50), UIKit.color("plate"), 0, 3)
	f.Name = "Reveal"
	f.ZIndex = 8
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), col, 9)
	local holder = UIKit.plate(f, UDim2.fromOffset(24, 24), UDim2.fromOffset(6, 12), UIKit.color("plate_light"), 0, 2)
	holder.ZIndex = 9
	PixelSprites.image(holder, "icon_" .. c.id, UDim2.fromOffset(4, 4), 10)
	UIKit.text(f, string.upper(Ideas.tierName(tier)) .. " IDEA!" .. (if msg.first == true then "  New!" else ""), UDim2.fromOffset(w - 40, 10), UDim2.fromOffset(36, 4), { color = col, z = 9, name = "Tier" })
	UIKit.text(f, Ideas.name(c), UDim2.fromOffset(w - 40, 18), UDim2.fromOffset(36, 14), { face = "big", kind = "title", color = UIKit.color("text"), z = 9, name = "Name" })
	UIKit.text(f, Numbers.oneIn(if type(msg.oneIn) == "number" then msg.oneIn else Ideas.oneIn(c)), UDim2.fromOffset(w - 40, 10), UDim2.fromOffset(36, 32), { color = UIKit.color("text_dim"), z = 9, name = "OneIn" })
	reveal = f
	UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(math.floor((s.X - w) / 2), 22) })
	Audio.play(if tier >= 5 then "rare_fanfare" elseif tier >= 4 then "fanfare" else "sparkle")
	if tier >= 4 then
		task.delay(0.25, function()
			if f.Parent then
				UIKit.confetti(f, if tier >= 5 then 50 else 28)
			end
		end)
	end
	task.delay(if tier >= 5 then 4 else 2.8, function()
		if f.Parent then
			UIKit.tween(f, 0.25, { Position = UDim2.fromOffset(math.floor((s.X - w) / 2), -50) })
			task.wait(0.3)
			f:Destroy()
		end
	end)
end

------------------------------------------------------------------ lifecycle
local function refresh(v: Types.ClientView)
	updateTop(v)
	updateCard(v)
	updateTips(v)
	local key = string.format("%d", v.office)
	if key ~= lastKey then
		lastKey = key
		hudRects()
	end
	if UIKit.currentPanel() ~= nil then
		UIKit.refreshPanel()
	end
	MicroUI.refresh()
end

local function rebuild()
	for _, f in chipFrames do
		f:Destroy()
	end
	table.clear(chips)
	table.clear(chipFrames)
	for _, f in { card, tips, homeButton } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	card, tips, homeButton = nil, nil, nil
	CARD_W = cardWidth()
	lastCoins = nil
	buildTop()
	buildBar()
	local v = StateClient.view()
	if v then
		lastKey = ""
		refresh(v)
	end
end

function Hud.start()
	buildCurtain()
	Menus.init()
	MicroUI.init()
	rebuild()
	StateClient.Changed:Connect(refresh)
	StateClient.Coins:Connect(function(coins: number)
		showCoins(coins)
	end)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "idea" then
			onIdea(msg)
		end
	end)
	UIKit.Resized:Connect(function()
		rebuild()
	end)
	-- a launched game: the team cheers with its income over their heads
	MicroUI.Launched:Connect(function(g: Types.Game)
		WorldView.cheer({ Numbers.rate(g.rate), "Yay!", "Woo!" }, UIKit.color("accent"))
	end)
	-- Build mode has its own tray: the menu bar, the card and the tips step aside
	BuildUI.Changed:Connect(function(on)
		for _, f in { bar, card, tips } :: { GuiObject? } do
			if f then
				f.Visible = not on
			end
		end
	end)
	local lastBeat = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - lastBeat)
		lastBeat = now
		stepEases(dt)
		local v = StateClient.view()
		-- the next idea: its seconds left on the chip, its progress along the bar
		if v then
			rollClock = math.min(v.rollEvery, rollClock + dt)
			local l = chips.idea
			if l then
				UIKit.setText(l, string.format("Idea in %.1fs", math.max(0, v.rollEvery - rollClock)))
			end
			local ib = ideaBar
			local chipF = chipFrames.idea
			if ib and ib.Parent and chipF then
				ib.Size = UDim2.fromOffset(math.floor((chipF.Size.X.Offset - 6) * rollClock / math.max(0.1, v.rollEvery)), 1)
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
		-- the card's main button pulses when it is the thing to do
		local c = card
		if c then
			local pulse = (math.sin(now * 5) + 1) / 2
			for _, b in c:GetChildren() do
				if b:IsA("TextButton") and b:GetAttribute("Pulse") == true and b.AutoButtonColor then
					local base = if b.Name == "CardPlay" then UIKit.color("accent") else UIKit.color("button_ok")
					UIKit.setButtonColor(b, base:Lerp(UIKit.color("button_warn"), pulse * 0.7))
				end
			end
		end
		local hb = homeButton
		if hb then
			local show = not atHome() and not BuildUI.isOpen()
			if hb.Visible ~= show then
				hb.Visible = show
			end
		end
	end)
	local _ = Words
end

return Hud
