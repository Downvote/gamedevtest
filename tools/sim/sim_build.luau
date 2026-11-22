-- Build mode's Undo, Select tool, tap twice and saved layouts (GAME_DESIGN 4.7; docs/ARCHITECTURE.md 6, 7.4, 10.7; the
-- request of 2026-11-21: "Also, when placing things in build mode, allow the player to tap twice to place the building
-- down. Also, add an undo button, selection tool and saving/loading of plots"). On the server: every build action one
-- Undo step (a piece put down, moved and turned, put away with a driftling's hut, replaced; tiles and fences drawn;
-- Remove all; a sale from the inventory), each taken back exactly (the same uids, the inventory, the coins it cost, the
-- driftlings home again), refused with a reason when it can't be (nothing left, the coins of a sale spent), the stack
-- capped at Tuning.UndoSteps and emptied when the island grows; a group moved and turned (four quarter turns back where
-- it was), refused where it doesn't fit or off the even studs, put away (the tree stays), copied (the inventory's
-- pieces first, the rest bought, the tree never), each one Undo step; a layout saved, quoted, loaded (the island's own
-- pieces kept with their uids, the rest from the inventory or bought, refused when the coins don't cover it) and taken
-- back with one Undo, kept over a leave and rejoin; malicious payloads for every new action (one deliberate NaN). In
-- Build mode's tray: the Undo button (grey with nothing to undo), tap twice on a touch screen (on the footprint, or on
-- a tall ghost's model), the Select tool (V, a tap and a box, the gold frames, "N selected", Move lifted and set down
-- by tapping twice, a copy stamped twice, Del, Esc, a right click), the tools' tooltips with their keys, and the
-- layouts' bar (Save, Load asking first, then loading).
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

local getD = I.getD
local Tuning = H.sharedServer("Config.Tuning")
local Street = H.sharedServer("Data.Street")
local Buildings = H.sharedServer("Data.Buildings")
local Plot = H.sharedServer("Logic.Plot")
local Layout = H.sharedServer("Logic.Layout")
local Tree = H.sharedServer("Logic.Tree")
local IslandL = H.sharedServer("Logic.Island")
local Creatures = H.sharedServer("Data.Creatures")

------------------------------------------------------------------ helpers
-- The island as one string (uids, ids, where, turn, level), the inventory and the driftlings' huts and work.
local function state(pr): string
	local parts = {}
	for _, q in pr.plot.placed do
		table.insert(parts, string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl))
	end
	table.sort(parts)
	local inv = {}
	for id, n in pr.inv do
		table.insert(inv, id .. "=" .. n)
	end
	table.sort(inv)
	local pals = {}
	for _, x in pr.pals do
		table.insert(pals, string.format("%d:%d:%d", x.id, x.home, x.work))
	end
	table.sort(pals)
	return table.concat(parts, ";") .. "|" .. table.concat(inv, ";") .. "|" .. table.concat(pals, ";")
end
-- The pieces where they stand, uids aside (a loaded layout).
local function arrangement(pr): string
	local parts = {}
	for _, q in pr.plot.placed do
		table.insert(parts, string.format("%s:%d:%d:%d", q.id, q.x, q.z, q.rot))
	end
	table.sort(parts)
	return table.concat(parts, ";")
end
-- The coins `pr` gained since `s0` come to `want`, give or take what its island made on its own since `t0`.
local function coinsNear(pr, s0: number, want: number, t0: number): (boolean, string)
	local got = pr.shells - s0
	local own = math.max(0, IslandL.rates(pr).shells) / Tuning.TurnSeconds * (E.now() - t0) * 1.5 + 1
	return got >= want - 1 and got <= want + own, string.format("%+.1f coins (want %+d)", got, want)
end
local function uidOf(pr, id: string): number
	for _, q in pr.plot.placed do
		if q.id == id then
			return q.uid
		end
	end
	return 0
end
local function indexOf(pr, uid: number): number
	for i, q in pr.plot.placed do
		if q.uid == uid then
			return i
		end
	end
	return 0
end
local function pieceBy(pr, uid: number)
	return pr.plot.placed[indexOf(pr, uid)]
end
-- A free area of w x d studs on the island's grass, its corner on even studs (scanning from the island's far corner).
local function area(pr, w: number, d: number): (number?, number?)
	local r = Street.plot(pr.tier)
	local x0 = math.floor(r.x0) + 2
	x0 -= x0 % 2
	local zs, xs = math.floor(r.z1) - d - 2, math.floor(r.x1) - w - 2
	zs -= zs % 2
	xs -= xs % 2
	for z = zs, math.floor(r.z0) + 2, -2 do
		for x = xs, x0, -2 do
			local ok = true
			for cz = z, z + d - 1 do
				for cx = x, x + w - 1 do
					if not Street.buildable(pr.tier, cx, cz) then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
			end
			if ok then
				local box = { x0 = x, z0 = z, x1 = x + w, z1 = z + d }
				for _, q in pr.plot.placed do
					local s = Plot.rect(q.id, q.x, q.z, q.rot)
					if s.x0 < box.x1 + 1 and box.x0 - 1 < s.x1 and s.z0 < box.z1 + 1 and box.z0 - 1 < s.z1 then
						ok = false
						break
					end
				end
			end
			if ok then
				return x, z
			end
		end
	end
	return nil, nil
