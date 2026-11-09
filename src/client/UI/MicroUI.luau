--!strict
-- Making a game (GAME_DESIGN 5, 6; docs/ARCHITECTURE.md 10.8): the card with the game's three ideas, each one's
-- microgame (Play, Retry at any time, or Play all for the ones not played yet), the sales boost so far, and Launch!
-- once all three have been played. A microgame: the server starts it (micro.start: a token, a seed, the difficulty),
-- its order word drops in (MicroIntro), then the engine (UI/MicroGames) runs on a fuse that shortens with the
-- difficulty; the idea's modifier changes how it plays (Turbo faster on a shorter fuse, Tiny small targets, Shaky
-- the screen shakes, Glitched it blinks out, Haunted only a roving spotlight shows it, Cosmic all but the dark). A
-- WIN or LOSE stamp, then micro.finish with the result. The launch card shows the income it earns for good. While a
-- microgame runs its keys are bound above the founder's walking keys.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local IdeasData = require(ReplicatedStorage.Shared.Data.Ideas)
local Modifiers = require(ReplicatedStorage.Shared.Data.Modifiers)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Ideas = require(ReplicatedStorage.Shared.Logic.Ideas)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Games = require(script.Parent.MicroGames)
local Words = require(script.Parent.Words)

local MicroUI = {}

-- A game was launched (the server's Game record): the HUD cheers.
MicroUI.Launched = Util.Signal() :: Types.Signal<Types.Game>

local ACTION = "BSS_Micro"
local KEYMAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.D] = "right",
	[Enum.KeyCode.Space] = "go",
	[Enum.KeyCode.Return] = "go",
	[Enum.KeyCode.F] = "go",
	[Enum.KeyCode.J] = "go",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
}

local shade: TextButton? = nil
local frame: Frame? = nil
local mode: string? = nil -- "card" | "play" | "launch"
local playing: Games.Micro? = nil
local playingKind: string? = nil
local pendingOpen = 0 -- os.clock until which the card opens as soon as the view has the project (just made)
local lastCtx: { [string]: any }? = nil -- the microgame in play's settings (MicroUI.debugCtx)

local function close()
	local s = shade
	shade, frame, mode, playing, playingKind = nil, nil, nil, nil, nil
	if s then
		s:Destroy()
	end
end

-- The card's frame (made once while open; its content is cleared and rebuilt for each screen).
local function ensureFrame(): Frame
	if frame and shade and shade.Parent then
		return frame :: Frame
	end
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local sh = Instance.new("TextButton")
	sh.Name = "MicroCard"
	sh.Text = ""
	sh.AutoButtonColor = false
	sh.BackgroundColor3 = UIKit.color("ink")
	sh.BackgroundTransparency = 1
	sh.BorderSizePixel = 0
	sh.Size = UDim2.fromScale(1, 1)
	sh.ZIndex = 5
	local w, h = math.min(280, s.X - 8), math.min(178, s.Y - 6)
	local x, y = math.floor((s.X - w) / 2), math.floor((s.Y - h) / 2)
	local f = UIKit.plate(sh, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y + 10), UIKit.color("plate"), 0, 3)
	f.Name = "Frame"
	f.ZIndex = 6
	sh.Parent = canvas
	UIKit.tween(sh, 0.15, { BackgroundTransparency = 0.4 })
	UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y) })
	Audio.play("open")
	shade, frame = sh, f
	return f
end

local function clearFrame(f: Frame)
	for _, c in f:GetChildren() do
		if c.Name ~= "Fill" then
			c:Destroy()
		end
	end
end

function MicroUI.isOpen(): boolean
	return shade ~= nil
end

------------------------------------------------------------------ the card
local function modTag(c: Types.Card): string
	local m = Modifiers.byId[c.mod]
	return if m and m.id ~= "plain" then m.name else ""
end

local showCard: () -> ()

local function nextUnplayed(proj: Types.Making, after: number): number?
	for i = after + 1, 3 do
		if proj.won[i] < 0 then
			return i
		end
	end
	return nil
end

local playSlot: (slot: number, chain: boolean) -> ()

