--!strict
-- The Rewards sheet and its words (GAME_DESIGN 15; Logic/Rewards, Data/Rewards). The request (2026-11-19): "add rewards
-- for playtime, daily rewards, streak rewards, codes, and as many retention features you can think of". Laid out the
-- way Random Bakery's Rewards sheet is, with this island's own things.
--   The panel ("rewards"; its argument a tab: "today", "tasks", "spin", "index", "codes"): a tab each, a red dot on one
--   while something on it waits.
--     Today: the daily reward (the streak, the 7-day round as cards, Claim: reward.daily, the next milestone) and the
--       gifts for playing (the next one's minutes running down, Claim: reward.play, a card each).
--     Tasks: today's three tasks (a bar each, Claim once done: reward.task) and the bonus for all three (reward.bonus).
--     Lucky Shell: its prizes with their odds and Spin (reward.spin): a light runs over the prizes, slows and stops on
--       the one won, then the notice says what it was.
--     Index: the gifts for kinds found (reward.index).
--     Codes: a box to type a code in and Redeem (code.redeem).
--   On the HUD (UI/Hud): the menu bar's Gifts button with a red dot while something waits (RewardsUI.ready), and the
--   status lines RewardsUI.status keeps: the next gift for playing, each timed boost running.
-- API: RewardsUI.init(), RewardsUI.words(v, r, short?) -> string, RewardsUI.icon(r) -> string, RewardsUI.ready(v) ->
-- number, RewardsUI.playSecs(v) -> number, RewardsUI.status(v, line) (Hud's second: line(name, icon?, text?, color?)),
-- RewardsUI.TABS, RewardsUI.tabOf() -> string.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local RewardsData = require(ReplicatedStorage.Shared.Data.Rewards)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Titles = require(ReplicatedStorage.Shared.Data.Titles)
local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Words = require(script.Parent.Words)
local StoreUI = require(script.Parent.StoreUI)

local RewardsUI = {}

type Reward = RewardsData.Reward
type View = Types.ClientView

RewardsUI.TABS = {
	{ id = "today", text = "Today", icon = "gift" },
	{ id = "tasks", text = "Tasks", icon = "check" },
	{ id = "spin", text = "Lucky Shell", icon = "wheel" },
	{ id = "index", text = "Index", icon = "star" },
	{ id = "codes", text = "Codes", icon = "ticket" },
}
local tab = "today"
local tabSeq = -1

------------------------------------------------------------------ words
local function an(word: string): string
	local c = string.lower(string.sub(word, 1, 1))
	return if c == "a" or c == "e" or c == "i" or c == "o" or c == "u" then "an" else "a"
end

-- A reward's words for this player now: "1,200 shells", "a rare egg", "2 spins", "Lucky Hour, 15 min", "the Devoted
-- title"; short (a card's): "1.2K", "Rare", "2 spins", "15 min", "Title".
function RewardsUI.words(v: View?, r: Reward, short: boolean?): string
	if r.kind == "shells" then
		local n = math.floor(((if v then v.minuteShells else 0) or 0) * (r.mins or 1))
		return if short then Numbers.short(n) else Numbers.coins(n) .. " shells"
	elseif r.kind == "egg" then
		local rar = Traits.RARITY[math.clamp(r.r or 1, 1, Traits.RMAX)]
		return if short then rar.name else string.format("%s %s egg", an(rar.name), string.lower(rar.name))
	elseif r.kind == "spin" then
		local n = r.n or 1
		return if n == 1 then "1 spin" else string.format("%d spins", n)
	elseif r.kind == "boost" then
		local name = RewardsData.BOOSTS[r.id or ""] or "Boost"
		return if short then string.format("%d min", r.mins or 1) else string.format("%s, %d min", name, r.mins or 1)
	elseif r.kind == "title" then
		local t = Titles.byId[r.id or ""]
		return if short then "Title" else "the " .. (if t then t.name else "new") .. " title"
	elseif r.kind == "look" then
		local c = Cosmetics.byId[r.id or ""]
		return if short then "Look" else (if c then c.name else "a piece")
	end
	return ""
end

-- A bundle in one line: "a rare egg and 5 min of shells".
local function bundleWords(v: View?, list: { Reward }): string
	local out = ""
	for i, r in list do
		out ..= (if i == 1 then "" elseif i == #list then " and " else ", ") .. RewardsUI.words(v, r)
	end
	return out
end

-- A reward's mini icon ("mini_" less).
function RewardsUI.icon(r: Reward): string
	if r.kind == "shells" then
		return "shell"
	elseif r.kind == "egg" then
		return "egg_" .. math.clamp(r.r or 1, 1, Traits.RMAX)
	elseif r.kind == "spin" then
		return "wheel"
	elseif r.kind == "boost" then
		return if r.id == "luck" then "star" else "boost"
	elseif r.kind == "title" then
		return "crown"
	elseif r.kind == "look" then
		return "visitor"
	end
	return "gift"
end

------------------------------------------------------------------ the view's rewards
local function rv(v: View?): any
	return if v then v.rewards else nil
end

-- Seconds on the island today, running on between the server's seconds (each says where it stood when it came); when
-- the last view came (the timed boosts run down from it).
local playBase, playAt = 0, os.clock()
local viewAt = os.clock()
function RewardsUI.playSecs(v: View?): number
	local r = rv(v)
	if r == nil then
		return 0
	end
	return playBase + (os.clock() - playAt)
end

-- The gift for playing claimable now (its index), and the next one still to come.
local function playState(v: View?): (number?, number?)
	local r = rv(v)
	if r == nil then
		return nil, nil
	end
	local secs = RewardsUI.playSecs(v)
	local ready: number?, nextI: number? = nil, nil
	for i, g in RewardsData.PLAY do
		if table.find(r.playGot, i) == nil then
			if secs >= g.min * 60 then
				ready = ready or i
			elseif nextI == nil then
				nextI = i
			end
		end
	end
	return ready, nextI
end

-- How many things wait to be claimed (the Gifts button's dot): the server's count, and a gift for playing whose
-- minutes came in since its last view.
function RewardsUI.ready(v: View?): number
	local r = rv(v)
	if r == nil then
		return 0
	end
	local n = r.ready or 0
	local secs = RewardsUI.playSecs(v)
	for i, g in RewardsData.PLAY do
		if table.find(r.playGot, i) == nil and secs >= g.min * 60 and r.play < g.min * 60 then
			n += 1
		end
	end
	return n
end

local function tabDots(v: View?): { [string]: boolean }
	local r = rv(v)
	local dots: { [string]: boolean } = {}
	if r == nil then
		return dots
	end
	dots.today = r.daily.ready == true or playState(v) ~= nil
	local all = #r.tasks > 0
	for _, t in r.tasks do
		if t.done and not t.got then
			dots.tasks = true
		end
		all = all and t.got
	end
	if all and not r.bonus then
		dots.tasks = true
	end
	dots.spin = (r.spins or 0) > 0
	for _, g in RewardsData.INDEX do
		if r.kinds >= g.n and table.find(r.indexGot, g.n) == nil then
			dots.index = true
		end
	end
	return dots
end

local function untilTomorrow(): number
	local now = StateClient.seaClock()
	return (math.floor(now / 86400) + 1) * 86400 - now
end

local function mmss(secs: number): string
	local s = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function claim(action: string, payload: { [string]: any }?)
	local res = StateClient.request(action, payload or {})
	if res.ok then
		Audio.play("reward")
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

------------------------------------------------------------------ pieces
local PAD = 4
local ROW_GAP = 3

-- A row on the sheet: an icon, a line in ink, a quieter line under it; returns the row.
local function infoRow(list: Instance, y: number, w: number, h: number, icon: string, top: string, sub: string?, name: string, feature: boolean?): Frame
	local f = UIKit.row(list, UDim2.fromOffset(w, h), UDim2.fromOffset(0, y), if feature then UIKit.color("sheet_feature") else nil, if feature then 0 else nil)
	f.Name = name
	PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(PAD + 1, math.floor((h - 11) / 2)), 4)
	UIKit.text(f, top, UDim2.fromOffset(w - 90, 10), UDim2.fromOffset(19, if sub then 2 else math.floor((h - 10) / 2)), { z = 4, name = "Top" })
	if sub then
		UIKit.text(f, sub, UDim2.fromOffset(w - 90, 10), UDim2.fromOffset(19, 12), { color = UIKit.color("text_dim"), z = 4, name = "Sub" })
	end
	return f
end

-- A small card: a label on top, an icon, words under it. state: "got" (dimmed, a tick), "now" (gold), "" (plain).
local function card(list: Instance, x: number, y: number, w: number, h: number, label: string, icon: string, words: string, state: string, name: string): Frame
	local c = if state == "now" then UIKit.color("sheet_feature") elseif state == "got" then UIKit.color("sheet_card") else nil
	local f = UIKit.row(list, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), c, if c then 0 else nil)
	f.Name = name
	UIKit.text(f, label, UDim2.fromOffset(w - 2, 10), UDim2.fromOffset(1, 2), { x = "center", color = UIKit.color(if state == "now" then "accent" else "text_dim"), z = 4, name = "Label" })
	PixelSprites.image(f, "mini_" .. (if state == "got" then "check" else icon), UDim2.fromOffset(math.floor((w - 11) / 2), math.floor(h / 2) - 5), 4)
	UIKit.text(f, words, UDim2.fromOffset(w - 2, 10), UDim2.fromOffset(1, h - 11), { x = "center", color = UIKit.color(if state == "got" then "text_dim" else "text"), z = 4, name = "Words" })
	return f
end

local function rightButton(f: Frame, w: number, text: string, name: string, fn: () -> (), on: boolean?)
	local bw = UIKit.buttonWidth(text, 6)
	local b = UIKit.button(f, text, UDim2.fromOffset(bw, 13), UDim2.new(1, -bw - PAD, 0.5, -7), fn, { name = name, color = UIKit.color("button_ok"), enabled = on ~= false })
	b.ZIndex = 5
end

local function rightNote(f: Frame, text: string, name: string?, icon: string?)
	local tw = UIKit.textWidth(text)
	UIKit.text(f, text, UDim2.fromOffset(tw + 2, 10), UDim2.new(1, -tw - PAD - 2, 0.5, -5), { color = UIKit.color("text_dim"), x = "right", z = 4, name = name or "Note" })
	if icon then
		PixelSprites.image(f, "mini_" .. icon, UDim2.new(1, -tw - PAD - 16, 0.5, -5), 4)
	end
end

local function bar(parent: Instance, x: number, y: number, w: number, frac: number, color: string)
	-- a groove in the paper (its top edge in shade), the fill along it
	local back = UIKit.rect(parent, UDim2.fromOffset(w, 4), UDim2.fromOffset(x, y), UIKit.color("sheet_card"), 4)
	back.Name = "Bar"
	UIKit.rect(back, UDim2.new(1, 0, 0, 1), nil, UIKit.color("sheet_btn"):Lerp(UIKit.color("sheet_ink"), 0.25), 5).Name = "Edge"
	local fill = UIKit.rect(back, UDim2.fromOffset(math.floor(w * math.clamp(frac, 0, 1) + 0.5), 3), UDim2.fromOffset(0, 1), UIKit.paperColor(UIKit.color(color)), 5)
	fill.Name = "Fill"
end

-- Words that fit `w` px: the long ones, else the short ones, else none.
local function fit(long: string, short: string, w: number): string
	if UIKit.textWidth(long) <= w then
		return long
	end
	return if UIKit.textWidth(short) <= w then short else ""
end

------------------------------------------------------------------ the tabs
local function buildToday(list: ScrollingFrame, v: View, W: number): number
	local r = rv(v)
	local d = r.daily
	local y = 0
	UIKit.heading(list, "Daily reward", y, "gift", string.format("Best %d", d.best))
	y += 14
	-- the streak: today's claim, the next milestone
	local streakTop = if d.ready then (if d.streak > 1 then string.format("Day %d of your streak", d.streak) else "Day 1 of a new streak") else string.format("%d day streak", d.streak)
	local mile: RewardsData.Milestone? = nil
	for _, m in RewardsData.MILESTONES do
		if m.day == d.next then
			mile = m
		end
	end
	local sub = if mile then string.format("Day %d gift: %s.", mile.day, bundleWords(v, mile.give)) else "Every streak gift is yours."
	local f = infoRow(list, y, W, 24, "heat", streakTop, sub, "Streak", d.ready)
	if d.ready then
		rightButton(f, W, "Claim", "DailyClaim", function()
			claim("reward.daily")
		end)
	else
		rightNote(f, "Next in " .. Numbers.duration(untilTomorrow()), "DailyNext")
	end
	y += 24 + ROW_GAP
	-- the round: a card a day
	-- (the seventh, the round's best, twice as wide)
	local n = #RewardsData.DAILY
	local cw = math.floor((W - n * 2) / (n + 1))
	local x = 0
	for i, give in RewardsData.DAILY do
		local first = give[1]
		local state = if i < d.round or (i == d.round and not d.ready) then "got" elseif i == d.round then "now" else ""
		local w = if i == n then W - x else cw
		local more = if #give > 1 then "+" else ""
		local words = fit(RewardsUI.words(v, first, true) .. more, (if first.kind == "egg" then "Egg" else RewardsUI.words(v, first, true)) .. more, w - 4)
		card(list, x, y, w, 36, string.format("Day %d", i), RewardsUI.icon(first), words, state, "Day_" .. i)
		x += w + 2
	end
	y += 36 + 8
	-- the gifts for playing
	local secs = RewardsUI.playSecs(v)
	local got = #r.playGot
	UIKit.heading(list, "Gifts for playing", y, "clock", string.format("%d of %d today", got, #RewardsData.PLAY))
	y += 14
	local ready, nextI = playState(v)
	if ready then
		local g = RewardsData.PLAY[ready]
		local row = infoRow(list, y, W, 24, RewardsUI.icon(g.give[1]), "A gift is ready", bundleWords(v, g.give) .. ".", "PlayGift", true)
		local i = ready
		rightButton(row, W, "Claim", "PlayClaim", function()
			claim("reward.play", { i = i })
		end)
	elseif nextI then
		local g = RewardsData.PLAY[nextI]
		local row = infoRow(list, y, W, 24, RewardsUI.icon(g.give[1]), "Next gift", bundleWords(v, g.give) .. ".", "PlayGift")
		rightNote(row, mmss(g.min * 60 - secs), "PlayTimer", "clock")
	else
		infoRow(list, y, W, 24, "check", "That's every gift for today", "More come tomorrow.", "PlayGift")
	end
	y += 24 + ROW_GAP
	local m = #RewardsData.PLAY
	local gw = math.floor((W - (m - 1) * 2) / m)
	for i, g in RewardsData.PLAY do
		local done = table.find(r.playGot, i) ~= nil
		local state = if done then "got" elseif secs >= g.min * 60 then "now" else ""
		local first = g.give[1]
		local more = if #g.give > 1 then "+" else ""
		local words = fit(RewardsUI.words(v, first, true) .. more, (if first.kind == "egg" then "Egg" else RewardsUI.words(v, first, true)) .. more, gw - 4)
		card(list, (i - 1) * (gw + 2), y, gw, 36, string.format("%d min", g.min), RewardsUI.icon(first), words, state, "Play_" .. i)
	end
	y += 36
	return y
end

local function buildTasks(list: ScrollingFrame, v: View, W: number): number
	local r = rv(v)
	local y = 0
	UIKit.heading(list, "Today's tasks", y, "check", "New ones in " .. Numbers.duration(untilTomorrow()))
	y += 14
	local all = #r.tasks > 0
	for i, t in r.tasks do
		local def = RewardsData.TASKS[1]
		for _, td in RewardsData.TASKS do
			if td.id == t.id then
				def = td
			end
		end
		local text = Lang.fmt(t.text, { n = if t.id == "earn" then Numbers.coins(t.n) else tostring(t.n) })
		local f = UIKit.row(list, UDim2.fromOffset(W, 28), UDim2.fromOffset(0, y), if t.done and not t.got then UIKit.color("sheet_feature") else nil, if t.done and not t.got then 0 else nil)
		f.Name = "Task_" .. i
		PixelSprites.image(f, "mini_" .. (if t.got then "check" else RewardsUI.icon(def.give[1])), UDim2.fromOffset(PAD + 1, 8), 4)
		UIKit.text(f, text, UDim2.fromOffset(W - 100, 10), UDim2.fromOffset(19, 2), { z = 4, name = "Top" })
		local bw = W - 19 - 100
		bar(f, 19, 15, bw, t.have / math.max(1, t.n), if t.done then "good" else "button")
		local count = if t.id == "earn" then Numbers.short(t.have) .. "/" .. Numbers.short(t.n) else string.format("%d/%d", t.have, t.n)
		UIKit.text(f, count, UDim2.fromOffset(56, 10), UDim2.fromOffset(19 + bw + 4, 12), { color = UIKit.color("text_dim"), z = 4, name = "Count" })
		if t.got then
			rightNote(f, "Done", "Done")
		elseif t.done then
			local idx = i
			rightButton(f, W, "Claim", "TaskClaim_" .. i, function()
				claim("reward.task", { i = idx })
			end)
		else
			rightNote(f, fit(RewardsUI.words(v, def.give[1]), RewardsUI.words(v, def.give[1], true), 92), "Gift")
		end
		all = all and t.got
		y += 28 + ROW_GAP
	end
	y += 3
	local bonusTop = if r.bonus then "Bonus claimed" else "Finish all three"
	local f = infoRow(list, y, W, 24, if r.bonus then "check" else "gift", bonusTop, bundleWords(v, RewardsData.BONUS) .. ".", "Bonus", all and not r.bonus)
	if all and not r.bonus then
		rightButton(f, W, "Claim", "BonusClaim", function()
			claim("reward.bonus")
		end)
	end
	y += 24
	return y
end

-- The Lucky Shell: the light over its prizes (spinAt), running while a spin plays out.
local spinAt = 0
local spinning = false
local function paintSpin()
	local name = UIKit.currentPanel()
	if name ~= "rewards" then
		return
	end
	local root = UIKit.canvas("Modal"):FindFirstChild("Panel_rewards")
	if root == nil then
		return
	end
	for i = 1, #RewardsData.SPIN do
		local c = root:FindFirstChild("Slice_" .. i, true)
		if c then
			UIKit.setPlate(c, if i == spinAt then UIKit.color("sheet_feature") else UIKit.color("sheet_row"), 0)
		end
	end
end

local function spin()
	if spinning then
		return
	end
	local res = StateClient.request("reward.spin", {})
	if not res.ok then
		Audio.play("deny")
		UIKit.notice(if res.err == "not_done" then "No spins left. A free one comes tomorrow." else Words.errText(res.err), UIKit.color("bad"))
		return
	end
	local data: any = res.data
	local slice = if type(data) == "table" and type(data.slice) == "number" then data.slice else 1
	local n = #RewardsData.SPIN
	spinning = true
	task.spawn(function()
		-- two laps and on to the prize, slowing as it goes
		local steps = 2 * n + ((slice - (if spinAt > 0 then spinAt else 1)) % n) + 1
		for k = 1, steps do
			spinAt = (spinAt % n) + 1
			paintSpin()
			Audio.play("tick")
			local t = k / steps
			task.wait(0.04 + 0.22 * t * t)
		end
		spinAt = slice
		paintSpin()
		spinning = false
		Audio.play("reward")
		local given = if type(data) == "table" and type(data.given) == "table" then data.given else {}
		UIKit.notice(StoreUI.rewardText("spin", given), UIKit.color("accent"), 5)
		if UIKit.currentPanel() == "rewards" then
			UIKit.refreshPanel()
		end
	end)
end

local function buildSpin(list: ScrollingFrame, v: View, W: number): number
	local r = rv(v)
	local y = 0
	UIKit.heading(list, "Lucky Shell", y, "wheel", if r.spins == 1 then "1 spin" else string.format("%d spins", r.spins))
	y += 14
	UIKit.text(list, "One free spin a day. Gifts and tasks give more.", UDim2.fromOffset(W, 10), UDim2.fromOffset(0, y), { color = UIKit.color("text_dim"), z = 4, name = "SpinHow" })
	y += 13
	local total = 0
	for _, s in RewardsData.SPIN do
		total += s.w
	end
	local cols = if W >= 300 then 3 else 2
	local cw = math.floor((W - (cols - 1) * 3) / cols)
	for i, s in RewardsData.SPIN do
		local cx, cy = ((i - 1) % cols) * (cw + 3), y + ((i - 1) // cols) * 25
		local f = UIKit.row(list, UDim2.fromOffset(cw, 22), UDim2.fromOffset(cx, cy), if i == spinAt then UIKit.color("sheet_feature") else UIKit.color("sheet_row"), 0)
		f.Name = "Slice_" .. i
		PixelSprites.image(f, "mini_" .. RewardsUI.icon(s.give), UDim2.fromOffset(PAD, 5), 4)
		local long = if s.give.kind == "shells" then RewardsUI.words(v, s.give) else Lang.t(s.label)
		local short = if s.give.kind == "boost" then RewardsData.BOOSTS[s.give.id or ""] or long else RewardsUI.words(v, s.give, true)
		UIKit.text(f, fit(long, short, cw - 52), UDim2.fromOffset(cw - 52, 10), UDim2.fromOffset(18, 6), { z = 4, name = "Words" })
		local pct = s.w / total * 100
		UIKit.text(f, if pct >= 1 then string.format("%d%%", math.floor(pct + 0.5)) else string.format("%.1f%%", pct), UDim2.fromOffset(30, 10), UDim2.new(1, -33, 0, 6), { x = "right", color = UIKit.color("text_dim"), z = 4, name = "Odds" })
	end
	y += math.ceil(#RewardsData.SPIN / cols) * 25 + 2
	local bw = 96
	y += 4
	local b = UIKit.button(list, if spinning then "Spinning" else "Spin", UDim2.fromOffset(bw, 18), UDim2.fromOffset(math.floor((W - bw) / 2), y), spin, {
		name = "Spin",
		color = UIKit.color("button_ok"),
		enabled = r.spins > 0 and not spinning,
	})
	b.ZIndex = 5
	PixelSprites.image(b, "mini_wheel", UDim2.fromOffset(6, 3), 6)
	y += 20
	return y
end

local function buildIndex(list: ScrollingFrame, v: View, W: number): number
	local r = rv(v)
	local y = 0
	UIKit.heading(list, "Gifts for the Index", y, "star", string.format("%d kinds found", r.kinds))
	y += 14
	for i, g in RewardsData.INDEX do
		local got = table.find(r.indexGot, g.n) ~= nil
		local can = not got and r.kinds >= g.n
		local f = UIKit.row(list, UDim2.fromOffset(W, 24), UDim2.fromOffset(0, y), if can then UIKit.color("sheet_feature") else nil, if can then 0 else nil)
		f.Name = "IndexGift_" .. i
		PixelSprites.image(f, "mini_" .. (if got then "check" else RewardsUI.icon(g.give[1])), UDim2.fromOffset(PAD + 1, 6), 4)
		UIKit.text(f, string.format("Find %d kinds", g.n), UDim2.fromOffset(W - 100, 10), UDim2.fromOffset(19, 2), { z = 4, name = "Top" })
		UIKit.text(f, bundleWords(v, g.give) .. ".", UDim2.fromOffset(W - 100, 10), UDim2.fromOffset(19, 12), { color = UIKit.color("text_dim"), z = 4, name = "Sub" })
		if got then
			rightNote(f, "Done", "Done")
		elseif can then
			local idx = i
			rightButton(f, W, "Claim", "IndexClaim_" .. i, function()
				claim("reward.index", { i = idx })
			end)
		else
			rightNote(f, string.format("%d to go", g.n - r.kinds), "ToGo")
		end
		y += 24 + ROW_GAP
	end
	return y
end

-- The code box stays while the sheet is rebuilt (a view can come while the player types): kept in the body.
local codeField: Frame? = nil
local function codeBox(body: Frame, y: number, W: number): Frame
	local f = codeField
	if f == nil or f.Parent == nil then
		local nf = UIKit.row(nil, UDim2.fromOffset(W - 70, 16), UDim2.fromOffset(0, y))
		nf.Name = "CodeField"
		nf:SetAttribute("Keep", true)
		local box = Instance.new("TextBox")
		box.Name = "Box"
		box.Text = ""
		box.PlaceholderText = ""
		box.ClearTextOnFocus = false
		box.MultiLine = false
		box.TextTransparency = 1
		box.TextStrokeTransparency = 1
		box.TextSize = 1
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = 8
		box.Parent = nf
		local mirror = UIKit.text(nf, "Type a code", UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 3), { color = UIKit.color("text_dim"), kind = "plain", z = 7, name = "Typed", raw = true })
		UIKit.setTextColor(mirror, UIKit.color("sheet_dim"))
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local t = string.sub(box.Text, 1, 24)
			UIKit.setText(mirror, if t ~= "" then string.upper(t) else "Type a code")
			UIKit.setTextColor(mirror, UIKit.color(if t ~= "" then "sheet_ink" else "sheet_dim"))
		end)
		codeField = nf
		f = nf
	end
	local cf = f :: Frame
	cf.Position = UDim2.fromOffset(0, y)
	cf.Size = UDim2.fromOffset(W - 70, 16)
	cf.Parent = body
	return cf
end

local function redeem()
	local f = codeField
	local box = if f then f:FindFirstChild("Box") else nil
	if box == nil or not box:IsA("TextBox") then
		return
	end
	local code = box.Text
	if string.gsub(code, "%s", "") == "" then
		UIKit.notice("Type a code first.", UIKit.color("bad"))
		return
	end
	local res = StateClient.request("code.redeem", { code = code })
	if res.ok then
		Audio.play("reward")
		box.Text = ""
	else
		Audio.play("deny")
		UIKit.notice(if res.err == "used" then "You already used that code." elseif res.err == "not_found" then "That code doesn't work. Check the spelling." else Words.errText(res.err), UIKit.color("bad"))
	end
end

local function buildCodes(body: Frame, top: number, W: number)
	local y = top
	UIKit.heading(body, "Codes", y, "ticket")
	y += 14
	UIKit.text(body, "We post codes with updates and in the group. Type one in to get its gift.", UDim2.fromOffset(W, 20), UDim2.fromOffset(0, y), { color = UIKit.color("text_dim"), wrap = true, y = "top", z = 4, name = "CodesHow" })
	y += 24
	codeBox(body, y, W)
	local b = UIKit.button(body, "Redeem", UDim2.fromOffset(64, 16), UDim2.fromOffset(W - 64, y), redeem, { name = "Redeem", color = UIKit.color("button_ok") })
	b.ZIndex = 5
end

local function build(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil or rv(v) == nil then
		return
	end
	if type(arg) == "string" and tabSeq ~= UIKit.openCount() then
		for _, t in RewardsUI.TABS do
			if t.id == arg then
				tab = arg
			end
		end
	end
	tabSeq = UIKit.openCount()
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local dots = tabDots(v)
	local items: { UIKit.Tab } = {}
	for _, t in RewardsUI.TABS do
		table.insert(items, { id = t.id, text = t.text, icon = t.icon, dot = dots[t.id] })
	end
	local top = UIKit.tabs(body, items, tab, 0, function(id: string)
		tab = id
		Audio.play("flip")
		UIKit.refreshPanel()
	end) + 3
	if tab ~= "codes" then
		local f = codeField
		if f then
			f:Destroy()
			codeField = nil
		end
	end
	if tab == "codes" then
		buildCodes(body, top, W)
		return
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	local cw = W - 6
	-- (its width for UIKit.heading's note, clear of the scroll bar)
	list:SetAttribute("W", cw)
	local h = 0
	if tab == "today" then
		h = buildToday(list, v, cw)
	elseif tab == "tasks" then
		h = buildTasks(list, v, cw)
	elseif tab == "spin" then
		h = buildSpin(list, v, cw)
	elseif tab == "index" then
		h = buildIndex(list, v, cw)
	end
	list.CanvasSize = UDim2.fromOffset(0, h + 2)
end

------------------------------------------------------------------ the HUD's lines
-- The status lines this module keeps (Hud's second): the next gift for playing (or one waiting), each timed boost.
function RewardsUI.status(v: View?, line: (name: string, icon: string?, text: string?, color: Color3?) -> ())
	local r = rv(v)
	if v == nil or r == nil then
		return
	end
	local ready, nextI = playState(v)
	if RewardsUI.ready(v) > 0 or ready then
		line("gift", "gift", "A gift is waiting", UIKit.color("accent"))
	elseif nextI then
		line("gift", "gift", "Gift in " .. mmss(RewardsData.PLAY[nextI].min * 60 - RewardsUI.playSecs(v)), nil)
	else
		line("gift", nil, nil)
	end
	for id, name in RewardsData.BOOSTS do
		local left = ((v.boosts or {})[id] or 0) - (os.clock() - viewAt)
		if left > 0 then
			line("boost_" .. id, if id == "luck" then "star" else "boost", name .. " " .. mmss(left), UIKit.color("good"))
		else
			line("boost_" .. id, nil, nil)
		end
	end
	-- the countdown on the open sheet
	if UIKit.currentPanel() == "rewards" and nextI then
		local root = UIKit.canvas("Modal"):FindFirstChild("Panel_rewards")
		local timer = root and root:FindFirstChild("PlayTimer", true)
		if timer and timer:IsA("TextLabel") then
			local left = RewardsData.PLAY[nextI].min * 60 - RewardsUI.playSecs(v)
			if left <= 0 then
				UIKit.refreshPanel()
			else
				UIKit.setText(timer, mmss(left))
			end
		end
	end
end

function RewardsUI.tabOf(): string
	return tab
end

function RewardsUI.init()
	UIKit.registerPanel("rewards", { title = "Rewards", icon = "gift", w = 380, h = 214, props = { "egg_3", "gift", "wheel" }, build = build })
	local function take(v: View)
		local r = rv(v)
		if r then
			playBase, playAt = r.play, os.clock()
		end
		viewAt = os.clock()
	end
	local v0 = StateClient.view()
	if v0 then
		take(v0)
	end
	StateClient.Changed:Connect(take)
	-- (the server's second carries the seconds played today)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "tick" and type(msg.play) == "number" and msg.play == msg.play then
			playBase, playAt = msg.play, os.clock()
		end
	end)
end

return RewardsUI
