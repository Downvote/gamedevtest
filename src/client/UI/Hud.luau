--!strict
-- The HUD (docs/ARCHITECTURE.md 10.3; GAME_DESIGN 2, 9): the chips along the top (the date, money, fans, research),
-- the menu bar along the bottom (New game, Staff, Research, Office, Games), the project card on the right while a
-- game is in the works, the tips banner, the loading curtain until the first picture, and the week's notices.
-- The camera fits the office clear of the HUD's blocks (CameraController.setHudRects).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Genres = require(ReplicatedStorage.Shared.Data.Genres)
local Topics = require(ReplicatedStorage.Shared.Data.Topics)
local Platforms = require(ReplicatedStorage.Shared.Data.Platforms)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Dev = require(ReplicatedStorage.Shared.Logic.Dev)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local Menus = require(script.Parent.Menus)
local ReviewUI = require(script.Parent.ReviewUI)
local BuildUI = require(script.Parent.BuildUI)

local Hud = {}

local TOP_H = 13
local BAR_H = 15
local CARD_W = 124 -- the project card's width (100 on phones: no bars, the numbers only)

local function cardWidth(): number
	return if UIKit.phone() then 100 else 124
end

local chips: { [string]: TextLabel } = {}
local chipFrames: { [string]: Frame } = {}
local bar: Frame? = nil
local card: Frame? = nil
local cardParts: { [string]: any } = {}
local tips: Frame? = nil
local curtain: Frame? = nil
local homeButton: TextButton? = nil
local lastKey = ""

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
		-- a phone (Random Bakery's rule): only Roblox's top bar and the menu bar are kept clear, so the office fills the
		-- screen; the chips and the card may overlap its margins
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y },
			r(math.floor(s.X / 2) - 140, s.Y - BAR_H - 3, math.floor(s.X / 2) + 140, s.Y),
		}
	else
		list = {
			{ x0 = 0, y0 = 0, x1 = s.X * K, y1 = o.Y + (TOP_H + 3) * K },
			r(0, s.Y - BAR_H - 3, s.X, s.Y),
		}
		-- the card's place is kept whether a game is in the works or not, so the view never moves when one starts
		table.insert(list, r(s.X - CARD_W - 3, TOP_H + 2, s.X, TOP_H + 2 + 104))
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
	x = chip("date", x, 64, UIKit.color("text_dim"))
	x = chip("money", x, 60, UIKit.color("good"))
	x = chip("fans", x, 58, UIKit.color("fun"))
	x = chip("rp", x, 50, UIKit.color("ideas"))
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

local function updateTop(v: Types.ClientView)
	UIKit.setText(chips.date, Calendar.label(v.week) .. (if v.paused then " II" else ""))
	UIKit.setText(chips.money, Numbers.money(v.money))
	UIKit.setTextColor(chips.money, if v.money < 0 then UIKit.color("bad") else UIKit.color("text"))
	UIKit.setText(chips.fans, Numbers.short(v.fans) .. " fans")
	UIKit.setText(chips.rp, tostring(v.rp) .. " RP")
end

-- "+$1.2K" floating up from the money chip (a week's sales).
local function moneyPop(amount: number)
	local f = chipFrames.money
	if not f or amount == 0 then
		return
	end
	local canvas = UIKit.canvas("Hud")
	local text = (if amount > 0 then "+" else "-") .. Numbers.money(math.abs(amount))
	local w = UIKit.textWidth(text) + 4
	local x, y = f.Position.X.Offset + 6, f.Position.Y.Offset + TOP_H + 1
	local l = UIKit.text(canvas, text, UDim2.fromOffset(w, 10), UDim2.fromOffset(x, y), {
		color = if amount > 0 then UIKit.color("good") else UIKit.color("bad"),
		kind = "outline",
		name = "MoneyPop",
	})
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 1.6 or l.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			l:Destroy()
			return
		end
		l.Position = UDim2.fromOffset(x, y + math.floor(math.min(t, 1) * 8))
	end)
end

------------------------------------------------------------------ the menu bar
local MENUS: { { text: string, panel: string } } = {
	{ text = "New game", panel = "newgame" },
	{ text = "Staff", panel = "staff" },
	{ text = "Research", panel = "research" },
	{ text = "Office", panel = "office" },
	{ text = "Games", panel = "games" },
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
			color = if m.panel == "newgame" then UIKit.color("button_ok") elseif m.panel == "build" then UIKit.color("button_warn") else nil,
		})
		b.ZIndex = 2
		x += w + 3
	end
	bar = f
