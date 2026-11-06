--!strict
-- Release day and awards night (GAME_DESIGN 6.3, 8; docs/ARCHITECTURE.md 10.5): Release! asks the server to ship the
-- game, and the card shows the four critics' scores one by one, the total out of 40, the Hall of Fame and the match
-- the studio just learned. The awards night's card shows what the year's best game won. Both hold the clock while
-- they are up; "Nice!" closes them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Critics = require(ReplicatedStorage.Shared.Data.Critics)
local Genres = require(ReplicatedStorage.Shared.Data.Genres)
local Topics = require(ReplicatedStorage.Shared.Data.Topics)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Dev = require(ReplicatedStorage.Shared.Logic.Dev)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local NewGameUI = require(script.Parent.NewGameUI)

local ReviewUI = {}

local REVEAL = 0.55 -- seconds between the critics
local current: Frame? = nil

local function scoreColor(n: number): Color3
	if n >= 9 then
		return UIKit.color("accent")
	elseif n >= 7 then
		return UIKit.color("good")
	elseif n >= 4 then
		return UIKit.color("text")
	end
	return UIKit.color("bad")
end

local function close()
	local f = current
	current = nil
	if f then
		f:Destroy()
	end
	StateClient.signal("pause", { key = "card", on = false })
end

-- A card in the middle of the Popup root, with a dim shade behind it; it rises into place.
local function card(w: number, h: number): (TextButton, Frame)
	close()
	StateClient.signal("pause", { key = "card", on = true })
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local shade = Instance.new("TextButton")
	shade.Name = "Card"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = UIKit.color("ink")
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 5
	local cw, ch = math.min(w, s.X - 8), math.min(h, s.Y - 6)
	local x, y = math.floor((s.X - cw) / 2), math.floor((s.Y - ch) / 2)
	local f = UIKit.plate(shade, UDim2.fromOffset(cw, ch), UDim2.fromOffset(x, y + 10), UIKit.color("plate"), 0, 3)
	f.ZIndex = 6
	shade.Parent = canvas
	current = shade :: any
	UIKit.tween(shade, 0.15, { BackgroundTransparency = 0.4 })
	UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y) })
	Audio.play("open")
	return shade, f
end

