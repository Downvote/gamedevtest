-- Leaderboards and friends (Logic/Social, Data/Rewards.REFERRAL; GAME_DESIGN 16; the request of 2026-11-21: "Make a
-- leaderboard system, along with friend invite bonuses"): the boards' scores, a friend invited (taken once, by a new
-- save, never from itself; the welcome gift; ten minutes of play; the inviter's reward and its daily cap), the friends
-- on the server in the island's pace, and the save's shape.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Social = require("../../build/luautest/shared/Logic/Social")
local Island = require("../../build/luautest/shared/Logic/Island")
local Validate = require("../../build/luautest/shared/Logic/Validate")

local DAY = 86400
local T0 = 20000 * DAY + 3600 -- a UTC day's first hour

local function fresh(createdAt: number?): any
	local p = Schema.default(createdAt or T0, 1)
	p.shells = 0
	return p
end

return function()
	T.it("the boards: coins earned, the island's charm, eggs hatched; whole numbers", function()
		local p = fresh()
		p.stats.earned = 1234.9
		p.stats.taken = 7
		p.stats.hatched = 3
		local sc = Social.scores(p)
		T.eq(sc.coins, 1234)
		T.eq(sc.hatched, 10)
		T.eq(sc.charm, math.floor(Island.charm(p, Island.isle(p))))
		T.eq(Social.score(p, "nope"), 0)
		T.truthy(Social.isBoard("coins") and Social.isBoard("charm") and Social.isBoard("hatched"))
		T.truthy(not Social.isBoard("best") and not Social.isBoard(3))
		T.eq(#Social.BOARDS, 3)
	end)

	T.it("an invite is taken once, by a new save, never from the player themself", function()
		local p = fresh()
		T.truthy(Social.canJoin(p, 555, 1, T0 + 60))
		T.truthy(not Social.canJoin(p, 1, 1, T0 + 60), "not from yourself")
		T.truthy(not Social.canJoin(p, 0, 1, T0 + 60), "a real user")
		T.truthy(not Social.canJoin(p, 5.5, 1, T0 + 60), "a whole id")
		T.truthy(not Social.canJoin(p, nil, 1, T0 + 60))
		T.truthy(not Social.canJoin(p, 555, 1, T0 + Tuning.ReferralMaxAgeSec + 1), "an older save brings no gifts")
		local given = Social.join(p, 555)
		T.eq(p.social.referredBy, 555)
		T.truthy(#given >= 2, "the welcome gift: " .. #given .. " things")
		T.truthy(p.shells > 0 or #p.bag > 0, "something to show for it")
		T.truthy(not Social.canJoin(p, 777, 1, T0 + 120), "once")
	end)

	T.it("ten minutes of play make the inviter's reward due, once", function()
		local p = fresh()
		T.truthy(not Social.play(p, 60), "nothing counts without an invite")
		T.eq(p.social.refPlay, 0)
		Social.join(p, 555)
		local turned = 0
		for _ = 1, Tuning.ReferralMinPlaySec + 30 do
			if Social.play(p, 1) then
				turned += 1
			end
		end
		T.eq(turned, 1, "due just once")
		T.truthy(Social.due(p))
		T.eq(p.social.refPlay, Tuning.ReferralMinPlaySec, "kept at the mark")
		p.social.refPaid = true
		T.truthy(not Social.due(p))
		T.truthy(not Social.play(p, 100))
	end)

	T.it("the inviter's reward: a friend more, the gifts, at most ReferralDailyCap a day", function()
		local p = fresh()
		T.eq(Social.todayLeft(p, T0), Tuning.ReferralDailyCap)
		for k = 1, Tuning.ReferralDailyCap do
			local ok, given = Social.reward(p, T0 + k)
			T.truthy(ok and given and #given >= 3, "reward " .. k)
		end
		T.eq(p.social.invited, Tuning.ReferralDailyCap)
		T.eq(Social.todayLeft(p, T0 + 100), 0)
		local ok = Social.reward(p, T0 + 200)
		T.truthy(not ok, "today's are taken")
		T.eq(p.social.invited, Tuning.ReferralDailyCap)
		-- a new day opens more
		T.eq(Social.todayLeft(p, T0 + DAY), Tuning.ReferralDailyCap)
		T.truthy((Social.reward(p, T0 + DAY)))
		T.eq(p.social.invited, Tuning.ReferralDailyCap + 1)
		T.eq(p.social.refToday, 1)
		-- the luck boost is one of them
		T.truthy((p.boosts.luck or 0) > 0)
	end)

	T.it("friends on the server: more coins each, to a cap, only in the live pace", function()
		local p = fresh()
		T.eq(Island.friendsMult(p), 1)
		p.social.here = 2
		T.near(Island.friendsMult(p), 1 + 2 * Tuning.FriendsBoostEach, 1e-9)
		p.social.here = 99
		T.near(Island.friendsMult(p), 1 + Tuning.FriendsBoostMax, 1e-9)
		-- the steady pace (time away, rewards in minutes) leaves them out
		p.social.here = 0
		local base = Island.rates(p).shells
		local steady0 = Island.rates(p, true).shells
		p.social.here = 3
		T.near(Island.rates(p).shells, base * (1 + 3 * Tuning.FriendsBoostEach), 1e-6)
		T.near(Island.rates(p, true).shells, steady0, 1e-9)
		local v = Social.view(p, T0)
		T.eq(v.here, 3)
		T.near(v.boost, 3 * Tuning.FriendsBoostEach, 1e-9)
	end)

	T.it("the save: friends kept through a reload, junk cleaned, the friends here always 0", function()
		local p = fresh()
		Social.join(p, 555)
		p.social.refPlay = 123
		p.social.invited = 4
		p.social.refDay = 20000
		p.social.refToday = 2
		p.social.here = 3
		local q = Schema.reconcile(p, T0 + 10, 1)
		T.eq(q.social.referredBy, 555)
		T.eq(q.social.refPlay, 123)
		T.eq(q.social.invited, 4)
		T.eq(q.social.refToday, 2)
		T.eq(q.social.here, 0, "counted again on the new server")
		local junk = Schema.reconcile({ v = 23, social = { referredBy = -3, refPaid = "yes", refPlay = 0 / 0, invited = 1e99, refToday = 500 } }, T0, 1)
		T.eq(junk.social.referredBy, 0)
		T.eq(junk.social.refPaid, false)
		T.eq(junk.social.refPlay, 0)
		T.eq(junk.social.invited, 1e6)
		T.eq(junk.social.refToday, Tuning.ReferralDailyCap)
		local old = Schema.reconcile({ v = 23 }, T0, 1)
		T.eq(old.social.referredBy, 0)
		T.eq(old.v, Schema.VERSION)
	end)

	T.it("lb.get takes a board's name only", function()
		T.truthy((Validate.request("lb.get", { board = "coins" })))
		T.truthy((Validate.request("lb.get", { board = "hatched" })))
		T.truthy(not Validate.request("lb.get", { board = "everything" }))
		T.truthy(not Validate.request("lb.get", {}))
	end)
end
