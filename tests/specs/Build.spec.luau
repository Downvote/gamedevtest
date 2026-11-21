-- Build mode's Undo, Select tool and saved layouts (Logic/Undo, Plot.moveMany / storeMany / copyMany, Logic/Layout;
-- GAME_DESIGN 4.7). The request of 2026-11-21: "add an undo button, selection tool and saving/loading of plots". Every
-- build action is one step an undo takes back exactly (the island, the inventory, the coins it cost, the driftlings'
-- huts and work), and is refused with a reason when it no longer can be; a group moves, turns, goes away or is copied
-- all or nothing; a layout saves into a short string and loads back with the island's own pieces first.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Undo = require("../../build/luautest/shared/Logic/Undo")
local Layout = require("../../build/luautest/shared/Logic/Layout")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Tree = require("../../build/luautest/shared/Logic/Tree")
local Validate = require("../../build/luautest/shared/Logic/Validate")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island of tier 3 with no pieces: the rules on their own)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells = 1e6
	p.tier = 3
	p.plot.placed = {}
	return p
end

-- What IslandService does round a build action: capture, the action, the huts and work settled, the step pushed.
local function act(p: any, stack: { any }, what: string, fn: () -> (boolean, any)): (boolean, any)
	local before = Undo.capture(p)
	local ok, data = fn()
	if ok then
		Tree.settle(p)
		Tree.fillJobs(p)
		local step = Undo.diff(before, p, what)
		if step then
			Undo.push(stack, step)
		end
	end
	return ok, data
end
local function undo(p: any, stack: { any }): (boolean, any)
	local step = stack[#stack]
	if step == nil then
		return false, "not_found"
	end
	local ok, data = Undo.apply(p, step)
	if ok then
		table.remove(stack)
		Tree.settle(p)
		Tree.fillJobs(p)
	end
	return ok, data
end

-- The island, the inventory, the coins and the driftlings as one string, to compare before and after.
local function state(p: any): string
	local parts = {}
	for _, q in p.plot.placed do
		table.insert(parts, string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl))
	end
	table.sort(parts)
	local inv = {}
	for id, n in p.inv do
		table.insert(inv, id .. "=" .. n)
	end
	table.sort(inv)
	local pals = {}
	for _, x in p.pals do
		table.insert(pals, string.format("%d:%d:%d", x.id, x.home, x.work))
	end
	table.sort(pals)
	return table.concat(parts, ";") .. "|" .. table.concat(inv, ";") .. "|" .. p.shells .. "|" .. table.concat(pals, ";")
end

-- The pieces where they stand, uids aside (a layout loaded back).
local function arrangement(p: any): string
	local parts = {}
	for _, q in p.plot.placed do
		table.insert(parts, string.format("%s:%d:%d:%d", q.id, q.x, q.z, q.rot))
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

local function uidOf(p: any, id: string): number
	for _, q in p.plot.placed do
		if q.id == id then
			return q.uid
		end
	end
	return 0
end
local function indexOf(p: any, uid: number): number
	for i, q in p.plot.placed do
		if q.uid == uid then
			return i
		end
	end
	return 0
end
local function addPal(p: any, home: number): any
	local x = { id = p.nextId, sp = Creatures.list[1].id, home = home, work = 0, muts = {} }
	p.nextId += 1
	table.insert(p.pals, x)
	return x
end

