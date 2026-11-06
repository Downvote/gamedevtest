-- The main simulation: a new studio's first game end to end through the real client API (StateClient.request), the
-- crew, research, ads, the move to the Loft, settings, the tips banner, then a malicious client, then a second
-- player. Every check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
local E = require("./loader")
local I = require("./inst")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.verboseUi = false
E.dt = 0.1
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Util = H.sharedServer("Logic.Util")
local Crew = H.sharedServer("Logic.Crew")
local getD = I.getD

------------------------------------------------------------------ 1. a new studio
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(2)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(#prof.staff == Tuning.StartStaff, "join", "two developers to start", tostring(#prof.staff))
H.expect(prof.money == Tuning.StartMoney, "join", "start money", tostring(prof.money))
H.expect(prof.week == 0 and prof.office == 1 and prof.tut == 1, "join", "week 0, the garage, tips at step 1", string.format("%d %d %d", prof.week, prof.office, prof.tut))
H.expect(s.plot == 1, "join", "the first player gets plot 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
-- Static.Office (a folder PlotService replaces as a whole) holds the office model (OfficeModels.build)
local function officeOf(st)
	local f = st and st:FindFirstChild("Office")
	return f and f:FindFirstChild("Office")
end
local office = officeOf(static)
H.expect(office ~= nil, "join", "the office is built under Plots.Plot_1.Static.Office")
if office then
	H.expect(office:GetAttribute("Tier") == 1, "join", "a tier 1 office")
	H.expect(#office.Desks:GetChildren() == Tuning.Offices[1].desks, "join", "three desks in the garage", tostring(#office.Desks:GetChildren()))
end
local WV = H.cmod(p, "Controllers.WorldView")
H.expect(WV.ownRigCount() == 2, "join", "a rig per developer", tostring(WV.ownRigCount()))
H.expect(WV.rigCount() == 2, "join", "no other studio on the street yet", tostring(WV.rigCount()))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
local devRigs = 0
if dyn then
	for _, c in dyn:GetChildren() do
		if string.sub(c.Name, 1, 8) == "Dev_own:" then
			devRigs += 1
		end
	end
end
H.expect(devRigs == 2, "join", "the rigs are in Workspace.PixelDynamic", tostring(devRigs))
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there too")
local v = H.view(p)
H.expect(v ~= nil and v.money == prof.money and v.plot == 1, "join", "the client has the view")
H.checkProfile(p, "join")
H.checkMirror(p, "join")

------------------------------------------------------------------ 2. the first game
E.phase = "first-game"
local fx = H.watchFx(p)
local money0 = prof.money
local res = H.req(p, "project.start", { genre = "puzzle", topic = "animals", platform = "pc", size = "small", focus = "fun", seed = 0 })
H.expect(res.ok, "game", "project.start", tostring(res.err))
prof = H.profile(p)
H.expect(prof.project ~= nil and prof.project.title == "Kitty Blocks", "game", "the project and its title", prof.project and prof.project.title)
H.expect(prof.money == money0 - Tuning.Sizes.small.cost, "game", "the small game's cost is paid", tostring(money0 - prof.money))
H.expect(prof.tut == 2, "game", "tips at step 2 once a game is in the works", tostring(prof.tut))
local again = H.req(p, "project.start", { genre = "puzzle", topic = "space", platform = "pc", size = "small", focus = "fun", seed = 0 })
H.expect(not again.ok and again.err == "busy", "game", "one project at a time", tostring(again.err))
local early = H.req(p, "project.release", {})
H.expect(not early.ok and early.err == "not_built", "game", "no release before the build is done", tostring(early.err))
E.run(0.5)
H.checkMirror(p, "started")
local build = prof.project.buildWeeks
E.run(Tuning.WeekSec * build + 0.5)
prof = H.profile(p)
H.expect(prof.project ~= nil and prof.project.phase == "polish", "game", "the build is done after its weeks", prof.project and string.format("%s %d", prof.project.phase, prof.project.weeksDone))
local weeks, works, built = 0, 0, false
for _, m in fx do
	if m.kind == "week" then
		weeks += 1
		for _, e in m.events do
			if e.kind == "work" then
				works += 1
				H.expect(type(e.pops) == "table" and #e.pops == #prof.staff, "game", "a popup per developer", tostring(e.pops and #e.pops))
			elseif e.kind == "built" then
				built = true
			end
		end
	end
end
H.expect(weeks >= build and works >= build, "game", "a week message with work every week", string.format("%d weeks, %d work", weeks, works))
H.expect(built, "game", "the build-done event")
H.expect(prof.tut == 3, "game", "tips at step 3 once the build is done", tostring(prof.tut))
local s1 = prof.project.scores
H.expect(s1.fun > 0 and s1.ideas > 0 and s1.graphics > 0 and s1.sound > 0, "game", "every score grew")
H.expect(prof.rp > 0, "game", "research points from the work", tostring(prof.rp))
H.checkProfile(p, "built")
H.checkMirror(p, "built")
res = H.req(p, "project.release", {})
H.expect(res.ok, "game", "project.release", tostring(res.err))
local r = res.data
if H.expect(type(r) == "table" and type(r.reviews) == "table", "game", "the release comes back with its reviews") then
	local sum = 0
	for _, x in r.reviews do
		H.expect(x >= 1 and x <= 10, "game", "a review in 1..10", tostring(x))
		sum += x
	end
	H.expect(#r.reviews == 4 and sum == r.total, "game", "four reviews summing to the total")
	H.log("released %s: %s = %d (%s), peak %d", r.title, table.concat(r.reviews, " "), r.total, r.match, r.peak)
end
prof = H.profile(p)
H.expect(prof.project == nil and #prof.releases == 1 and prof.releases[1].onSale, "game", "on sale, no project left")
H.expect(prof.matches["puzzle|animals"] == "great", "game", "the match is learned", tostring(prof.matches["puzzle|animals"]))
H.expect(prof.stats.games == 1 and prof.tut == 4, "game", "stats and tips step 4", string.format("%d %d", prof.stats.games, prof.tut))
local fans0, rev0 = prof.fans, prof.releases[1].revenue
E.run(Tuning.WeekSec * 3 + 0.2)
prof = H.profile(p)
local rel = prof.releases[1]
H.expect(rel.copies > 0 and rel.revenue > rev0 and rel.weeks >= 3, "game", "it sells week after week", string.format("%d copies, $%d, %d weeks", rel.copies, rel.revenue, rel.weeks))
H.expect(prof.fans > fans0, "game", "fans from the sales", string.format("%d -> %d", fans0, prof.fans))
H.checkProfile(p, "selling")
H.checkMirror(p, "selling")

------------------------------------------------------------------ 3. the crew
E.phase = "crew"
v = H.view(p)
H.expect(#v.candidates == Tuning.Candidates, "crew", "three candidates this month", tostring(#v.candidates))
local n0 = #prof.staff
res = H.req(p, "staff.hire", { i = 1 })
H.expect(res.ok, "crew", "hire a candidate", tostring(res.err))
prof = H.profile(p)
H.expect(#prof.staff == n0 + 1 and prof.tut == 0, "crew", "a third developer, the tips banner done", string.format("%d %d", #prof.staff, prof.tut))
res = H.req(p, "staff.hire", { i = 1 })
H.expect(not res.ok and res.err == "full", "crew", "the garage has three desks", tostring(res.err))
local newId = prof.staff[#prof.staff].id
res = H.req(p, "staff.fire", { id = newId })
H.expect(res.ok and #H.profile(p).staff == n0, "crew", "let a developer go", tostring(res.err))
res = H.req(p, "staff.fire", { id = 99999 })
H.expect(not res.ok and res.err == "bad_payload", "crew", "letting go of nobody", tostring(res.err))
res = H.req(p, "staff.hire", { i = 1 })
H.expect(res.ok, "crew", "hire again", tostring(res.err))
-- training happens in the Staff panel, which holds the clock (a week passing mid-request would pay and tire)
H.signal(p, "pause", { key = "menu", on = true })
E.run(0.2)
prof = H.profile(p)
prof.rp = 100
local dev = prof.staff[1]
local code0, e0, rp0, m0 = dev.skills.code, dev.energy, prof.rp, prof.money
res = H.req(p, "staff.train", { id = dev.id, skill = "code" })
H.expect(res.ok, "crew", "train", tostring(res.err))
H.expect(dev.skills.code > code0 and prof.rp == rp0 - Tuning.TrainRp and prof.money == m0 - Tuning.TrainMoney, "crew", "training costs and pays", string.format("code %d -> %d", code0, dev.skills.code))
H.expect(dev.energy == math.max(0, e0 - Tuning.TrainEnergy), "crew", "training tires", string.format("%g -> %g", e0, dev.energy))
H.signal(p, "pause", { key = "menu", on = false })
H.expect(dev.salary == Crew.salary(dev.skills), "crew", "the salary follows the skills")
res = H.req(p, "staff.party", {})
H.expect(res.ok, "crew", "a pizza party", tostring(res.err))
for _, x in H.profile(p).staff do
	H.expect(x.energy == Tuning.EnergyMax, "crew", "the party fills everyone's energy", tostring(x.energy))
end
res = H.req(p, "staff.party", {})
H.expect(not res.ok and res.err == "cooldown", "crew", "one party a month", tostring(res.err))
E.run(0.3)
H.checkProfile(p, "crew")
H.checkMirror(p, "crew")

------------------------------------------------------------------ 4. research and ads
E.phase = "research"
prof = H.profile(p)
prof.rp = 100
res = H.req(p, "research.genre", { id = "rpg" })
H.expect(res.ok and prof.genres.rpg and prof.rp == 100 - Tuning.GenreRp[2], "research", "unlock a genre", tostring(res.err))
res = H.req(p, "research.genre", { id = "rpg" })
H.expect(not res.ok and res.err == "max", "research", "a genre once", tostring(res.err))
res = H.req(p, "research.topic", { id = "robots" })
H.expect(res.ok and prof.topics.robots, "research", "unlock a topic", tostring(res.err))
res = H.req(p, "research.genre", { id = "nope" })
H.expect(not res.ok and res.err == "bad_payload", "research", "an unknown genre", tostring(res.err))
prof.rp = 0
res = H.req(p, "research.genre", { id = "horror" })
H.expect(not res.ok and res.err == "rp", "research", "not enough research points", tostring(res.err))
local fansAd = prof.fans
res = H.req(p, "office.ad", {})
H.expect(res.ok and prof.fans == fansAd + Tuning.AdFans * prof.office, "research", "an ad campaign brings fans", tostring(res.err))
res = H.req(p, "office.ad", {})
H.expect(not res.ok and res.err == "cooldown", "research", "one campaign a month", tostring(res.err))

------------------------------------------------------------------ 5. the Loft
E.phase = "office"
res = H.req(p, "office.move", {})
H.expect(not res.ok and res.err == "fans", "office", "the Loft needs fans", tostring(res.err))
prof = H.profile(p)
prof.fans = Tuning.Offices[2].fans + 100
prof.money = Tuning.Offices[2].cost + 50000
H.push(p)
res = H.req(p, "office.move", {})
H.expect(res.ok and prof.office == 2, "office", "move to the Loft", tostring(res.err))
E.run(1)
static = plot1:FindFirstChild("Static")
office = officeOf(static)
H.expect(office ~= nil and office:GetAttribute("Tier") == 2, "office", "the office is rebuilt as the Loft")
H.expect(office ~= nil and #office.Desks:GetChildren() == Tuning.Offices[2].desks, "office", "five desks", tostring(office and #office.Desks:GetChildren()))
local statics, olds, offices = 0, 0, 0
for _, c in plot1:GetChildren() do
	if c.Name == "Static" then
		statics += 1
	end
end
for _, c in static:GetChildren() do
	if c.Name == "Old" then
		olds += 1
	elseif c.Name == "Office" then
		offices += 1
	end
end
H.expect(statics == 1 and olds == 0 and offices == 1, "office", "the old office came down", string.format("%d static, %d old, %d offices", statics, olds, offices))
local CC = H.cmod(p, "Controllers.CameraController")
H.expect(CC.view().tier == 2, "office", "the client's camera frames the Loft", tostring(CC.view().tier))
H.expect(WV.ownRigCount() == #prof.staff, "office", "the rigs moved with the crew", tostring(WV.ownRigCount()))
res = H.req(p, "office.move", {})
H.expect(not res.ok and (res.err == "fans" or res.err == "money"), "office", "the Studio Floor needs more", tostring(res.err))
res = H.req(p, "settings.set", { k = "pixel", v = "low" })
H.expect(res.ok and prof.settings.pixel == "low", "office", "settings.set pixel", tostring(res.err))
res = H.req(p, "settings.set", { k = "pixel", v = "ultra" })
H.expect(not res.ok and res.err == "bad_payload", "office", "an unknown tier", tostring(res.err))
H.req(p, "settings.set", { k = "pixel", v = "high" })
prof.tut = 2
res = H.req(p, "tut.next", {})
H.expect(res.ok and prof.tut == 0, "office", "tut.next dismisses the tips", tostring(prof.tut))
E.run(0.4)
H.checkProfile(p, "office")
H.checkMirror(p, "office")

------------------------------------------------------------------ 6. a malicious client
E.phase = "malicious"
prof = H.profile(p)
prof.money = 30000
local function snap()
	local q = H.profile(p)
	return { money = q.money, fans = q.fans, rp = q.rp, staff = #q.staff, project = q.project ~= nil, releases = #q.releases, office = q.office, week = q.week }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
-- pause the clock so the snapshots compare like with like
H.signal(p, "pause", { key = "sim", on = true })
E.run(0.3)
local before = snap()
local ok, out = H.raw(p, "money.give", { n = 1e9 })
expectRefused("an unknown action", ok, out, "unknown_action")
ok, out = H.rawArgs(p, nil)
expectRefused("no action", ok, out, "unknown_action")
ok, out = H.raw(p, "project.start", { genre = 5, topic = "space", platform = "pc", size = "small", focus = "fun", seed = 0 })
expectRefused("a number for a genre", ok, out, "bad_payload")
ok, out = H.raw(p, "staff.hire", { i = 0 / 0 })
expectRefused("NaN", ok, out, "bad_payload")
ok, out = H.raw(p, "staff.hire", { i = math.huge })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "research.genre", { id = string.rep("a", 100000) })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "project.release", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "staff.party", "x")
expectRefused("a string payload", ok, out, "bad_payload")
ok, out = H.raw(p, "staff.train", { id = { 1 }, skill = "code" })
expectRefused("a table for an id", ok, out, "bad_payload")
ok, out = H.raw(p, "project.release", {})
expectRefused("a release with no project", ok, out, "no_project")
ok, out = H.raw(p, "project.start", { genre = "horror", topic = "space", platform = "pc", size = "small", focus = "fun", seed = 0 })
expectRefused("a locked genre", ok, out, "locked")
ok, out = H.raw(p, "project.start", { genre = "action", topic = "space", platform = "cloud", size = "small", focus = "fun", seed = 0 })
expectRefused("a platform not out yet", ok, out, "unavailable")
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
-- hiring into a full office
prof.money = 1e6
prof.candidates = Crew.candidates(Util.newRng(5), 1, 3)
local hires = 0
for _ = 1, 3 do
	local okH, outH = H.raw(p, "staff.hire", { i = 1 })
	if okH and outH.ok then
		hires += 1
	end
end
ok, out = H.raw(p, "staff.hire", { i = 1 })
prof = H.profile(p)
H.expect(#prof.staff == Tuning.Offices[2].desks, "malicious", "the Loft fills up", string.format("%d hired, %d staff", hires, #prof.staff))
expectRefused("a hire with every desk taken", ok, out, "full")
-- no money: a large game is refused (and never takes the studio below zero)
prof.money = 0
ok, out = H.raw(p, "project.start", { genre = "action", topic = "space", platform = "pc", size = "large", focus = "fun", seed = 0 })
expectRefused("a game the studio cannot pay for", ok, out, "money")
H.expect(prof.money == 0 and prof.project == nil, "malicious", "nothing spent")
-- a flood: 30 requests at once, the rate limit refuses most
local results = {}
H.inClient(p, function()
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	local done = 0
	for i = 1, 30 do
		E.task.spawn(function()
			results[i] = remote:InvokeServer("staff.party", {})
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
prof.money = 30000
H.signal(p, "pause", { key = "sim", on = false })
E.run(0.5)
H.checkProfile(p, "malicious")
H.checkMirror(p, "malicious")

------------------------------------------------------------------ 7. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets plot 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their office is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own office")
H.checkProfile(q, "second")
H.checkMirror(q, "second")
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
