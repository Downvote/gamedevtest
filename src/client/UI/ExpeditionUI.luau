--!strict
-- An expedition on screen (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.8): the islet's 3D stage (UI/MicroStage, drawn
-- full screen by the pixel filter) with the party on the left (the founder, villagers as their own chibis,
-- driftlings as their 3D models) and, in a battle, the wild driftlings on the right. Along the top the islet's path
-- of stops (the landing, loot, chests, battles, a rest, the guardian) and the loot gathered; along the bottom the
-- party's cards with their health and the buttons: Go on (exp.next) and Sail home (exp.home) between stops; Fight,
-- Guard, Treat (a wild one picked by tapping its card) and Flee in a battle (exp.act). A round's events (Logic/Battle)
-- play back one by one: lunges, flashes, numbers, skills' names, heals, shields, a treat's hearts, knock-outs. A win
-- shows the experience, shells and level-ups; a new friend joins with confetti; the guardian's fall opens the next
-- islet. The screen can be closed (Back to island) while the expedition waits: the HUD's card brings it back. A
-- curtain covers the screen while the stage's picture bakes.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local MicroStage = require(script.Parent.MicroStage)
local Words = require(script.Parent.Words)

local ExpeditionUI = {}
ExpeditionUI.Changed = Util.Signal() :: Types.Signal<boolean>

local HEAD_H = 22
local FOOT_H = 42
local CARD_W = 80
local STEP = 0.5 -- seconds an event plays

-- Someone on the stage: the founder, a villager (a rival chibi), a driftling or a wild one (a 3D model).
type Actor = {
	key: string,
	foe: boolean,
	founder: boolean,
	rival: MicroStage.Rival?,
	thing: MicroModels.Thing?,
	u: number,
	v: number,
	du: number,
	dy: number,
	yaw: number,
	action: string,
	until_: number,
	ko: boolean,
	gone: boolean,
	enterAt: number,
	ph: number,
	big: boolean,
}