end

local function updateBar(v: Types.ClientView)
	local f = bar
	if f == nil then
		return
	end
	local b = f:FindFirstChild("Menu_newgame")
	if b and b:IsA("TextButton") then
		UIKit.setEnabled(b, v.project == nil)
	end
end

------------------------------------------------------------------ the project card
local function buildCard()
	local phone = UIKit.phone()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local f = UIKit.plate(canvas, UDim2.fromOffset(CARD_W, 104), UDim2.fromOffset(s.X - CARD_W - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
	f.Name = "ProjectCard"
	local p: { [string]: any } = {}
	p.title = UIKit.text(f, "", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent"), name = "Title" })
	p.sub = UIKit.text(f, "", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 12), { color = UIKit.color("text_dim"), name = "Sub" })
	p.phase = UIKit.text(f, "", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 22), { name = "Phase" })
	local _, setProgress = UIKit.bar(f, UDim2.fromOffset(CARD_W - 8, 3), UDim2.fromOffset(4, 33), UIKit.color("accent"))
	p.progress = setProgress
	p.rows = {}
	for i, axis in Dev.AXES do
		local y = 38 + (i - 1) * 10
		UIKit.text(f, Dev.AXIS_NAMES[axis], UDim2.fromOffset(48, 10), UDim2.fromOffset(4, y), { color = UIKit.color(axis) })
		local value = UIKit.text(f, "0", UDim2.fromOffset(28, 10), UDim2.fromOffset(CARD_W - 32, y), { x = "right", name = "Value_" .. axis })
		local setBar = function(_: number) end
		if not phone then
			local _, sb = UIKit.bar(f, UDim2.fromOffset(CARD_W - 90, 3), UDim2.fromOffset(52, y + 4), UIKit.color(axis), UIKit.color("plate_light"))
			setBar = sb
		end
		p.rows[axis] = { value = value, bar = setBar }
	end
	p.bugs = UIKit.text(f, "", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 78), { name = "Bugs" })
	p.release = UIKit.button(f, "Release!", UDim2.fromOffset(CARD_W - 8, 13), UDim2.fromOffset(4, 89), function()
		ReviewUI.release()
	end, { color = UIKit.color("button_ok"), name = "Release" })
	card = f
	cardParts = p
end

