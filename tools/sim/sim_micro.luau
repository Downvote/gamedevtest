-- The minigames (GAME_DESIGN 5; docs/ARCHITECTURE.md 7.4, 10.8): every one of the 24 ideas' party rounds played
-- through the real making card to a WIN by MicroUI.debugAuto (the rivals' brains at full skill steering the founder),
-- each of the 11 engines lost by doing nothing, a retry never losing a win, the difficulty from the rarity (and a
-- reused engine a step harder), the rivals and the scoreboard on the stage, each modifier's effect on the runner
-- (Turbo's speed and shorter fuse, Icy, Crowded's two more rivals, Frenzy, Shrinking's closing walls, Cosmic's three),
-- Play all chaining the slots, Launch only once all three are played, and the server's rules: a new start replaces
-- the one in play, a stale or wrong token refused, a win sooner than MicroMinSec a loss, a player leaving mid-game.
local E = require("./loader")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.dt = 0.05
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Ideas = H.sharedServer("Logic.Ideas")
local IdeasData = H.sharedServer("Data.Ideas")
local Modifiers = H.sharedServer("Data.Modifiers")

local p = H.addPlayer({ userId = 9401, name = "Gamer" })
E.run(1.5)
local prof = H.profile(p)
local s = H.session(p)
local MUI = H.cmod(p, "UI.MicroUI")
prof.tut = 0

-- A game whose first idea is `card`; play its slot 1 from the card (auto: the auto player; else hands off).
-- Returns whether it was won and the engine that ran.
local function playIdea(card: any, auto: boolean): (boolean, string?, any)
	prof.project = { title = "Test Game", ideas = { card, { id = "action", mod = "plain" }, { id = "puzzle", mod = "plain" } }, won = { -1, -1, -1 }, seed = 1 }
	H.push(p, 0.3)
	H.inClient(p, MUI.open)
	E.run(0.3)
	if not H.clickNamed(p, "Play_1", { wait = 0.1, optional = true }) then
		H.finding("micro", "no Play_1 button for " .. card.id)
		return false, nil, nil
	end
	local kind = H.inClient(p, MUI.playing)
	local ctx = H.inClient(p, MUI.debugCtx)
	-- the runner's layers, looked at while the game is up
	if ctx then
		ctx = table.clone(ctx)
		local board = ctx.area:FindFirstChild("Scoreboard")
		local rows = 0
		if board then
			for _, r in board:GetChildren() do
				if string.sub(r.Name, 1, 4) == "Row_" then
					rows += 1
				end
			end
		end
		ctx.rows = rows
		ctx.pads = ctx.area:FindFirstChild("Pad_up") ~= nil and ctx.area:FindFirstChild("Pad_go") ~= nil
	end
	E.runUntil(function()
		if auto then
			H.inClient(p, MUI.debugAuto)
		end
		local pr = prof.project
		return pr ~= nil and pr.won[1] >= 0
	end, Tuning.MicroMaxSec + 10, 0.05)
	E.run(0.4)
	local pr = prof.project
	return pr ~= nil and pr.won[1] == 1, kind, ctx
end

------------------------------------------------------------------ every idea, won
E.phase = "win-all"
local engines: { [string]: boolean } = {}
local wonCount = 0
for _, d in IdeasData.list do
	local won, kind, ctx = playIdea({ id = d.id, mod = "plain" }, true)
	H.expect(kind == d.micro, "micro", d.id .. " runs its engine " .. d.micro, tostring(kind))
	H.expect(ctx ~= nil and ctx.diff == Ideas.difficulty({ id = d.id, mod = "plain" }), "micro", d.id .. ": the difficulty from its rarity", tostring(ctx and ctx.diff))
	H.expect(ctx ~= nil and ctx.rivals == 3 and ctx.rows == 4 and ctx.pads, "micro", d.id .. ": three rivals on the scoreboard, the touch pads", string.format("%s rivals, %s rows", tostring(ctx and ctx.rivals), tostring(ctx and ctx.rows)))
	if won then
		wonCount += 1
		engines[d.micro] = true
	end
	H.expect(won, "micro", d.id .. " won by the auto player")
end
H.expect(wonCount == #IdeasData.list, "micro", "every idea's microgame can be won", string.format("%d of %d", wonCount, #IdeasData.list))
H.expect(H.buttonNamed(p, "Retry_1") ~= nil, "micro", "a played slot offers Retry")

------------------------------------------------------------------ every engine, lost by doing nothing
E.phase = "lose"
local tried: { [string]: boolean } = {}
for _, d in IdeasData.list do
	if not tried[d.micro] then
		tried[d.micro] = true
		local won = playIdea({ id = d.id, mod = "plain" }, false)
		H.expect(not won, "micro", d.micro .. " (" .. d.id .. ") is lost doing nothing")
		H.expect(prof.project.won[1] == 0, "micro", d.micro .. ": a loss is recorded", tostring(prof.project.won[1]))
	end
end

------------------------------------------------------------------ a retry never loses a win
E.phase = "retry"
local won = playIdea({ id = "animals", mod = "plain" }, true)
H.expect(won, "micro", "a win first")
H.clickNamed(p, "Retry_1", { wait = 0.1 })
E.runUntil(function()
	return s.micro == nil and H.inClient(p, MUI.playing) == nil and H.buttonNamed(p, "Retry_1") ~= nil
end, 60, 0.05)
E.run(0.4)
H.expect(prof.project.won[1] == 1, "micro", "a lost retry keeps the win")

------------------------------------------------------------------ the modifiers
E.phase = "modifiers"
local _, _, plainCtx = playIdea({ id = "action", mod = "plain" }, true)
for _, m in Modifiers.list do
	if m.id ~= "plain" then
		local w, kind, ctx = playIdea({ id = "action", mod = m.id }, true)
		local e = {}
		for _, x in m.effects do
			e[x] = true
		end
		if ctx then
			H.expect(ctx.diff > plainCtx.diff or m.odds < 10, "micro", m.id .. ": a rarer card plays harder", string.format("%d vs %d", ctx.diff, plainCtx.diff))
			H.expect((ctx.speed > 1) == (e.speed == true), "micro", m.id .. ": the speed effect", tostring(ctx.speed))
			H.expect(ctx.ice == (e.ice == true), "micro", m.id .. ": the icy floor", tostring(ctx.ice))
			H.expect((ctx.more > 1) == (e.more == true), "micro", m.id .. ": more of everything", tostring(ctx.more))
			H.expect(ctx.shrink == (e.shrink == true), "micro", m.id .. ": the closing walls", tostring(ctx.shrink))
			H.expect(ctx.rivals == (if e.rival then 5 else 3) and ctx.rows == ctx.rivals + 1, "micro", m.id .. ": the rivals", string.format("%s rivals, %s rows", tostring(ctx.rivals), tostring(ctx.rows)))
			if e.speed then
				H.expect(math.abs(ctx.seconds - plainCtx.seconds * Tuning.TurboClock) < 1e-6, "micro", m.id .. ": a shorter fuse", string.format("%.2f vs %.2f", ctx.seconds, plainCtx.seconds))
			end
		else
			H.finding("micro", m.id .. ": no runner settings")
		end
		H.expect(kind == "bombs", "micro", m.id .. ": still Action's engine")
		local _ = w
	end
end
-- Tuning.TurboClock and the effects lists stay what the design says
H.expect(#Modifiers.byId.cosmic.effects == 3, "micro", "Cosmic is Turbo, Frenzy and Shrinking at once")

------------------------------------------------------------------ Play all and Launch
E.phase = "play-all"
prof.project = { title = "Chain", ideas = { { id = "animals", mod = "plain" }, { id = "puzzle", mod = "plain" }, { id = "school", mod = "plain" } }, won = { -1, -1, -1 }, seed = 2 }
H.push(p, 0.3)
H.inClient(p, MUI.open)
E.run(0.3)
H.expect(H.buttonNamed(p, "Launch", true) ~= nil and H.buttonNamed(p, "Launch") == nil, "micro", "Launch! is off before the minigames")
local res = H.req(p, "game.launch", {})
H.expect(not res.ok and res.err == "not_built", "micro", "and the server refuses it", tostring(res.err))
H.clickNamed(p, "PlayAll", { wait = 0.1 })
local seen: { [number]: boolean } = {}
E.runUntil(function()
	if s.micro then
		seen[s.micro.slot] = true
	end
	H.inClient(p, MUI.debugAuto)
	local pr = prof.project
	return pr ~= nil and pr.won[3] >= 0 and H.buttonNamed(p, "Launch") ~= nil
end, 240, 0.05)
H.expect(seen[1] and seen[2] and seen[3], "micro", "Play all plays the three in turn")
H.expect(prof.project.won[1] >= 0 and prof.project.won[2] >= 0 and prof.project.won[3] >= 0, "micro", "all three played")
H.clickNamed(p, "Launch", { wait = 0.8 })
H.expect(prof.project == nil and prof.live ~= nil and prof.live.id == prof.games[#prof.games].id, "micro", "launched: it is on sale")
H.clickNamed(p, "Nice", { wait = 0.4 })

------------------------------------------------------------------ the server's rules
E.phase = "rules"
prof.project = { title = "Rules", ideas = { { id = "action", mod = "plain" }, { id = "puzzle", mod = "plain" }, { id = "space", mod = "plain" } }, won = { -1, -1, -1 }, seed = 3 }
H.push(p, 0.3)
local r1 = H.req(p, "micro.start", { slot = 1 })
local r2 = H.req(p, "micro.start", { slot = 2 })
H.expect(r1.ok and r2.ok and s.micro and s.micro.slot == 2, "micro", "a new start replaces the one in play (retry at any time)")
res = H.req(p, "micro.finish", { token = r1.data.token, won = 1 })
H.expect(not res.ok and res.err == "busy", "micro", "the replaced game's token is refused", tostring(res.err))
res = H.req(p, "micro.finish", { token = (r2.data.token + 1) % 1000000, won = 1 })
H.expect(not res.ok and res.err == "busy", "micro", "a wrong token is refused")
res = H.req(p, "micro.finish", { token = r2.data.token, won = 1 })
H.expect(res.ok and prof.project.won[2] == 0, "micro", "a win sooner than MicroMinSec counts as a loss", tostring(prof.project.won[2]))
r1 = H.req(p, "micro.start", { slot = 3 })
E.run(Tuning.MicroMinSec + 0.3)
res = H.req(p, "micro.finish", { token = r1.data.token, won = 1 })
H.expect(res.ok and prof.project.won[3] == 1, "micro", "a fair win counts")
H.expect(r1.data.diff == Ideas.difficulty({ id = "space", mod = "plain" }) and r1.data.card.id == "space", "micro", "the start answers the difficulty and the idea")
res = H.req(p, "micro.finish", { token = r1.data.token, won = 1 })
H.expect(not res.ok, "micro", "a finished game cannot be finished again")
-- junk
for _, payload in { { slot = 0 }, { slot = 4 }, { slot = 1.5 }, { slot = "1" }, {} } :: { any } do
	local okCall, r = H.raw(p, "micro.start", payload)
	H.expect(okCall and type(r) == "table" and r.err == "bad_payload", "micro", "junk start refused", tostring(r and r.err))
end
for _, payload in { { token = 1, won = 2 }, { token = -1, won = 1 }, { token = 1, won = true }, { won = 1 } } :: { any } do
	local okCall, r = H.raw(p, "micro.finish", payload)
	H.expect(okCall and type(r) == "table" and r.err == "bad_payload", "micro", "junk finish refused", tostring(r and r.err))
end

------------------------------------------------------------------ leaving mid-game
E.phase = "leave"
local q = H.addPlayer({ userId = 9402, name = "Quitter" })
E.run(1.5)
local qp = H.profile(q)
qp.ideas = { { id = "action", mod = "plain" }, { id = "puzzle", mod = "plain" }, { id = "space", mod = "plain" } }
H.push(q, 0.3)
H.req(q, "game.make", { a = 1, b = 2, c = 3 })
res = H.req(q, "micro.start", { slot = 1 })
H.expect(res.ok, "micro", "the second player starts a microgame", tostring(res.err))
E.removePlayer(q, "leave")
E.run(3)
H.expect(H.session(q) == nil and H.session(p) ~= nil, "micro", "the leaver's session is gone, the first plays on")

E.run(0.5)
H.checkProfile(p, "micro")
H.checkMirror(p, "micro")
report(E, H)