-- The shown health (the events move it; the view's numbers settle it after a round).
type Bar = { hp: number, maxHp: number, name: string, lvl: number, card: Frame?, fill: Frame?, label: TextLabel?, w: number }

local isOpen = false
local stage: MicroStage.Stage? = nil
local root: Frame? = nil
local actors: { [string]: Actor } = {}
local bars: { [string]: Bar } = {}
local busy = false
local target: string? = nil
local beat: RBXScriptConnection? = nil
local keys: RBXScriptConnection? = nil
local opened = 0
local lifted = false
local islet = 0
local lastNode = 0
local foeKey = "" -- the battle's foes shown (rebuilt when they change)
local pendingOpen = 0 -- os.clock until which the screen opens as soon as the view has the expedition (just started)

local refresh: () -> () = function() end

local function view(): Types.ClientView?
	return StateClient.view()
end

local function exp(): Types.Expedition?
	local v = view()
	return if v then v.exp else nil
end

local function hideWorldUI(on: boolean)
	for _, name in { "Hud", "World" } do
		UIKit.root(name).Enabled = not on
	end
	pcall(function()
		GuiService.TouchControlsEnabled = not on
	end)
end

------------------------------------------------------------------ the actors
local PARTY_SPOTS = { { -6, -1 }, { -9, -4.5 }, { -9, 2.5 }, { -12, -1 } }
local FOE_SPOTS = { { 6, -1 }, { 9, -4.5 }, { 9, 2.5 } }

local function actorAt(a: Actor): Vector3
	local st = stage :: MicroStage.Stage
	return st.at(a.u + a.du, a.v, a.dy)
end

local function removeActor(key: string)
	local a = actors[key]
	local st = stage
	if a == nil or st == nil then
		return
	end
	if a.thing then
		st.remove(a.thing :: MicroModels.Thing)
	end
	if a.rival then
		(a.rival :: MicroStage.Rival).hide()
	end
	actors[key] = nil
end

local function newActor(key: string, foe: boolean, spot: { number }): Actor
	return {
		key = key,
		foe = foe,
		founder = key == "f",
		rival = nil,
		thing = nil,
		u = spot[1],
		v = spot[2],
		du = 0,
		dy = 0,
		yaw = if foe then MicroStage.FACE_LEFT else MicroStage.FACE_RIGHT,
		action = "stand",
		until_ = 0,
		ko = false,
		gone = false,
		enterAt = os.clock(),
		ph = math.random() * 4,
		big = false,
	}
end

local function driftling(st: MicroStage.Stage, sp: string, big: boolean): MicroModels.Thing
	local d = Creatures.byId[sp]
	local t = MicroModels.driftling(if d then d.shape else "blob", if d then d.body else "steel", if d then d.accent else "steel_dark")
	if big then
		MicroModels.scale(t, Vector3.one * 1.6)
	end
	return st.adopt(t, if big then 1.6 else 1)
end

-- The party on the stage, from the expedition's fighters (once: they stay while the screen is open).
local function buildParty(e: Types.Expedition)
	local st = stage :: MicroStage.Stage
	local delay = 0
	for i, f in e.party do
		if actors[f.key] then
			continue
		end
		local a = newActor(f.key, false, PARTY_SPOTS[i] or PARTY_SPOTS[#PARTY_SPOTS])
		if f.kind == "villager" and f.look then
			delay += 0.12
			a.rival = st.rival(f.look :: Types.Look, delay)
		elseif f.kind == "pal" and f.sp then
			a.thing = driftling(st, f.sp :: string, false)
			a.dy = 8
		end
		actors[f.key] = a
	end
end

-- The battle's wild ones drop in from above (rebuilt when the battle's foes change).
local function buildFoes(e: Types.Expedition)
	local b = e.battle
	local key = ""
	if b then
		for _, f in b.foes do
			key ..= f.key .. (f.sp or "") .. ","
		end
	end
	if key == foeKey then
		return
	end
	foeKey = key
	for k, a in actors do
		if a.foe then
			removeActor(k)
		end
	end
	if b == nil then
		return
	end
	local st = stage :: MicroStage.Stage
	for i, f in b.foes do
		if f.hp <= 0 then
			continue
		end
		local a = newActor(f.key, true, FOE_SPOTS[i] or FOE_SPOTS[1])
		a.big = b.boss and i == 1
		a.thing = driftling(st, f.sp or "pebblit", a.big)
		a.dy = 10
		a.enterAt = os.clock() + (i - 1) * 0.15
		actors[f.key] = a
	end
	Audio.play(if b.boss then "drumroll" else "pop")
end

local function act(a: Actor, action: string, seconds: number)
	a.action = action
	a.until_ = os.clock() + seconds
end

-- Every frame: everyone posed (idle bobs, lunges, drops, knock-outs), the stage's life.
local function poseAll(t: number, dt: number)
	local st = stage
	if st == nil then
		return
	end
	local now = os.clock()
	for _, a in actors do
		-- drops land, lunges ease back
		if a.dy > 0 and lifted and now >= a.enterAt then
			a.dy = math.max(0, a.dy - dt * 30)
			if a.dy == 0 then
				st.puff(st.at(a.u, a.v, 0.2), "dust", 6)
			end
		end
		if now > a.until_ then
			a.du = a.du * math.max(0, 1 - dt * 14)
			if math.abs(a.du) < 0.05 then
				a.du = 0
			end
			a.action = "stand"
		end
		local u = a.u + math.floor(a.du * 4 + 0.5) / 4
		if a.gone then
			if a.thing then
				st.place(a.thing :: MicroModels.Thing, 0, 0, -50)
			end
			continue
		end
		local entry = if lifted then a.dy else 8
		-- a knocked-out founder or villager crouches low (the stage drops the founder and the villagers in itself)
		if a.founder then
			st.pose(u, a.v, 0, a.yaw, t, 0, if a.ko then "sneak" else a.action, 1)
		elseif a.rival then
			local r = a.rival :: MicroStage.Rival
			r.pose(u, a.v, 0, a.yaw, t, 0, if a.ko then "sneak" else a.action, 1)
		elseif a.thing then
			local th = a.thing :: MicroModels.Thing
			if a.ko then
				st.place(th, u, a.v, 0, a.yaw, CFrame.Angles(0, 0, math.rad(90)))
			else
				-- an idle hop in whole quarter studs; a happy bounce while cheering
				local hop = if a.action == "cheer" then (if math.floor(t * 8 + a.ph) % 2 == 0 then 0.75 else 0) else (if math.floor(t * 2.5 + a.ph) % 2 == 0 then 0.125 else 0)
				st.place(th, u, a.v, entry + hop, a.yaw)
			end
		end
	end
	st.step(t, dt)
end

------------------------------------------------------------------ the overlay
local function canvasSize(): (number, number)
	local s = UIKit.size("Stage")
	return s.X, s.Y
end

-- The Stage root covers the whole screen: Roblox's top bar (its buttons) takes this many UI px at the top.
local function topInset(): number
	return math.ceil(UIKit.canvasOrigin("Hud").Y / math.max(1, UIKit.P()))
end

-- A word floating up over someone on the stage.
local function floatOver(key: string, text: string, color: Color3)
	local a = actors[key]
	local st, r = stage, root
	if a == nil or st == nil or r == nil then
		return
	end
	local x, y, on = st.screen(actorAt(a) + Vector3.new(0, if a.big then 4.5 else 3.2, 0))
	if on then
		UIKit.popText(r, x, y, text, color)
	end
end

-- The narration: a plate across the middle of the screen for a moment.
local sayFrame: Frame? = nil
local function say(text: string, color: Color3?, seconds: number?)
	local r = root
	if r == nil then
		return
	end
	if sayFrame then
		sayFrame:Destroy()
	end
	local w, _ = canvasSize()
	local tw = math.min(UIKit.textWidth(text) + 16, w - 16)
	local f = UIKit.plate(r, UDim2.fromOffset(tw, 14), UDim2.fromOffset(math.floor((w - tw) / 2), topInset() + HEAD_H + 2), UIKit.color("plate"), 0.05, 2)
	f.Name = "Say"
	f.ZIndex = 12
	UIKit.text(f, text, UDim2.fromScale(1, 1), nil, { x = "center", color = color or UIKit.color("text"), z = 13, name = "Words" })
	sayFrame = f
	task.delay(seconds or 1.8, function()
		if f.Parent and sayFrame == f then
			f:Destroy()
			sayFrame = nil
		end
	end)
end

local function setBar(key: string, hp: number)
	local b = bars[key]
	if b == nil then
		return
	end
	b.hp = math.clamp(hp, 0, b.maxHp)
	local fill, label = b.fill, b.label
	if fill then
		local k = b.hp / math.max(1, b.maxHp)
		fill.Size = UDim2.fromOffset(math.floor((b.w - 2) * k + 0.5), 2)
		fill.BackgroundColor3 = if k > 0.5 then UIKit.color("good") elseif k > 0.25 then UIKit.color("accent") else UIKit.color("bad")
	end
	if label then
		UIKit.setText(label, string.format("%d/%d", math.floor(b.hp + 0.5), b.maxHp))
	end
end

-- A fighter's card: its portrait or icon, name and level, its health bar.
local function fighterCard(parent: Instance, f: Types.Fighter, x: number, y: number, w: number, foe: boolean): Frame
	local selected = foe and target == f.key
	local card = UIKit.plate(parent, UDim2.fromOffset(w, 18), UDim2.fromOffset(x, y), if selected then UIKit.color("accent") else UIKit.color("plate"), 0.05, 2)
	card.Name = "Card_" .. f.key
	card.ZIndex = 10
	if f.sp then
		local icon = PixelSprites.image(card, "icon_" .. (f.sp :: string), UDim2.fromOffset(1, 1), 11)
		local _ = icon
	elseif f.look then
		UIKit.portrait(card, f.look :: Types.Look, 16, UDim2.fromOffset(1, 1)).ZIndex = 11
	end
	UIKit.text(card, f.name, UDim2.fromOffset(w - 20, 9), UDim2.fromOffset(19, 0), { color = if selected then UIKit.color("ink") else UIKit.color("text"), kind = if selected then "plain" else nil, z = 11, name = "Name" })
	-- the level beside the health bar (a long name keeps the whole top line)
	local lv = "Lv" .. f.lvl
	local lvW = UIKit.textWidth(lv)
	UIKit.text(card, lv, UDim2.fromOffset(lvW + 2, 9), UDim2.fromOffset(w - lvW - 3, 8), { x = "right", color = if selected then UIKit.color("ink") else UIKit.color("text_dim"), kind = if selected then "plain" else nil, z = 11, name = "Lv" })
	local bw = w - 21 - lvW - 3
	local back = UIKit.rect(card, UDim2.fromOffset(bw, 4), UDim2.fromOffset(19, 10), UIKit.color("ink"), 11)
	back.Name = "HpBack"
	local fill = UIKit.rect(back, UDim2.fromOffset(bw - 2, 2), UDim2.fromOffset(1, 1), UIKit.color("good"), 12)
	fill.Name = "HpFill"
	local label = UIKit.text(card, "", UDim2.fromOffset(bw, 8), UDim2.fromOffset(19, 11), { x = "right", color = UIKit.color("text_dim"), z = 13, name = "Hp" })
	label.Visible = false
	bars[f.key] = { hp = f.hp, maxHp = f.maxHp, name = f.name, lvl = f.lvl, card = card, fill = fill, label = label, w = bw }
	setBar(f.key, f.hp)
	if foe then
		local b = Instance.new("TextButton")
		b.Name = "Pick"
		b.Text = ""
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromScale(1, 1)
		b.ZIndex = 14
		b.Parent = card
		b.Activated:Connect(function()
			if f.hp <= 0 then
				return
			end
			target = f.key
			Audio.play("flip")
			refresh()
		end)
	end
	return card
end

local function lootLine(parent: Instance, e: Types.Expedition, x: number, y: number)
	local items: { { icon: string, n: number } } = { { icon = "shell", n = e.loot.shells }, { icon = "food", n = e.loot.food }, { icon = "wood", n = e.loot.wood } }
	for _, it in items do
		PixelSprites.image(parent, "mini_" .. it.icon, UDim2.fromOffset(x, y), 11)
		local t = Numbers.coins(it.n)
		UIKit.text(parent, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 12, y + 1), { color = UIKit.color("text"), z = 11, name = "Loot_" .. it.icon })
		x += 16 + UIKit.textWidth(t)
	end
end

------------------------------------------------------------------ requests
local function ask(action: string, payload: { [string]: any }?): Types.Response
	local res = StateClient.request(action, payload)
	if not res.ok then
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
	return res
end

local playRound: (data: { [string]: any }) -> ()
local playNode: (data: { [string]: any }) -> ()
local goHome: () -> ()

local function goOn()
	if busy then
		return
	end
	busy = true
	refresh()
	-- the party walks on: a few steps in place while the next stop comes up
	for _, a in actors do
		if not a.foe and not a.ko then
			act(a, "stand", 0.6)
		end
	end
	Audio.play("tick")
	local res = ask("exp.next", {})
	if res.ok and type(res.data) == "table" then
		playNode(res.data :: { [string]: any })
	end
	busy = false
	refresh()
end

local function doAct(kind: string)
	if busy then
		return
	end
	local e = exp()
	local b = if e then e.battle else nil
	if b == nil then
		return
	end
	local tgt = ""
	if kind == "treat" then
		local t = target
		if t == nil then
			-- the most hurt one left
			local best: Types.Fighter? = nil
			for _, f in b.foes do
				if f.hp > 0 and (best == nil or f.hp / f.maxHp < (best :: Types.Fighter).hp / (best :: Types.Fighter).maxHp) then
					best = f
				end
			end
			t = if best then best.key else nil
		end
		tgt = t or ""
	end
	busy = true
	refresh()
	local res = ask("exp.act", { act = kind, target = tgt })
	if res.ok and type(res.data) == "table" then
		playRound(res.data :: { [string]: any })
	end
	busy = false
	refresh()
end

------------------------------------------------------------------ playback
local function nameOf(key: string): string
	local b = bars[key]
	return if b then b.name else key
end

local function flashActor(a: Actor)
	local st = stage
	if st and a.thing then
		st.flash(a.thing :: MicroModels.Thing, 0.12)
	end
end

local function playEvent(ev: { [string]: any })
	local st = stage
	if st == nil then
		return
	end
	local t = ev.t
	if t == "hit" then
		local by, to = actors[ev.by], actors[ev.to]
		if by then
			local dir = if by.foe then -1 else 1
			by.du = dir * 2.5
			act(by, if by.founder or by.rival then "swing" else "cheer", 0.18)
		end
		if ev.skill then
			floatOver(ev.by, (Creatures.skills[ev.skill] or ev.skill) .. "!", UIKit.color("accent"))
			Audio.play("combo")
		end
		task.wait(0.14)
		if to then
			to.du = (if to.foe then 1 else -1) * 0.75
			act(to, "hurt", 0.25)
			flashActor(to)
			st.puff(actorAt(to) + Vector3.new(0, 1.5, 0), if ev.skill == "zap" then "splash" else "spark", 6)
		end
		Audio.play("squish", { pitch = if ev.skill then 0.85 else 1 })
		local b = bars[ev.to]
		if b then
			setBar(ev.to, b.hp - (tonumber(ev.dmg) or 0))
		end
		floatOver(ev.to, "-" .. tostring(ev.dmg), UIKit.color("bad"))
		if ev.ko and to then
			task.wait(0.12)
			to.ko = true
			st.puff(actorAt(to), "dust", 10)
			floatOver(ev.to, "Down!", UIKit.color("text_dim"))
			Audio.play("pop", { pitch = 0.7 })
		end
	elseif t == "heal" then
		local to = actors[ev.to]
		floatOver(ev.by, "Soothe!", UIKit.color("good"))
		if to then
			st.puff(actorAt(to) + Vector3.new(0, 1, 0), "heal", 8)
		end
		local b = bars[ev.to]
		if b then
			setBar(ev.to, b.hp + (tonumber(ev.amt) or 0))
		end
		floatOver(ev.to, "+" .. tostring(ev.amt), UIKit.color("good"))
		Audio.play("sparkle")
	elseif t == "shield" then
		local by = actors[ev.by]
		floatOver(ev.by, "Shell Guard!", UIKit.color("accent"))
		for _, a in actors do
			if by and a.foe == by.foe and not a.ko then
				st.puff(actorAt(a) + Vector3.new(0, 1.2, 0), "twinkle", 3)
			end
		end
		Audio.play("ding")
	elseif t == "rally" then
		local by = actors[ev.by]
		if by then
			act(by, "cheer", 0.5)
		end
		floatOver(ev.by, "Rally!", UIKit.color("accent"))
		for _, a in actors do
			if not a.foe and not a.ko and a ~= by then
				act(a, "cheer", 0.4)
			end
		end
		Audio.play("cheer")
	elseif t == "guard" then
		for _, a in actors do
			if not a.foe and not a.ko then
				act(a, "reach", 0.5)
				st.puff(actorAt(a) + Vector3.new(0, 1, 0), "twinkle", 2)
			end
		end
		say("The party guards!", UIKit.color("accent"), 1)
		Audio.play("ding")
	elseif t == "treat" then
		local to = actors[ev.to]
		local f = actors.f
		if f then
			act(f, "reach", 0.5)
		end
		floatOver("f", "Here, a treat!", UIKit.color("text"))
		Audio.play("flip")
		task.wait(0.3)
		if to then
			if ev.ok then
				st.puff(actorAt(to) + Vector3.new(0, 1.5, 0), "heart", 10)
				act(to, "cheer", 0.9)
				floatOver(ev.to, "<3", UIKit.color("pink"))
				Audio.play("fanfare")
				say(nameOf(ev.to) .. " wants to be friends!", UIKit.color("pink"), 2)
				task.wait(0.7)
				to.gone = true
				st.puff(actorAt(to), "confetti")
				local b = bars[ev.to]
				if b and b.card then
					(b.card :: Frame).Visible = false
				end
			else
				floatOver(ev.to, "Hmph!", UIKit.color("text_dim"))
				Audio.play("deny")
			end
		end
	elseif t == "flee" then
		if ev.ok then
			say("Got away!", UIKit.color("good"), 1.4)
			for _, a in actors do
				if not a.foe then
					a.du = -3
					act(a, "jump", 0.3)
				end
			end
			Audio.play("pop")
		else
			say("Couldn't get away!", UIKit.color("bad"), 1.4)
			Audio.play("deny")
		end
	end
	task.wait(STEP)
end

-- A results card in the middle: lines, then a button.
local function resultCard(title: string, color: Color3, lines: { { text: string, color: Color3? } }, icon: string?, button: string, onClick: () -> ())
	local r = root
	if r == nil then
		return
	end
	local w, h = canvasSize()
	local cw = 180
	for _, l in lines do
		cw = math.max(cw, UIKit.textWidth(l.text) + 20)
	end
	cw = math.min(cw, w - 16)
	local ch = 22 + #lines * 10 + 22 + (if icon then 18 else 0)
	local x, y = math.floor((w - cw) / 2), math.floor((h - ch) / 2)
	local f = UIKit.plate(r, UDim2.fromOffset(cw, ch), UDim2.fromOffset(x, -ch - 4), UIKit.color("plate"), 0, 3)
	f.Name = "Result"
	f.ZIndex = 20
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), color, 21)
	UIKit.text(f, title, UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 4), { x = "center", face = "big", kind = "title", color = color, z = 21, name = "Title" })
	local ly = 22
	if icon then
		PixelSprites.image(f, icon, UDim2.fromOffset(math.floor(cw / 2) - 8, ly), 21)
		ly += 18
	end
	for i, l in lines do
		UIKit.text(f, l.text, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, ly + (i - 1) * 10), { x = "center", color = l.color or UIKit.color("text"), z = 21, name = "Line" .. i })
	end
	local b = UIKit.button(f, button, UDim2.fromOffset(cw - 40, 14), UDim2.new(0, 20, 1, -18), function()
		f:Destroy()
		onClick()
	end, { name = "ResultOk", color = UIKit.color("button_ok") })
	b.ZIndex = 22
	UIKit.tween(f, 0.22, { Position = UDim2.fromOffset(x, y) })
	task.delay(0.25, function()
		if f.Parent then
			UIKit.confetti(f, 20)
		end
	end)
