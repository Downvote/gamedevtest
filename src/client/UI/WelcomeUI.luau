--!strict
-- The welcome-back card (GAME_DESIGN 14.3; Random Bakery's welcome-back modal; the request of 2026-11-14: "Add offline
-- earnings just like the bakery game, and a gamepass which allows for 24h offline earnings"). When the view says the
-- island made shells while its player was away (ClientView.offline), the card opens by itself once the loading card
-- has gone and nothing else is up (a panel, Build mode, the hatch scene): the shells, how long the player was away and
-- how much of it counted, Collect ("offline.collect" free), Collect x2 while it's free (an island's first days), and,
-- without the Offline Pass, what the pass would make of it with a button to the Store's Passes tab. Closed without
-- collecting, it waits behind the HUD's "Away earnings" chip (StoreUI.offers); leaving pays it as shown.
--   WelcomeUI.init(), WelcomeUI.step() (Hud's heartbeat: opens the card when it should), WelcomeUI.open()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local LoadingCard = require(game:GetService("ReplicatedFirst").Loading.LoadingCard)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local BuildUI = require(script.Parent.BuildUI)
local HatchScene = require(script.Parent.HatchScene)
local Words = require(script.Parent.Words)

local WelcomeUI = {}

local shownFor = "" -- the report the card last opened for by itself (it opens once a report)
local busy = false

local function reportOf(v: Types.ClientView?): Types.OfflineReport?
	if v == nil or v.offline == false then
		return nil
	end
	return v.offline :: Types.OfflineReport
end

local function keyOf(r: Types.OfflineReport): string
	return string.format("%d:%d", r.away, r.shells)
end

-- "at 30% pace" / "at full pace"
local function pace(pct: number): string
	return if pct >= 0.999 then "at full pace" else string.format("at %d%% pace", math.floor(pct * 100 + 0.5))
end

local function collect(mode: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local res = StateClient.request("offline.collect", { mode = mode })
		busy = false
		if res.ok and type(res.data) == "table" then
			Audio.play("reward")
			if UIKit.currentPanel() == "welcome" then
				UIKit.closePanel()
			end
			UIKit.notice("Collected " .. Numbers.coins(tonumber(res.data.shells) or 0) .. " shells.", UIKit.color("accent"), 3)
		else
			Audio.play("deny")
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
			if UIKit.currentPanel() == "welcome" then
				UIKit.refreshPanel()
			end
		end
	end)
end

local PAD = 6

local function build(body: Frame, _arg: any?)
	local v = StateClient.view()
	local r = reportOf(v)
	if v == nil or r == nil then
		UIKit.text(body, "Nothing waiting. Your island is busy right now.", UDim2.new(1, -2 * PAD, 0, 10), UDim2.fromOffset(PAD, 6), { color = UIKit.color("text_dim"), name = "Empty" })
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	-- the haul: the shell and the shells, big
	PixelSprites.image(body, "mini_shell", UDim2.fromOffset(PAD, 7), 3).Name = "Shell"
	UIKit.text(body, "+" .. Numbers.coins(r.shells) .. " shells", UDim2.fromOffset(W - 2 * PAD - 16, 18), UDim2.fromOffset(PAD + 15, 2), { face = "big", color = UIKit.color("accent"), name = "Shells" })
	-- how long the player was away and how much of it counted
	local line = if r.secs < r.away
		then string.format("You were away for %s. Your driftlings worked the first %s of it, %s.", Numbers.duration(r.away), Numbers.duration(r.secs), pace(v.offlinePct))
		else string.format("You were away for %s. Your driftlings kept working, %s.", Numbers.duration(r.away), pace(v.offlinePct))
	UIKit.text(body, line, UDim2.fromOffset(W - 2 * PAD, 20), UDim2.fromOffset(PAD, 24), { color = UIKit.color("text"), wrap = true, y = "top", name = "Away" })
	local y = 48
	-- without the Offline Pass: what it would make of a long time away
	local pass = v.passes ~= nil and v.passes.OfflinePass == true
	if not pass then
		local gw = math.max(40, UIKit.buttonWidth("See pass", 6))
		PixelSprites.image(body, "mini_moon", UDim2.fromOffset(PAD, y + 1), 3)
		UIKit.text(body, string.format("Offline Pass: up to %d h away, %s.", Tuning.OfflinePassHours, pace(Tuning.OfflinePassPct)), UDim2.fromOffset(W - 2 * PAD - gw - 18, 10), UDim2.fromOffset(PAD + 14, y + 1), { color = UIKit.color("text_dim"), name = "PassNote" })
		local b = UIKit.button(body, "See pass", UDim2.fromOffset(gw, 12), UDim2.fromOffset(W - PAD - gw, y), function()
			Audio.play("click")
			UIKit.openPanel("store", "passes")
		end, { name = "SeePass", color = UIKit.color("plate_light") })
		b.ZIndex = 3
		y += 15
	elseif r.secs < r.away then
		UIKit.text(body, string.format("They work up to %d h while you're away.", math.floor(v.offlineHours + 0.5)), UDim2.fromOffset(W - 2 * PAD, 10), UDim2.fromOffset(PAD, y + 1), { color = UIKit.color("text_dim"), name = "CapNote" })
		y += 15
	end
	-- Collect, and Collect x2 while it's free
	local bw = 70
	local by = H - 18
	local double = v.offlineDouble
	local total = bw + (if double then bw + 6 else 0)
	local bx = math.floor((W - total) / 2)
	local b1 = UIKit.button(body, "Collect", UDim2.fromOffset(bw, 14), UDim2.fromOffset(bx, by), function()
		collect("free")
	end, { name = "Collect", color = UIKit.color("button_ok") })
	b1.ZIndex = 3
	if double then
		local b2 = UIKit.button(body, "Collect x2", UDim2.fromOffset(bw, 14), UDim2.fromOffset(bx + bw + 6, by), function()
			collect("double")
		end, { name = "CollectDouble", color = UIKit.color("accent") })
		b2.ZIndex = 3
		UIKit.text(body, string.format("Double is free for your first %d days.", Tuning.OfflineDoubleDays), UDim2.fromOffset(W - 2 * PAD, 10), UDim2.fromOffset(PAD, by - 12), { x = "center", color = UIKit.color("text_dim"), name = "DoubleNote" })
	end
end

function WelcomeUI.open()
	if reportOf(StateClient.view()) then
		Audio.play("sparkle")
		UIKit.openPanel("welcome")
	end
end

-- (Hud's heartbeat) The card by itself, once a report: when the loading card has gone and nothing else is up.
function WelcomeUI.step()
	local r = reportOf(StateClient.view())
	if r == nil then
		if UIKit.currentPanel() == "welcome" then
			UIKit.closePanel()
		end
		return
	end
	local key = keyOf(r)
	if key == shownFor then
		return
	end
	if LoadingCard.state().up or UIKit.currentPanel() ~= nil or BuildUI.isOpen() or HatchScene.isOpen() then
		return
	end
	shownFor = key
	WelcomeUI.open()
end

function WelcomeUI.init()
	UIKit.registerPanel("welcome", { title = "Welcome back", icon = "shell", w = 250, h = 112, build = build })
end

return WelcomeUI
