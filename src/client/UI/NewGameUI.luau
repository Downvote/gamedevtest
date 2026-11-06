--!strict
-- The New game wizard (GAME_DESIGN 6.1; docs/ARCHITECTURE.md 10.4): genre, topic, platform, size and focus, then the
-- title (Shuffle picks another) and the cost, and Start. One page at a time so it fits a phone; Back goes a page back.
-- The server checks everything again (Studio.start).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Genres = require(ReplicatedStorage.Shared.Data.Genres)
local Topics = require(ReplicatedStorage.Shared.Data.Topics)
local Platforms = require(ReplicatedStorage.Shared.Data.Platforms)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Dev = require(ReplicatedStorage.Shared.Logic.Dev)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local UIKit = require(script.Parent.UIKit)

local NewGameUI = {}

type Pick = { step: number, genre: string?, topic: string?, platform: string?, size: string, focus: Types.Axis, seed: number }
local pick: Pick = { step = 1, size = "small", focus = "fun", seed = 0 }

local function reset()
	pick = { step = 1, size = "small", focus = "fun", seed = math.random(0, 999) }
end

local function go(step: number)
	pick.step = step
	UIKit.refreshPanel()
end

-- A grid of choice buttons in the body: returns the next free y.
local function grid(body: Frame, y: number, items: { { text: string, on: boolean, color: Color3?, click: () -> () } }, cellW: number): number
	local bw = UIKit.bodyWidth(body)
	local cols = math.max(1, math.floor((bw + 3) / (cellW + 3)))
	for i, it in items do
		local c, r = (i - 1) % cols, (i - 1) // cols
		UIKit.button(body, it.text, UDim2.fromOffset(cellW, 13), UDim2.fromOffset(c * (cellW + 3), y + r * 16), it.click, { enabled = it.on, color = it.color })
	end
	return y + math.ceil(#items / cols) * 16
end

local function header(body: Frame, text: string, sub: string?)
	UIKit.text(body, text, UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, 0), { color = UIKit.color("text") })
	if sub then
		UIKit.text(body, sub, UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, 10), { color = UIKit.color("text_dim") })
	end
end

local function backButton(body: Frame, to: number)
	UIKit.button(body, "Back", UDim2.fromOffset(34, 12), UDim2.new(0, 0, 1, -12), function()
		go(to)
	end, { color = UIKit.color("plate_light"), name = "Back" })
end

local function matchText(v: Types.ClientView, genre: string, topic: string): (string, Color3)
	local m = v.matches[Dev.matchKey(genre, topic)]
	if m then
		return Dev.MATCH_NAMES[m] .. " match", UIKit.color(m)
	end
	return "Match: ???", UIKit.color("text_dim")
end