end

playRound = function(data: { [string]: any })
	local events = if type(data.events) == "table" then data.events else {}
	for _, ev in events do
		if type(ev) == "table" and isOpen then
			playEvent(ev)
		end
	end
	if not isOpen then
		return
	end
	local result = data.result
	local st = stage
	if result == "win" then
		Audio.play("fanfare")
		for _, a in actors do
			if not a.foe then
				a.ko = false
				act(a, "cheer", 1.4)
			end
		end
		local lines: { { text: string, color: Color3? } } = {}
		table.insert(lines, { text = string.format("+%s xp for the party   +%s shells", Numbers.int(tonumber(data.xp) or 0), Numbers.int(tonumber(data.shells) or 0)), color = UIKit.color("good") })
		if type(data.ups) == "table" then
			for key, n in data.ups do
				table.insert(lines, { text = string.format("%s grew %d level%s!", nameOf(key), n, if n == 1 then "" else "s"), color = UIKit.color("accent") })
			end
		end
		local icon: string? = nil
		if type(data.friend) == "table" and type(data.friend.sp) == "string" then
			local d = Creatures.byId[data.friend.sp]
			icon = "icon_" .. data.friend.sp
			table.insert(lines, 1, { text = (if d then d.name else "A driftling") .. " joined your island!", color = UIKit.color("pink") })
		end
		if data.reward then
			local def = Islets.list[islet]
			table.insert(lines, 1, { text = string.format("The guardian is beaten! +%s shells", Numbers.int(tonumber(data.reward) or 0)), color = UIKit.color("accent") })
			local nxt = Islets.list[islet + 1]
			if data.first and nxt then
				table.insert(lines, { text = nxt.name .. " is open: set sail there next!", color = UIKit.color("good") })
			end
			if st then
				for _ = 1, 3 do
					st.puff(st.at(0, 0, 2), "confetti")
				end
			end
			Audio.play("rare_fanfare")
			resultCard(if def then def.name .. " cleared!" else "Cleared!", UIKit.color("accent"), lines, icon, "Sail home", goHome)
		else
			resultCard("Victory!", UIKit.color("good"), lines, icon, "Onward", function()
				refresh()
			end)
		end
	elseif result == "lose" then
		Audio.play("sad")
		resultCard("The party fell...", UIKit.color("bad"), {
			{ text = "Everyone is back on their feet at home." },
			{ text = "Half of the loot comes home.", color = UIKit.color("text_dim") },
		}, nil, "Sail home", goHome)
	elseif result == "fled" then
		refresh()
	elseif type(data.friend) == "table" and type(data.friend.sp) == "string" then
		-- befriended mid-battle (others still fighting)
		local d = Creatures.byId[data.friend.sp]
		UIKit.notice((if d then d.name else "A driftling") .. " joined your island!", UIKit.color("pink"), 3)
	end
