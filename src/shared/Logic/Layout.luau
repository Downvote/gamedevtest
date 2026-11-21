--!strict
-- Saved layouts (GAME_DESIGN 4.7; docs/ARCHITECTURE.md 6). Pure. The request of 2026-11-21: "add an undo button,
-- selection tool and saving/loading of plots". A profile keeps Tuning.LayoutSlots layouts (Profile.layouts), each the
-- island's pieces where they stood when it was saved, with the time and the island's tier. Loading one puts the
-- island's pieces away and lays the layout down in their place: the pieces already on the island first (each keeps its
-- uid, so its workers and driftlings stay), then the inventory's, then bought (Layout.plan says what it costs first;
-- the load is refused with "money" when the coins don't cover it). The Tree of Life goes to its saved spot when that
-- fits, else stays; a Hatchery warming an egg stays where it is. A piece a smaller island has no room for, one not yet
-- unlocked, or one past a limit is passed over and counted. A load is one Undo step (Logic/Undo).
--
-- A layout is stored as one short string: the piece ids it uses, joined by ",", then ";", then seven characters a
-- piece: the id's place in that list (two base-36 digits), x + 240 and z + 240 (two each) and the quarter turn (0-3).
-- The biggest island at every limit is about 4,700 pieces, some 33 KB.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Office = require(script.Parent.Parent.Data.Office)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Piece = Types.Piece
type ErrCode = Types.ErrCode

local Layout = {}

export type Entry = { id: string, x: number, z: number, rot: number }
-- What loading a layout does (Layout.plan): pieces laid down (the tree apart), from the island or the inventory
-- (`held`), bought and for how many coins; passed over: not unlocked (`locked`, or no longer in the game), past a limit,
-- no room; the island's pieces put away; whether the tree moves.
export type Plan = {
	placed: number,
	held: number,
	bought: number,
	shells: number,
	locked: number,
	limit: number,
	blocked: number,
	away: number,
	tree: boolean,
}