return function()
	T.it("Undo takes back a piece put down: the coins come back, the piece goes, nothing lands in the inventory", function()
		local p = fresh()
		local stack = {}
		local s0 = state(p)
		local built = p.stats.built
		T.truthy(act(p, stack, "plot.place", function()
			return Plot.place(p, "flowers", 8, 4, 0)
		end))
		T.eq(#stack, 1)
		T.eq(stack[1].shells, Buildings.byId.flowers.shells, "the step knows what it cost")
		T.truthy(undo(p, stack))
		T.eq(state(p), s0, "the island and the coins as they were")
		T.eq(p.stats.built, built, "the build count too")
		T.eq(#stack, 0)
		T.eq(select(2, undo(p, stack)), "not_found", "nothing left to take back")
	end)
	T.it("Undo of a piece from the inventory puts it back in the inventory, coins untouched", function()
		local p = fresh()
		p.inv = { flowers = 1 }
		local stack = {}
		local s0 = state(p)
		T.truthy(act(p, stack, "plot.place", function()
			return Plot.place(p, "flowers", 8, 4, 0)
		end))
		T.eq(Plot.held(p, "flowers"), 0)
		T.truthy(undo(p, stack))
		T.eq(state(p), s0)
		T.eq(Plot.held(p, "flowers"), 1)
	end)
	T.it("Undo of a hut put away brings it back with its uid and its driftlings home; of a move, back where it stood", function()
		local p = fresh()
		local stack = {}
		T.truthy(Plot.place(p, "nest", 8, 4, 0))
		local hut = uidOf(p, "nest")
		local a, b = addPal(p, hut), addPal(p, hut)
		T.truthy(Plot.place(p, "patch", 0, -6, 0))
		Tree.fillJobs(p)
		local s0 = state(p)
		T.truthy(act(p, stack, "plot.store", function()
			return Plot.store(p, indexOf(p, hut))
		end))
		T.eq(a.home, 0, "out of the hut")
		T.eq(Plot.held(p, "nest"), 1)
		T.truthy(undo(p, stack))
		T.eq(state(p), s0, "the hut back, the same uid, both home and at work again")
		T.truthy(a.home == hut and b.home == hut)
		-- a move and a turn
		T.truthy(act(p, stack, "plot.move", function()
			return Plot.move(p, indexOf(p, hut), 12, 4, 90)
		end))
		T.truthy(undo(p, stack))
		T.eq(state(p), s0)
	end)
	T.it("Undo of drawn tiles, rubbed out water (and the lily pads on it), fences and Remove all puts each back exactly", function()
		local p = fresh()
		local stack = {}
		local s0 = state(p)
		local cells = { { 8, -8 }, { 10, -8 }, { 12, -8 }, { 8, -6 }, { 10, -6 }, { 12, -6 } }
		T.truthy(act(p, stack, "plot.paint", function()
			return Plot.paint(p, "stream", cells)
		end))
		T.truthy(act(p, stack, "plot.place", function()
			return Plot.place(p, "lilypads", 10, -8, 0)
		end))
		T.truthy(act(p, stack, "plot.fence", function()
			return Plot.fence(p, "picket", { { 0, 6, 0 }, { 2, 6, 0 } })
		end))
		T.truthy(act(p, stack, "plot.paint", function()
			return Plot.paint(p, "dirtpath", { { 0, 0 }, { 2, 0 } })
		end))
		local s1 = state(p)
		T.truthy(act(p, stack, "plot.unpaint", function()
			return Plot.unpaint(p, { { 10, -8 } }, "water")
		end))
		T.truthy(act(p, stack, "plot.unfence", function()
			return Plot.unfence(p, { { 0, 6, 0 } })
		end))
		T.truthy(act(p, stack, "plot.clear", function()
			return Plot.clear(p, "tiles")
		end))
		T.eq(#p.plot.placed, 1, "a fence length left")
		T.truthy(undo(p, stack))
		T.truthy(undo(p, stack))
		T.truthy(undo(p, stack))
		T.eq(state(p), s1, "the water, the lily pads and the fence back as they stood")
		for _ = 1, 4 do
			T.truthy(undo(p, stack))
		end
		T.eq(state(p), s0, "and on back to the empty island, every coin returned")
	end)
	T.it("Undo of a replace and of a sale: the old piece and its price back; a sale's coins taken back, or refused when spent", function()
		local p = fresh()
		p.tier = 2
		local stack = {}
		T.truthy(Plot.place(p, "nest", 8, 4, 0))
		local s0 = state(p)
		T.truthy(act(p, stack, "plot.replace", function()
			return Plot.replace(p, indexOf(p, uidOf(p, "nest")), "burrow")
		end))
		T.truthy(undo(p, stack))
		T.eq(state(p), s0)
		p.inv = { flowers = 3 }
		local s1 = state(p)
		T.truthy(act(p, stack, "inv.sell", function()
			return Plot.sellHeld(p, "flowers", 2)
		end))
		T.truthy(undo(p, stack))
		T.eq(state(p), s1, "the two back in the inventory, the coins they gave taken back")
		T.truthy(act(p, stack, "inv.sell", function()
			return Plot.sellHeld(p, "flowers", 3)
		end))
		p.shells = 0
		T.eq(select(2, undo(p, stack)), "money", "the coins the sale gave are spent")
		T.eq(#stack, 1, "the step stays")
	end)
	T.it("Undo is refused when the island no longer allows it: a piece gone, a Hatchery warming an egg, a spot taken", function()
		local p = fresh()
		local stack = {}
		T.truthy(act(p, stack, "plot.place", function()
			return Plot.place(p, "flowers", 8, 4, 0)
		end))
		local placeStep = stack[1]
		T.truthy(act(p, stack, "plot.store", function()
			return Plot.store(p, indexOf(p, uidOf(p, "flowers")))
		end))
		T.eq(select(2, Undo.apply(p, placeStep)), "not_found", "the piece it put down is gone")
		-- the stored piece's spot taken by another
		local storeStep = stack[2]
		T.truthy(Plot.place(p, "torch", 8, 4, 0))
		local s = state(p)
		T.eq(select(2, Undo.apply(p, storeStep)), "blocked", "a torch stands where it stood")
		T.eq(state(p), s, "nothing changed")
		-- a Hatchery warming an egg
		local q = fresh()
		local st = {}
		T.truthy(act(q, st, "plot.place", function()
			return Plot.place(q, "hatchery", 8, 4, 0)
		end))
		q.eggs = { { uid = uidOf(q, "hatchery"), sp = Creatures.list[1].id, left = 10 } :: any }
		T.eq(select(2, undo(q, st)), "egg")
	end)
	T.it("the stack keeps the last Tuning.UndoSteps steps and at most Tuning.UndoRecords records, the newest always", function()
		local stack = {}
		for i = 1, Tuning.UndoSteps + 5 do
			Undo.push(stack, { what = "plot.place", gone = {}, added = { i }, moved = {}, inv = {}, shells = 1, built = 1, pals = {}, size = 2 } :: any)
		end
		T.eq(#stack, Tuning.UndoSteps)
		T.eq(stack[#stack].added[1], Tuning.UndoSteps + 5, "the newest on top")
		Undo.push(stack, { what = "plot.clear", gone = {}, added = {}, moved = {}, inv = {}, shells = 0, built = 0, pals = {}, size = Tuning.UndoRecords + 1 } :: any)
		T.eq(#stack, 1, "one huge step pushes the rest out, and stays")
	end)
	T.it("Select: a group moves by an offset, keeping its uids; turns a quarter about its middle; all or nothing", function()
		local p = fresh()
		local stack = {}
		T.truthy(Plot.place(p, "flowers", 8, 4, 0))
		T.truthy(Plot.place(p, "torch", 10, 4, 0))
		T.truthy(Plot.paint(p, "dirtpath", { { 8, 6 } }))
		local uids = {}
		for _, q in p.plot.placed do
			table.insert(uids, q.uid)
		end
		local s0 = state(p)
		T.eq(select(2, Plot.moveMany(p, uids, 1, 0, 0)), "bad_payload", "a path keeps to the even studs")
		local ok = act(p, stack, "plot.moveMany", function()
			return Plot.moveMany(p, uids, 2, -2, 0)
		end)
		T.truthy(ok)
		T.eq(p.plot.placed[1].x, 10)
		T.eq(p.plot.placed[1].z, 2)
		T.eq(p.plot.placed[1].uid, uids[1])
		-- four quarter turns come back round
		local s1 = state(p)
		for _ = 1, 4 do
			T.truthy(Plot.moveMany(p, uids, 0, 0, 90))
		end
		T.eq(state(p), s1, "four turns, the same island")
		T.truthy(Plot.moveMany(p, uids, 0, 0, 180))
		T.truthy(Plot.moveMany(p, uids, 0, 0, 180))
		T.eq(state(p), s1, "two half turns, the same island")
		T.truthy(Plot.moveMany(p, uids, 0, 0, 90))
		T.eq(p.plot.placed[1].rot, 90, "a piece turns with its group")
		T.eq(p.plot.placed[3].rot, 0, "a tile stays square")
		T.eq(p.plot.placed[3].x % 2 + p.plot.placed[3].z % 2, 0, "on the even studs")
		T.truthy(Plot.moveMany(p, uids, 0, 0, 270))
		T.eq(state(p), s1, "a quarter and three quarters")
		T.eq(select(2, Plot.moveMany(p, uids, 0, 0, 45)), "bad_payload")
		-- a piece in the way: nothing moves
		p.inv = { nest = 1 }
		T.truthy(Plot.place(p, "nest", 14, 2, 0))
		local s2 = state(p)
		T.eq(select(2, Plot.moveMany(p, uids, 4, 0, 0)), "blocked")
		T.eq(state(p), s2)
		T.eq(select(2, Plot.moveMany(p, { 99999 }, 2, 0, 0)), "bad_payload", "a uid not on the island")
		-- one undo takes the whole move back
		local nest = indexOf(p, uidOf(p, "nest"))
		table.remove(p.plot.placed, nest)
		T.truthy(undo(p, stack))
		T.eq(state(p), s0)
	end)
	T.it("Select: a group put away together (never the tree, nor a warming Hatchery) and copied, the inventory's first", function()
		local p = Schema.default(0, 1)
		p.shells = 1e6
		p.tier = 3
		local tree = uidOf(p, Tree.ID)
		T.truthy(Plot.place(p, "flowers", 8, 4, 0))
		T.truthy(Plot.place(p, "torch", 10, 4, 0))
		local f, t = uidOf(p, "flowers"), uidOf(p, "torch")
		T.eq(select(2, Plot.storeMany(p, { tree })), "fixed", "the tree alone stays")
		T.eq(select(2, Plot.copyMany(p, { f, tree }, 0, 6, 0)), "fixed", "the tree isn't copied")
		-- copy: one flower bed waits in the inventory, the torch is bought
		p.inv = { flowers = 1 }
		local cost = Plot.copyCost(p, { f, t }) :: any
		T.deepEq(cost, { shells = Buildings.byId.torch.shells, held = 1, bought = 1 })
		local before = p.shells
		local ok, data = Plot.copyMany(p, { f, t }, 0, 4, 0)
		T.truthy(ok)
		T.eq(data.placed, 2)
		T.eq(p.shells, before - cost.shells, "paid what the quote said")
		T.eq(Plot.held(p, "flowers"), 0)
		T.eq(#p.plot.placed, 5)
		T.eq(select(2, Plot.copyMany(p, { f, t }, 0, 4, 0)), "blocked", "the copies stand there now")
		p.shells = 0
		T.eq(select(2, Plot.copyMany(p, { f, t }, 0, 8, 0)), "money")
		p.shells = 1e6
		-- put away: the tree stays and is counted
		ok, data = Plot.storeMany(p, { f, t, tree })
		T.truthy(ok)
		T.eq(data.removed, 2)
		T.eq(data.kept, 1)
		T.eq(Plot.held(p, "flowers"), 1)
		T.truthy(uidOf(p, Tree.ID) == tree)
	end)
	T.it("the tips' free workplace is free once in a copied group", function()
		local p = fresh()
		p.tut = Plot.TIP_WORK
		local w = Plot.tipWork(p.tier)
		local price = Plot.pricer(p)
		T.eq(price(w), 0, "the first is free")
		T.eq(price(w), Buildings.byId[w].shells, "the second is paid")
	end)
	T.it("a layout packs into a short string and reads back; garbage doesn't read", function()
		local p = Schema.default(0, 1)
		p.tier = 3
		p.shells = 1e6
		T.truthy(Plot.place(p, "flowers", 8, 4, 90))
		T.truthy(Plot.paint(p, "stream", { { 8, -8 }, { 10, -8 } }))
		T.truthy(Plot.fence(p, "picket", { { 8, 0, 0 } }))
		local code = Layout.pack(p.plot.placed)
		local list = Layout.unpack(code) :: any
		T.eq(#list, #p.plot.placed)
		for i, q in p.plot.placed do
			T.deepEq(list[i], { id = q.id, x = q.x, z = q.z, rot = q.rot })
		end
		T.eq(#code, #(string.match(code, "^[^;]*;") :: string) + 7 * #p.plot.placed, "seven characters a piece")
		for _, bad in { "", ";", "flowers;0", "flo wers;0000000", "flowers;0100000", "flowers;00zz000", "flowers;0000004", 5, {} } do
			local got = Layout.unpack(bad)
			T.truthy(got == nil or (bad == ";" and #got == 0), "garbage: " .. tostring(bad))
		end
		T.eq(Layout.unpack(string.rep("a", Layout.CODE_MAX + 1)), nil, "too long")
		-- a save's layouts: always the slots, empty where they don't read
		local clean = Layout.clean({ { at = 5, tier = 3, n = 99, code = code }, { code = "junk" }, "x" })
		T.eq(#clean, Tuning.LayoutSlots)
		T.eq(clean[1].n, #p.plot.placed - 1, "the tree apart")
		T.eq(clean[1].at, 5)
		T.eq(clean[2].code, "")
		T.eq(clean[3].n, 0)
		T.eq(#Layout.clean(nil), Tuning.LayoutSlots)
	end)
	T.it("a layout saved and loaded: the island's pieces first, then the inventory's, then bought; one undo takes it back", function()
		local p = Schema.default(0, 1)
		p.tier = 3
		p.shells = 1e6
		T.truthy(Plot.place(p, "nest", 8, 4, 0))
		local hut = uidOf(p, "nest")
		local pal = addPal(p, hut)
		T.truthy(Plot.place(p, "flowers", 0, -6, 0))
		T.truthy(Plot.paint(p, "stream", { { 8, -8 }, { 10, -8 } }))
		T.truthy(Plot.place(p, "lilypads", 8, -8, 0))
		T.truthy(Layout.save(p, 1, 1000))
		local saved = arrangement(p)
		T.eq(Layout.view(p)[1].n, 5)
		T.eq(Layout.view(p)[2].n, 0, "the other slots empty")
		-- the island changed: the hut moved, the flowers sold, a torch put down
		T.truthy(Plot.move(p, indexOf(p, hut), 12, 4, 0))
		T.truthy(Plot.store(p, indexOf(p, uidOf(p, "flowers"))))
		T.truthy(Plot.sellHeld(p, "flowers", 1))
		T.truthy(Plot.place(p, "torch", 2, -2, 0))
		local stack = {}
		local s0 = state(p)
		local ok, plan = Layout.plan(p, 1)
		T.truthy(ok)
		T.eq(plan.bought, 1, "the flowers were sold")
		T.eq(plan.shells, Buildings.byId.flowers.shells)
		T.eq(plan.away, 1, "the torch goes into the inventory")
		T.eq(state(p), s0, "a plan changes nothing")
		p.shells = plan.shells - 1
		T.eq(select(2, Layout.load(p, 1)), "money")
		p.shells = 1e6
		s0 = state(p)
		local before = p.shells
		ok = act(p, stack, "layout.load", function()
			return Layout.load(p, 1)
		end)
		T.truthy(ok)
		T.eq(arrangement(p), saved, "the island as it was saved")
		T.eq(p.shells, before - plan.shells)
		T.eq(uidOf(p, "nest"), hut, "the hut kept its uid")
		T.eq(pal.home, hut, "and its driftling")
		T.eq(Plot.held(p, "torch"), 1)
		T.eq(#stack, 1, "one step")
		T.truthy(undo(p, stack))
		T.eq(state(p), s0, "taken back whole")
		T.eq(select(2, Layout.plan(p, 2)), "not_found", "an empty slot")
		T.eq(select(2, Layout.save(p, Tuning.LayoutSlots + 1, 0)), "bad_payload")
	end)
	T.it("a layout on a smaller island: what's locked, past a limit or off the grass is passed over and counted", function()
		local p = Schema.default(0, 1)
		p.tier = 3
		p.shells = 1e6
		T.truthy(Plot.place(p, "hatchery", 8, 4, 0))
		T.truthy(Plot.place(p, "flowers", 0, -6, 0))
		T.truthy(Layout.save(p, 2, 0))
		p.tier = 1
		local ok, plan = Layout.plan(p, 2)
		T.truthy(ok)
		T.eq(plan.locked, 1, "no Hatchery on a first island")
		T.eq(plan.placed + plan.locked + plan.limit + plan.blocked, 2)
	end)
	T.it("the requests: uids, offsets and slots checked; every new action's fields exact", function()
		local good = { "1", "12,40,41", "999999999" }
		for _, v in good do
			T.truthy(Validate.request("plot.storeMany", { uids = v }), "uids " .. v)
		end
		local many = {}
		for i = 1, 301 do
			table.insert(many, tostring(i))
		end
		for _, v in { "", ",", "1,", ",1", "1,,2", "01", "1,1", "a", "1.5", "-1", "1234567890", table.concat(many, ","), 5, true } do
			T.eq(Validate.request("plot.storeMany", { uids = v }), false, "uids " .. tostring(v))
		end
		T.truthy(Validate.request("plot.moveMany", { uids = "1,2", dx = -400, dz = 400, rot = 90 }))
		T.eq(Validate.request("plot.moveMany", { uids = "1,2", dx = 401, dz = 0, rot = 0 }), false)
		T.eq(Validate.request("plot.moveMany", { uids = "1,2", dx = 0.5, dz = 0, rot = 0 }), false)
		T.eq(Validate.request("plot.copyMany", { uids = "1,2", dx = 0, dz = 0 }), false, "rot missing")
		T.eq(Validate.request("plot.copyMany", { uids = "1", dx = 0, dz = 0, rot = 45 }), false)
		T.truthy(Validate.request("plot.undo", {}))
		T.eq(Validate.request("plot.undo", { all = true }), false)
		for _, a in { "layout.save", "layout.quote", "layout.load" } do
			T.truthy(Validate.request(a, { slot = 1 }))
			T.truthy(Validate.request(a, { slot = Tuning.LayoutSlots }))
			T.eq(Validate.request(a, { slot = 0 }), false)
			T.eq(Validate.request(a, { slot = Tuning.LayoutSlots + 1 }), false)
			T.eq(Validate.request(a, { slot = 0 / 0 }), false)
		end
	end)
	T.it("a save from before layouts loads with every slot empty; a saved layout survives a load", function()
		local old = Schema.default(0, 1) :: any
		old.v = 25
		old.layouts = nil
		local p = Schema.reconcile(old, 0, 1)
		T.eq(p.v, Schema.VERSION)
		T.eq(#p.layouts, Tuning.LayoutSlots)
		for _, s in p.layouts do
			T.eq(s.code, "")
		end
		T.truthy(Layout.save(p, 3, 77))
		local again = Schema.reconcile(p, 0, 1)
		T.eq(again.layouts[3].code, p.layouts[3].code)
		T.eq(again.layouts[3].at, 77)
	end)
end