end

playNode = function(data: { [string]: any })
	local st = stage
	if st == nil then
		return
	end
	local kind = data.kind
	if kind == "loot" then
		Audio.play("coin")
		say(string.format("Found %d food and %d wood!", tonumber(data.food) or 0, tonumber(data.wood) or 0), UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				act(a, "reach", 0.6)
			end
		end
		st.puff(st.at(-2, -1, 0.5), "debris", 8)
	elseif kind == "chest" then
		Audio.play("coins")
		say(string.format("A chest: %s shells!", Numbers.int(tonumber(data.shells) or 0)), UIKit.color("accent"))
		st.puff(st.at(-2, -1, 1), "spark", 12)
		for _, a in actors do
			if not a.foe then
				act(a, "cheer", 0.8)
			end
		end
	elseif kind == "rest" then
		Audio.play("sparkle")
		say("A quiet spot: the party rests.", UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				st.puff(actorAt(a) + Vector3.new(0, 1, 0), "heal", 6)
			end
		end
	elseif kind == "wild" then
		say("Wild driftlings!", UIKit.color("orange"))
	elseif kind == "boss" then
		local def = Islets.list[islet]
		say((if def then def.bossName else "The guardian") .. " blocks the way!", UIKit.color("bad"), 2.4)
	end
	target = nil
end

goHome = function()
	local e = exp()
	if e == nil then
		ExpeditionUI.close()
		return
	end
	busy = true
	local res = ask("exp.home", {})
	busy = false
	if res.ok then
		local got = if type(res.data) == "table" then res.data.got else nil
		ExpeditionUI.close()
		if type(got) == "table" then
			UIKit.notice(string.format("Home again: +%s shells, +%s food, +%s wood", Numbers.int(tonumber(got.shells) or 0), Numbers.int(tonumber(got.food) or 0), Numbers.int(tonumber(got.wood) or 0)), UIKit.color("good"), 4)
		end
		Audio.play("reward")
	else
		refresh()
	end
end

------------------------------------------------------------------ the overlay's layout
local function button(parent: Instance, text: string, x: number, y: number, w: number, color: Color3?, enabled: boolean, click: () -> (), name: string)
	local b = UIKit.button(parent, text, UDim2.fromOffset(w, 15), UDim2.fromOffset(x, y), click, { name = name, color = color, enabled = enabled and not busy })
	b.ZIndex = 11
end

refresh = function()
	local r = root
	local e = exp()
	if r == nil or not isOpen then
		return
	end
	-- everything but the curtain, a results card and the narration is laid out again
	for _, c in r:GetChildren() do
		if c.Name ~= "Curtain" and c.Name ~= "Result" and c.Name ~= "Say" and not c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if e == nil then
		return
	end
	if stage then
		buildParty(e)
		buildFoes(e)
	end
	table.clear(bars)
	local w, h = canvasSize()
	local def = Islets.list[e.islet]
	-- the header: the islet, the path, the loot, Back (below Roblox's top bar: its strip is the header's backdrop)
	local top = topInset()
	local back = UIKit.rect(r, UDim2.fromOffset(w, top), UDim2.fromOffset(0, 0), UIKit.color("ink"), 9)
	back.Name = "TopBar"
	back.BackgroundTransparency = 0.2
	local head = UIKit.rect(r, UDim2.fromOffset(w, HEAD_H), UDim2.fromOffset(0, top), UIKit.color("ink"), 9)
	head.Name = "Header"
	head.BackgroundTransparency = 0.2
	UIKit.rect(head, UDim2.fromOffset(w, 1), UDim2.fromOffset(0, HEAD_H - 1), UIKit.color(if def then def.color else "accent"), 9)
	UIKit.text(head, if def then def.name else "?", UDim2.fromOffset(100, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("accent"), z = 11, name = "Islet" })
	lootLine(head, e, 4, 10)
	local px = math.max(110, math.floor(w / 2) - #e.nodes * 7)
	for i, kind in e.nodes do
		local done = e.done[i]
		local here = i == e.node
		local name = "mini_" .. kind
		if i > 1 then
			UIKit.rect(head, UDim2.fromOffset(2, 1), UDim2.fromOffset(px - 2, 10), if done then UIKit.color("accent") else UIKit.color("plate_light"), 10)
		end
		local img = PixelSprites.image(head, if done or here or kind == "boss" then name else "mini_wild_sil", UDim2.fromOffset(px, if here then 2 else 5), 11)
		img.Name = "Node" .. i
		if here then
			UIKit.rect(head, UDim2.fromOffset(11, 1), UDim2.fromOffset(px, 15), UIKit.color("accent"), 10).Name = "Here"
		end
		px += 13
	end
	button(head, "Back to island", w - 72, 3, 68, UIKit.color("plate_light"), true, function()
		ExpeditionUI.close()
	end, "BackToIsland")
	-- the party along the bottom
	local foot = UIKit.rect(r, UDim2.fromOffset(w, FOOT_H), UDim2.fromOffset(0, h - FOOT_H), UIKit.color("ink"), 9)
	foot.Name = "Footer"
	foot.BackgroundTransparency = 0.2
	local cw = math.min(CARD_W, math.floor((w - 112) / 2) - 3)
	for i, f in e.party do
		local col, rowI = (i - 1) % 2, (i - 1) // 2
		fighterCard(foot, f, 4 + col * (cw + 3), 2 + rowI * 20, cw, false)
	end
	-- the foes down the right, under the header
	local b = e.battle
	if b then
		-- the treat's target: only a wild one still standing
		local ok = false
		for _, f in b.foes do
			if f.key == target and f.hp > 0 then
				ok = true
			end
		end
		if not ok then
			target = nil
		end
		local alive = 0
		for _, f in b.foes do
			if f.hp > 0 then
				alive += 1
				fighterCard(r, f, w - 86, top + HEAD_H + 2 + (alive - 1) * 20, 82, true)
			end
		end
	end
	-- the buttons
	local bx = w - 104
	if e.over then
		button(foot, "Sail home", bx, 13, 100, UIKit.color("button_ok"), true, goHome, "SailHome")
	elseif b then
		local treatOk = not b.boss
		button(foot, "Fight", bx, 4, 49, UIKit.color("button_ok"), true, function()
			doAct("fight")
		end, "Act_fight")
		button(foot, "Guard", bx + 51, 4, 49, nil, true, function()
			doAct("guard")
		end, "Act_guard")
		button(foot, "Treat", bx, 22, 49, UIKit.color("accent"), treatOk, function()
			doAct("treat")
		end, "Act_treat")
		button(foot, "Flee", bx + 51, 22, 49, UIKit.color("button_warn"), not b.boss, function()
			doAct("flee")
		end, "Act_flee")
		if treatOk then
			local tname = if target and bars[target] then bars[target].name else "the most hurt one"
			local hx = 4 + 2 * (cw + 3)
			UIKit.text(foot, string.format("Treat (%d food): %s", Tuning.TreatFood, tname), UDim2.fromOffset(math.max(10, bx - hx - 2), 9), UDim2.fromOffset(hx, 32), { color = UIKit.color("text_dim"), z = 11, name = "TreatHint" })
		end
	else
		local last = e.node >= #e.nodes
		button(foot, if last then "All explored" else "Go on!", bx, 4, 100, UIKit.color("button_ok"), not last, goOn, "GoOn")
		button(foot, "Sail home", bx, 22, 100, UIKit.color("button_warn"), true, goHome, "SailHome")
	end
	-- the wild ones' names stay on the cards; the stage's spots follow the fighters
	lastNode = e.node
end

------------------------------------------------------------------ open, close
function ExpeditionUI.isOpen(): boolean
	return isOpen
end

-- Whether an expedition is under way (the view's).
function ExpeditionUI.active(): boolean
	return exp() ~= nil
end

function ExpeditionUI.open()
	local e = exp()
	if isOpen then
		return
	end
	if e == nil then
		-- just set sail: the view with the expedition is on its way
		pendingOpen = os.clock() + 3
		return
	end
	pendingOpen = 0
	isOpen = true
	UIKit.closePanel()
	hideWorldUI(true)
	islet = e.islet
	local def = Islets.list[e.islet]
	local canvas = UIKit.canvas("Stage")
	local w, h = canvasSize()
	local r = Instance.new("Frame")
	r.Name = "Expedition"
	r.BackgroundTransparency = 1
	r.BorderSizePixel = 0
	r.Size = UDim2.fromOffset(w, h)
	r.Parent = canvas
	root = r
	stage = MicroStage.open(if def then def.stage else "loot", { top = topInset() + HEAD_H + 2, bottom = FOOT_H + 2 })
	actors = {}
	foeKey = ""
	target = nil
	lifted = false
	opened = os.clock()
	-- the founder stands with the party (MicroStage's own avatar)
	actors.f = newActor("f", false, PARTY_SPOTS[1])
	-- the curtain: ink blinds with the islet's name while the stage's picture is baked
	local curtain = Instance.new("Frame")
	curtain.Name = "Curtain"
	curtain.BackgroundTransparency = 1
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.ZIndex = 35
	curtain.Parent = r
	local BLIND = 12
	local blinds: { Frame } = {}
	for y = 0, h - 1, BLIND do
		local band = UIKit.rect(curtain, UDim2.fromOffset(w, math.min(BLIND, h - y)), UDim2.fromOffset(0, y), UIKit.color("ink"), 35)
		band.Name = "Blind"
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 35)
		table.insert(blinds, band)
	end
	PixelSprites.image(curtain, "mini_boat", UDim2.fromOffset(math.floor(w / 2) - 5, math.floor(h / 2) - 26), 40)
	UIKit.text(curtain, if def then def.name else "Expedition", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 12), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 40, name = "IsletName" })
	UIKit.text(curtain, if def then def.blurb else "", UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(8, math.floor(h / 2) + 8), { x = "center", color = UIKit.color("text"), z = 40, name = "Blurb" })
	Audio.play("trumpet")
	refresh()
	beat = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		if not lifted then
			local st = stage
			if st and ((st.ready() and now - opened >= 1.2) or now - opened > Tuning.StageWait) then
				lifted = true
				st.lift()
				local mid = #blinds / 2
				for i, band in blinds do
					local d = math.abs(i - 0.5 - mid) * 0.018
					local y0 = band.Position.Y.Offset
					local bh = band.Size.Y.Offset
					task.delay(d, function()
						if band.Parent then
							UIKit.tween(band, 0.16, { Size = UDim2.fromOffset(w, 0), Position = UDim2.fromOffset(0, y0 + math.floor(bh / 2)) })
						end
					end)
				end
				task.delay(0.5, function()
					if curtain.Parent then
						curtain:Destroy()
					end
				end)
			end
		end
		poseAll(now - opened, math.min(dt, 0.1))
	end)
	keys = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not lifted or busy then
			return
		end
		local cur = exp()
		if cur == nil then
			return
		end
		local k = input.KeyCode
		if cur.battle then
			if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.One then
				task.spawn(doAct, "fight")
			elseif k == Enum.KeyCode.Two then
				task.spawn(doAct, "guard")
			elseif k == Enum.KeyCode.Three then
				task.spawn(doAct, "treat")
			elseif k == Enum.KeyCode.Four then
				task.spawn(doAct, "flee")
			end
		elseif not cur.over and (k == Enum.KeyCode.Space or k == Enum.KeyCode.Return) then
			task.spawn(goOn)
		end
	end)
	ExpeditionUI.Changed:Fire(true)