showCard = function()
	local v = StateClient.view()
	local proj = if v then v.project else nil
	if proj == nil then
		close()
		return
	end
	local p = proj :: Types.Making
	local f = ensureFrame()
	clearFrame(f)
	mode = "card"
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	UIKit.text(f, "Making", UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 3), { color = UIKit.color("text_dim"), z = 7 })
	UIKit.text(f, p.title, UDim2.fromOffset(w - 12, 18), UDim2.fromOffset(6, 11), { face = "big", kind = "title", color = UIKit.color("accent"), z = 7, name = "GameTitle" })
	local rowH = math.min(32, math.floor((h - 66) / 3))
	local played, wins = true, 0
	for i, c in p.ideas do
		local y = 31 + (i - 1) * (rowH + 2)
		local def = IdeasData.byId[c.id]
		local r = UIKit.plate(f, UDim2.fromOffset(w - 12, rowH), UDim2.fromOffset(6, y), UIKit.color("plate_light"), 0, 2)
		r.Name = "Slot_" .. i
		r.ZIndex = 7
		local icon = PixelSprites.ICONS[c.id]
		if icon then
			PixelSprites.sprite(r, icon, UDim2.fromOffset(4, math.floor((rowH - 16) / 2)), 2, 8)
		end
		local tier = Ideas.tier(c)
		UIKit.text(r, Ideas.name(c), UDim2.fromOffset(w - 110, 10), UDim2.fromOffset(24, 2), { color = UIKit.color(Ideas.tierColor(tier)), z = 8 })
		local mod = Modifiers.byId[c.mod]
		local sub = string.format('"%s"  %sDifficulty %d', if def then def.word else "", if mod and mod.id ~= "plain" then mod.name .. "  " else "", Ideas.difficulty(c))
		UIKit.text(r, sub, UDim2.fromOffset(w - 110, 10), UDim2.fromOffset(24, rowH - 12), { color = UIKit.color("text_dim"), z = 8 })
		local won = p.won[i]
		played = played and won >= 0
		if won == 1 then
			wins += 1
		end
		UIKit.text(r, if won == 1 then "WIN" elseif won == 0 then "LOSE" else "", UDim2.fromOffset(34, 10), UDim2.new(1, -86, 0, math.floor(rowH / 2) - 5), { x = "right", color = if won == 1 then UIKit.color("good") else UIKit.color("bad"), z = 8, name = "Result" })
		local b = UIKit.button(r, if won < 0 then "Play" else "Retry", UDim2.fromOffset(44, 14), UDim2.new(1, -48, 0, math.floor((rowH - 14) / 2)), function()
			playSlot(i, false)
		end, { name = (if won < 0 then "Play_" else "Retry_") .. i, color = if won < 0 then UIKit.color("accent") else UIKit.color("plate"), textColor = if won < 0 then UIKit.color("ink") else nil })
		b.ZIndex = 8
	end
	UIKit.text(f, string.format("Sales x%.2f  (each win +%d%%)", 1 + Tuning.WinBoost * wins, math.floor(Tuning.WinBoost * 100 + 0.5)), UDim2.fromOffset(w - 12, 10), UDim2.new(0, 6, 1, -30), { color = UIKit.color("good"), z = 7, name = "Boost" })
	local bw = math.floor((w - 18) / 3)
	local first = nextUnplayed(p, 0)
	local pa = UIKit.button(f, "Play all", UDim2.fromOffset(bw, 14), UDim2.new(0, 6, 1, -18), function()
		local n = nextUnplayed(p, 0)
		if n then
			playSlot(n, true)
		end
	end, { name = "PlayAll", color = UIKit.color("accent"), textColor = UIKit.color("ink"), enabled = first ~= nil })
	pa.ZIndex = 7
	local la = UIKit.button(f, "Launch!", UDim2.fromOffset(bw, 14), UDim2.new(0, 9 + bw, 1, -18), function()
		local res = StateClient.request("game.launch", {})
		if res.ok and type(res.data) == "table" then
			MicroUI.showLaunch(res.data :: Types.Game)
		else
			Audio.play("deny")
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		end
	end, { name = "Launch", color = UIKit.color("button_ok"), enabled = played })
	la.ZIndex = 7
	local cl = UIKit.button(f, "Later", UDim2.fromOffset(bw, 14), UDim2.new(0, 12 + 2 * bw, 1, -18), function()
		Audio.play("close")
		close()
	end, { name = "CloseMicro", color = UIKit.color("plate_light") })
	cl.ZIndex = 7
