--!strict
-- The HUD (docs/ARCHITECTURE.md 10.3; GAME_DESIGN 3-9): the chips along the top (wood, shells, the day and its clock),
-- the menu bar along the bottom (Build, Driftlings, Index, Looks), the island card on the right (the island's name,
-- driftlings in huts and their room, visitors, charm, what it makes) with the Tree of Life's card under it (the time to
-- its next eggs, its best few eggs with their prices to hatch them), the questline's card, the tips banner, the new
-- day's banner and the alerts for a new lot of eggs (the loading card is src/first's). The camera fits the
-- island clear of the HUD's blocks (CameraController.setHudRects).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
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
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Words = require(script.Parent.Words)
local Menus = require(script.Parent.Menus)
local BuildUI = require(script.Parent.BuildUI)

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
local treeCard: Frame? = nil -- the Tree of Life's card (GAME_DESIGN 6)
local tips: Frame? = nil
local quest: Frame? = nil -- the questline's card (GAME_DESIGN 9)
local QUEST_W = 150
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
	x = chip("wood", x, 56, "wood")
	x = chip("shells", x, 56, "shell")
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
	showStore("wood", v.wood, last.wood == nil)
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
	{ text = "Driftlings", panel = "pals", icon = "pal" },
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
			else
				UIKit.openPanel(m.panel)
			end
		end, {
			name = "Menu_" .. m.panel,
			color = if m.panel == "build" then UIKit.color("button_warn") else nil,
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
	return string.format("%d|%d/%d|%.1f|%d|%d|%d", v.tier, housedOf(v), v.nests, v.visitors, math.floor(v.charm), math.floor(v.rates.wood + 0.5), math.floor(v.rates.shells + 0.5))
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
	local h = 3 + 12 + 3 * LINE_H + 4 + 2 * LINE_H + 3
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - 7, CARD_Y), UIKit.color("plate"), 0.04, 3, { shadow = true, wood = 3 })
	f.Name = "IslandCard"
	local plan = Office.plans[v.tier]
	-- the island's name on a plank across the top
	UIKit.plank(f, 11, 3)
	UIKit.text(f, if plan then plan.name else "Your island", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("paper"), kind = "shadow", z = 4, name = "Title" })
	local y = 15
	local housed = housedOf(v)
	line(f, "pal", "In huts", y, w, nil, string.format("%d/%d", housed, v.nests), if housed >= v.nests and v.nests > 0 then UIKit.color("orange") else nil, "Pals")
	y += LINE_H
	line(f, "visitor", "Visitors", y, w, nil, string.format("%.1f", v.visitors), nil, "Visitors")
	y += LINE_H
	line(f, "charm", "Charm", y, w, nil, Numbers.int(math.floor(v.charm)), UIKit.color("pink"), "Charm")
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
	rate("wood", v.rates.wood, "Wood")
	rate("shell", v.rates.shells, "Shells")
	f:SetAttribute("Key", key)
	f.Visible = not BuildUI.isOpen()
	card = f
end

