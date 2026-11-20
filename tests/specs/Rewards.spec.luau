-- The rewards for coming back and for playing (Logic/Rewards, Data/Rewards; GAME_DESIGN 15; the request of 2026-11-19:
-- "add rewards for playtime, daily rewards, streak rewards, codes, and as many retention features you can think of"):
-- the daily reward and its streak, the playtime gifts, the daily tasks and their bonus, the Lucky Shell, codes, the
-- Index's milestones, the timed boosts, and the save's shape.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Rewards = require("../../build/luautest/shared/Logic/Rewards")
local RewardsData = require("../../build/luautest/shared/Data/Rewards")
local Tree = require("../../build/luautest/shared/Logic/Tree")
local Titles = require("../../build/luautest/shared/Data/Titles")
local Util = require("../../build/luautest/shared/Logic/Util")

local DAY = 86400

local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells = 0
	return p
end

return function()
	T.it("the daily reward: once a day, the streak on the next day, back to 1 after a day missed; the 7-day round", function()
		local p = fresh()
		local d0 = 100 * DAY + 3600
		local st = Rewards.daily(p, d0)
		T.truthy(st.ready and st.streak == 1 and st.round == 1)
		local ok, data = Rewards.claimDaily(p, d0)
		T.truthy(ok and data.streak == 1 and #data.given >= 1)
		T.truthy(p.shells > 0, "day 1's shells")
		T.eq(select(2, Rewards.claimDaily(p, d0 + 3600)), "cooldown", "once a day")
		T.eq(Rewards.daily(p, d0).streak, 1)
		-- the next day goes on
		for k = 1, 6 do
			local ok2, d2 = Rewards.claimDaily(p, d0 + k * DAY)
			T.truthy(ok2)
			T.eq(d2.streak, k + 1)
			T.eq(d2.round, k + 1)
		end
		T.eq(p.rewards.daily.best, 7)
		-- day 8 starts the round again
		local _, d8 = Rewards.claimDaily(p, d0 + 7 * DAY)
		T.truthy(d8.streak == 8 and d8.round == 1)
		-- a day missed: back to 1, the best kept
		local _, again = Rewards.claimDaily(p, d0 + 9 * DAY)
		T.eq(again.streak, 1)
		T.eq(p.rewards.daily.best, 8)
		-- a server whose clock runs a day behind gives no second claim (days compared in order: the server review of
		-- 2026-11-19), and neither does the free spin
		T.eq(select(2, Rewards.claimDaily(p, d0 + 8 * DAY)), "cooldown", "an earlier day than the last claim")
		local sp = p.rewards.spin
		sp.day, sp.extra = Rewards.day(d0 + 9 * DAY), 0
		T.eq(Rewards.spins(p, d0 + 8 * DAY), 0, "no free spin on an earlier day")
	end)
	T.it("streak milestones: given once each, the day the streak reaches them (a title among them)", function()
		local p = fresh()
		local d0 = 50 * DAY
		local got: { number } = {}
		for k = 0, 14 do
			local _, data = Rewards.claimDaily(p, d0 + k * DAY)
			for _, m in data.miles do
				table.insert(got, m)
			end
		end
		T.deepEq(got, { 3, 7, 14 })
		T.truthy(p.titles.dropin and p.titles.devoted, "the 3 and 14 day titles")
		T.eq(Rewards.daily(p, d0 + 15 * DAY).next, 30, "the next one")
		-- a streak broken and built again: never twice
		for k = 20, 34 do
			local _, data = Rewards.claimDaily(p, d0 + k * DAY)
			T.truthy(table.find(data.miles, 3) == nil and table.find(data.miles, 7) == nil)
		end
		for _, m in RewardsData.MILESTONES do
			for _, r in m.give do
				if r.kind == "title" then
					T.truthy(Titles.byId[r.id or ""] ~= nil and Titles.byId[r.id or ""].how == "reward", tostring(r.id))
				end
			end
		end
	end)
	T.it("playtime gifts: seconds today count while here, each gift once its minutes are in; a new day starts again", function()
		local p = fresh()
		local now = 10 * DAY
		T.eq(select(2, Rewards.claimPlay(p, 1, now)), "not_done")
		for _ = 1, 2 * 60 do
			Rewards.tick(p, now, 1)
		end
		T.truthy((Rewards.claimPlay(p, 1, now)), "2 minutes: the first gift")
		T.eq(select(2, Rewards.claimPlay(p, 1, now)), "used")
		T.eq(select(2, Rewards.claimPlay(p, 2, now)), "not_done")
		T.eq(select(2, Rewards.claimPlay(p, 99, now)), "bad_payload")
		Rewards.tick(p, now, 9999)
		T.near(p.rewards.play.secs, 2 * 60 + 5, 1e-9, "a long gap counts 5 seconds at most")
		-- tomorrow
		Rewards.tick(p, now + DAY, 1)
		T.eq(p.rewards.play.secs, 1)
		T.eq(#p.rewards.play.got, 0)
		local last = 0
		for _, g in RewardsData.PLAY do
			T.truthy(g.min > last, "the gifts come in order")
			last = g.min
		end
	end)
	T.it("daily tasks: three a day the island is big enough for, the same three on a rejoin; counted from the deal; the bonus", function()
		local p = fresh()
		local now = 20 * DAY
		T.truthy(Rewards.sync(p, now))
		T.eq(#p.rewards.tasks.list, RewardsData.TASK_COUNT)
		local ids: { string } = {}
		for _, t in p.rewards.tasks.list do
			T.truthy(Rewards.taskDef[t.id] and Rewards.taskDef[t.id].tier <= p.tier)
			T.truthy(table.find(ids, t.id) == nil, "three different")
			table.insert(ids, t.id)
		end
		T.eq(Rewards.sync(p, now + 60), false, "the same day: nothing new")
		-- the same island the same day deals the same three
		local q = fresh()
		Rewards.sync(q, now)
		for i, t in q.rewards.tasks.list do
			T.eq(t.id, ids[i])
		end
		-- each counts from the deal: nothing done yet
		for _, s in Rewards.taskState(p) do
			T.truthy(not s.done and s.have == 0)
		end
		T.eq(select(2, Rewards.claimTask(p, 1, now)), "not_done")
		T.eq(select(2, Rewards.claimBonus(p, now)), "not_done")
		-- everything done
		p.stats.taken += 100
		p.stats.built += 100
		p.stats.earned += 1e9
		p.stats.sold += 100
		p.stats.hatched += 100
		p.rewards.play.secs += 3600
		for i = 1, #p.rewards.tasks.list do
			T.truthy(Rewards.taskState(p)[i].done)
			T.truthy((Rewards.claimTask(p, i, now)), "task " .. i)
			T.eq(select(2, Rewards.claimTask(p, i, now)), "used")
		end
		T.truthy((Rewards.claimBonus(p, now)), "all three: the bonus")
		T.eq(select(2, Rewards.claimBonus(p, now)), "used")
		-- tomorrow, three new ones
		Rewards.sync(p, now + DAY)
		T.eq(p.rewards.tasks.bonus, false)
		T.eq(p.rewards.tasks.got[1], false)
	end)
	T.it("the Lucky Shell: one free spin a day, extra spins from the rewards, a slice by weight", function()
		local p = fresh()
		local now = 30 * DAY
		local rng = Util.newRng(7)
		T.eq(Rewards.spins(p, now), 1)
		local ok, data = Rewards.spin(p, rng, now)
		T.truthy(ok and data.slice >= 1 and data.slice <= #RewardsData.SPIN)
		T.eq(Rewards.spins(p, now), 0)
		T.eq(select(2, Rewards.spin(p, rng, now)), "not_done")
		Rewards.give(p, { kind = "spin", n = 2 })
		T.eq(Rewards.spins(p, now), 2)
		Rewards.spin(p, rng, now)
		T.eq(Rewards.spins(p, now), 1)
		T.eq(Rewards.spins(p, now + DAY), 2, "tomorrow's free one and the extra")
		local sum = 0
		for _, sl in RewardsData.SPIN do
			sum += sl.w
		end
		T.near(sum, 100, 1e-9)
		-- the slices come about as often as their weights say
		local q = fresh()
		q.rewards.spin.extra = 999
		local r2, hits = Util.newRng(9), table.create(#RewardsData.SPIN, 0)
		for _ = 1, 999 do
			local _, d = Rewards.spin(q, r2, now)
			hits[d.slice] += 1
		end
		T.truthy(hits[1] > hits[#hits] * 5, "the commonest far more often than the rarest")
	end)
	T.it("codes: trimmed and upper case, once each, gone past their end", function()
		local p = fresh()
		local defs = { HELLO = { give = { { kind = "shells", mins = 5 } } }, OLD = { give = { { kind = "spin", n = 1 } }, ends = 1000 } }
		local ok, data = Rewards.redeem(p, "  hello ", defs :: any, 0)
		T.truthy(ok and data.code == "HELLO" and p.shells > 0)
		T.eq(select(2, Rewards.redeem(p, "HELLO", defs :: any, 0)), "used")
		T.eq(select(2, Rewards.redeem(p, "nope", defs :: any, 0)), "not_found")
		T.eq(select(2, Rewards.redeem(p, "old", defs :: any, 2000)), "not_found", "ended")
		T.truthy((Rewards.redeem(p, "old", defs :: any, 500)))
	end)
	T.it("the Index's milestones: kinds had, once each", function()
		local p = fresh()
		T.eq(select(2, Rewards.claimIndex(p, 1)), "not_done")
		local n = 0
		for sp in require("../../build/luautest/shared/Data/Creatures").byId do
			if n < 12 then
				p.seen[sp] = 2
				n += 1
			end
		end
		T.eq(Rewards.kinds(p), 12)
		T.truthy((Rewards.claimIndex(p, 1)))
		T.truthy((Rewards.claimIndex(p, 2)))
		T.eq(select(2, Rewards.claimIndex(p, 2)), "used")
		T.eq(select(2, Rewards.claimIndex(p, 3)), "not_done")
	end)
	T.it("timed boosts: luck for the tree's eggs, shells for everything, held to BOOST_MAX; the view's red dot counts", function()
		local p = fresh()
		local luck0 = Tree.luck(p)
		Rewards.give(p, { kind = "boost", id = "luck", mins = 15 })
		T.near(p.boosts.luck, 900, 1e-9)
		T.near(Tree.luck(p), luck0 + Tuning.TimedLuck, 1e-9)
		for _ = 1, 40 do
			Rewards.give(p, { kind = "boost", id = "shells", mins = 15 })
		end
		T.eq(p.boosts.shells, RewardsData.BOOST_MAX)
		T.eq(Rewards.give(p, { kind = "boost", id = "nope", mins = 5 }).kind, "none")
		local v = Rewards.view(p, 40 * DAY)
		T.truthy(v.daily.ready and v.spins == 1 and v.ready >= 2, "the daily and the free spin wait")
	end)
	T.it("the save: fresh on a new island, cleaned from anything; v19 saves come up to v20", function()
		local p = Schema.default(0, 1)
		T.eq(p.v, Schema.VERSION)
		T.eq(p.rewards.daily.last, -1)
		T.deepEq(p.boosts, {})
		local raw: any = table.clone(p)
		raw.rewards = {
			daily = { last = 3, streak = 5, best = 2, miles = { 3, 9, 3, "x" } },
			play = { day = 3, secs = 1e9, got = { 1, 1, 99, 2 } },
			tasks = { day = 3, list = { { id = "hatch", n = 5, at = 2 }, { id = "nope", n = 1, at = 0 }, "x" }, got = { true, true }, bonus = 1 },
			spin = { day = 3, extra = 5000, total = 4 },
			codes = { hello = true, [5] = true, LONGCODE = "yes" },
			index = { got = { 5, 6, 10 } },
		}
		raw.boosts = { shells = 120, luck = 1e9, gold = 50 }
		local q = Schema.reconcile(raw, 0, 1)
		T.deepEq(q.rewards.daily, { last = 3, streak = 5, best = 5, miles = { 3 } })
		T.deepEq(q.rewards.play, { day = 3, secs = 86400, got = { 1, 2 } })
		T.eq(#q.rewards.tasks.list, 1)
		T.deepEq(q.rewards.tasks.got, { true })
		T.eq(q.rewards.tasks.bonus, false)
		T.eq(q.rewards.spin.extra, 999)
		T.deepEq(q.rewards.codes, { HELLO = true })
		T.deepEq(q.rewards.index.got, { 5, 10 })
		T.deepEq(q.boosts, { shells = 120, luck = RewardsData.BOOST_MAX })
		local old: any = Schema.default(0, 1)
		old.v = 19
		old.rewards = nil
		old.boosts = nil
		local up = Schema.reconcile(Schema.migrate(old), 0, 1)
		T.eq(up.v, Schema.VERSION)
		T.eq(up.rewards.spin.extra, 0)
	end)
end
