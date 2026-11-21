-- Leaderboards and friends (GAME_DESIGN 16; docs/ARCHITECTURE.md 7.8; the request of 2026-11-21: "Make a leaderboard
-- system, along with friend invite bonuses"): the player list's leaderstats; the Top sheet's Invite (Roblox's invite
-- prompt, the inviter's id in its LaunchData); a friend joining from it (ReferredByPlayerId, or the LaunchData alone):
-- the welcome gift once, never from yourself, never to an old save; friends on the server (each pair checked once,
-- Profile.social.here, the island's pace, the HUD's line, counted again when one leaves); ten minutes of play paying
-- the inviter live, at most Tuning.ReferralDailyCap a day; a friend finishing while the inviter is away (queued in the
-- referral store, paid at the inviter's next join; one past today's cap stays queued); the boards (written on their
-- timer and at leaving, read by "lb.get": best first, names, the asker's place; the Top sheet's rows); a junk board.
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
local Schema = H.sharedServer("Logic.Schema")
local Island = H.sharedServer("Logic.Island")
local Social = H.sharedServer("Logic.Social")
local Creatures = H.sharedServer("Data.Creatures")
local Traits = H.sharedServer("Data.Traits")
local REF = Tuning.ReferralStoreName .. "/global"
local STORE = Tuning.DataStoreName .. "/global"

-- A label with these words on the player's screen within `limit` seconds (a notice, a HUD line).
local function shows(p, words: string, limit: number?): boolean
	local found = false
	E.runUntil(function()
		local pg = p:FindFirstChild("PlayerGui")
		for _, x in (if pg then pg:GetDescendants() else {}) do
			if x:IsA("TextLabel") and string.find(x.Text, words, 1, true) then
				found = true
				return true
			end
		end
		return false
	end, limit or 3, 0.05)
	return found
end
-- The friends waiting in the referral store for an inviter: { invitee ids }.
local function queued(inviter: number): { number }
	local e = (E.cloud.stores[REF] or {})["u_" .. inviter]
	local out = {}
	for _, it in (if e and type(e.value) == "table" then e.value else {}) do
		table.insert(out, it.invitee)
	end
	return out
end
local function fxFrom(list, from: string): number
	local n = 0
	for _, m in list do
		if m.kind == "rewards" and m.from == from then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------ the inviter
E.phase = "inviter"
local a = H.addPlayer({ userId = 9401, name = "Inviter" })
local fxa = H.watchFx(a)
E.run(2)
local pa = H.profile(a)
H.expect(pa ~= nil and pa.social ~= nil and pa.social.referredBy == 0 and pa.social.here == 0, "social", "a new save's friends: no inviter, nobody here")
local ls = a:FindFirstChild("leaderstats")
local lsIsland = ls and ls:FindFirstChild("Island")
local lsEarned = ls and ls:FindFirstChild("Earned")
H.expect(lsIsland ~= nil and lsEarned ~= nil, "social", "the player list's leaderstats: Island and Earned")
H.expect(lsIsland and lsIsland.Value == pa.tier, "social", "Island is the island's level", lsIsland and tostring(lsIsland.Value))
-- the Top sheet's Friends tab: Invite friends opens Roblox's invite prompt, the inviter's id in its LaunchData
H.openPanel(a, "top", "friends")
H.expect(shows(a, "Invite friends", 1), "social", "the Friends tab shows Invite friends")
H.clickNamed(a, "Invite", { wait = 0.6 })
local inv = E.invites[#E.invites]
H.expect(#E.invites == 1 and inv.player == a, "social", "Invite friends opens the invite prompt once", tostring(#E.invites))
local launch = inv and inv.launchData or ""
H.expect(tonumber(string.match(launch, '"r":%s*(%d+)') or "") == 9401, "social", "its LaunchData carries the inviter's id", launch)
H.expect(inv ~= nil and type(inv.prompt) == "string" and #inv.prompt > 0, "social", "and a message", inv and tostring(inv.prompt))
H.closePanel(a)

------------------------------------------------------------------ friends join from the invite
E.cloud.friends["9401:9402"] = true
E.phase = "invitee"
local b = H.addPlayer({ userId = 9402, name = "Friend", joinData = { ReferredByPlayerId = 9401, LaunchData = launch } })
local fxb = H.watchFx(b)
E.run(2.5)
local pb = H.profile(b)
H.expect(pb.social.referredBy == 9401, "social", "a new save joining from an invite takes the inviter", tostring(pb.social.referredBy))
H.expect(fxFrom(fxb, "invited") == 1, "social", "the welcome gift, once (Fx rewards from invited)", tostring(fxFrom(fxb, "invited")))
H.expect(shows(b, "Welcome gift", 3), "social", "and its notice")
-- a second friend with only the LaunchData (no ReferredByPlayerId), not friends with the inviter on Roblox
local c = H.addPlayer({ userId = 9403, name = "Pal", joinData = { LaunchData = launch } })
local fxc = H.watchFx(c)
E.run(2.5)
local pc = H.profile(c)
H.expect(pc.social.referredBy == 9401 and fxFrom(fxc, "invited") == 1, "social", "the LaunchData alone works too", tostring(pc.social.referredBy))
-- inviting yourself: nothing
local d = H.addPlayer({ userId = 9404, name = "Self", joinData = { ReferredByPlayerId = 9404 } })
local fxd = H.watchFx(d)
E.run(2.5)
local pd = H.profile(d)
H.expect(pd.social.referredBy == 0 and fxFrom(fxd, "invited") == 0, "social", "an invite from yourself is no invite")
-- (an epic driftling with a tier 2 and a tier 3 mutation, waiting for a hut, for the Driftlings board)
local epic, m2, m3
for _, cr in Creatures.list do
	if cr.rarity == 4 and epic == nil then
		epic = cr.id
	end
end
for id, m in Traits.byId do
	if m.tier == 2 and (m2 == nil or id < m2) then
		m2 = id
	end
end
for id, m in Traits.byId do
	if m.tier == 3 and m.family ~= Traits.byId[m2].family and (m3 == nil or id < m3) then
		m3 = id
	end
end
table.insert(pd.pals, { id = pd.nextId, sp = epic, home = 0, work = 0, muts = { m2, m3 } })
pd.nextId += 1
pd.seen[epic] = 2
H.push(d, 0.3)
-- an old save joining from an invite: welcome, no gift
E.cloud.stores[STORE] = E.cloud.stores[STORE] or {}
local old = Schema.default(1000, 7)
E.cloud.stores[STORE]["u_9406"] = { value = { data = old }, meta = {}, userIds = {}, version = 1, created = E.SIM.now, updated = E.SIM.now }
local o = H.addPlayer({ userId = 9406, name = "Oldtimer", joinData = { ReferredByPlayerId = 9401 } })
local fxo = H.watchFx(o)
E.run(2.5)
local po = H.profile(o)
H.expect(po.social.referredBy == 0 and fxFrom(fxo, "invited") == 0, "social", "an old save brings no gifts", tostring(po.social.referredBy))
E.removePlayer(o, "leave")
E.run(1)

------------------------------------------------------------------ friends on the server
E.phase = "together"
H.expect(pa.social.here == 1 and pb.social.here == 1 and pc.social.here == 0, "social", "friends here: the inviter and the friend count each other, the others nobody", string.format("%d %d %d", pa.social.here, pb.social.here, pc.social.here))
H.expect(math.abs(Island.friendsMult(pa) - (1 + Tuning.FriendsBoostEach)) < 1e-9, "social", "one friend here: the island's pace up by FriendsBoostEach")
local va = H.view(a)
H.expect(va and va.social and va.social.here == 1 and math.abs(va.social.boost - Tuning.FriendsBoostEach) < 1e-9, "social", "the view carries it")
H.expect(shows(a, "1 friend here", 2), "social", "the HUD's line: 1 friend here")

------------------------------------------------------------------ ten minutes of play
E.phase = "play"
E.run(Tuning.ReferralMinPlaySec + 8, 0.5)
H.expect(pb.social.refPaid and pc.social.refPaid, "social", "ten minutes in, both friends' rewards went out", tostring(pb.social.refPlay))
H.expect(pa.social.invited == 2, "social", "the inviter, on the server: two friends invited", tostring(pa.social.invited))
H.expect(fxFrom(fxa, "friend") == 2, "social", "two notices from friends (Fx rewards from friend)", tostring(fxFrom(fxa, "friend")))
H.expect((pa.boosts.luck or 0) > 0, "social", "the inviter's Lucky Hour running")
H.expect(pd.social.refPlay == 0, "social", "no play counted without an invite")
E.run(6)
H.expect(lsEarned.Value == math.floor(pa.stats.earned), "social", "Earned keeps up with the coins earned", string.format("%d %d", lsEarned.Value, math.floor(pa.stats.earned)))

------------------------------------------------------------------ the boards
E.phase = "boards"
local res = H.req(a, "lb.get", { board = "coins" })
local rows = res.ok and res.data and res.data.rows or {}
H.expect(res.ok and #rows >= 4, "boards", "lb.get coins: the players written on the board's timer", tostring(#rows))
local sorted, mineAt = true, nil
for i, r in rows do
	if i > 1 and r.value > rows[i - 1].value then
		sorted = false
	end
	if r.rank ~= i then
		sorted = false
	end
	if r.userId == 9401 then
		mineAt = i
		H.expect(r.name == "Inviter", "boards", "the board's names", r.name)
	end
end
H.expect(sorted, "boards", "best first, ranked 1, 2, 3...")
H.expect(mineAt ~= nil and res.data.you.rank == mineAt, "boards", "the asker's place", tostring(mineAt))
H.expect(res.data.you.value == math.floor(pa.stats.earned), "boards", "and their score now")
for _, bd in { "charm", "hatched", "driftlings" } do
	local r2 = H.req(a, "lb.get", { board = bd })
	H.expect(r2.ok and #r2.data.rows >= 4, "boards", "lb.get " .. bd, tostring(r2.ok and #r2.data.rows))
end
-- the Driftlings board: the epic driftling's points (its rarity's and five stars) and its kind read back
local rd = H.req(a, "lb.get", { board = "driftlings" })
local dRow = nil
for _, r in (rd.ok and rd.data.rows or {}) do
	if r.userId == 9404 then
		dRow = r
	end
end
local dPts, dSp = Social.decode(dRow and dRow.value or 0)
H.expect(dRow ~= nil and dRow.rank == 1, "boards", "Driftlings: the only island with a driftling on top", tostring(dRow and dRow.rank))
H.expect(dPts == Tuning.BoardRarityPoints[4] + 5 * Tuning.BoardStarPoints and dSp == epic, "boards", "its points (rarity and five stars) and its kind read back", string.format("%d %s", dPts, tostring(dSp)))
H.openPanel(a, "top", "driftlings")
E.run(0.8)
local dPanel = a.PlayerGui:FindFirstChild("Panel_top", true)
local palLabel = dPanel and dPanel:FindFirstChild("Row_1", true)
palLabel = palLabel and palLabel:FindFirstChild("Pal")
H.expect(palLabel ~= nil and palLabel:IsA("TextLabel") and palLabel.Text == Creatures.byId[epic].name, "boards", "the Top sheet's Driftlings tab names the driftling", palLabel and palLabel.Text)
H.closePanel(a)
E.phase = "malicious"
H.expect(H.req(a, "lb.get", { board = "everything" }).err == "bad_payload", "boards", "a board that isn't one: bad_payload")
H.expect(H.req(a, "lb.get", { board = 12 }).err == "bad_payload", "boards", "a number for a board: bad_payload")
E.phase = "boards"
-- the sheet's rows
H.openPanel(a, "top", "coins")
E.run(0.8)
local panelRoot = a.PlayerGui:FindFirstChild("Panel_top", true)
-- (the player's own row is "You" wherever it is: pinned on top and in the list)
local youRows = 0
for _, x in (if panelRoot then panelRoot:GetDescendants() else {}) do
	if x.Name == "You" and x:IsA("Frame") then
		youRows += 1
	end
end
H.expect(youRows == 2 and panelRoot ~= nil and panelRoot:FindFirstChild("Row_2", true) ~= nil, "boards", "the Top sheet: the player's line pinned, the rows, the player among them", tostring(youRows))
H.closePanel(a)

------------------------------------------------------------------ the inviter away
E.phase = "away"
E.removePlayer(a, "leave")
E.run(2)
H.expect(pb.social.here == 0, "social", "the inviter gone: the friend's count goes down")
local f = H.addPlayer({ userId = 9405, name = "Later", joinData = { ReferredByPlayerId = 9401 } })
E.run(2.5)
local pf = H.profile(f)
H.expect(pf.social.referredBy == 9401, "social", "a friend joins while the inviter is away")
pf.social.refPlay = Tuning.ReferralMinPlaySec - 2
E.run(5)
H.expect(pf.social.refPaid and table.find(queued(9401), 9405) ~= nil, "social", "their ten minutes done: the reward waits in the referral store", table.concat(queued(9401), ","))
-- the inviter back: paid at the join, the queue emptied
local a2 = H.addPlayer({ userId = 9401, name = "Inviter" })
local fxa2 = H.watchFx(a2)
E.run(3)
local pa2 = H.profile(a2)
H.expect(pa2.social.invited == 3 and fxFrom(fxa2, "friend") == 1 and #queued(9401) == 0, "social", "back again: the waiting friend paid, the queue empty", string.format("%d %d %d", pa2.social.invited, fxFrom(fxa2, "friend"), #queued(9401)))
-- today's rewards all taken: the next friend waits for another day
-- (today by the game's clock: the fake engine's, not this script's)
pa2.social.refDay = math.floor(E.now() / 86400)
pa2.social.refToday = Tuning.ReferralDailyCap
local g = H.addPlayer({ userId = 9407, name = "Capped", joinData = { ReferredByPlayerId = 9401 } })
E.run(2.5)
local pg = H.profile(g)
pg.social.refPlay = Tuning.ReferralMinPlaySec - 1
E.run(5)
H.expect(pg.social.refPaid and pa2.social.invited == 3 and table.find(queued(9401), 9407) ~= nil, "social", "past today's cap: queued, not paid", string.format("%d %s", pa2.social.invited, table.concat(queued(9401), ",")))

------------------------------------------------------------------ the end
E.phase = "end"
for _, who in { a2, b, c, d, f, g } do
	H.checkProfile(who, "end")
	H.checkMirror(who, "end")
end
report(E, H)
