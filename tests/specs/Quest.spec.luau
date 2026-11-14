-- The questline (Data/Quests, Logic/Quest; GAME_DESIGN 9): its quests in order, each goal counted from what the
-- island has now, nothing while the tips are on, a claim paying the reward once the goal is met and moving on, and
-- the save keeping where the player is.
local T = require("../TestKit")
local Quests = require("../../build/luautest/shared/Data/Quests")
local Quest = require("../../build/luautest/shared/Logic/Quest")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

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
local TABS = { farm = true, wood = true, shop = true, nest = true, gen = true, path = true, decor = true }

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
		T.eq(Quests.list[1].id, "help", "it starts with putting a driftling to work")
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
		T.eq(select(2, Quest.claim(p)), "not_done", "no driftling at work yet")
		T.eq(p.quest, 1)
		table.insert(p.pals, { id = 1, sp = "pebblit", home = 4, work = 5, muts = {} })
		T.truthy(Quest.done(Quest.facts(p), q), "one at work")
		local shells = p.shells
		local ok, data = Quest.claim(p)
		T.truthy(ok, "claimed")
		T.eq(p.shells, shells + (q.reward.shells or 0), "its shells")
		T.eq(p.quest, 2, "the next quest")
		T.eq(data.id, "help")
		T.eq(data.next, 2)
	end)

	T.it("the counts: driftlings at work, paths, a kind built, the Index, the ones taken in", function()
		local p = fresh()
		local f = Quest.facts(p)
		table.insert(p.plot.placed, { uid = 1, id = "patch", x = 0, z = 0, rot = 0, lvl = 2 })
		table.insert(p.plot.placed, { uid = 2, id = "dirtpath", x = 2, z = 0, rot = 0, lvl = 1 })
		table.insert(p.plot.placed, { uid = 3, id = "nest", x = 6, z = 0, rot = 0, lvl = 1 })
		T.eq(Quest.count(f, { kind = "built", n = 2, of = "farm" }), 1, "one farm")
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
end