end

function ExpeditionUI.close()
	if not isOpen then
		return
	end
	isOpen = false
	if beat then
		beat:Disconnect()
		beat = nil
	end
	if keys then
		keys:Disconnect()
		keys = nil
	end
	local st = stage
	stage = nil
	if st then
		st.close()
	end
	actors = {}
	table.clear(bars)
	local r = root
	root = nil
	if r then
		r:Destroy()
	end
	sayFrame = nil
	hideWorldUI(false)
	ExpeditionUI.Changed:Fire(false)
end

function ExpeditionUI.init()
	-- the view changed (the round's numbers settled, the expedition ended elsewhere): lay out again
	StateClient.Changed:Connect(function(v: Types.ClientView)
		if not isOpen then
			if v.exp ~= nil and os.clock() < pendingOpen then
				ExpeditionUI.open()
			end
			return
		end
		if v.exp == nil then
			ExpeditionUI.close()
			return
		end
		if not busy then
			refresh()
		end
	end)
end

-- Sims and previews: what is on screen, and the actions as a player would tap them (they yield).
function ExpeditionUI.debugState(): { [string]: any }
	local n = 0
	for _ in actors do
		n += 1
	end
	return { open = isOpen, lifted = lifted, actors = n, busy = busy, node = lastNode, foes = foeKey }
end
function ExpeditionUI.debugGo()
	goOn()
end
function ExpeditionUI.debugAct(kind: string)
	doAct(kind)
end
function ExpeditionUI.debugHome()
	goHome()
end

return ExpeditionUI