-- With no game in the works the card's place shows the games on sale and their last week.
local salesCard: Frame? = nil
local function updateSales(v: Types.ClientView)
	if salesCard then
		salesCard:Destroy()
		salesCard = nil
	end
	if v.project ~= nil then
		return
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local selling = {}
	for i = #v.releases, 1, -1 do
		local r = v.releases[i]
		if r.onSale then
			table.insert(selling, r)
		end
	end
	local rows = math.min(#selling, 5)
	local h = 26 + math.max(1, rows) * 10
	local f = UIKit.plate(canvas, UDim2.fromOffset(CARD_W, h), UDim2.fromOffset(s.X - CARD_W - 3, TOP_H + 4), UIKit.color("plate"), 0.06, 3)
	f.Name = "SalesCard"
	UIKit.text(f, "On sale", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent") })
	if rows == 0 then
		UIKit.text(f, "Nothing yet", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, 13), { color = UIKit.color("text_dim") })
	end
	for i = 1, rows do
		local r = selling[i]
		local y = 3 + i * 10
		UIKit.text(f, r.title, UDim2.fromOffset(CARD_W - 44, 10), UDim2.fromOffset(4, y), { color = UIKit.color("text") })
		UIKit.text(f, if r.weeks == 0 then "new!" else Numbers.short(r.last) .. "/wk", UDim2.fromOffset(40, 10), UDim2.fromOffset(CARD_W - 44, y), { x = "right", color = if r.weeks == 0 then UIKit.color("accent") else UIKit.color("text_dim") })
	end
	UIKit.text(f, "No game in the works", UDim2.fromOffset(CARD_W - 8, 10), UDim2.fromOffset(4, h - 12), { color = UIKit.color("text_dim") })
	salesCard = f
end

local function updateCard(v: Types.ClientView)
	updateSales(v)
	local proj = v.project
	if proj == nil then
		if card then
			card.Visible = false
		end
		return
	end
	if card == nil then
		buildCard()
	end
	local f = card :: Frame
	f.Visible = true
	local p = cardParts
	UIKit.setText(p.title, proj.title)
	local g, t, pl = Genres.byId[proj.genre], Topics.byId[proj.topic], Platforms.byId[proj.platform]
	UIKit.setText(p.sub, (if t then t.name else "?") .. " " .. (if g then g.name else "?") .. " / " .. (if pl then pl.short else "?"))
	if proj.phase == "build" then
		UIKit.setText(p.phase, string.format("Building %d/%d weeks", proj.weeksDone, proj.buildWeeks))
	else
		UIKit.setText(p.phase, if proj.bugs > 0 then "Polishing..." else "Ready to ship!")
	end
	p.progress(Dev.progress(proj))
	local most = 1
	for _, a in Dev.AXES do
		most = math.max(most, (proj.scores :: any)[a])
	end
	for _, a in Dev.AXES do
		local n = (proj.scores :: any)[a] :: number
		UIKit.setText(p.rows[a].value, Numbers.short(n))
		p.rows[a].bar(n / most)
	end
	UIKit.setText(p.bugs, string.format("Bugs: %d", proj.bugs))
	UIKit.setTextColor(p.bugs, if proj.bugs > 0 then UIKit.color("bad") else UIKit.color("good"))
	p.release.Visible = proj.phase == "polish"
end

------------------------------------------------------------------ tips
local TIPS: { [number]: string } = {
	[1] = "Tap New game to make your first game!",
	[2] = "Your crew is working: watch the ideas pop!",
	[3] = "Built! Polishing fixes bugs. Release when you're ready.",
	[4] = "Reviews are in! Hire more crew in Staff.",
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
	curtain = f
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
		curtain = nil
	end)
end

------------------------------------------------------------------ the week's notices
local function onWeek(msg: { [string]: any })
	local events = msg.events
	if type(events) ~= "table" then
		return
	end
	local v = StateClient.view()
	for _, e in events do
		if type(e) ~= "table" then
			continue
		end
		if e.kind == "pay" and (e.amount or 0) > 0 then
			UIKit.notice("Payday: " .. Numbers.money(e.amount or 0) .. " for salaries and rent", UIKit.color("text_dim"))
			moneyPop(-(e.amount or 0))
		elseif e.kind == "broke" then
			UIKit.notice("Out of money! A small Home PC game is free to start.", UIKit.color("bad"), 6)
		elseif e.kind == "built" then
			UIKit.notice((e.title or "The game") .. " is built! Polish it or release it.", UIKit.color("accent"), 5)
		elseif e.kind == "ready" then
			UIKit.notice((e.title or "The game") .. " has no bugs left: ready to ship!", UIKit.color("good"), 5)
		elseif e.kind == "sales" then
			moneyPop(e.amount or 0)
		elseif e.kind == "platform" then
			UIKit.notice("New platform out: " .. (e.title or "?") .. "!", UIKit.color("graphics"), 6)
		elseif e.kind == "candidates" and v and #v.staff < 8 then
			UIKit.notice("New job seekers are waiting in Staff.", UIKit.color("text_dim"))
		elseif e.kind == "award" then
			ReviewUI.award(e)
		end
	end
end

------------------------------------------------------------------ lifecycle
local function refresh(v: Types.ClientView)
	updateTop(v)
	updateBar(v)
	updateCard(v)
	updateTips(v)
	if BuildUI.isOpen() then
		for _, f in { bar, card, salesCard, tips } do
			if f then
				f.Visible = false
			end
		end
	end
	local key = string.format("%d", v.office)
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
	if card then
		card:Destroy()
		card = nil
	end
	if salesCard then
		salesCard:Destroy()
		salesCard = nil
	end
	if tips then
		tips:Destroy()
		tips = nil
	end
	if homeButton then
		homeButton:Destroy()
		homeButton = nil
	end
	CARD_W = cardWidth()
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
	ReviewUI.init()
	rebuild()
	StateClient.Changed:Connect(refresh)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "week" then
			onWeek(msg)
		end
	end)
	UIKit.Resized:Connect(function()
		rebuild()
	end)
	-- full-screen menus hold the clock (the server pauses this player's weeks)
	UIKit.PanelChanged:Connect(function(name)
		StateClient.signal("pause", { key = "menu", on = name ~= nil })
	end)
	-- Build mode has its own tray: the menu bar, the cards and the tips step aside
	BuildUI.Changed:Connect(function(on)
		for _, f in { bar, card, salesCard, tips } do
			if f then
				f.Visible = not on
			end
		end
		if not on then
			local v = StateClient.view()
			if v then
				refresh(v)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		local b = homeButton
		if b then
			local show = not atHome() and not BuildUI.isOpen()
			if b.Visible ~= show then
				b.Visible = show
			end
		end
	end)
end

return Hud
