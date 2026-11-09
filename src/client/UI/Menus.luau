--!strict
-- The HUD's panels (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 4-9): Ideas (the idea board: pick three, make a game),
-- Index (every idea and modifier the team has thought of), Upgrades (roll speed and luck), Games (the launched games
-- and their income) and Looks (the founder's look). Every action is a request; the panel rebuilds from the next view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local IdeasData = require(ReplicatedStorage.Shared.Data.Ideas)
local Modifiers = require(ReplicatedStorage.Shared.Data.Modifiers)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Ideas = require(ReplicatedStorage.Shared.Logic.Ideas)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)
local Live = require(ReplicatedStorage.Shared.Logic.Live)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local MicroUI = require(script.Parent.MicroUI)
local Words = require(script.Parent.Words)
local SalesGraph = require(script.Parent.SalesGraph)

local Menus = {}

-- Ask the server; tell the player when it says no.
local function ask(action: string, payload: { [string]: any }?, ok: string?): Types.Response
	local res = StateClient.request(action, payload)
	if res.ok then
		if ok then
			UIKit.notice(ok, UIKit.color("good"))
		end
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
	return res
end

local function row(list: Instance, order: number, h: number): Frame
	local f = UIKit.plate(list, UDim2.new(1, -6, 0, h), nil, UIKit.color("plate_light"), 0, 2)
	f.Name = "Row"
	f.LayoutOrder = order
	return f
end

-- An idea's 16 px icon; its dark silhouette (the same outline) when `known` is false.
local function icon(parent: Instance, id: string, pos: UDim2, known: boolean?): GuiObject?
	local name = "icon_" .. id
	if not PixelSprites.has(name) then
		return nil
	end
	return PixelSprites.image(parent, if known == false then name .. "_sil" else name, pos, 4)
end

------------------------------------------------------------------ Ideas: the board
local picked: { number } = {} -- board indices, in the order picked
local pickedKeys: { string } = {}

local function validPicks(v: Types.ClientView)
	for i = #picked, 1, -1 do
		local c = v.ideas[picked[i]]
		if c == nil or Ideas.key(c) ~= pickedKeys[i] then
			table.remove(picked, i)
			table.remove(pickedKeys, i)
		end
	end
end