end
local function spot(pr, id: string): (number?, number?)
	local r = Street.plot(pr.tier)
	for z = math.floor(r.z1) - 2, math.floor(r.z0) + 1, -1 do
		for x = math.floor(r.x1) - 2, math.floor(r.x0) + 1, -1 do
			if Plot.fits(pr.tier, pr.plot.placed, id, x, z, 0) then
				return x, z
			end
		end
	end
	return nil, nil
end
local function undoCount(p): number
	local s = H.session(p)
	return s and #s.undo or -1
end

------------------------------------------------------------------ 1. an island to build on
E.phase = "island"
local a = H.addPlayer({ userId = 9601, name = "Builder" })
E.run(3)
local prof = H.profile(a)
prof.shells = 2e6
prof.tut = 0
H.push(a, 0.3)
for _ = 1, 2 do
	local r = H.req(a, "island.expand", {})
	H.expect(r.ok, "island", "an expansion", tostring(r.err))
	E.run(1.5)
end
H.expect(prof.tier == 3, "island", "a tier 3 island", tostring(prof.tier))
local v0 = H.view(a)
H.expect(v0 ~= nil and v0.undo == 0 and type(v0.layouts) == "table" and #v0.layouts == Tuning.LayoutSlots, "island", "the view: nothing to undo, the layouts' slots empty", v0 and tostring(v0.undo))
H.expect(prof.v >= 26 and #prof.layouts == Tuning.LayoutSlots, "island", "a version 26 (or later) profile with its layout slots", tostring(prof.v))

------------------------------------------------------------------ 2. Undo on the server
E.phase = "undo"
do
	local fx, fz = spot(prof, "flowers")
	local s0, t0 = prof.shells, E.now()
	local before = state(prof)
	local res = H.req(a, "plot.place", { id = "flowers", x = fx, z = fz, rot = 0 })
	H.expect(res.ok and undoCount(a) == 1, "undo", "a piece put down: one step", tostring(res.err))
	E.run(0.4)
	H.expect(H.view(a).undo == 1, "undo", "the view counts it")
	res = H.req(a, "plot.undo", {})
	local ok, say = coinsNear(prof, s0, 0, t0)
	H.expect(res.ok and state(prof) == before and ok, "undo", "taken back: the piece gone, its price back", say)
	H.expect(undoCount(a) == 0, "undo", "the step gone from the stack")
	res = H.req(a, "plot.undo", {})
	H.expect(not res.ok and res.err == "not_found", "undo", "nothing left: not_found", tostring(res.err))
end
-- several in a row, taken back in turn: pieces, tiles, fences
do
	local ax, az = area(prof, 14, 10)
	H.expect(ax ~= nil, "undo", "a free area to build in")
	ax, az = ax or 0, az or 0
	local marks = { state(prof) }
	local steps = {
		{ "plot.place", { id = "flowers", x = ax, z = az, rot = 0 } },
		{ "plot.place", { id = "torch", x = ax + 3, z = az, rot = 0 } },
		{ "plot.place", { id = "nest", x = ax + 6, z = az, rot = 90 } },
		{ "plot.paint", { id = "dirtpath", cells = string.format("%d,%d;%d,%d;%d,%d", ax, az + 4, ax + 2, az + 4, ax + 4, az + 4) } },
		{ "plot.fence", { id = "picket", edges = string.format("%d,%d,0;%d,%d,0", ax, az + 8, ax + 2, az + 8) } },
	}
	for _, st in steps do
		local r = H.req(a, st[1], st[2])
		H.expect(r.ok, "undo", st[1] .. " for the stack", tostring(r.err))
		table.insert(marks, state(prof))
	end
	H.expect(undoCount(a) == #steps, "undo", "a step each", tostring(undoCount(a)))
	for k = #steps, 1, -1 do
		local r = H.req(a, "plot.undo", {})
		H.expect(r.ok and state(prof) == marks[k], "undo", "undo " .. k .. ": back to how it was before " .. steps[k][1], tostring(r.err))
	end
end
-- a hut put away with its driftling in it: back with the same uid, the driftling home again
do
	-- (room round it for a bigger hut)
	local hx, hz = area(prof, 4, 4)
	H.req(a, "plot.place", { id = "nest", x = hx, z = hz, rot = 0 })
	local hut = prof.plot.placed[#prof.plot.placed].uid
	table.insert(prof.pals, { id = prof.nextId, sp = Creatures.list[1].id, home = hut, work = 0, muts = {} })
	local pal = prof.pals[#prof.pals]
	prof.nextId += 1
	H.push(a, 0.3)
	local before = state(prof)
	local r = H.req(a, "plot.store", { i = indexOf(prof, hut) })
	H.expect(r.ok and pal.home == 0 and Plot.held(prof, "nest") >= 1, "undo", "the hut put away: its driftling has no hut", tostring(pal.home))
	r = H.req(a, "plot.undo", {})
	H.expect(r.ok and state(prof) == before and pal.home == hut, "undo", "undo: the hut back with its uid, the driftling home", tostring(pal.home))
	-- a move and a turn
	r = H.req(a, "plot.move", { i = indexOf(prof, hut), x = hx, z = hz, rot = 90 })
	H.expect(r.ok, "undo", "the hut turned", tostring(r.err))
	r = H.req(a, "plot.undo", {})
	H.expect(r.ok and state(prof) == before, "undo", "undo: turned back")
	-- replaced with another hut that fits there, then back
	local s0, t0 = prof.shells, E.now()
	local hq = pieceBy(prof, hut)
	local alt = nil
	for _, id in Plot.replacements(hq, prof.tier) do
		if alt == nil and Plot.fits(prof.tier, prof.plot.placed, id, hq.x, hq.z, hq.rot, indexOf(prof, hut)) then
			alt = id
		end
	end
	r = H.req(a, "plot.replace", { i = indexOf(prof, hut), id = alt or "burrow" })
	if H.expect(alt ~= nil and r.ok, "undo", "the hut replaced with a " .. tostring(alt), tostring(r.err)) then
		r = H.req(a, "plot.undo", {})
		local ok, say = coinsNear(prof, s0, 0, t0)
		H.expect(r.ok and state(prof) == before and ok, "undo", "undo: the hut back, the new one's price back", say)
	end
end
-- Remove all, then everything back with its uids
do
	local before = state(prof)
	local r = H.req(a, "plot.clear", { what = "pieces" })
	H.expect(r.ok and r.data.removed > 0, "undo", "Remove all buildings", tostring(r.err))
	r = H.req(a, "plot.undo", {})
	H.expect(r.ok and state(prof) == before, "undo", "undo: every one back where it stood, the inventory as it was")
end
-- a sale from the inventory: the pieces back, the coins it gave taken back; refused when they're spent
do
	prof.inv.torch = 3
	H.push(a, 0.2)
	local before = state(prof)
	local s0, t0 = prof.shells, E.now()
	local r = H.req(a, "inv.sell", { id = "torch", n = 2 })
	H.expect(r.ok and prof.inv.torch == 1, "undo", "two torches sold", tostring(r.err))
	r = H.req(a, "plot.undo", {})
	local ok, say = coinsNear(prof, s0, 0, t0)
	H.expect(r.ok and state(prof) == before and ok, "undo", "undo: the torches back, their coins taken back", say)
	r = H.req(a, "inv.sell", { id = "torch", n = 3 })
	local keep = prof.shells
	local stack0 = undoCount(a)
	prof.shells = 0
	H.push(a, 0.2)
	r = H.req(a, "plot.undo", {})
	H.expect(not r.ok and r.err == "money" and undoCount(a) == stack0, "undo", "the sale's coins spent: refused (money), the step kept", tostring(r.err))
	prof.shells = keep
	H.push(a, 0.2)
	r = H.req(a, "plot.undo", {})
	H.expect(r.ok and prof.inv.torch == 3, "undo", "with the coins back it goes")
	prof.inv.torch = nil
	H.push(a, 0.2)
end
-- the stack keeps the last Tuning.UndoSteps steps
do
	local placedNow = #prof.plot.placed
	local n = Tuning.UndoSteps + 4
	local put = 0
	for _ = 1, n do
		local tx, tz = spot(prof, "torch")
		if tx and H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 }).ok then
			put += 1
		end
	end
	H.expect(put == n and undoCount(a) == Tuning.UndoSteps, "undo", "the stack holds the last " .. Tuning.UndoSteps, tostring(undoCount(a)))
	E.run(0.4)
	H.expect(H.view(a).undo == Tuning.UndoSteps, "undo", "the view says so")
	for _ = 1, Tuning.UndoSteps do
		H.req(a, "plot.undo", {})
	end
	H.expect(#prof.plot.placed == placedNow + n - Tuning.UndoSteps and undoCount(a) == 0, "undo", "all of them taken back, the oldest stay", string.format("%d pieces", #prof.plot.placed))
	-- (the torches that stayed go again, by hand)
	for _ = 1, n - Tuning.UndoSteps do
		local i = indexOf(prof, uidOf(prof, "torch"))
		if i > 0 then
			H.req(a, "plot.store", { i = i })
		end
	end
end

------------------------------------------------------------------ 3. the Select tool on the server
E.phase = "select"
local gx, gz = area(prof, 16, 12)
H.expect(gx ~= nil, "select", "a free area for a group")
gx, gz = gx or 0, gz or 0
local group = {}
do
	H.req(a, "plot.place", { id = "flowers", x = gx + 2, z = gz + 2, rot = 0 })
	table.insert(group, prof.plot.placed[#prof.plot.placed].uid)
	H.req(a, "plot.place", { id = "torch", x = gx + 5, z = gz + 2, rot = 0 })
	table.insert(group, prof.plot.placed[#prof.plot.placed].uid)
	H.req(a, "plot.paint", { id = "dirtpath", cells = string.format("%d,%d;%d,%d", gx + 2, gz + 6, gx + 4, gz + 6) })
	table.insert(group, prof.plot.placed[#prof.plot.placed - 1].uid)
	table.insert(group, prof.plot.placed[#prof.plot.placed].uid)
	H.req(a, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", gx + 2, gz + 8) })
	table.insert(group, prof.plot.placed[#prof.plot.placed].uid)
end
local uids = Plot.uidString(group)
H.expect(#group == 5, "select", "a group of five: a flower bed, a torch, two path tiles, a fence length", uids)
do
	local stack0 = undoCount(a)
	local first = pieceBy(prof, group[1])
	local x0, z0 = first.x, first.z
	local r = H.req(a, "plot.moveMany", { uids = uids, dx = 2, dz = -2, rot = 0 })
	H.expect(r.ok and first.x == x0 + 2 and first.z == z0 - 2 and pieceBy(prof, group[1]) == first, "select", "moved together by (2, -2), each keeping its uid", tostring(r.err))
	H.expect(undoCount(a) == stack0 + 1, "select", "one Undo step for the group")
	E.run(0.4)
	local decor = E.workspace.Plots:FindFirstChild("Plot_" .. H.session(a).plot)
	decor = decor and decor:FindFirstChild("Static")
	decor = decor and decor:FindFirstChild("Decor")
	local key = string.format("%d:%s:%d:%d:%d:%d", first.uid, first.id, first.x, first.z, first.rot, first.lvl)
	H.expect(decor ~= nil and decor:FindFirstChild(key) ~= nil, "select", "the island's models follow", key)
	local before = state(prof)
	for k = 1, 4 do
		r = H.req(a, "plot.moveMany", { uids = uids, dx = 0, dz = 0, rot = 90 })
		H.expect(r.ok, "select", "a quarter turn " .. k, tostring(r.err))
	end
	H.expect(state(prof) == before, "select", "four quarter turns: back where it was")
	r = H.req(a, "plot.moveMany", { uids = uids, dx = 0, dz = 0, rot = 90 })
	H.expect(r.ok and first.rot == 90 and pieceBy(prof, group[3]).rot == 0, "select", "turned: the flower bed turns, a tile stays square")
	r = H.req(a, "plot.moveMany", { uids = uids, dx = 0, dz = 0, rot = 270 })
	H.expect(r.ok and state(prof) == before, "select", "and back with three quarters")
	-- refusals: off the even studs, onto the tree
	r = H.req(a, "plot.moveMany", { uids = uids, dx = 1, dz = 0, rot = 0 })
	H.expect(not r.ok and r.err == "bad_payload" and state(prof) == before, "select", "an odd offset under tiles: bad_payload", tostring(r.err))
	local tq = Tree.piece(prof)
	r = H.req(a, "plot.moveMany", { uids = uids, dx = tq.x - first.x + 2, dz = tq.z - first.z + 2, rot = 0 })
	H.expect(not r.ok and r.err == "blocked" and state(prof) == before, "select", "onto the Tree of Life: blocked, nothing moved", tostring(r.err))
	-- undo the turns and the move, a step each (the refusals pushed none)
	H.expect(undoCount(a) == stack0 + 7, "select", "a step for the move and each turn", tostring(undoCount(a) - stack0))
	for _ = 1, 7 do
		r = H.req(a, "plot.undo", {})
	end
	H.expect(r.ok and first.x == x0 and first.z == z0 and first.rot == 0, "select", "Undo seven times: the group back where it first stood")
end
do
	-- put away with the tree in the group: the tree stays
	local tree0 = Tree.piece(prof)
	local before = state(prof)
	local r = H.req(a, "plot.storeMany", { uids = uids .. "," .. tree0.uid })
	H.expect(r.ok and r.data.removed == 5 and r.data.kept == 1 and Tree.piece(prof) ~= nil, "select", "put away together; the tree stays", r.ok and string.format("%d %d", r.data.removed, r.data.kept) or tostring(r.err))
	r = H.req(a, "plot.storeMany", { uids = tostring(tree0.uid) })
	H.expect(not r.ok and r.err == "fixed", "select", "the tree alone: fixed", tostring(r.err))
	r = H.req(a, "plot.undo", {})
	H.expect(r.ok and state(prof) == before, "select", "Undo: the group back from the inventory")
	-- copy: the inventory's first, the rest bought; never the tree
	prof.inv = { flowers = 1 }
	H.push(a, 0.2)
	local before2 = state(prof)
	local s0, t0 = prof.shells, E.now()
	local two = Plot.uidString({ group[1], group[2] })
	r = H.req(a, "plot.copyMany", { uids = two, dx = 8, dz = 0, rot = 0 })
	local ok, say = coinsNear(prof, s0, -Buildings.byId.torch.shells, t0)
	H.expect(r.ok and r.data.placed == 2 and (prof.inv.flowers or 0) == 0 and ok, "select", "copied: the flower bed from the inventory, the torch bought", say)
	r = H.req(a, "plot.copyMany", { uids = two, dx = 8, dz = 0, rot = 0 })
	H.expect(not r.ok and r.err == "blocked", "select", "again on the copies: blocked", tostring(r.err))
	r = H.req(a, "plot.copyMany", { uids = two .. "," .. tree0.uid, dx = 0, dz = 8, rot = 0 })
	H.expect(not r.ok and r.err == "fixed", "select", "the tree is never copied", tostring(r.err))
	r = H.req(a, "plot.undo", {})
	ok, say = coinsNear(prof, s0, 0, t0)
	H.expect(r.ok and state(prof) == before2 and ok, "select", "Undo: the copies gone, the flower bed back in the inventory, the torch's price back", say)
	prof.inv.flowers = nil
	H.push(a, 0.2)
end

------------------------------------------------------------------ 4. malicious payloads
E.phase = "malicious"
do
	local before = state(prof)
	local stack0 = undoCount(a)
	local function refused(label, err, action, payload)
		local ok, out = H.raw(a, action, payload)
		H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, type(out) == "table" and tostring(out.err) or tostring(out))
		E.run(0.15)
	end
	local many = {}
	for i = 1, Plot.MANY_MAX + 1 do
		table.insert(many, tostring(i))
	end
	refused("no uids", "bad_payload", "plot.moveMany", { uids = "", dx = 0, dz = 0, rot = 0 })
	refused("uid 0", "bad_payload", "plot.storeMany", { uids = "0" })
	refused("a uid twice", "bad_payload", "plot.storeMany", { uids = group[1] .. "," .. group[1] })
	refused("too many uids", "bad_payload", "plot.storeMany", { uids = table.concat(many, ",") })
	refused("uids as a table", "bad_payload", "plot.storeMany", { uids = { group[1] } })
	refused("a trailing comma", "bad_payload", "plot.storeMany", { uids = group[1] .. "," })
	refused("a uid not on the island", "bad_payload", "plot.storeMany", { uids = "999999" })
	refused("an offset out of range", "bad_payload", "plot.moveMany", { uids = uids, dx = 401, dz = 0, rot = 0 })
	refused("a fractional offset", "bad_payload", "plot.copyMany", { uids = uids, dx = 0.5, dz = 0, rot = 0 })
	refused("NaN", "bad_payload", "plot.moveMany", { uids = uids, dx = 0 / 0, dz = 0, rot = 0 })
	refused("a 45 degree turn", "bad_payload", "plot.moveMany", { uids = uids, dx = 0, dz = 0, rot = 45 })
	refused("no turn", "bad_payload", "plot.copyMany", { uids = uids, dx = 0, dz = 0 })
	refused("an extra field", "bad_payload", "plot.storeMany", { uids = uids, all = true })
	refused("undo with a field", "bad_payload", "plot.undo", { steps = 5 })
	refused("slot 0", "bad_payload", "layout.save", { slot = 0 })
	refused("a slot past the last", "bad_payload", "layout.load", { slot = Tuning.LayoutSlots + 1 })
	refused("a slot as words", "bad_payload", "layout.quote", { slot = "1" })
	refused("a layout's code sent along", "bad_payload", "layout.save", { slot = 1, code = "tree;0000000" })
	refused("an empty slot", "not_found", "layout.load", { slot = 2 })
	H.expect(state(prof) == before and undoCount(a) == stack0, "malicious", "the refusals changed nothing, and pushed no step")
end

------------------------------------------------------------------ 5. layouts on the server
E.phase = "layouts"
local saved
do
	local r = H.req(a, "layout.save", { slot = 1 })
	local n = 0
	for _, q in prof.plot.placed do
		if not Plot.isFixed(q.id) then
			n += 1
		end
	end
	H.expect(r.ok and r.data.n == n and prof.layouts[1].n == n and prof.layouts[1].tier == 3, "layouts", "the island saved into slot 1", r.ok and tostring(r.data.n) or tostring(r.err))
	E.run(0.4)
	local v = H.view(a)
	H.expect(v.layouts[1].n == n and v.layouts[1].at > 0 and v.layouts[2].n == 0 and v.layouts[1].code == nil, "layouts", "the view: slot 1's pieces and time, the others empty, no code sent")
	saved = arrangement(prof)
	local code = prof.layouts[1].code
	H.expect(#code <= Layout.CODE_MAX and Layout.unpack(code) ~= nil, "layouts", "a short string that reads back", tostring(#code))
	-- the island changed: the group moved, a flower bed sold, a torch put down
	H.req(a, "plot.moveMany", { uids = uids, dx = -2, dz = 0, rot = 0 })
	H.req(a, "plot.store", { i = indexOf(prof, group[1]) })
	H.req(a, "inv.sell", { id = "flowers", n = 1 })
	local tx, tz = spot(prof, "torch")
	H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	local extra = prof.plot.placed[#prof.plot.placed].uid
	local torchUid = group[2]
	r = H.req(a, "layout.quote", { slot = 1 })
	H.expect(r.ok and r.data.bought == 1 and r.data.shells == Buildings.byId.flowers.shells and r.data.away == 1, "layouts", "the quote: one to buy (the flower bed sold), one to put away (the new torch)", r.ok and string.format("bought %d away %d coins %d", r.data.bought, r.data.away, r.data.shells) or tostring(r.err))
	local before = state(prof)
	local keep = prof.shells
	prof.shells = (r.ok and r.data.shells or 1) - 1
	H.push(a, 0.2)
	local r2 = H.req(a, "layout.load", { slot = 1 })
	H.expect(not r2.ok and r2.err == "money" and state(prof) == before, "layouts", "too few coins: money, nothing changed", tostring(r2.err))
	prof.shells = keep
	H.push(a, 0.2)
	local stack0 = undoCount(a)
	r2 = H.req(a, "layout.load", { slot = 1 })
	H.expect(r2.ok and arrangement(prof) == saved, "layouts", "loaded: the island as it was saved", tostring(r2.err))
	H.expect(pieceBy(prof, torchUid) ~= nil and pieceBy(prof, extra) == nil and (prof.inv.torch or 0) >= 1, "layouts", "the island's own pieces kept their uids; the new torch went to the inventory")
	H.expect(undoCount(a) == stack0 + 1, "layouts", "one Undo step")
	r2 = H.req(a, "plot.undo", {})
	H.expect(r2.ok and state(prof) == before, "layouts", "Undo: the island back as it was before the load")
	r2 = H.req(a, "layout.load", { slot = 1 })
	H.expect(r2.ok and arrangement(prof) == saved, "layouts", "and loaded again")
	-- (the group again: the flower bed was bought new)
	group = {}
	for _, q in prof.plot.placed do
		local rr = Plot.spanOf(q)
		if rr.x0 >= gx and rr.x1 <= gx + 16 and rr.z0 >= gz and rr.z1 <= gz + 12 and (q.id == "flowers" or q.id == "torch" or q.id == "dirtpath" or q.id == "picket") then
			table.insert(group, q.uid)
		end
	end
	table.sort(group, function(x, y)
		local qa, qb = pieceBy(prof, x), pieceBy(prof, y)
		return (if qa.id == "flowers" then 0 elseif qa.id == "torch" then 1 else 2) < (if qb.id == "flowers" then 0 elseif qb.id == "torch" then 1 else 2)
	end)
	H.expect(#group == 5, "layouts", "the group of five back in its place", tostring(#group))
end
-- expanding empties the stack
do
	H.expect(undoCount(a) > 0, "layouts", "(steps on the stack before growing)")
	local r = H.req(a, "island.expand", {})
	E.run(1.5)
	H.expect(r.ok and prof.tier == 4 and undoCount(a) == 0, "layouts", "the island grew: nothing left to undo", tostring(undoCount(a)))
end
-- a leave and a rejoin: the layouts kept
do
	local code = prof.layouts[1].code
	E.removePlayer(a, "leave")
	E.run(2)
	a = H.addPlayer({ userId = 9601, name = "Builder" })
	E.run(3)
	prof = H.profile(a)
	H.expect(prof ~= nil and prof.layouts[1].code == code and prof.layouts[1].tier == 3, "layouts", "back again: the layout kept")
	H.expect(undoCount(a) == 0, "layouts", "a new session: nothing to undo")
end

------------------------------------------------------------------ 6. Build mode's tray
E.phase = "build-ui"
local BuildUI = H.cmod(a, "UI.BuildUI")
local PRa = H.cmod(a, "Pixel.PixelRenderer")
local ox, oz = Street.origin(H.session(a).plot)
local function screenOf(world)
	return H.inClient(a, function()
		local pos = PRa.project(world)
		return E.v2(pos.X, pos.Y - E.inset)
	end)
end
local function press(key)
	local input = I.new("InputObject")
	input.UserInputType = E.Enum.UserInputType.Keyboard
	input.KeyCode = E.Enum.KeyCode[key]
	input.UserInputState = E.Enum.UserInputState.Begin
	I.fire(I.getSig(E.services.UserInputService, "InputBegan"), input, false)
	E.flushDeferred()
	E.run(0.3)
end
local function rightClick(pos)
	for _, sig in { "InputBegan", "InputEnded" } do
		local input = I.new("InputObject")
		input.UserInputType = E.Enum.UserInputType.MouseButton2
		input.Position = E.v3(pos.X, pos.Y, 0)
		input.UserInputState = if sig == "InputBegan" then E.Enum.UserInputState.Begin else E.Enum.UserInputState.End
		I.fire(I.getSig(E.services.UserInputService, sig), input, false)
	end
	E.flushDeferred()
	E.run(0.3)
end
local function findIn(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function tapAt(world, mouse)
	H.inClient(a, BuildUI.tapScreen, screenOf(world), mouse == true)
	E.run(0.3)
end
-- a tap on piece q (the ray meets its model's biggest part)
local function tapPiece(q)
	local plotM = E.workspace.Plots:FindFirstChild("Plot_" .. H.session(a).plot)
	local decorF = plotM and plotM:FindFirstChild("Static")
	decorF = decorF and decorF:FindFirstChild("Decor")
	local m = decorF and decorF:FindFirstChild(string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl))
	local big, vol = nil, 0
	for _, part in (m and m:GetDescendants() or {}) do
		if part:IsA("BasePart") and part.Size.X * part.Size.Y * part.Size.Z > vol then
			big, vol = part, part.Size.X * part.Size.Y * part.Size.Z
		end
	end
	if big then
		E.raycastParts = true
		tapAt(big.Position, false)
		E.raycastParts = nil
	end
	return big ~= nil
end
local Blocks = H.sharedServer("Models.Blocks")
H.expect(H.clickNamed(a, "Menu_build"), "build-ui", "the HUD's Build button")
E.run(0.4)
do
	local undoB = H.buttonNamed(a, "Undo", true)
	H.expect(undoB ~= nil and getD(undoB).props.AutoButtonColor == false, "build-ui", "the Undo button by Done, grey with nothing to undo")
	H.expect(H.buttonNamed(a, "SelectTool", true) ~= nil and H.buttonNamed(a, "LayoutsTool", true) ~= nil and H.buttonNamed(a, "QuickRemove", true) ~= nil, "build-ui", "the tools by the tabs: Select, Layouts, Quick remove")
	-- the tools' tooltips with their keys (a mouse over the button)
	local sb = H.buttonNamed(a, "SelectTool", true)
	if sb then
		I.fire(I.getSig(sb, "MouseEnter"))
		E.run(0.1)
		local tipF = findIn(a.PlayerGui, "ToolTip")
		local key = tipF and findIn(tipF, "TipKey")
		local name = tipF and findIn(tipF, "TipName")
		H.expect(key ~= nil and key.Text == "V" and name ~= nil and name.Text == "Select", "build-ui", "Select's tooltip: its name and its key, V", key and key.Text)
		I.fire(I.getSig(sb, "MouseLeave"))
		E.run(0.1)
	end
end
-- tap twice (touch): the first tap brings the ghost, the second on it puts it down
do
	local fx, fz = spot(prof, "flowers")
	local n0 = #prof.plot.placed
	H.inClient(a, BuildUI.pick, "flowers", 0)
	E.run(0.2)
	local at = E.v3(ox + fx + 1, Street.LAWN_Y, oz + fz + 1)
	tapAt(at, false)
	H.expect(#prof.plot.placed == n0 and BuildUI.debugState().ghost, "build-ui", "the first tap: the ghost there, nothing placed")
	tapAt(E.v3(ox + fx + 1.6, Street.LAWN_Y, oz + fz + 0.4), false)
	local last = prof.plot.placed[#prof.plot.placed]
	H.expect(#prof.plot.placed == n0 + 1 and last.id == "flowers" and last.x == fx and last.z == fz, "build-ui", "a second tap on the same spot (a finger's wobble off) puts it down where the ghost stood", last and string.format("%s %d,%d", last.id, last.x, last.z))
	E.run(0.4)
	local undoB = H.buttonNamed(a, "Undo", true)
	H.expect(undoB ~= nil and getD(undoB).props.AutoButtonColor ~= false, "build-ui", "Undo lit now")
	H.clickNamed(a, "Undo", { wait = 0.5 })
	H.expect(#prof.plot.placed == n0, "build-ui", "the Undo button takes it back", tostring(#prof.plot.placed))
	-- a nudge: on a big ghost, a tap on its footprint away from the spot moves it there (a hatchery, 4 x 4)
	local hx, hz = area(prof, 8, 6)
	if H.expect(hx ~= nil, "build-ui", "(room for a nudge)") then
		H.inClient(a, BuildUI.pick, "hatchery", 0)
		E.run(0.2)
		tapAt(E.v3(ox + hx + 2, Street.LAWN_Y, oz + hz + 2), false)
		tapAt(E.v3(ox + hx + 4, Street.LAWN_Y, oz + hz + 2), false)
		H.expect(#prof.plot.placed == n0 and BuildUI.debugState().ghost, "build-ui", "a tap two studs off on its footprint nudges the ghost, nothing placed")
		press("Escape")
	end
	-- a tall piece: the second tap on the model over the footprint
	local wx, wz = spot(prof, "windmill")
	H.inClient(a, BuildUI.pick, "windmill", 0)
	E.run(0.2)
	tapAt(E.v3(ox + wx + 1.5, Street.LAWN_Y, oz + wz + 1.5), false)
	H.expect(#prof.plot.placed == n0 and BuildUI.debugState().ghost, "build-ui", "a windmill's ghost")
	tapAt(E.v3(ox + wx + 1.5, Street.LAWN_Y + 2.5, oz + wz + 1.5), false)
	last = prof.plot.placed[#prof.plot.placed]
	H.expect(#prof.plot.placed == n0 + 1 and last.id == "windmill" and last.x == wx and last.z == wz, "build-ui", "a tap on its model, well above the footprint, puts it down there", last and string.format("%s %d,%d (wanted %d,%d)", last.id, last.x, last.z, wx, wz))
	press("Escape")
	H.expect(not BuildUI.debugState().ghost, "build-ui", "Esc drops the pick")
end
-- the Select tool
do
	press("V")
	local st = BuildUI.debugState()
	H.expect(st.sel and st.picked == 0, "build-ui", "V: the Select tool", tostring(st.sel))
	H.expect(H.buttonNamed(a, "SelMove", true) ~= nil and H.buttonNamed(a, "SelStore", true) ~= nil and getD(H.buttonNamed(a, "SelMove", true)).props.AutoButtonColor == false, "build-ui", "its bar: Move and Put away, grey with nothing selected")
	-- a tap on a piece adds it
	local q = pieceBy(prof, group[2])
	H.expect(q ~= nil and tapPiece(q), "build-ui", "(a tap on the group's torch)")
	st = BuildUI.debugState()
	local marks = E.workspace:FindFirstChild("SelMarks", true)
	local edge = marks and marks:FindFirstChildWhichIsA("BasePart")
	H.expect(st.picked == 1 and edge ~= nil and edge.Color == Blocks.color("gold"), "build-ui", "a tap on a piece selects it, framed in gold", tostring(st.picked))
	local what = a.PlayerGui:FindFirstChild("What", true)
	H.expect(what ~= nil and what.Text == "1 selected", "build-ui", "the bar says 1 selected", what and what.Text)
	-- a box over the group
	local n = H.inClient(a, BuildUI.debugSelect, true, nil, { gx + 2, gz + 2, gx + 6, gz + 9 })
	H.expect(n == 5, "build-ui", "a box over the group selects all five", tostring(n))
	E.run(0.3)
	what = a.PlayerGui:FindFirstChild("What", true)
	H.expect(what ~= nil and what.Text == "5 selected", "build-ui", "5 selected", what and what.Text)
	-- Move: lifted, then tapped where it goes and tapped again
	local first = pieceBy(prof, group[1])
	local x0, z0 = first.x, first.z
	press("M")
	H.expect(BuildUI.debugState().lifted == "move" and E.workspace:FindFirstChild("SelGhost", true) ~= nil, "build-ui", "M lifts the group: its ghost")
	local target = E.v3(ox + gx + 8.5, Street.LAWN_Y, oz + gz + 6.5)
	tapAt(target, false)
	H.expect(first.x == x0 and BuildUI.debugState().lifted == "move", "build-ui", "a tap brings the ghost there, nothing moved yet")
	local spans = 0
	local g = E.workspace:FindFirstChild("SelGhost", true)
	for _, d in (g and g:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Name == "Edge" and d.Color == Blocks.color("screen_on") then
			spans += 1
		end
	end
	H.expect(spans >= 5 * 4, "build-ui", "the ghost's footprints cyan where it fits", tostring(spans))
	tapAt(target, false)
	H.expect((first.x ~= x0 or first.z ~= z0) and BuildUI.debugState().lifted == "", "build-ui", "a second tap on it sets the group down", string.format("%d,%d -> %d,%d", x0, z0, first.x, first.z))
	-- a copy stamped, staying lifted for another
	local n0 = #prof.plot.placed
	H.clickNamed(a, "SelCopy", { wait = 0.3 })
	H.expect(BuildUI.debugState().lifted == "copy", "build-ui", "Copy lifts a copy")
	local t2 = E.v3(ox + gx + 2.5, Street.LAWN_Y, oz + gz + 3.5)
	tapAt(t2, false)
	tapAt(t2, false)
	H.expect(#prof.plot.placed == n0 + 5 and BuildUI.debugState().lifted == "copy", "build-ui", "tapped twice: five copies down, the copy still lifted for another", tostring(#prof.plot.placed - n0))
	-- a right click lets the copy go, Esc ends the tool
	rightClick(screenOf(t2))
	H.expect(BuildUI.debugState().lifted == "" and BuildUI.debugState().sel, "build-ui", "a right click lets the copy go")
	-- Del puts the group away (the originals)
	local held0 = Plot.held(prof, "torch")
	press("Delete")
	H.expect(pieceBy(prof, group[2]) == nil and Plot.held(prof, "torch") == held0 + 1 and BuildUI.debugState().picked == 0, "build-ui", "Del puts the group away")
	press("Escape")
	H.expect(not BuildUI.debugState().sel and E.workspace:FindFirstChild("SelMarks", true) == nil, "build-ui", "Esc ends the Select tool, its frames gone")
	H.clickNamed(a, "Undo", { wait = 0.5 })
	H.expect(pieceBy(prof, group[2]) ~= nil, "build-ui", "Undo brings the group back")
end
-- the layouts' bar
do
	H.clickNamed(a, "LayoutsTool", { wait = 0.3 })
	local s1 = a.PlayerGui:FindFirstChild("Slot_1", true)
	H.expect(BuildUI.debugState().layouts and s1 ~= nil and H.buttonNamed(a, "Load_1") ~= nil, "build-ui", "the layouts' bar: a plate a slot, Load lit on the saved one")
	local l2 = H.buttonNamed(a, "Load_2", true)
	H.expect(l2 ~= nil and getD(l2).props.AutoButtonColor == false, "build-ui", "Load grey on an empty slot")
	H.clickNamed(a, "Save_2", { wait = 0.5 })
	H.expect(prof.layouts[2].n > 0, "build-ui", "Save on an empty slot saves at once", tostring(prof.layouts[2].n))
	local arr = arrangement(prof)
	H.clickNamed(a, "Save_2", { wait = 0.3 })
	local again = H.buttonNamed(a, "Save_2")
	local againText = again and table.concat(H.textsOf(again), "/") or ""
	H.expect(string.find(againText, "Tap again", 1, true) ~= nil, "build-ui", "Save over a saved slot asks first", againText)
	-- Load asks (the quote), then loads
	local tx, tz = spot(prof, "torch")
	H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	E.run(0.3)
	H.clickNamed(a, "Load_2", { wait = 0.5 })
	local line1 = a.PlayerGui:FindFirstChild("Slot_2", true)
	line1 = line1 and line1:FindFirstChild("Line1", true)
	H.expect(arrangement(prof) ~= arr and line1 ~= nil and string.find(line1.Text, "all yours", 1, true) ~= nil, "build-ui", "the first tap on Load says what it takes", line1 and line1.Text)
	H.clickNamed(a, "Load_2", { wait = 0.6 })
	H.expect(arrangement(prof) == arr, "build-ui", "the second loads it")
	H.clickNamed(a, "LayoutsBack", { wait = 0.3 })
	H.expect(not BuildUI.debugState().layouts, "build-ui", "Back to the catalog")
	H.clickNamed(a, "BuildDone", { wait = 0.4 })
	H.expect(not BuildUI.isOpen(), "build-ui", "Done closes Build mode")
end

------------------------------------------------------------------ the end
E.phase = "end"
H.checkProfile(a, "end")
H.checkMirror(a, "end")
report(E, H)