------------------------------------------------------------------ the tree's card
-- Under the island card (GAME_DESIGN 6): the Tree of Life's name and Open (its panel), how long till it lays its next
-- eggs (a bar running down: Heartbeat runs it on from StateClient.clutchLeft), then its best few eggs (EggView.best:
-- the rarest, and one the shells cover if none of those is): each one's egg, its rarity's name in its colour and its
-- price on a button that hatches it (EggView.hatch; green when the shells are there). On a phone only the best (the
-- card sits over the quest's, which must clear the menu bar).
local TREE_ROW = 15
local treeBar: Frame? = nil
local treeTime: TextLabel? = nil
local function clock(secs: number): string
	local s = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", s // 60, s % 60)
end
local function updateTree(v: Types.ClientView)
	local shown = EggView.best(v, if UIKit.phone() then 1 else 3)
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
	local rows = math.max(1, #shown)
	local h = 26 + rows * TREE_ROW + 1
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(s.X - w - 7, CARD_Y), UIKit.color("plate"), 0.04, 3, { shadow = true, wood = 3 })
	f.Name = "TreeCard"
	UIKit.plank(f, 11, 3)
	PixelSprites.image(f, "mini_tree", UDim2.fromOffset(3, 1), 4)
	UIKit.text(f, if UIKit.phone() then "Eggs" else "Tree of Life", UDim2.fromOffset(w - 56, 10), UDim2.fromOffset(16, 1), { color = UIKit.color("paper"), kind = "shadow", z = 4, name = "Title" })
	UIKit.button(f, "Open", UDim2.fromOffset(34, 10), UDim2.fromOffset(w - 37, 1), function()
		UIKit.openPanel("tree")
	end, { name = "TreeOpen", color = UIKit.color("button_ok") }).ZIndex = 5
	-- (how long till the next eggs: the time and a bar running down)
	treeTime = UIKit.text(f, "New eggs in 0:00", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 13), { color = UIKit.color("text_dim"), z = 4, name = "TreeNext" })
	local back = UIKit.rect(f, UDim2.fromOffset(w - 8, 3), UDim2.fromOffset(4, 23), UIKit.color("ink"), 4)
	back.Name = "TreeBar"
	treeBar = UIKit.rect(back, UDim2.fromOffset(w - 10, 1), UDim2.fromOffset(1, 1), UIKit.color("good"), 5)
	if #shown == 0 then
		UIKit.text(f, "No eggs right now", UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 28), { color = UIKit.color("text_dim"), z = 4 })
	end
	for i, e in shown do
		local rar = Traits.RARITY[e.r] or Traits.RARITY[1]
		local y = 27 + (i - 1) * TREE_ROW
		local cost = e.cost or 0
		local text = Numbers.coins(cost)
		local bw = math.max(34, UIKit.textWidth(text) + 18)
		PixelSprites.image(f, "egg_" .. math.clamp(e.r, 1, 5), UDim2.fromOffset(3, y), 4).Name = "EggIcon_" .. e.id
		UIKit.text(f, rar.name, UDim2.fromOffset(w - bw - 22, 10), UDim2.fromOffset(17, y + 2), { color = UIKit.color(rar.color), z = 4, name = "EggName_" .. e.id })
		local can = v.shells >= cost
		local id = e.id
		local b = UIKit.button(f, text, UDim2.fromOffset(bw, 12), UDim2.fromOffset(w - bw - 4, y + 1), function()
			EggView.hatch(id)
		end, { name = "CardHatch_" .. e.id, color = if can then UIKit.color("button_ok") else UIKit.color("plate_light") })
		b.ZIndex = 5
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(2, 0)
			words.Size = UDim2.new(1, -16, 1, 0)
		end
		PixelSprites.image(b, "mini_shell", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
	end
	f:SetAttribute("Key", key)
	treeCard = f
end

-- The cards stack down the right edge (on a phone the tree's card sits on the left, clear of the jump button).
local function stack()
	local s = UIKit.size("Hud")
	local c, e = card, treeCard
	-- (the tree's wide panel covers the cards but a sliver: they step aside for it too)
	local hide = BuildUI.isOpen() or UIKit.currentPanel() == "tree"
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
	-- the quest's card down the left under the chips (under the tree's card on a phone); it steps aside for a panel
	local qf = quest
	if qf then
		qf.Visible = not (BuildUI.isOpen() or UIKit.currentPanel() ~= nil)
		local y = CARD_Y
		if UIKit.phone() and e and e.Visible then
			y = e.Position.Y.Offset + e.Size.Y.Offset + 7
		end
		qf.Position = UDim2.fromOffset(7, y)
	end
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
			for _, it in { { "wood", "wood" }, { "shells", "shells" } } do
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(7, CARD_Y), UIKit.color("plate"), 0.05, 2, { bevel = true, wood = 2 })
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
		for _, it in { { "wood", "wood" }, { "shells", "shell" } } do
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
		local back = UIKit.rect(f, UDim2.fromOffset(bw, 4), UDim2.fromOffset(5, y + 4), UIKit.color("ink"), 3)
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
	[1] = "Wood pays for everything you build. Tap Build and place a Lumber Camp.",
	[2] = "Shells hatch eggs. Place a Veggie Patch. It sells what it grows.",
	[3] = "Driftlings need somewhere to live. Place a Driftling Hut.",
	[4] = "The Tree of Life laid eggs round its roots. Tap one to hatch it.",
	[5] = "Visitors buy snacks too. Place a Snack Stall for more shells.",
	[6] = "The tree lays new eggs every few minutes. When the huts are full, swap a weak one for a better one.",
}
-- in Build mode (the tray already on the right tab, the building pulsing)
local TIPS_BUILD: { [number]: string } = {
	[1] = "Place a Lumber Camp. Wood pays for everything you build.",
	[2] = "Place a Veggie Patch. It sells its veggies for shells.",
	[3] = "Place a Driftling Hut. Driftlings live there and go to work.",
	[5] = "Place a Snack Stall. Visitors buy snacks there.",
}

-- The tip's banner sits over the menu bar, or over the build tray in Build mode (the tips show there too).
local function tipsLift(): number
	return if BuildUI.isOpen() then BuildUI.trayHeight() + 12 else BAR_H + 2 * DOCK + 8
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
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, -h - 10), UIKit.color("plate"), 0, 3, { shadow = true, wood = 3 })
	f.Name = "DayBanner"
	f.ZIndex = 8
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), UIKit.color("accent"), 9)
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
-- it's named (its rarity's colour, a burst on the tree's card).
local function onEggs(msg: { [string]: any })
	if type(msg.laid) ~= "table" then
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
		UIKit.notice("The Tree of Life laid new eggs.", UIKit.color("good"), 3)
		Audio.play("rare")
	end
end

local function refresh(v: Types.ClientView)
	updateTop(v)
	updateCard(v)
	updateTree(v)
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
	for _, f in { card, treeCard, tips, quest, homeButton, musicButton } :: { Instance? } do
		if f then
			f:Destroy()
		end
	end
	card, treeCard, tips, quest, homeButton, dayBar, musicButton = nil, nil, nil, nil, nil, nil, nil
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
	Menus.init()
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
		-- the background music: easygoing island tunes by day, softer ones from the twilight; the note in the corner
		-- switches it off and on
		local f = DayLight.frac()
		Audio.music(if f >= 0.74 or f < 0.02 then "night" else "day")
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
		-- jumping on the island: held while the build tray or a panel is up (the phone's jump button hides with it,
		-- clear of the tray's and the panels' buttons)
		local char = Players.LocalPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			local want = if BuildUI.isOpen() or UIKit.currentPanel() ~= nil then 0 else Tuning.JumpHeight
			if hum.JumpHeight ~= want then
				hum.JumpHeight = want
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
end

return Hud