end

------------------------------------------------------------------ a microgame
local function bindKeys(fn: (string) -> ()): () -> ()
	local keys: { Enum.KeyCode } = {}
	for k in KEYMAP do
		table.insert(keys, k)
	end
	local ok = pcall(function()
		ContextActionService:BindActionAtPriority(ACTION, function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				local m = KEYMAP[input.KeyCode]
				if m then
					fn(m)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
	end)
	if ok then
		return function()
			pcall(function()
				ContextActionService:UnbindAction(ACTION)
			end)
		end
	end
	local conn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed then
			local m = KEYMAP[input.KeyCode]
			if m then
				fn(m)
			end
		end
	end)
	return function()
		conn:Disconnect()
	end
end

local function has(list: { string }, x: string): boolean
	return table.find(list, x) ~= nil
end

playSlot = function(slot: number, chain: boolean)
	local v = StateClient.view()
	local proj = if v then v.project else nil
	if proj == nil or mode == "play" then
		return
	end
	local card = (proj :: Types.Making).ideas[slot]
	local def = IdeasData.byId[card.id]
	local mod = Modifiers.byId[card.mod]
	if def == nil or mod == nil then
		return
	end
	mode = "play"
	local asked = os.clock()
	local res = StateClient.request("micro.start", { slot = slot })
	if not res.ok or type(res.data) ~= "table" then
		mode = "card"
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		showCard()
		return
	end
	local data = res.data :: { [string]: any }
	local token = tonumber(data.token) or 0
	local diff = math.clamp(tonumber(data.diff) or 1, 1, Tuning.DiffMax)
	local f = ensureFrame()
	clearFrame(f)
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	local effects = mod.effects
	local tier = Ideas.tier(card)
	-- the header: the idea, its modifier, the difficulty
	local icon = PixelSprites.ICONS[card.id]
	if icon then
		PixelSprites.sprite(f, icon, UDim2.fromOffset(6, 4), 2, 7)
	end
	UIKit.text(f, Ideas.name(card), UDim2.fromOffset(w - 90, 10), UDim2.fromOffset(26, 3), { color = UIKit.color(Ideas.tierColor(tier)), z = 7, name = "IdeaName" })
	UIKit.text(f, string.format("Idea %d of 3  Difficulty %d", slot, diff), UDim2.fromOffset(w - 90, 10), UDim2.fromOffset(26, 12), { color = UIKit.color("text_dim"), z = 7 })
	if mod.id ~= "plain" then
		local tw = UIKit.textWidth(mod.name) + 8
		UIKit.plate(f, UDim2.fromOffset(tw, 12), UDim2.new(1, -tw - 6, 0, 4), UIKit.color(mod.color), 0, 2).ZIndex = 7
		UIKit.text(f, mod.name, UDim2.fromOffset(tw, 12), UDim2.new(1, -tw - 6, 0, 4), { x = "center", color = UIKit.color("ink"), kind = "plain", z = 8, name = "ModTag" })
	end
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundColor3 = UIKit.color("ink")
	area.BackgroundTransparency = 0.6
	area.BorderSizePixel = 0
	area.Size = UDim2.fromOffset(w - 12, h - 50)
	area.Position = UDim2.fromOffset(6, 24)
	area.ZIndex = 7
	area.ClipsDescendants = true
	area.Parent = f
	local areaPos = area.Position
	-- the fuse
	local fuseBack = UIKit.rect(f, UDim2.fromOffset(w - 12, 4), UDim2.new(0, 6, 1, -22), UIKit.color("plate_light"), 7)
	fuseBack.Name = "FuseBack"
	local fuse = UIKit.rect(f, UDim2.fromOffset(w - 12, 4), UDim2.new(0, 6, 1, -22), UIKit.color("accent"), 8)
	fuse.Name = "Fuse"
	local spark = UIKit.rect(f, UDim2.fromOffset(3, 6), UDim2.new(0, w - 9, 1, -23), UIKit.color("yellow"), 9)
	spark.Name = "Spark"
	local hintText = string.format('"%s"  %s', def.word, if #effects > 0 then mod.blurb else "")
	UIKit.text(f, hintText, UDim2.fromOffset(w - 12, 10), UDim2.new(0, 6, 1, -14), { color = UIKit.color("text_dim"), z = 7, name = "Hint" })

	-- floating words
	type Pop = { l: TextLabel, x: number, y: number, t0: number }
	local pops: { Pop } = {}
	local shakeUntil = 0
	local outcome: boolean? = nil
	local aw, ah = area.Size.X.Offset, area.Size.Y.Offset
	local engine: Games.Micro? = nil
	local ctx: Games.Ctx = {
		area = area,
		w = aw,
		h = ah,
		rng = Util.newRng(tonumber(data.seed) or 1),
		diff = diff,
		speed = if has(effects, "speed") then Tuning.TurboSpeed else 1,
		px = if has(effects, "tiny") then 1 else 2,
		variant = def.variant,
		pop = function(x: number, y: number, text: string, color: Color3)
			local tw = UIKit.textWidth(text) + 4
			local l = UIKit.text(area, text, UDim2.fromOffset(tw, 10), UDim2.fromOffset(math.floor(x - tw / 2), math.floor(y)), { x = "center", color = color, kind = "outline", z = 30, name = "Pop" })
			table.insert(pops, { l = l, x = math.floor(x - tw / 2), y = math.floor(y), t0 = os.clock() })
		end,
		shake = function()
			shakeUntil = os.clock() + 0.25
		end,
		win = function()
			if outcome == nil then
				outcome = true
			end
		end,
		lose = function()
			if outcome == nil then
				outcome = false
			end
		end,
		press = function(k: string)
			local e = engine
			if e and outcome == nil then
				e.key(k)
			end
		end,
	}
	local okE, built = pcall(function(): Games.Micro
		return (Games :: any)[def.micro](ctx)
	end)
	if not okE then
		warn("[MicroUI] " .. def.micro .. ": " .. tostring(built))
		built = { update = function() end, key = function() end, auto = function() end, survive = true }
	end
	engine = built :: Games.Micro
	local eng = engine :: Games.Micro
	playing, playingKind = eng, def.micro
	local base = math.max(Tuning.MicroSecondsMin, Tuning.MicroSeconds - Tuning.MicroSecondsStep * (diff - 1))
	local seconds = math.min(Tuning.MicroMaxSec - 10, base * (eng.clock or 1) * (if has(effects, "speed") then Tuning.TurboClock else 1))
	if eng.clock == 99 then
		seconds = Tuning.MicroMaxSec - 10 -- the song decides when it ends
	end
	lastCtx = { diff = diff, speed = ctx.speed, px = ctx.px, seconds = seconds, effects = effects, micro = def.micro, area = area }

	-- the modifiers' screen effects
	local dark: { Frame } = {}
	if has(effects, "dark") then
		for i = 1, 4 do
			local r = UIKit.rect(area, UDim2.fromOffset(1, 1), nil, UIKit.color("ink"), 25)
			r.Name = "Dark" .. i
			r.Active = false
			table.insert(dark, r)
		end
	end
	local glitchAt, glitchUntil = 0.6, 0
	local fx = Instance.new("Frame")
	fx.Name = "GlitchFlash"
	fx.BackgroundColor3 = UIKit.color("screen_code")
	fx.BackgroundTransparency = 1
	fx.BorderSizePixel = 0
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 26
	fx.Active = false
	fx.Parent = area

	-- the order word drops in
	local word = UIKit.text(f, def.word, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 30), { x = "center", face = "big", kind = "title", color = UIKit.color(Ideas.tierColor(math.max(2, tier))), z = 40, name = "Word" })
	UIKit.tween(word, 0.18, { Position = UDim2.fromOffset(0, math.floor(h / 2) - 14) })
	Audio.play("ding")

	local unbind = bindKeys(function(k: string)
		if outcome == nil and mode == "play" then
			eng.key(k)
		end
	end)
	local t0 = os.clock() + Tuning.MicroIntro
	local last = t0
	local finished = false
	local conn: RBXScriptConnection? = nil
	local function finish(won: boolean)
		if finished then
			return
		end
		finished = true
		playing, playingKind = nil, nil
		if conn then
			conn:Disconnect()
		end
		unbind()
		-- the stamp
		local stamp = UIKit.text(f, if won then "WIN!" else "LOSE", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 40), { x = "center", face = "big", kind = "title", color = if won then UIKit.color("good") else UIKit.color("bad"), z = 40, name = "Stamp" })
		UIKit.tween(stamp, 0.15, { Position = UDim2.fromOffset(0, math.floor(h / 2) - 12) })
		if won then
			Audio.play("combo")
			UIKit.confetti(area, 18)
		else
			Audio.play("deny")
		end
		task.spawn(function()
			local wait = math.max(0.9, Tuning.MicroMinSec + 0.2 - (os.clock() - asked))
			task.wait(wait)
			local fin = StateClient.request("micro.finish", { token = token, won = if won then 1 else 0 })
			if shade == nil then
				return
			end
			mode = "card"
			if not fin.ok then
				UIKit.notice(Words.errText(fin.err), UIKit.color("bad"))
			end
			-- the view lags a moment behind the answer: show the result now, then the card follows the view
			local pv = StateClient.view()
			local pp = if pv then pv.project else nil
			if fin.ok and pp and type(fin.data) == "table" then
				pp.won[slot] = if fin.data.won == true then 1 else math.max(pp.won[slot], 0)
			end
			local n = if chain and pp then nextUnplayed(pp, slot) else nil
			if n then
				playSlot(n, true)
			else
				showCard()
			end
		end)
	end
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if f.Parent == nil or shade == nil then
			if conn then
				conn:Disconnect()
			end
			unbind()
			playing, playingKind = nil, nil
			return
		end
		for i = #pops, 1, -1 do
			local p = pops[i]
			local pt = now - p.t0
			if pt > 0.7 or p.l.Parent == nil then
				p.l:Destroy()
				table.remove(pops, i)
			else
				p.l.Position = UDim2.fromOffset(p.x, p.y - math.floor(pt * 18))
			end
		end
		if now < t0 then
			return
		end
		if word.Parent then
			word:Destroy()
		end
		local t = now - t0
		local dt = math.min(0.1, now - last)
		last = now
		if outcome == nil then
			local ok, err = pcall(function()
				eng.update(t, dt)
			end)
			if not ok then
				warn("[MicroUI] " .. def.micro .. ": " .. tostring(err))
				outcome = false
			end
		end
		-- the fuse burns down
		local left = math.clamp(1 - t / seconds, 0, 1)
		fuse.Size = UDim2.fromOffset(math.floor((w - 12) * left), 4)
		spark.Position = UDim2.new(0, 6 + math.floor((w - 12) * left) - 1, 1, -23)
		spark.BackgroundColor3 = if math.floor(now * 12) % 2 == 0 then UIKit.color("yellow") else UIKit.color("orange")
		fuse.BackgroundColor3 = if left < 0.3 then UIKit.color("bad") else UIKit.color("accent")
		-- the modifiers
		local ox, oy = 0, 0
		if has(effects, "shake") then
			ox, oy = math.floor(math.sin(now * 37) * 2 + 0.5), math.floor(math.cos(now * 29) * 2 + 0.5)
		end
		if now < shakeUntil then
			ox += if math.floor(now * 40) % 2 == 0 then 2 else -2
		end
		area.Position = UDim2.new(areaPos.X.Scale, areaPos.X.Offset + ox, areaPos.Y.Scale, areaPos.Y.Offset + oy)
		if has(effects, "glitch") then
			if t >= glitchAt then
				glitchUntil = t + 0.1 + 0.08 * ctx.rng:next()
				glitchAt = t + 0.55 + 0.4 * ctx.rng:next()
			end
			local off = t < glitchUntil
			fx.BackgroundTransparency = if off then 0 else 1
		end
		if #dark == 4 then
			local hw, hh = math.floor(aw * 0.5), math.floor(ah * 0.6)
			local cx = math.floor(aw / 2 + math.cos(t * 1.3) * aw * 0.28)
			local cy = math.floor(ah / 2 + math.sin(t * 1.9) * ah * 0.22)
			local x0, y0 = math.clamp(cx - hw // 2, 0, aw), math.clamp(cy - hh // 2, 0, ah)
			local x1, y1 = math.clamp(cx + hw // 2, 0, aw), math.clamp(cy + hh // 2, 0, ah)
			dark[1].Position, dark[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(aw, y0)
			dark[2].Position, dark[2].Size = UDim2.fromOffset(0, y1), UDim2.fromOffset(aw, ah - y1)
			dark[3].Position, dark[3].Size = UDim2.fromOffset(0, y0), UDim2.fromOffset(x0, y1 - y0)
			dark[4].Position, dark[4].Size = UDim2.fromOffset(x1, y0), UDim2.fromOffset(aw - x1, y1 - y0)
		end
		if outcome ~= nil then
			finish(outcome :: boolean)
		elseif t >= seconds then
			finish(eng.survive == true)
		end
	end)
end

------------------------------------------------------------------ the launch
function MicroUI.showLaunch(g: Types.Game)
	local f = ensureFrame()
	clearFrame(f)
	mode = "launch"
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	UIKit.text(f, "Launched!", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, 10), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 7, name = "Launched" })
	UIKit.text(f, g.title, UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 32), { x = "center", color = UIKit.color("text"), z = 7, name = "GameTitle" })
	for i, c in g.ideas do
		local x = math.floor(w / 2 - 54 + (i - 1) * 40)
		local icon = PixelSprites.ICONS[c.id]
		if icon then
			PixelSprites.sprite(f, icon, UDim2.fromOffset(x + 4, 46), 3, 7)
		end
	end
	UIKit.text(f, string.format("%d of 3 minigames won: sales x%.2f", g.wins, 1 + Tuning.WinBoost * g.wins), UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 74), { x = "center", color = UIKit.color("good"), z = 7 })
	UIKit.text(f, Numbers.rate(g.rate) .. " coins", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, 88), { x = "center", face = "big", kind = "title", color = UIKit.color("good"), z = 7, name = "Rate" })
	UIKit.text(f, "It earns this for good, even while you make the next one.", UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 110), { x = "center", color = UIKit.color("text_dim"), z = 7 })
	local nice = UIKit.button(f, "Nice!", UDim2.fromOffset(60, 14), UDim2.new(0.5, -30, 1, -20), function()
		close()
		MicroUI.Launched:Fire(g)
	end, { name = "Nice", color = UIKit.color("button_ok") })
	nice.ZIndex = 7
	Audio.play(if g.wins == 3 then "rare_fanfare" else "fanfare")
	task.delay(0.15, function()
		if f.Parent then
			UIKit.confetti(f, if g.wins == 3 then 50 else 26)
		end
	end)
	local _ = h