local function build(body: Frame)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if v.project ~= nil then
		header(body, "A game is already in the works.", "Release it first.")
		return
	end
	local year = Calendar.year(v.week)
	if pick.step == 1 then
		header(body, "1/5  Pick a genre", "More genres open in Research.")
		local items = {}
		for _, g in Genres.list do
			table.insert(items, {
				text = g.name,
				on = v.genres[g.id] == true,
				click = function()
					pick.genre = g.id
					go(2)
				end,
			})
		end
		grid(body, 22, items, 70)
	elseif pick.step == 2 then
		local g = Genres.byId[pick.genre or "action"]
		header(body, "2/5  Pick a topic for your " .. g.name .. " game", "Matches you have found show their colour.")
		local items = {}
		for _, t in Topics.list do
			local m = v.matches[Dev.matchKey(g.id, t.id)]
			table.insert(items, {
				text = t.name,
				on = v.topics[t.id] == true,
				color = if m then UIKit.color(m) else nil,
				click = function()
					pick.topic = t.id
					go(3)
				end,
			})
		end
		grid(body, 22, items, 70)
		backButton(body, 1)
	elseif pick.step == 3 then
		header(body, "3/5  Pick a platform")
		local list = UIKit.scroll(body, UDim2.new(1, 0, 1, -28), UDim2.fromOffset(0, 12))
		UIKit.vlist(list, 2)
		for i, p in Dev.platformsIn(year) do
			local row = Instance.new("Frame")
			row.Name = "Row"
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, -6, 0, 22)
			row.LayoutOrder = i
			row.Parent = list
			local loves = {}
			for _, gid in p.loves do
				local gd = Genres.byId[gid]
				table.insert(loves, if gd then gd.name else gid)
			end
			local afford = v.money >= p.licence + Tuning.Sizes.small.cost or (v.money < 0 and p.id == Tuning.RescuePlatform)
			UIKit.button(row, p.name, UDim2.fromOffset(80, 20), UDim2.fromOffset(0, 1), function()
				pick.platform = p.id
				go(4)
			end, { enabled = afford, name = "Platform_" .. p.id })
			UIKit.text(row, string.format("Licence %s  Market x%.1f", Numbers.money(p.licence), p.market), UDim2.new(1, -86, 0, 10), UDim2.fromOffset(86, 0), { color = UIKit.color("text") })
			UIKit.text(row, "Loves " .. table.concat(loves, ", "), UDim2.new(1, -86, 0, 10), UDim2.fromOffset(86, 10), { color = UIKit.color("text_dim") })
		end
		backButton(body, 2)
	elseif pick.step == 4 then
		header(body, "4/5  Size and focus")
		local items = {}
		for _, id in Dev.SIZE_ORDER do
			local sz = Tuning.Sizes[id]
			table.insert(items, {
				text = string.format("%s %dw", Dev.SIZE_NAMES[id], sz.weeks),
				on = true,
				color = if pick.size == id then UIKit.color("accent") else nil,
				click = function()
					pick.size = id
					go(4)
				end,
			})
		end
		local y = grid(body, 12, items, 76)
		UIKit.text(body, "Focus: that score +30%, the others -10%", UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, y + 2), { color = UIKit.color("text_dim") })
		local fitems = {}
		for _, a in Dev.AXES do
			table.insert(fitems, {
				text = Dev.AXIS_NAMES[a],
				on = true,
				color = if pick.focus == a then UIKit.color(a) else nil,
				click = function()
					pick.focus = (a :: any) :: Types.Axis
					go(4)
				end,
			})
		end
		y = grid(body, y + 14, fitems, 60)
		UIKit.button(body, "Next", UDim2.fromOffset(40, 12), UDim2.new(1, -40, 1, -12), function()
			go(5)
		end, { color = UIKit.color("button_ok"), name = "Next" })
		backButton(body, 3)
	else
		local genre, topic, platform = pick.genre or "action", pick.topic or "space", pick.platform or "pc"
		local g, t = Genres.byId[genre], Topics.byId[topic]
		local title = Dev.sequelTitle(Dev.title(genre, topic, pick.seed), v.releases, nil)
		header(body, "5/5  Ready to start?")
		UIKit.text(body, title, UDim2.new(1, -70, 0, 18), UDim2.fromOffset(0, 12), { face = "big", color = UIKit.color("accent"), name = "GameTitle" })
		UIKit.button(body, "Shuffle", UDim2.fromOffset(52, 12), UDim2.new(1, -52, 0, 14), function()
			pick.seed += 1
			go(5)
		end, { color = UIKit.color("plate_light"), name = "Shuffle" })
		local mt, mc = matchText(v, genre, topic)
		local cost = Dev.startCost(pick.size, platform)
		local rescue = v.money < 0 and pick.size == Tuning.RescueSize and platform == Tuning.RescuePlatform
		if rescue then
			cost = 0
		end
		local lines: { { text: string, color: Color3 } } = {
			{ text = string.format("%s %s for %s", t.name, g.name, Platforms.byId[platform].name), color = UIKit.color("text") },
			{ text = string.format("%s game, %d weeks, focus %s", Dev.SIZE_NAMES[pick.size], Tuning.Sizes[pick.size].weeks, Dev.AXIS_NAMES[pick.focus]), color = UIKit.color("text") },
			{ text = mt, color = mc },
			{ text = "Cost: " .. Numbers.money(cost, true) .. (if rescue then " (free: you're broke)" else ""), color = if v.money >= cost then UIKit.color("good") else UIKit.color("bad") },
		}
		for i, l in lines do
			UIKit.text(body, l.text, UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, 32 + (i - 1) * 11), { color = l.color })
		end
		UIKit.button(body, "Start!", UDim2.fromOffset(52, 13), UDim2.new(1, -52, 1, -13), function()
			local res = StateClient.request("project.start", { genre = genre, topic = topic, platform = platform, size = pick.size, focus = pick.focus, seed = pick.seed })
			if res.ok then
				local started = res.data and res.data.title or title
				UIKit.closePanel()
				UIKit.notice("Work on " .. tostring(started) .. " begins!", UIKit.color("accent"))
				reset()
			else
				UIKit.notice(NewGameUI.errText(res.err), UIKit.color("bad"))
			end
		end, { enabled = v.money >= cost, color = UIKit.color("button_ok"), name = "Start" })
		backButton(body, 4)
	end
end

local ERR: { [string]: string } = {
	money = "Not enough money for that.",
	busy = "A game is already in the works.",
	locked = "That isn't open yet: unlock it in Research.",
	unavailable = "That platform isn't on sale this year.",
	rp = "Not enough research points.",
	full = "Every desk is taken: move to a bigger office.",
	cooldown = "Once a month: try again next month.",
	fans = "You need more fans first.",
	max = "That's as far as it goes.",
	last = "You can't let your last developer go.",
	not_built = "The game isn't built yet.",
	no_project = "There's no game in the works.",
	rate = "Slow down a little!",
}

function NewGameUI.errText(err: string?): string
	return ERR[err or ""] or "That didn't work. Try again."
end

function NewGameUI.init()
	reset()
	UIKit.registerPanel("newgame", { title = "New game", w = 320, h = 172, build = build })
	UIKit.PanelChanged:Connect(function(name)
		if name == nil then
			pick.step = 1
		end
	end)
end

return NewGameUI
