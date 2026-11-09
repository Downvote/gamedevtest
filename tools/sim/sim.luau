-- The main simulation: a new studio's first game end to end through the real client and its UI (the idea team's
-- first ideas, the board, Make, the three microgames played by MicroUI.debugAuto, Launch, the income), the upgrades,
-- the founder's looks, the panels, settings, the tips banner, then a malicious client, then a second player. Every
-- check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
local E = require("./loader")
local I = require("./inst")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.verboseUi = false
E.dt = 0.05
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Ideas = H.sharedServer("Logic.Ideas")
local getD = I.getD
local _ = getD

------------------------------------------------------------------ 1. a new studio
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(1.5)
local fx = H.watchFx(p)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(#prof.team == Tuning.TeamSize, "join", "an idea team of three", tostring(#prof.team))
H.expect(prof.coins == Tuning.StartCoins and prof.live == nil, "join", "no coins, no game on sale yet", tostring(prof.coins))
H.expect(prof.office == 1 and prof.tut == 1 and #prof.ideas == 0 and prof.project == nil, "join", "the garage, tips at step 1, an empty board")
H.expect(s.plot == 1, "join", "the first player gets plot 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local officeF = static and static:FindFirstChild("Office")
local office = officeF and officeF:FindFirstChild("Office")
H.expect(office ~= nil and office:GetAttribute("Tier") == 1, "join", "the garage is built under Plots.Plot_1.Static.Office")
local WV = H.cmod(p, "Controllers.WorldView")
H.expect(WV.ownRigCount() == Tuning.TeamSize, "join", "a rig per team member", tostring(WV.ownRigCount()))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there")
H.expect(H.buttonNamed(p, "MakeGame", true) ~= nil and H.buttonNamed(p, "MakeGame") == nil, "join", "the board card's Make a game! waits for three ideas")
H.checkProfile(p, "join")
H.checkMirror(p, "join")

------------------------------------------------------------------ 2. the idea team's ideas
E.phase = "ideas"
local function ideaFx(i0: number): number
	local n = 0
	for i = i0 + 1, #fx do
		if fx[i].kind == "idea" then
			n += 1
		end
	end
	return n
end
local f0 = #fx
E.run(Tuning.RollBase + 0.4)
H.expect(prof.stats.rolls == 1 and #prof.ideas == 1, "ideas", "an idea after RollBase seconds", string.format("%d rolls, %d on the board", prof.stats.rolls, #prof.ideas))
H.expect(ideaFx(f0) == 1, "ideas", "the client hears of it (Fx idea)")
local c1 = prof.ideas[1]
H.expect(Ideas.valid(c1) and prof.found[Ideas.key(c1)] == 1, "ideas", "it is in the Index")
E.runUntil(function()
	return #prof.ideas >= 3
end, Tuning.RollBase * 3, 0.1)
E.run(0.5)
H.expect(#prof.ideas >= 3, "ideas", "three ideas within three rolls", tostring(#prof.ideas))
H.expect(H.buttonNamed(p, "MakeGame") ~= nil, "ideas", "Make a game! is on")
H.checkMirror(p, "ideas")

------------------------------------------------------------------ 3. making a game through the UI
E.phase = "make"
H.clickNamed(p, "MakeGame", { wait = 0.5 })
H.expect(H.currentPanel(p) == "ideas", "make", "the idea board opens", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "Make", true) ~= nil and H.buttonNamed(p, "Make") == nil, "make", "Make is off until three are picked")
local picks = { prof.ideas[1], prof.ideas[2], prof.ideas[3] }
for i = 1, 3 do
	H.clickNamed(p, "Pick_" .. i, { wait = 0.2 })
end
H.clickNamed(p, "Make", { wait = 1 })
local proj = prof.project
H.expect(proj ~= nil, "make", "the game is being made")
if proj then
	for i = 1, 3 do
		H.expect(Ideas.key(proj.ideas[i]) == Ideas.key(picks[i]), "make", "idea " .. i .. " is the one picked")
	end
	H.expect(proj.won[1] == -1 and proj.won[2] == -1 and proj.won[3] == -1, "make", "no minigame played yet")
end
H.expect(prof.tut == 2, "make", "the tips move on", tostring(prof.tut))
H.expect(H.currentPanel(p) == nil, "make", "the board closes")
H.expect(H.buttonNamed(p, "Play_1") ~= nil and H.buttonNamed(p, "PlayAll") ~= nil, "make", "the making card opens with its Play buttons")
H.expect(H.buttonNamed(p, "Launch", true) ~= nil and H.buttonNamed(p, "Launch") == nil, "make", "Launch! waits for all three")

------------------------------------------------------------------ 4. the three microgames and the launch
E.phase = "play"
local MUI = H.cmod(p, "UI.MicroUI")
H.clickNamed(p, "PlayAll", { wait = 0.2 })
H.expect(s.micro ~= nil and s.micro.slot == 1, "play", "the server started slot 1's microgame")
E.run(1.2)
H.expect(H.inClient(p, MUI.playing) ~= nil, "play", "the client plays it", tostring(H.inClient(p, MUI.playing)))
E.runUntil(function()
	H.inClient(p, MUI.debugAuto)
	local pr = prof.project
	return pr ~= nil and pr.won[1] >= 0 and pr.won[2] >= 0 and pr.won[3] >= 0 and H.buttonNamed(p, "Launch") ~= nil
end, 240, 0.05)
proj = prof.project
local wins = 0
if proj then
	for i = 1, 3 do
		H.expect(proj.won[i] >= 0, "play", "slot " .. i .. " played (Play all chains them)", tostring(proj.won[i]))
		if proj.won[i] == 1 then
			wins += 1
		end
	end
end
H.expect(wins >= 1, "play", "the auto player wins some", tostring(wins))
H.expect(s.micro == nil, "play", "no microgame left open on the server")
local launchB = H.buttonNamed(p, "Launch")
H.expect(launchB ~= nil, "play", "Launch! is on")
local cards = if proj then proj.ideas else {}
H.clickNamed(p, "Launch", { wait = 1 })
H.expect(prof.project == nil and #prof.games == 1 and prof.stats.games == 1, "play", "launched: one game")
local game1 = prof.games[1]
H.expect(game1 ~= nil and math.abs(game1.rate - Ideas.rate(cards, wins)) < 1e-6, "play", "its peak income is the ideas' worth with the wins' boost", string.format("%s vs %s", game1 and game1.rate, Ideas.rate(cards, wins)))
H.expect(prof.live ~= nil and game1 ~= nil and prof.live.id == game1.id and prof.live.players > 0, "play", "it is on sale, with players", tostring(prof.live and prof.live.players))
H.expect(prof.tut == 3, "play", "the tips move on", tostring(prof.tut))
H.expect(H.buttonNamed(p, "Nice") ~= nil, "play", "the launch card shows")
H.clickNamed(p, "Nice", { wait = 0.5 })
H.expect(H.buttonNamed(p, "Nice") == nil and not H.inClient(p, MUI.isOpen), "play", "Nice! closes it")
H.checkProfile(p, "play")
H.checkMirror(p, "play")

------------------------------------------------------------------ 5. the income
E.phase = "income"
local Live = H.sharedServer("Logic.Live")
local coins0, fx0, rate0 = prof.coins, #fx, Live.earning(prof.live)
E.run(3.05)
local gained = prof.coins - coins0
local rate1 = Live.earning(prof.live)
H.expect(gained >= math.floor(math.min(rate0, rate1) * 2) - 1 and gained <= math.ceil(math.max(rate0, rate1) * 4) + 1, "income", "about three seconds of the game's sales", string.format("+%d at %.2f .. %.2f a second", gained, rate0, rate1))
H.expect(prof.live ~= nil and prof.live.age >= 3 and #prof.live.samples >= 2, "income", "its players are sampled for the graph", tostring(prof.live and #prof.live.samples))
local paid = 0
for i = fx0 + 1, #fx do
	if fx[i].kind == "coins" then
		paid += 1
	end
end
H.expect(paid >= 2, "income", "the client hears of each payment (Fx coins)", tostring(paid))
E.run(0.1)
local v = H.view(p)
H.expect(v ~= nil and math.abs(v.coins - prof.coins) <= math.ceil(Live.earning(prof.live)) + 1, "income", "the view's coins follow the payments", string.format("%s vs %s", v and v.coins, prof.coins))
H.expect(v ~= nil and v.live ~= nil and prof.live ~= nil and math.abs(#v.live.samples - #prof.live.samples) <= 1 and math.abs(v.live.players - prof.live.players) <= prof.live.peak, "income", "the view's game on sale follows (samples patched in)", string.format("%s vs %s samples", v and v.live and #v.live.samples, prof.live and #prof.live.samples))

------------------------------------------------------------------ 6. upgrades through the UI
E.phase = "upgrades"
prof.coins = 1e6
H.push(p, 0.4)
H.openPanel(p, "upgrades")
E.run(0.4)
local every0 = H.view(p).rollEvery
local before = prof.coins -- (measured at the click: income ticks land while the panel opens)
H.clickNamed(p, "Buy_speed", { wait = 0.5 })
H.expect(prof.upgrades.speed == 1, "upgrades", "roll speed level 1", tostring(prof.upgrades.speed))
local spent = before - prof.coins
local price = H.sharedServer("Logic.Studio").upgradeCost("speed", 0)
H.expect(spent <= price and spent >= price - math.ceil(Live.earning(prof.live) * 1.5) - 1, "upgrades", "its price paid (an income tick may land meanwhile)", string.format("%d spent, price %d", spent, price))
H.expect(H.view(p).rollEvery < every0, "upgrades", "ideas come faster", string.format("%s -> %s", every0, H.view(p).rollEvery))
H.clickNamed(p, "Buy_luck", { wait = 0.5 })
H.expect(prof.upgrades.luck == 1 and math.abs(H.view(p).luck - (1 + Tuning.LuckStep)) < 1e-9, "upgrades", "luck level 1")
H.closePanel(p)
prof.coins = 0
local res = H.req(p, "upgrade.buy", { k = "luck" })
H.expect(not res.ok and res.err == "money", "upgrades", "no coins: refused", tostring(res.err))
H.checkProfile(p, "upgrades")

------------------------------------------------------------------ 7. the founder's looks
E.phase = "looks"
local skin0 = prof.founder.skin
H.openPanel(p, "looks")
E.run(0.4)
H.clickNamed(p, "Next_skin", { wait = 0.2 })
H.clickNamed(p, "SaveLook", { wait = 0.6 })
H.expect(prof.founder.skin == skin0 % 4 + 1, "looks", "the new skin is saved", string.format("%d -> %d", skin0, prof.founder.skin))
H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", prof.founder.skin, prof.founder.hair, prof.founder.style, prof.founder.shirt), "looks", "every client sees the new look (the Founder attribute)", tostring(p:GetAttribute("Founder")))
H.closePanel(p)

------------------------------------------------------------------ 8. the other panels, settings, tips
E.phase = "panels"
local errs0 = #E.errors
for _, name in { "ideas", "index", "games", "upgrades", "looks" } do
	H.openPanel(p, name)
	E.run(0.3)
	H.expect(H.currentPanel(p) == name, "panels", name .. " opens")
end
H.closePanel(p)
H.expect(#E.errors == errs0, "panels", "no script errors in the panels", tostring(#E.errors - errs0))
res = H.req(p, "settings.set", { k = "pixel", v = "low" })
H.expect(res.ok and prof.settings.pixel == "low", "panels", "the pixel tier setting")
res = H.req(p, "settings.set", { k = "pixel", v = "ultra" })
H.expect(not res.ok and res.err == "bad_payload", "panels", "an unknown tier refused")
H.req(p, "settings.set", { k = "pixel", v = "high" })
E.run(0.4)
H.expect(H.buttonNamed(p, "TipsOk") ~= nil, "panels", "the tips banner shows")
H.clickNamed(p, "TipsOk", { wait = 0.5 })
H.expect(prof.tut == 0 and H.buttonNamed(p, "TipsOk") == nil, "panels", "OK puts the tips away for good")
H.checkProfile(p, "panels")
H.checkMirror(p, "panels")

------------------------------------------------------------------ 9. a malicious client
E.phase = "malicious"
local function snap()
	local q = H.profile(p)
	local owned = 0
	for _ in q.plot.owned do
		owned += 1
	end
	return { project = q.project ~= nil, games = #q.games, speed = q.upgrades.speed, luck = q.upgrades.luck, skin = q.founder.skin, owned = owned, placed = #q.plot.placed, tut = q.tut, office = q.office }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
local before = snap()
local ok, out = H.raw(p, "coins.give", { n = 1e9 })
expectRefused("an unknown action", ok, out, "unknown_action")
ok, out = H.rawArgs(p, nil)
expectRefused("no action", ok, out, "unknown_action")
ok, out = H.raw(p, "project.start", { genre = "action" })
expectRefused("the old studio's actions", ok, out, "unknown_action")
ok, out = H.raw(p, "game.make", { a = 0 / 0, b = 1, c = 2 })
expectRefused("NaN", ok, out, "bad_payload")
ok, out = H.raw(p, "game.make", { a = math.huge, b = 1, c = 2 })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.buy", { id = string.rep("a", 100000) })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "game.launch", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "game.launch", "x")
expectRefused("a string payload", ok, out, "bad_payload")
ok, out = H.raw(p, "micro.start", { slot = { 1 } })
expectRefused("a table for a slot", ok, out, "bad_payload")
ok, out = H.raw(p, "game.launch", {})
expectRefused("a launch with no game", ok, out, "no_project")
ok, out = H.raw(p, "micro.start", { slot = 1 })
expectRefused("a microgame with no game", ok, out, "no_project")
ok, out = H.raw(p, "micro.finish", { token = 1, won = 1 })
expectRefused("a finish with no microgame", ok, out, "busy")
ok, out = H.raw(p, "game.make", { a = 1, b = 2, c = 16 })
expectRefused("a board index past the board", ok, out, "bad_payload")
ok, out = H.raw(p, "founder.set", { skin = 9, hair = 1, style = 1, shirt = 1 })
expectRefused("a skin that does not exist", ok, out, "bad_payload")
ok, out = H.raw(p, "upgrade.buy", { k = "coins" })
expectRefused("an unknown upgrade", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.buy", { id = "castle" })
expectRefused("unknown decor", ok, out, "bad_payload")
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
-- a flood: 30 requests at once, the rate limit refuses most
local results = {}
H.inClient(p, function()
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	local done = 0
	for i = 1, 30 do
		E.task.spawn(function()
			results[i] = remote:InvokeServer("tut.next", {})
			done += 1
		end)
	end
	while done < 30 do
		E.task.wait(0.05)
	end
end)
local rated = 0
for _, x in results do
	if type(x) == "table" and x.err == "rate" then
		rated += 1
	end
end
H.expect(rated >= 30 - Tuning.RateLimitPerSec, "malicious", "the rate limit refuses a flood", string.format("%d of 30 refused", rated))
E.run(0.5)
H.checkProfile(p, "malicious")
H.checkMirror(p, "malicious")

------------------------------------------------------------------ 10. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets plot 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their office is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own office")
H.expect(H.cmod(p, "Controllers.WorldView").rigCount() >= Tuning.TeamSize * 2, "second", "the first client draws both teams")
H.checkProfile(q, "second")
H.checkMirror(q, "second")
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