end

------------------------------------------------------------------ API
-- The card for the game being made.
function MicroUI.open()
	if mode == "play" then
		return
	end
	UIKit.closePanel()
	local v = StateClient.view()
	if v == nil or v.project == nil then
		-- just made: the view with the project is on its way
		pendingOpen = os.clock() + 3
		return
	end
	showCard()
end

-- After a new view: the card follows it (not while a microgame or the launch card is up).
function MicroUI.refresh()
	if mode == "card" then
		showCard()
	elseif mode == nil and os.clock() < pendingOpen then
		local v = StateClient.view()
		if v and v.project then
			pendingOpen = 0
			showCard()
		end
	end
end

-- The engine of the microgame in play, or nil (the sims and the previews).
function MicroUI.playing(): string?
	return playingKind
end

-- One right move in the microgame in play (the sims' and the previews' player).
function MicroUI.debugAuto()
	local e = playing
	if e then
		e.auto()
	end
end

-- The last microgame's settings: diff, speed, px, seconds, effects, micro, area (the sims).
function MicroUI.debugCtx(): { [string]: any }?
	return lastCtx
end

-- Play a slot from code (the sims and the previews), as the card's Play button does.
function MicroUI.play(slot: number, chain: boolean?)
	playSlot(slot, chain == true)
end

function MicroUI.init() end

return MicroUI
