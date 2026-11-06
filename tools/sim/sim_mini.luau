-- The minigames (GAME_DESIGN 14; docs/ARCHITECTURE.md 7.4, 10.8): pushes earned at the build's milestones (the
-- week's "push" event, the HUD's Push! button), the picker, each of the four score games played through the real UI
-- (MinigameUI.debugAuto: one right move a step) to its results card and its points on the right score, the clock
-- held while a game is up, Bug Squash while polishing (its cooldown on the HUD), and the server's refusals: no push
-- banked, Bug Squash while building, two games at once, a wrong token, a finish too soon (a score of 0), a game left
-- open past Tuning.MiniMaxSec (dropped, the clock runs again), junk payloads, and a player leaving mid-game.
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
local Minigames = H.sharedServer("Logic.Minigames")

local p = H.addPlayer({ userId = 9401, name = "Gamer" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)
local MUI = H.cmod(p, "UI.MinigameUI")

local function waitTick()
	local w = prof.week
	E.runUntil(function()
		return prof.week ~= w
	end, Tuning.WeekSec * 3, 0.05)
end

-- Play the game in play with a right move every `step` seconds until its results card's Nice! button shows.
local function playThrough(step: number?): boolean
	local ok = E.runUntil(function()
		H.inClient(p, MUI.debugAuto)
		return H.buttonNamed(p, "Nice") ~= nil
	end, Tuning.MiniSeconds + 12, step or 0.05)
	E.run(1.2)
	return ok
end

local function pauseKeys(): string
	local keys = {}
	for k in H.session(p).paused do
		table.insert(keys, k)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

------------------------------------------------------------------ pushes come with the build
E.phase = "pushes"
local res = H.req(p, "project.start", { genre = "action", topic = "space", platform = "pc", size = "small", focus = "fun", seed = 1 })
H.expect(res.ok, "mini", "a small game starts", tostring(res.err))
local proj = prof.project
H.expect(proj.pushes == 0 and proj.nextPush == 0 and proj.played == 0, "mini", "a new game has no push banked")
E.run(0.4)
H.expect(H.buttonNamed(p, "Push") == nil, "mini", "no Push! button yet")
local ms = Minigames.milestones("small")
H.expect(#ms == Tuning.MiniMilestones.small, "mini", "the small game's milestones", table.concat(ms, ","))
local before = #fx
while proj.weeksDone < ms[1] do
	waitTick()
end
E.run(0.4)
local heard = false
for i = before + 1, #fx do
	for _, e in fx[i].events or {} do
		if e.kind == "push" and e.title == proj.title then
			heard = true
		end
	end
end
H.expect(heard, "mini", "the week's push event reaches the client")
H.expect(proj.pushes == 1 and proj.nextPush == 1, "mini", "a push banked at the first milestone", string.format("%d %d", proj.pushes, proj.nextPush))
H.expect(H.buttonNamed(p, "Push") ~= nil, "mini", "the HUD's Push! button shows")

------------------------------------------------------------------ the picker and a game through the UI
E.phase = "picker"
H.clickNamed(p, "Push", { wait = 0.5 })
for _, kind in Minigames.PUSH_ORDER do
	H.expect(H.buttonNamed(p, "Mini_" .. kind) ~= nil, "mini", "the picker offers " .. kind)
end
H.expect(H.session(p).paused.pick == true, "mini", "the picker holds the clock", pauseKeys())
H.clickNamed(p, "Later", { wait = 0.5 })
H.expect(H.buttonNamed(p, "Mini_code") == nil and next(H.session(p).paused) == nil, "mini", "Later closes it and the clock runs", pauseKeys())
H.expect(proj.pushes == 1, "mini", "closing the picker spends nothing")

local function playKind(kind: string, axis: string)
	E.phase = "play-" .. kind
	proj.pushes = math.max(proj.pushes, 1)
	H.push(p, 0.4)
	local pushes0, played0 = proj.pushes, proj.played
	local score0 = proj.scores[axis]
	H.clickNamed(p, "Push", { wait = 0.4 })
	H.clickNamed(p, "Mini_" .. kind, { wait = 0.3 })
	local s = H.session(p)
	H.expect(s.mini ~= nil and s.mini.kind == kind, "mini", kind .. ": the server started it", tostring(s.mini and s.mini.kind))
	H.expect(proj.pushes == pushes0 - 1 and proj.played == played0 + 1, "mini", kind .. ": the push is spent at the start", string.format("%d -> %d", pushes0, proj.pushes))
	H.expect(s.paused.mini == true, "mini", kind .. ": the server holds the clock", pauseKeys())
	local w0 = prof.week
	E.run(2)
	H.expect(H.inClient(p, MUI.playing) == kind, "mini", kind .. ": the client plays it", tostring(H.inClient(p, MUI.playing)))
	H.expect(H.buttonNamed(p, "Nice") == nil, "mini", kind .. ": no results yet")
	local done = playThrough(if kind == "code" then 0.15 else 0.05)
	H.expect(done, "mini", kind .. ": the game ends with its results card")
	H.expect(prof.week == w0, "mini", kind .. ": no week passed while it was up", string.format("%d -> %d", w0, prof.week))
	H.expect(s.mini == nil and s.paused.mini == nil, "mini", kind .. ": the server let go of it", pauseKeys())
	local gained = proj.scores[axis] - score0
	H.expect(gained > 0, "mini", kind .. ": points on " .. axis, tostring(gained))
	-- the reward line on the card says what the server did
	local pg = p:FindFirstChild("PlayerGui")
	local reward = pg and pg:FindFirstChild("Reward", true)
	local text = reward and reward.Text or ""
	H.expect(string.find(text, "+" .. tostring(gained), 1, true) ~= nil, "mini", kind .. ": the card shows the reward", text)
	H.clickNamed(p, "Nice", { wait = 0.5 })
	H.expect(H.buttonNamed(p, "Nice") == nil and next(H.session(p).paused) == nil, "mini", kind .. ": Nice! closes it, the clock runs", pauseKeys())
end
playKind("code", "fun")
playKind("ideas", "ideas")
playKind("pixels", "graphics")
playKind("beats", "sound")

------------------------------------------------------------------ the server's refusals
E.phase = "refusals"
proj.pushes = 0
H.push(p, 0.3)
res = H.req(p, "mini.start", { kind = "code" })
H.expect(not res.ok and res.err == "cooldown", "mini", "no push banked: refused", tostring(res.err))
res = H.req(p, "mini.start", { kind = "bugs" })
if proj.phase == "build" then
	H.expect(not res.ok and res.err == "not_built", "mini", "Bug Squash while building: refused", tostring(res.err))
end
res = H.req(p, "mini.start", { kind = "chess" })
H.expect(not res.ok and res.err == "bad_payload", "mini", "an unknown game: refused", tostring(res.err))
proj.pushes = 2
res = H.req(p, "mini.start", { kind = "ideas" })
H.expect(res.ok and type(res.data) == "table" and type(res.data.token) == "number", "mini", "a raw start answers a token", tostring(res.err))
local token = res.data and res.data.token or 0
local res2 = H.req(p, "mini.start", { kind = "code" })
H.expect(not res2.ok and res2.err == "busy", "mini", "two games at once: refused", tostring(res2.err))
H.expect(proj.pushes == 1, "mini", "the refused start spent nothing", tostring(proj.pushes))
res2 = H.req(p, "mini.finish", { token = (token + 1) % 1000000, score = 100 })
H.expect(not res2.ok and res2.err == "busy", "mini", "a wrong token: refused", tostring(res2.err))
local ideas0 = proj.scores.ideas
res2 = H.req(p, "mini.finish", { token = token, score = 100 })
H.expect(res2.ok and res2.data.score == 0 and proj.scores.ideas == ideas0, "mini", "a finish sooner than MiniMinSec counts as 0", tostring(res2.data and res2.data.score))
res2 = H.req(p, "mini.finish", { token = token, score = 100 })
H.expect(not res2.ok, "mini", "a finished game cannot be finished again", tostring(res2.err))
-- a game left open: dropped after MiniMaxSec, the clock runs again
res = H.req(p, "mini.start", { kind = "beats" })
H.expect(res.ok and proj.pushes == 0, "mini", "start one and leave it open", tostring(res.err))
local w0 = prof.week
E.run(Tuning.MiniMaxSec * 0.5)
H.expect(prof.week == w0, "mini", "the clock holds while it is open", string.format("%d -> %d", w0, prof.week))
E.run(Tuning.MiniMaxSec * 0.5 + Tuning.WeekSec * 2 + 1)
H.expect(H.session(p).mini == nil and H.session(p).paused.mini == nil, "mini", "a game left open past MiniMaxSec is dropped")
H.expect(prof.week > w0, "mini", "and the clock runs again", string.format("%d -> %d", w0, prof.week))
res = H.req(p, "mini.finish", { token = res.data and res.data.token or 0, score = 100 })
H.expect(not res.ok, "mini", "its late finish is refused", tostring(res.err))
-- the client cannot let go of the server's own pause key
proj.pushes = 1
res = H.req(p, "mini.start", { kind = "pixels" })
H.signal(p, "pause", { key = "mini", on = false })
E.run(0.3)
H.expect(H.session(p).paused.mini == true, "mini", "a client signal cannot lift the minigame's hold", pauseKeys())
E.run(Tuning.MiniMinSec + 0.5)
res = H.req(p, "mini.finish", { token = res.data and res.data.token or 0, score = 64 })
H.expect(res.ok and res.data.score == 64 and res.data.grade == Minigames.grade(64), "mini", "a fair finish keeps its score", tostring(res.data and res.data.score))

------------------------------------------------------------------ junk payloads
E.phase = "junk"
for _, payload in { { kind = 5 }, { kind = string.rep("k", 60) }, { kind = "code", extra = 1 }, {} } :: { any } do
	local okCall, r = H.raw(p, "mini.start", payload)
	H.expect(okCall and type(r) == "table" and not r.ok and r.err == "bad_payload", "mini", "junk start refused", tostring(r and r.err))
end
for _, payload in { { token = -1, score = 50 }, { token = 1, score = 2e6 }, { token = "1", score = 5 }, { score = 5 } } :: { any } do
	local okCall, r = H.raw(p, "mini.finish", payload)
	H.expect(okCall and type(r) == "table" and not r.ok and r.err == "bad_payload", "mini", "junk finish refused", tostring(r and r.err))
end

------------------------------------------------------------------ Bug Squash while polishing
E.phase = "squash"
proj.weeksDone = proj.buildWeeks
proj.phase = "polish"
proj.bugs = 12
proj.squashWeek = 0
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "Squash") ~= nil, "mini", "the HUD's Squash button shows while polishing with bugs")
local bugs0 = proj.bugs
H.clickNamed(p, "Squash", { wait = 0.3 })
H.expect(H.session(p).mini ~= nil and H.session(p).mini.kind == "bugs", "mini", "Bug Squash started from the HUD")
H.expect(proj.squashWeek == prof.week + Tuning.SquashCooldown, "mini", "its cooldown starts", tostring(proj.squashWeek - prof.week))
E.run(2)
local played = playThrough(0.1)
H.expect(played, "mini", "Bug Squash ends with its results card")
H.expect(proj.bugs < bugs0, "mini", "bugs squashed", string.format("%d -> %d", bugs0, proj.bugs))
H.expect(bugs0 - proj.bugs <= Minigames.squashed(prof.staff, bugs0, 100), "mini", "no more than a perfect game squashes", tostring(bugs0 - proj.bugs))
H.clickNamed(p, "Nice", { wait = 0.5 })
local sq = H.buttonNamed(p, "Squash", true)
H.expect(sq ~= nil and H.buttonNamed(p, "Squash") == nil, "mini", "Squash waits out its cooldown on the HUD (disabled)")
res = H.req(p, "mini.start", { kind = "bugs" })
H.expect(not res.ok and res.err == "cooldown", "mini", "and the server refuses it", tostring(res.err))

------------------------------------------------------------------ leaving mid-game
E.phase = "leave"
local q = H.addPlayer({ userId = 9402, name = "Quitter" })
E.run(1)
H.req(q, "project.start", { genre = "puzzle", topic = "animals", platform = "pc", size = "small", focus = "ideas", seed = 2 })
local qp = H.profile(q)
qp.project.pushes = 1
H.push(q, 0.4)
res = H.req(q, "mini.start", { kind = "code" })
H.expect(res.ok, "mini", "the second player starts a game", tostring(res.err))
E.removePlayer(q, "leave")
E.run(3)
H.expect(H.session(q) == nil, "mini", "the leaver's session (and its game) is gone")
H.expect(H.session(p) ~= nil, "mini", "the first player plays on")

E.run(0.5)
H.checkProfile(p, "mini")
H.checkMirror(p, "mini")
local _ = fx
report(E, H)
