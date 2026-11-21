-- The questline (Data/Quests, Logic/Quest; GAME_DESIGN 9): its quests in order, each goal counted from what the
-- island has now, nothing while the tips are on, a claim paying the reward once the goal is met and moving on, and
-- the save keeping where the player is.
local T = require("../TestKit")
local Quests = require("../../build/luautest/shared/Data/Quests")
local Quest = require("../../build/luautest/shared/Logic/Quest")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Plot = require("../../build/luautest/shared/Logic/Plot")

local KINDS = {
	helpers = true,
	paths = true,
	decor = true,
	built = true,
	housed = true,
	taken = true,
	sold = true,
	best = true,
	tier = true,
	seen = true,
	hatched = true,
}
local PANELS = { pals = true, index = true, hatch = true, tree = true }
local TABS = { work = true, nest = true, gen = true, path = true, decor = true }

local function fresh(): any
	local p = Schema.default(0, 1)
	p.tut = 0
	return p
end

return function()
	T.it("every quest is whole: a unique id, a goal it can count, a reward, a place to go", function()
		local seen: { [string]: boolean } = {}
		for i, q in Quests.list do
			T.truthy(not seen[q.id], "unique id " .. q.id)
			seen[q.id] = true
			T.truthy(KINDS[q.goal.kind], q.id .. ": a known goal")
			T.truthy(q.goal.n >= 1, q.id .. ": a goal to reach")
			if q.goal.kind == "built" then
				local any = false
				for _, b in Buildings.list do
					if b.kind == q.goal.of then
						any = true
					end
				end
				T.truthy(any, q.id .. ": a kind of building that exists")
			end
			T.truthy((q.reward.shells or 0) > 0 and (q.reward :: any).wood == nil, q.id .. ": pays shells")
			T.eq((q.reward :: any).food, nil, q.id .. ": no food")
			local tab = string.match(q.go, "^build:(%a+)$")
			T.truthy(PANELS[q.go] or q.go == "build" or (tab ~= nil and TABS[tab]), q.id .. ": goes somewhere real (" .. q.go .. ")")
			T.truthy(#q.title > 0 and #q.text > 0 and #q.icon > 0, q.id .. ": words and an icon")
			T.truthy(not string.find(q.text, "\226\128\148") and not string.find(q.text, "\226\128\147"), q.id .. ": no dashes")
			T.eq(Quests.byId[q.id], q, "by id " .. i)
		end
		-- (the request of 2026-11-21: "the first goal after the tutorial should be "Place down 4 huts"")
		T.eq(Quests.list[1].id, "huts4", "it starts with four huts")
		T.eq(Quests.list[1].title, "Place down 4 huts")
		T.eq(Quests.list[1].goal.kind, "built")
		T.eq(Quests.list[1].goal.of, "nest")
		T.eq(Quests.list[1].goal.n, 4)
		T.eq(Quests.byId.huts, nil, "Build another hut (two) is gone")
	end)

	T.it("nothing while the tips are on; the quest on the go after", function()
		local p = Schema.default(0, 1)
		T.eq(p.quest, 1)
		T.eq(Quest.current(p.tut, p.quest), nil, "tips first")
		T.eq(select(2, Quest.claim(p)), "not_found")
		p.tut = 0
		T.eq(Quest.current(p.tut, p.quest), Quests.list[1])
		T.eq(Quest.current(0, #Quests.list + 1), nil, "every quest done")
	end)

	T.it("a goal counts what the island has now; a claim pays once it is met and moves on", function()
		local p = fresh()
		local q = Quests.list[1]
		T.eq(select(1, Quest.progress(Quest.facts(p), q)), 0)
		T.eq(select(2, Quest.claim(p)), "not_done", "no huts yet")
		T.eq(p.quest, 1)
		for k = 1, 3 do
			table.insert(p.plot.placed, { uid = 100 + k, id = "nest", x = 4 * k, z = 0, rot = 0, lvl = 1 })
		end
		T.eq(select(1, Quest.progress(Quest.facts(p), q)), 3)
		T.eq(select(2, Quest.claim(p)), "not_done", "three huts: not yet")
		table.insert(p.plot.placed, { uid = 104, id = "nest", x = 16, z = 0, rot = 0, lvl = 1 })
		T.truthy(Quest.done(Quest.facts(p), q), "four huts")
		local shells = p.shells
		local ok, data = Quest.claim(p)
		T.truthy(ok, "claimed")
		T.eq(p.shells, shells + (q.reward.shells or 0), "its shells")
		T.eq(p.quest, 2, "the next quest")
		T.eq(data.id, "huts4")
		T.eq(data.next, 2)
		-- the next: a driftling at work
		local q2 = Quests.list[2]
		T.eq(q2.id, "help")
		T.eq(select(2, Quest.claim(p)), "not_done", "no driftling at work yet")
		table.insert(p.pals, { id = 1, sp = "pebblit", home = 101, work = 5, muts = {} })
		T.truthy(Quest.done(Quest.facts(p), q2), "one at work")
		T.truthy((Quest.claim(p)), "claimed")
		T.eq(p.quest, 3)
	end)

	T.it("four huts fit the first island's room for driftlings", function()
		local slots = Buildings.byId.nest.slots
		T.truthy(Quests.list[1].goal.n * slots <= Plot.housingLimit(1), string.format("%d huts of %d beds, %d on the first island", Quests.list[1].goal.n, slots, Plot.housingLimit(1)))
	end)

	T.it("the counts: driftlings at work, paths, a kind built, the Index, the ones taken in", function()
		local p = fresh()
		local f = Quest.facts(p)
		table.insert(p.plot.placed, { uid = 1, id = "patch", x = 0, z = 0, rot = 0, lvl = 2 })
		table.insert(p.plot.placed, { uid = 2, id = "dirtpath", x = 2, z = 0, rot = 0, lvl = 1 })
		table.insert(p.plot.placed, { uid = 3, id = "nest", x = 6, z = 0, rot = 0, lvl = 1 })
		T.eq(Quest.count(f, { kind = "built", n = 4, of = "work" }), 1, "one workplace (one kind of work since 2026-11-19)")
		T.eq(Quest.count(f, { kind = "paths", n = 8 }), if Buildings.byId.dirtpath then 1 else 0)
		T.eq(Quest.count(f, { kind = "built", n = 1, of = "nest" }), 1)
		p.seen.pebblit, p.seen.mossbun = 2, 2
		T.eq(Quest.count(f, { kind = "seen", n = 12 }), 2)
		table.insert(p.pals, { id = 7, sp = "pebblit", home = 3, work = 0 })
		table.insert(p.pals, { id = 8, sp = "pebblit", home = 0, work = 0 })
		T.eq(Quest.count(f, { kind = "housed", n = 1 }), 1, "one in a hut")
		T.eq(Quest.count(f, { kind = "helpers", n = 1 }), 0, "resting")
		p.pals[1].work = 1
		T.eq(Quest.count(f, { kind = "helpers", n = 1 }), 1, "one at the farm")
		p.stats.sold, p.stats.taken, p.stats.best = 4, 9, 3
		T.eq(Quest.count(f, { kind = "sold", n = 1 }), 4)
		T.eq(Quest.count(f, { kind = "taken", n = 1 }), 9)
		T.eq(Quest.count(f, { kind = "best", n = 3 }), 3)
	end)

	T.it("the save: a new one starts at the first quest; an older one comes in there; a stray number is put right", function()
		local d = Schema.default(0, 1)
		T.eq(d.quest, 1)
		local old = Schema.default(0, 1) :: any
		old.v = 9
		old.quest = 12
		local p = Schema.reconcile(Schema.migrate(old), 0, 1) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.quest, 1, "a save from before the tree starts the new questline")
		local far = Schema.default(0, 1) :: any
		far.quest = 9999
		T.eq((Schema.reconcile(far, 0, 1) :: any).quest, #Quests.list + 1, "past the last: all done")
		far.quest = 5
		T.eq((Schema.reconcile(far, 0, 1) :: any).quest, 5, "kept")
	end)

	-- 2026-11-18: "this quest is uncompletable without removing a work building. thus, remove the quest that asks you
	-- to make a second lumber camp"
	T.it("no second Lumber Camp; a save from before keeps its place in the questline", function()
		local farmAt = 0
		for i, q in Quests.list do
			T.truthy(q.id ~= "camp", "the camp quest is gone")
			if q.id == "farm" then
				farmAt = i
			end
		end
		T.eq(#Quests.list, 19)
		T.eq(farmAt, 7, "Another workplace (Another farm till 2026-11-19) is the seventh now (four huts in, two huts out: 2026-11-21)")
		local function from18(q: number): number
			local old = Schema.default(0, 1) :: any
			old.v = 18
			old.quest = q
			return (Schema.reconcile(Schema.migrate(old), 0, 1) :: any).quest
		end
		-- (by the quest itself: since version 25 "Place down 4 huts" comes first, so each is one place later)
		T.eq(Quests.list[from18(3)].id, "take3", "before the camp quest: the same (Hatch three eggs)")
		T.eq(Quests.list[from18(4)].id, "three", "on it: the next one, Three at work")
		T.eq(Quests.list[from18(8)].id, "farm", "on Another farm (the eighth): still on it")
		T.eq(from18(21), #Quests.list + 1, "all done: still all done")
	end)

	T.it("the quests before the first expansion fit the first island's work spaces", function()
		-- the workplaces the tips have built (one since 2026-11-21: the best one; a camp, a farm and a stall before),
		-- then the most any quest asks for (one kind of work since 2026-11-19), at the first island's places a workplace
		local need = 1
		for _, q in Quests.list do
			if q.goal.kind == "tier" then
				break
			end
			if q.goal.kind == "built" and q.goal.of == "work" then
				need = math.max(need, q.goal.n)
			end
		end
		local each = math.huge
		for _, d in Buildings.list do
			if d.kind == "work" and d.tier == 1 then
				each = math.min(each, d.jobs)
			end
		end
		local jobs = need * each
		T.truthy(jobs <= Plot.workLimit(1), string.format("%d work spaces asked for, %d on the first island", jobs, Plot.workLimit(1)))
	end)

	T.it("a quest for driftlings at work goes to what the island is short of: beds, driftlings, places at work", function()
		local q = Quests.list[1]
		for _, x in Quests.list do
			if x.id == "three" then
				q = x
			end
		end
		T.eq(q.goal.kind, "helpers", "Three at work counts driftlings at work")
		local work = ""
		for _, d in Buildings.list do
			if d.kind == "work" and d.tier == 1 and work == "" then
				work = d.id
			end
		end
		local function facts(huts: number, works: number, pals: number, tier: number?): any
			local pieces = {}
			for i = 1, huts do
				table.insert(pieces, { id = "nest", uid = i })
			end
			for i = 1, works do
				table.insert(pieces, { id = work, uid = 100 + i })
			end
			local ps = {}
			for i = 1, pals do
				table.insert(ps, { id = i, work = 0, home = 0 })
			end
			return { pals = ps, pieces = pieces, tier = tier or 1, seen = {}, stats = {} }
		end
		T.eq(Quest.goFor(facts(1, 2, 3), q), "build:nest", "two beds for three: the Huts tab")
		T.eq(Quest.goFor(facts(2, 2, 1), q), "tree", "beds enough, one driftling: the tree's eggs")
		T.eq(Quest.goFor(facts(2, 1, 3), q), "build:work", "beds and driftlings enough, two places at work: the Work tab")
		T.eq(Quest.goFor(facts(2, 2, 3), q), q.go, "all of it there: the quest's own place (Driftlings)")
		local ten = Quests.list[1]
		for _, x in Quests.list do
			if x.id == "housed" then
				ten = x
			end
		end
		T.truthy(Plot.housingLimit(1) < ten.goal.n, "the first island holds fewer than ten")
		T.eq(Quest.goFor(facts(4, 1, 2, 1), ten), "build", "Ten at work on a full first island: Build mode, to expand")
		T.eq(Quest.goFor(facts(0, 0, 0), Quests.list[1]), Quests.list[1].go, "another quest: its own place")
	end)
end