Layout.SLOTS = Tuning.LayoutSlots
-- (every count's limit on the biggest island, and the tree)
local TOP = #Tuning.PlotPieces
Layout.MAX_PIECES = Plot.limit(TOP) + Plot.pathLimit(TOP) + Plot.fenceLimit(TOP) + 1
Layout.CODE_MAX = Layout.MAX_PIECES * 7 + 8192
local OFF = 240
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function enc2(n: number): string
	local hi, lo = n // 36, n % 36
	return string.sub(DIGITS, hi + 1, hi + 1) .. string.sub(DIGITS, lo + 1, lo + 1)
end
local VAL: { [string]: number } = {}
for i = 1, #DIGITS do
	VAL[string.sub(DIGITS, i, i)] = i - 1
end
local function dec2(s: string, at: number): number?
	local a, b = VAL[string.sub(s, at, at)], VAL[string.sub(s, at + 1, at + 1)]
	if a == nil or b == nil then
		return nil
	end
	return a * 36 + b
end

function Layout.pack(placed: { Piece }): string
	local ids: { string } = {}
	local at: { [string]: number } = {}
	local recs: { string } = table.create(#placed)
	for _, q in placed do
		local k = at[q.id]
		if k == nil then
			table.insert(ids, q.id)
			k = #ids - 1
			at[q.id] = k
		end
		table.insert(recs, enc2(k) .. enc2(q.x + OFF) .. enc2(q.z + OFF) .. tostring((q.rot // 90) % 4))
	end
	return table.concat(ids, ",") .. ";" .. table.concat(recs)
end

-- The pieces of a layout's string, or nil when it doesn't read (too long, a bad id, a record out of range, too many).
-- An id the game no longer has reads (Layout.plan passes over it).
function Layout.unpack(code: any): { Entry }?
	if type(code) ~= "string" or #code < 1 or #code > Layout.CODE_MAX then
		return nil
	end
	local cut = string.find(code, ";", 1, true)
	if cut == nil then
		return nil
	end
	local head, body = string.sub(code, 1, cut - 1), string.sub(code, cut + 1)
	if #body % 7 ~= 0 or #body // 7 > Layout.MAX_PIECES then
		return nil
	end
	local ids: { string } = {}
	if #head > 0 then
		for id in string.gmatch(head .. ",", "([^,]*),") do
			if #id < 1 or #id > 24 or string.match(id, "^[%w_]+$") == nil or #ids >= 36 * 36 then
				return nil
			end
			table.insert(ids, id)
		end
	end
	local out: { Entry } = table.create(#body // 7)
	for i = 1, #body, 7 do
		local k, x, z = dec2(body, i), dec2(body, i + 2), dec2(body, i + 4)
		local r = tonumber(string.sub(body, i + 6, i + 6))
		if k == nil or x == nil or z == nil or r == nil or r > 3 or k >= #ids then
			return nil
		end
		x -= OFF
		z -= OFF
		if x < -240 or x > 160 or z < -240 or z > 160 then
			return nil
		end
		table.insert(out, { id = ids[k + 1], x = x, z = z, rot = r * 90 })
	end
	return out
end

local function empty(): Types.LayoutSave
	return { at = 0, tier = 0, n = 0, code = "" }
end

-- A save's layouts (Logic/Schema): exactly SLOTS of them, each one that reads or empty.
function Layout.clean(v: any): { Types.LayoutSave }
	local out: { Types.LayoutSave } = {}
	for i = 1, Layout.SLOTS do
		local s = if type(v) == "table" then v[i] else nil
		local list = if type(s) == "table" then Layout.unpack(s.code) else nil
		if type(s) == "table" and list and #list > 0 then
			local n = 0
			for _, e in list do
				local d = Buildings.byId[e.id]
				if d == nil or d.kind ~= "tree" then
					n += 1
				end
			end
			local at = if type(s.at) == "number" and s.at == s.at then math.clamp(math.floor(s.at), 0, 1e11) else 0
			local tier = if type(s.tier) == "number" and s.tier == s.tier then math.clamp(math.floor(s.tier), 1, #Office.plans) else 1
			table.insert(out, { at = at, tier = tier, n = n, code = s.code })
		else
			table.insert(out, empty())
		end
	end
	return out
end

local function slotsOf(p: Profile): { Types.LayoutSave }
	local l = (p :: any).layouts
	if type(l) ~= "table" or #l ~= Layout.SLOTS then
		l = Layout.clean(l)
		;(p :: any).layouts = l
	end
	return l
end

-- What the client sees of the layouts: each slot's time saved, tier and pieces (the tree apart; 0: empty).
function Layout.view(p: Profile): { { at: number, tier: number, n: number } }
	local out = {}
	for _, s in slotsOf(p) do
		table.insert(out, { at = s.at, tier = s.tier, n = s.n })
	end
	return out
end

-- Save the island as it stands into a slot (`now`: os.time). bad_payload (no such slot). Data { slot, n }.
function Layout.save(p: Profile, slot: number, now: number): (boolean, any)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Layout.SLOTS then
		return false, "bad_payload" :: ErrCode
	end
	local slots = slotsOf(p)
	local n = 0
	for _, q in p.plot.placed do
		if not Plot.isFixed(q.id) then
			n += 1
		end
	end
	slots[slot] = { at = math.floor(now), tier = p.tier, n = n, code = Layout.pack(p.plot.placed) }
	return true, { slot = slot, n = n }
end

------------------------------------------------------------------ loading
type Lay = { id: string, x: number, z: number, rot: number, src: Piece?, from: string }
type Work = { plan: Plan, keep: { Piece }, tree: Piece?, treeAt: Entry?, lays: { Lay }, away: { Piece } }

-- The island's counts as pieces go down (Plot.roomFor's limits, kept as running totals so a layout of thousands is
-- tried in one pass).
type Tally = { groups: { [string]: number }, slots: number, jobs: number, hatch: number, boosts: { [string]: number } }
local function tallyAdd(t: Tally, id: string)
	local d = Buildings.byId[id]
	if d == nil then
		return
	end
	local g = Plot.group(id)
	t.groups[g] = (t.groups[g] or 0) + 1
	if d.kind == "nest" then
		t.slots += d.slots
	end
	t.jobs += d.jobs
	if d.kind == "breed" then
		t.hatch += 1
	end
	if d.kind == "gen" then
		t.boosts[id] = (t.boosts[id] or 0) + 1
	end
end
local function tallyRoom(t: Tally, tier: number, id: string): boolean
	local d = Buildings.byId[id]
	if d == nil then
		return false
	end
	local g = Plot.group(id)
	if (t.groups[g] or 0) + 1 > Plot.groupLimit(g, tier) then
		return false
	end
	if d.kind == "nest" and t.slots + d.slots > Plot.housingLimit(tier) then
		return false
	end
	if d.jobs > 0 and t.jobs + d.jobs > Plot.workLimit(tier) then
		return false
	end
	if d.kind == "breed" and t.hatch + 1 > Plot.hatcheryLimit(tier) then
		return false
	end
	if d.kind == "gen" and (t.boosts[id] or 0) + 1 > Plot.boostLimit() then
		return false
	end
	return true
end

local function work(p: Profile, list: { Entry }): Work
	local plan: Plan = { placed = 0, held = 0, bought = 0, shells = 0, locked = 0, limit = 0, blocked = 0, away = 0, tree = false }
	local warming: { [number]: boolean } = {}
	local eggs: { Types.Egg } = p.eggs or {}
	for _, egg in eggs do
		warming[egg.uid] = true
	end
	-- (what stays: the tree, and a Hatchery warming an egg; the rest is the pool the layout takes from first)
	local keep: { Piece } = {}
	local tree: Piece? = nil
	local pool: { [string]: { Piece } } = {}
	for _, q in p.plot.placed do
		if Plot.isFixed(q.id) then
			tree = q
		elseif warming[q.uid] then
			table.insert(keep, q)
		else
			local l = pool[q.id]
			if l == nil then
				l = {}
				pool[q.id] = l
			end
			table.insert(l, q)
		end
	end
	local t: Tally = { groups = {}, slots = 0, jobs = 0, hatch = 0, boosts = {} }
	for _, q in keep do
		tallyAdd(t, q.id)
	end
	local idx = Plot.index(keep)
	-- the tree first, to its saved spot when that fits
	local treeAt: Entry? = nil
	if tree then
		tallyAdd(t, tree.id)
		local at: Entry = { id = tree.id, x = tree.x, z = tree.z, rot = tree.rot }
		for _, e in list do
			if e.id == tree.id then
				if (e.x ~= tree.x or e.z ~= tree.z or e.rot ~= tree.rot) and Plot.fitsNear(p.tier, idx, tree.id, e.x, e.z, e.rot) then
					at = e
					plan.tree = true
				end
				break
			end
		end
		treeAt = at
		idx.add({ uid = tree.uid, id = tree.id, x = at.x, z = at.z, rot = at.rot, lvl = tree.lvl })
	end
	-- then the rest, the water before what floats on it (Plot.groupRank), each in the order it was saved
	local order: { number } = {}
	for i, e in list do
		local d = Buildings.byId[e.id]
		if d == nil or d.kind ~= "tree" then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a: number, b: number): boolean
		local ra, rb = Plot.groupRank(list[a].id), Plot.groupRank(list[b].id)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	local inv = p.inv or {}
	local used: { [string]: number } = {}
	local priceOf = Plot.pricer(p)
	local lays: { Lay } = {}
	for _, i in order do
		local e = list[i]
		local d = Buildings.byId[e.id]
		if d == nil or d.tier > p.tier then
			plan.locked += 1
		elseif not tallyRoom(t, p.tier, e.id) then
			plan.limit += 1
		elseif not Plot.fitsNear(p.tier, idx, e.id, e.x, e.z, e.rot) then
			plan.blocked += 1
		else
			tallyAdd(t, e.id)
			local lay: Lay = { id = e.id, x = e.x, z = e.z, rot = e.rot, src = nil, from = "buy" }
			local l = pool[e.id]
			if l and #l > 0 then
				lay.src = table.remove(l, 1)
				lay.from = "island"
				plan.held += 1
			elseif (inv[e.id] or 0) - (used[e.id] or 0) > 0 then
				used[e.id] = (used[e.id] or 0) + 1
				lay.from = "inv"
				plan.held += 1
			else
				plan.shells += priceOf(e.id)
				plan.bought += 1
			end
			plan.placed += 1
			idx.add({ uid = 0, id = e.id, x = e.x, z = e.z, rot = e.rot, lvl = 1 })
			table.insert(lays, lay)
		end
	end
	local away: { Piece } = {}
	for _, l in pool do
		for _, q in l do
			table.insert(away, q)
		end
	end
	plan.away = #away
	return { plan = plan, keep = keep, tree = tree, treeAt = treeAt, lays = lays, away = away }
end

local function listOf(p: Profile, slot: any): ({ Entry }?, ErrCode?)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Layout.SLOTS then
		return nil, "bad_payload"
	end
	local s = slotsOf(p)[slot]
	local list = if s.code ~= "" then Layout.unpack(s.code) else nil
	if list == nil or #list == 0 then
		return nil, "not_found"
	end
	return list, nil
end

-- What loading the layout in `slot` would do now, changing nothing. True with the Plan, else bad_payload (no such
-- slot) or not_found (nothing saved there).
function Layout.plan(p: Profile, slot: number): (boolean, any)
	local list, why = listOf(p, slot)
	if list == nil then
		return false, why
	end
	return true, work(p, list).plan
end

-- Load the layout in `slot`, all or nothing: bad_payload, not_found, money (the coins don't cover what it buys). True
-- with the Plan.
function Layout.load(p: Profile, slot: number): (boolean, any)
	local list, why = listOf(p, slot)
	if list == nil then
		return false, why
	end
	local w = work(p, list)
	if p.shells < w.plan.shells then
		return false, "money" :: ErrCode
	end
	-- the pieces the layout doesn't use go into the inventory (their workers rest, their huts empty)
	for _, q in w.away do
		Plot.stow(p, q.id)
		Plot.freeWorkers(p, q.uid)
		Plot.unhouse(p, q.uid)
	end
	local placed: { Piece } = table.clone(w.keep)
	if w.tree and w.treeAt then
		w.tree.x, w.tree.z, w.tree.rot = w.treeAt.x, w.treeAt.z, w.treeAt.rot
		table.insert(placed, w.tree)
	end
	local priceOf = Plot.pricer(p)
	for _, lay in w.lays do
		local src = lay.src
		if src then
			src.x, src.z, src.rot = lay.x, lay.z, lay.rot
			table.insert(placed, src)
		else
			if lay.from == "inv" then
				Plot.takeHeld(p, lay.id)
			else
				p.shells -= priceOf(lay.id)
			end
			local uid = p.nextId
			p.nextId += 1
			table.insert(placed, { uid = uid, id = lay.id, x = lay.x, z = lay.z, rot = lay.rot, lvl = 1 })
			p.stats.built += 1
		end
	end
	p.plot.placed = placed
	return true, w.plan
end

return Layout