local function buildIdeas(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	validPicks(v)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local proj = v.project
	if proj then
		UIKit.text(body, "You're making " .. proj.title .. ". Finish it to make the next one.", UDim2.fromOffset(W - 70, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Making" })
		UIKit.button(body, "Continue", UDim2.fromOffset(64, 12), UDim2.fromOffset(W - 64, 0), function()
			UIKit.closePanel()
			MicroUI.open()
		end, { name = "Continue", color = UIKit.color("button_ok") })
	elseif v.live and not Live.over(v.live) then
		-- one game sells at a time: a new one takes the one on sale off
		local l = v.live :: Types.Live
		UIKit.text(body, string.format("Making a game takes %s off sale (%s players now)", l.title, Numbers.int(l.players)), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("orange"), name = "Hint" })
	else
		UIKit.text(body, string.format("Pick three ideas to make a game. Board %d/%d", #v.ideas, Tuning.BoardSize), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Hint" })
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - 46), UDim2.fromOffset(0, 14))
	local cols = if W >= 290 then 3 else 2
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 30)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	if #v.ideas == 0 then
		UIKit.text(list, "No ideas yet: your team is thinking.", UDim2.fromOffset(W - 8, 12), nil, { color = UIKit.color("text_dim") })
	end
	for i, c in v.ideas do
		local tier = Ideas.tier(c)
		local mod = Modifiers.byId[c.mod]
		local def = IdeasData.byId[c.id]
		local order = table.find(picked, i)
		local b = Instance.new("TextButton")
		b.Name = "Pick_" .. i
		b.Text = ""
		b.AutoButtonColor = proj == nil
		b.BackgroundTransparency = 1
		b.LayoutOrder = i
		b.ZIndex = 3
		local plate = UIKit.plate(b, UDim2.fromScale(1, 1), nil, if order then UIKit.color("plate") else UIKit.color("plate_light"), 0, 2)
		plate.ZIndex = 3
		UIKit.rect(b, UDim2.new(0, 2, 1, -4), UDim2.fromOffset(1, 2), UIKit.color(Ideas.tierColor(tier)), 4)
		icon(b, c.id, UDim2.fromOffset(5, 7))
		UIKit.text(b, if def then def.name else "?", UDim2.new(1, -26, 0, 10), UDim2.fromOffset(24, 1), { color = UIKit.color("text"), z = 4 })
		UIKit.text(b, if mod then mod.name else "", UDim2.new(1, -26, 0, 10), UDim2.fromOffset(24, 10), { color = UIKit.color(if mod then mod.color else "text_dim"), z = 4 })
		UIKit.text(b, Numbers.oneIn(Ideas.oneIn(c)), UDim2.new(1, -26, 0, 10), UDim2.fromOffset(24, 19), { color = UIKit.color(Ideas.tierColor(tier)), z = 4 })
		if order then
			UIKit.plate(b, UDim2.fromOffset(11, 11), UDim2.new(1, -13, 0, 2), UIKit.color("accent"), 0, 1).ZIndex = 5
			UIKit.text(b, tostring(order), UDim2.fromOffset(11, 11), UDim2.new(1, -13, 0, 2), { x = "center", color = UIKit.color("ink"), kind = "plain", z = 6 })
		end
		b.Activated:Connect(function()
			if proj then
				return
			end
			local k = table.find(picked, i)
			if k then
				table.remove(picked, k)
				table.remove(pickedKeys, k)
			elseif #picked < 3 then
				table.insert(picked, i)
				table.insert(pickedKeys, Ideas.key(c))
				UIKit.burstOn(b, { Ideas.tierColor(tier), "white" }, 8, 35)
			else
				Audio.play("deny")
				return
			end
			Audio.play("flip")
			UIKit.refreshPanel()
		end)
		b.Parent = list
	end
	-- the game these three would make
	local ready = proj == nil and #picked == 3
	local cards: { Types.Card } = {}
	for _, k in picked do
		table.insert(cards, v.ideas[k])
	end
	local preview = if #cards > 0 then string.format("%d/3 picked: peaks at about %s, up to %s with three wins", #cards, Numbers.rate(Ideas.rate(cards, 0)), Numbers.rate(Ideas.rate(cards, 3))) else "Each idea brings a minigame. Rarer ideas sell more and play harder."
	UIKit.text(body, preview, UDim2.fromOffset(W, 12), UDim2.fromOffset(0, H - 30), { color = if ready then UIKit.color("good") else UIKit.color("text_dim"), name = "Preview" })
	UIKit.button(body, if ready then "Make this game!" else "Pick three ideas", UDim2.fromOffset(W, 14), UDim2.fromOffset(0, H - 16), function()
		local a, b, c = picked[1], picked[2], picked[3]
		local res = ask("game.make", { a = a, b = b, c = c })
		if res.ok then
			local mk = body:FindFirstChild("Make")
			if mk and mk:IsA("GuiObject") then
				UIKit.burstOn(mk, { "good", "accent", "white", "fun", "ideas" }, 22, 60)
			end
			table.clear(picked)
			table.clear(pickedKeys)
			UIKit.closePanel()
			Audio.play("level_up")
			MicroUI.open()
		end
	end, { name = "Make", color = UIKit.color("button_ok"), enabled = ready })
end

------------------------------------------------------------------ Index: the discoveries
local function buildIndex(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local total = #IdeasData.list * #Modifiers.list
	local found = 0
	for _, n in v.found do
		if n > 0 then
			found += 1
		end
	end
	UIKit.text(body, string.format("Found %d of %d   Rarest: %s", found, total, if v.stats.best > 0 then Numbers.oneIn(v.stats.best) else "-"), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Found" })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - 14), UDim2.fromOffset(0, 14))
	local cols = if W >= 300 then 4 elseif W >= 220 then 3 else 2
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 32)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, d in IdeasData.list do
		local known = false
		for _, m in Modifiers.list do
			if (v.found[d.id .. "|" .. m.id] or 0) > 0 then
				known = true
			end
		end
		local f = UIKit.plate(list, UDim2.fromOffset(60, 32), nil, UIKit.color("plate_light"), 0, 2)
		f.Name = "Entry_" .. d.id
		f.LayoutOrder = i
		icon(f, d.id, UDim2.fromOffset(4, 4), known)
		UIKit.text(f, if known then d.name else "???", UDim2.new(1, -24, 0, 10), UDim2.fromOffset(22, 1), { color = if known then UIKit.color("text") else UIKit.color("text_dim"), z = 4 })
		UIKit.text(f, Numbers.oneIn(d.odds), UDim2.new(1, -24, 0, 10), UDim2.fromOffset(22, 10), { color = UIKit.color(Ideas.tierColor(Ideas.tierOf(d.odds))), z = 4 })
		-- a dot a modifier: lit in its colour once found with this idea
		for k, m in Modifiers.list do
			local on = (v.found[d.id .. "|" .. m.id] or 0) > 0
			UIKit.rect(f, UDim2.fromOffset(3, 3), UDim2.fromOffset(22 + (k - 1) * 5, 24), if on then UIKit.color(m.color) else UIKit.color("plate"), 4)
		end
	end
	-- the modifiers' key
	local key = UIKit.plate(list, UDim2.fromOffset(60, 32), nil, UIKit.color("plate"), 0, 2)
	key.Name = "Key"
	key.LayoutOrder = #IdeasData.list + 1
	UIKit.text(key, "Dots:", UDim2.new(1, -4, 0, 10), UDim2.fromOffset(3, 1), { color = UIKit.color("text_dim"), z = 4 })
	for k, m in Modifiers.list do
		UIKit.rect(key, UDim2.fromOffset(3, 3), UDim2.fromOffset(4 + (k - 1) * 8, 14), UIKit.color(m.color), 4)
	end
	UIKit.text(key, "Plain..Cosmic", UDim2.new(1, -4, 0, 10), UDim2.fromOffset(3, 20), { color = UIKit.color("text_dim"), z = 4 })
end

------------------------------------------------------------------ Upgrades: the idea team
local upgradeButtons: { [string]: TextButton } = {}

local function costOf(v: Types.ClientView, k: string): number?
	if k == "speed" and Studio.rollEvery({ upgrades = v.upgrades } :: any) <= Tuning.RollMin then
		return nil
	end
	return Studio.upgradeCost(k, if k == "speed" then v.upgrades.speed else v.upgrades.luck)
end

local function buildUpgrades(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W = UIKit.bodyWidth(body)
	table.clear(upgradeButtons)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, UIKit.bodyHeight(body)), nil)
	UIKit.vlist(list, 3)
	local items = {
		{
			k = "speed",
			title = "Faster ideas",
			level = v.upgrades.speed,
			now = string.format("An idea every %.1fs", v.rollEvery),
			next = string.format("then every %.1fs", math.max(Tuning.RollMin, v.rollEvery * Tuning.RollStep)),
		},
		{
			k = "luck",
			title = "Lucky ideas",
			level = v.upgrades.luck,
			now = string.format("Luck x%.1f: rare ideas come more often", v.luck),
			next = string.format("then x%.1f", v.luck + Tuning.LuckStep),
		},
	}
	for i, it in items do
		local f = row(list, i, 40)
		UIKit.text(f, it.title, UDim2.new(1, -90, 0, 10), UDim2.fromOffset(5, 3), { color = UIKit.color("accent"), z = 4 })
		UIKit.text(f, "Lv " .. it.level, UDim2.fromOffset(40, 10), UDim2.new(1, -130, 0, 3), { x = "right", color = UIKit.color("text_dim"), z = 4 })
		UIKit.text(f, it.now, UDim2.new(1, -90, 0, 10), UDim2.fromOffset(5, 14), { color = UIKit.color("text"), z = 4 })
		local cost = costOf(v, it.k)
		UIKit.text(f, if cost then it.next else "maxed out", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(5, 25), { color = UIKit.color("text_dim"), z = 4 })
		local b = UIKit.button(f, if cost then Numbers.coins(cost) .. " coins" else "Max", UDim2.fromOffset(80, 16), UDim2.new(1, -84, 0, 12), function()
			local res = ask("upgrade.buy", { k = it.k })
			if res.ok then
				Audio.play("level_up")
				local bb = upgradeButtons[it.k]
				if bb then
					UIKit.burstOn(bb, { "good", "accent", "white" }, 18, 50)
					UIKit.popText(bb.Parent or body, bb.Position.X.Offset + 40, 0, "Level up!", UIKit.color("good"))
				end
			end
		end, { name = "Buy_" .. it.k, color = UIKit.color("button_ok"), enabled = cost ~= nil and v.coins >= cost })
		b.ZIndex = 4
		upgradeButtons[it.k] = b
	end
	local f = row(list, 3, 24)
	UIKit.text(f, "Rarer ideas earn more coins and play harder minigames. Coins also buy decor in Build.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), wrap = true, z = 4 })
end

------------------------------------------------------------------ Games: the launched games
local function buildGames(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	UIKit.text(body, string.format("%d games made, %s coins earned", v.stats.games, Numbers.coins(v.stats.earned)), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Total" })
	-- the game on sale: its players' graph, Game Dev Tycoon style, and its numbers
	local top = 14
	local l = v.live
	if l then
		local over = Live.over(l)
		UIKit.text(body, (if over then "Off sale: " else "On sale: ") .. l.title, UDim2.fromOffset(W, 10), UDim2.fromOffset(0, top), { color = UIKit.color(if over then "text_dim" else "accent"), name = "LiveTitle" })
		local gh = 44
		local graph = SalesGraph.new(body, W, gh, 4)
		graph.frame.Position = UDim2.fromOffset(0, top + 11)
		graph.set(l)
		local left = math.max(0, l.life - l.age)
		local stats = if over
			then string.format("Made %s coins. Peak: %s players", Numbers.coins(l.earned), Numbers.int(l.peak))
			else string.format("%s players  %s  Peak %s  Made %s  %d:%02d left", Numbers.int(l.players), Numbers.rate(v.rate), Numbers.int(l.peak), Numbers.coins(l.earned), math.floor(left / 60), math.floor(left % 60))
		UIKit.text(body, stats, UDim2.fromOffset(W, 10), UDim2.fromOffset(0, top + 12 + gh), { color = UIKit.color("good"), name = "LiveStats" })
		top += 24 + gh
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	if #v.games == 0 then
		UIKit.text(list, "No games yet: make one from the idea board.", UDim2.fromOffset(W - 8, 12), nil, { color = UIKit.color("text_dim") })
	end
	for i = #v.games, 1, -1 do
		local g = v.games[i]
		local f = row(list, #v.games - i, 24)
		local onSale = l ~= nil and l.id == g.id
		local peak = if onSale and l then l.peak else g.peak
		local made = if onSale and l then l.earned else g.earned
		UIKit.text(f, g.title, UDim2.new(1, -110, 0, 10), UDim2.fromOffset(5, 2), { color = UIKit.color(if onSale then "accent" else "text"), z = 4 })
		UIKit.text(f, string.format("%s coins", Numbers.coins(made)), UDim2.fromOffset(100, 10), UDim2.new(1, -104, 0, 2), { x = "right", color = UIKit.color("good"), z = 4 })
		local names = {}
		for _, c in g.ideas do
			table.insert(names, Ideas.name(c))
		end
		UIKit.text(f, table.concat(names, " + "), UDim2.new(1, -110, 0, 10), UDim2.fromOffset(5, 12), { color = UIKit.color("text_dim"), z = 4 })
		UIKit.text(f, string.format("peak %s  %s", Numbers.short(peak), string.rep("*", g.wins) .. string.rep("-", 3 - g.wins)), UDim2.fromOffset(100, 10), UDim2.new(1, -104, 0, 12), { x = "right", color = UIKit.color("accent"), z = 4 })
	end
end

------------------------------------------------------------------ Looks: the founder
local draft: Types.Look? = nil
local LOOK_ROWS: { { key: string, label: string, n: number } } = {
	{ key = "skin", label = "Skin", n = #Looks.skin },
	{ key = "hair", label = "Hair", n = #Looks.hair },
	{ key = "style", label = "Style", n = #Looks.styles },
	{ key = "shirt", label = "Shirt", n = #Looks.shirt },
}

local function buildLooks(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local d: Types.Look = draft or table.clone(v.founder)
	draft = d
	UIKit.portrait(body, d, 48, UDim2.fromOffset(4, 4))
	for i, r in LOOK_ROWS do
		local y = (i - 1) * 16
		UIKit.text(body, r.label, UDim2.fromOffset(40, 12), UDim2.fromOffset(64, y), { color = UIKit.color("text") })
		local function step(delta: number)
			local cur = (d :: any)[r.key] :: number
			;(d :: any)[r.key] = (cur - 1 + delta) % r.n + 1
			Audio.play("flip")
			UIKit.refreshPanel()
		end
		UIKit.button(body, "<", UDim2.fromOffset(14, 12), UDim2.fromOffset(106, y), function()
			step(-1)
		end, { name = "Prev_" .. r.key, color = UIKit.color("plate_light") })
		UIKit.text(body, string.format("%d/%d", (d :: any)[r.key], r.n), UDim2.fromOffset(30, 12), UDim2.fromOffset(122, y), { x = "center", color = UIKit.color("text_dim") })
		UIKit.button(body, ">", UDim2.fromOffset(14, 12), UDim2.fromOffset(154, y), function()
			step(1)
		end, { name = "Next_" .. r.key, color = UIKit.color("plate_light") })
	end
	UIKit.button(body, "Save look", UDim2.fromOffset(104, 14), UDim2.fromOffset(64, 66), function()
		local res = ask("founder.set", { skin = d.skin, hair = d.hair, style = d.style, shirt = d.shirt }, "Looking good!")
		if res.ok then
			Audio.play("reward")
		end
	end, { name = "SaveLook", color = UIKit.color("button_ok") })
end

function Menus.init()
	UIKit.registerPanel("ideas", { title = "Idea board", w = 320, h = 186, build = buildIdeas })
	UIKit.registerPanel("index", { title = "Index", w = 320, h = 186, build = buildIndex })
	UIKit.registerPanel("upgrades", { title = "Upgrades", w = 300, h = 140, build = buildUpgrades })
	UIKit.registerPanel("games", { title = "Games", w = 320, h = 170, build = buildGames })
	UIKit.registerPanel("looks", { title = "Looks", w = 200, h = 106, build = buildLooks })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= "looks" then
			draft = nil
		end
		if name ~= "ideas" then
			table.clear(picked)
			table.clear(pickedKeys)
		end
	end)
	-- the income ticks: the upgrade buttons follow the coins without rebuilding the panel
	StateClient.Coins:Connect(function(coins: number)
		local v = StateClient.view()
		if v == nil or UIKit.currentPanel() ~= "upgrades" then
			return
		end
		for k, b in upgradeButtons do
			if b.Parent then
				local cost = costOf(v, k)
				UIKit.setEnabled(b, cost ~= nil and coins >= cost)
			end
		end
	end)
end

return Menus