-- The reviews card for a release (the server's Release record).
function ReviewUI.show(r: Types.Release)
	local _, f = card(260, 152)
	local w = f.Size.X.Offset
	UIKit.text(f, "Reviews are in!", UDim2.new(1, -8, 0, 10), UDim2.fromOffset(5, 3), { color = UIKit.color("text_dim"), z = 7 })
	UIKit.text(f, r.title, UDim2.new(1, -8, 0, 18), UDim2.fromOffset(5, 13), { face = "big", color = UIKit.color("accent"), kind = "title", z = 7, name = "GameTitle" })
	local scores: { TextLabel } = {}
	for i, c in Critics.list do
		local y = 34 + (i - 1) * 15
		UIKit.text(f, c.name, UDim2.fromOffset(80, 10), UDim2.fromOffset(8, y + 2), { color = UIKit.color("text"), z = 7 })
		UIKit.text(f, c.outlet, UDim2.fromOffset(90, 10), UDim2.fromOffset(88, y + 2), { color = UIKit.color("text_dim"), z = 7 })
		scores[i] = UIKit.text(f, "...", UDim2.fromOffset(30, 16), UDim2.fromOffset(w - 38, y), { face = "big", x = "right", color = UIKit.color("text_dim"), z = 7, name = "Score_" .. i })
	end
	local totalY = 34 + 4 * 15 + 2
	local total = UIKit.text(f, "", UDim2.new(1, -16, 0, 10), UDim2.fromOffset(8, totalY), { color = UIKit.color("text"), z = 7, name = "Total" })
	local g, t = Genres.byId[r.genre], Topics.byId[r.topic]
	local match = UIKit.text(f, "", UDim2.new(1, -16, 0, 10), UDim2.fromOffset(8, totalY + 11), { color = UIKit.color(r.match), z = 7, name = "Match" })
	local nice = UIKit.button(f, "Nice!", UDim2.fromOffset(44, 13), UDim2.new(1, -48, 1, -16), close, { color = UIKit.color("button_ok"), name = "Nice" })
	nice.ZIndex = 8
	Audio.play("drumroll")
	task.spawn(function()
		for i, v in r.reviews do
			task.wait(REVEAL)
			local l = scores[i]
			if l and l.Parent then
				-- each score slams down into its place
				UIKit.setText(l, tostring(v))
				UIKit.setTextColor(l, scoreColor(v))
				local home = l.Position
				l.Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset - 8)
				UIKit.tween(l, 0.12, { Position = home })
				Audio.play("pop", { pitch = 0.8 + v * 0.04 })
			end
		end
		task.wait(REVEAL * 0.6)
		if total.Parent then
			-- the total counts up
			local t0 = os.clock()
			while total.Parent do
				local k = math.clamp((os.clock() - t0) / 0.5, 0, 1)
				UIKit.setText(total, string.format("Total %d/40", math.floor(r.total * k + 0.5)))
				if k >= 1 then
					break
				end
				Audio.play("tick", { volume = 0.6 })
				task.wait(0.04)
			end
			if not total.Parent then
				return
			end
			UIKit.setText(total, string.format("Total %d/40", r.total) .. (if r.hof then "   Hall of Fame!" else ""))
			UIKit.setTextColor(total, if r.hof then UIKit.color("accent") else UIKit.color("text"))
			UIKit.setText(match, string.format("%s %s: %s match!", if t then t.name else r.topic, if g then g.name else r.genre, Dev.MATCH_NAMES[r.match]))
			if r.hof then
				UIKit.confetti(f, 50)
				Audio.play("rare_fanfare")
			elseif r.total >= 28 then
				UIKit.confetti(f, 24)
				Audio.play("fanfare")
			elseif r.total >= 16 then
				Audio.play("applause")
			else
				Audio.play("sad")
			end
		end
	end)
end

-- Ship the game in the works and show its reviews.
function ReviewUI.release()
	local res = StateClient.request("project.release", {})
	if res.ok and type(res.data) == "table" then
		ReviewUI.show(res.data :: Types.Release)
	else
		UIKit.notice(NewGameUI.errText(res.err), UIKit.color("bad"))
	end
end

-- The awards night's card (a Studio.week "award" event).
function ReviewUI.award(e: { [string]: any })
	local _, f = card(240, 92)
	UIKit.text(f, string.format("Awards night, Year %d", e.year or 0), UDim2.new(1, -8, 0, 10), UDim2.fromOffset(5, 3), { color = UIKit.color("text_dim"), z = 7 })
	UIKit.text(f, if e.award == "goty" then "Game of the Year!" else "Critics' Choice!", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(5, 14), { face = "big", color = UIKit.color("accent"), kind = "title", z = 7 })
	UIKit.text(f, string.format("%s (%d/40)", tostring(e.title), e.total or 0), UDim2.new(1, -8, 0, 10), UDim2.fromOffset(5, 36), { color = UIKit.color("text"), z = 7 })
	UIKit.text(f, string.format("+%s fans   +%s", Numbers.int(e.fans or 0), Numbers.money(e.amount or 0)), UDim2.new(1, -8, 0, 10), UDim2.fromOffset(5, 48), { color = UIKit.color("good"), z = 7 })
	local nice = UIKit.button(f, "Nice!", UDim2.fromOffset(44, 13), UDim2.new(1, -48, 1, -16), close, { color = UIKit.color("button_ok"), name = "Nice" })
	nice.ZIndex = 8
	Audio.play("trumpet")
	task.delay(0.2, function()
		if f.Parent then
			UIKit.confetti(f, 40)
		end
	end)
end

function ReviewUI.isOpen(): boolean
	return current ~= nil
end

function ReviewUI.init()
	local _ = Tuning
end

return ReviewUI
