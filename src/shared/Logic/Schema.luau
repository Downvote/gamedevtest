--!strict
-- The save's shape (docs/ARCHITECTURE.md 7.6): default, migrate, reconcile. Pure.
-- Never rename a field or the DataStore (Tuning.DataStoreName): change the shape with a new VERSION and a step in
-- migrate, and keep a profile from before loading (tests/specs/Schema.spec.luau).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Looks = require(script.Parent.Parent.Data.Looks)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Quests = require(script.Parent.Parent.Data.Quests)
local Office = require(script.Parent.Parent.Data.Office)
local Util = require(script.Parent.Util)
local Island = require(script.Parent.Island)
local Plot = require(script.Parent.Plot)
local Tree = require(script.Parent.Tree)
local Weather = require(script.Parent.Weather)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Titles = require(script.Parent.Parent.Data.Titles)
local Track = require(script.Parent.Parent.Data.Track)
local Monetization = require(script.Parent.Parent.Config.Monetization)

type Profile = Types.Profile

local Schema = {}

-- 1: the first shape; 2: the founder's look and the plot; 3: the idea loop; 4: one game on sale at a time;
-- 5: the island (GAME_DESIGN 1: the game studio is gone); 10: the Tree of Life (the fights and expeditions gone);
-- 11: no villagers (the driftlings do all the work); 12: the tide (no Tree of Life, no pen, no food); 13: the Tree of
-- Life again, laying eggs (no tide); 15: shells the one store; 16: the store (passes, receipts, the bag, cosmetics,
-- titles, the rotating shop, the pass track: GAME_DESIGN 14); 17: offline earnings (when the island was last open) and the
-- group gift (GAME_DESIGN 14.3)
Schema.VERSION = 17

-- driftlings a save may hold at most: a bound on garbage, far past every hut's room on the biggest island
local MAX_PALS = 5000

local function num(v: any, default: number, lo: number?, hi: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	if lo and v < lo then
		return lo
	end
	if hi and v > hi then
		return hi
	end
	return v
end

local function int(v: any, default: number, lo: number?, hi: number?): number
	return math.floor(num(v, default, lo, hi))
end

-- `owned`: the cosmetics the player owns (a slot keeps a piece only when it is owned and of that slot).
local function look(v: any, owned: { [string]: boolean }?): Types.Look
	local t = if type(v) == "table" then v else {}
	local out: Types.Look = {
		skin = int(t.skin, 1, 1, #Looks.skin),
		hair = int(t.hair, 1, 1, #Looks.hair),
		style = int(t.style, 1, 1, #Looks.styles),
		shirt = int(t.shirt, 1, 1, #Looks.shirt),
	}
	for _, slot in Looks.worn do
		local id = t[slot]
		local c = if type(id) == "string" then Cosmetics.byId[id] else nil
		if c and c.slot == slot and owned and owned[id] then
			(out :: any)[slot] = id
		end
	end
	return out
end

-- A set of known ids (cosmetics or titles): { id = true } kept for ids `known` has.
local function idSet(v: any, known: { [string]: any }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(v) == "table" then
		for id, on in v do
			if type(id) == "string" and on == true and known[id] ~= nil then
				out[id] = true
			end
		end
	end
	return out
end

-- Whole numbers 1 .. hi, none twice, at most n of them.
local function levels(v: any, hi: number): { number }
	local out: { number } = {}
	if type(v) == "table" then
		for _, x in v do
			if type(x) == "number" and x == math.floor(x) and x >= 1 and x <= hi and table.find(out, x) == nil and #out < hi then
				table.insert(out, x)
			end
		end
	end
	return out
end

------------------------------------------------------------------ default
-- A new island: Tuning.StartWood (enough for the tips' buildings) and StartShells (the first eggs), no driftling yet,
-- its Tree of Life behind the campfire (Logic/Tree.plant) about to lay its first eggs.
function Schema.default(now: number, seed: number): Profile
	local rng = Util.newRng(seed)
	local p: Profile = {
		v = Schema.VERSION,
		shells = Tuning.StartShells,
		day = 1,
		tier = 1,
		founder = Island.randomLook(rng),
		pals = {},
		plot = { placed = {} },
		seen = {},
		eggs = {},
		clutch = { left = 0, list = {}, next = 1 },
		nextId = 1,
		tut = 1,
		quest = 1,
		stats = { days = 0, built = 0, earned = 0, taken = 0, sold = 0, best = 0, hatched = 0 },
		settings = { pixel = "high", music = "on", sfx = "on" },
		createdAt = now,
		inv = {},
		passes = {},
		receipts = {},
		gifts = {},
		vipDay = -1,
		bag = {},
		owned = {},
		titles = { newcomer = true },
		title = "newcomer",
		shop = { at = -1, n = 0 },
		track = { s = -1, xp = 0, got = {}, gotP = {} },
		seenAt = now,
		group = { member = false, gift = false },
	}
	Tree.plant(p)
	return p
end

------------------------------------------------------------------ migrate
-- Brings an older save up to VERSION (each step one version).
--   1 -> 2: a founder's look (reconcile fills it in).
--   2..4 -> 5: the island. The studios (the old one, the idea loop) are gone with their money, ideas, games, upgrades,
--           team, office and decor; the founder's look and the settings stay, and the island starts afresh.
--   5 -> 6: the tips grew from four to six (food, wood, shells, a home, sailing, treats): a save on the old "build a
--           nest and sail" tip (3) goes to it (5), one on the last tip (4) to the new last (6). The sea chart comes in:
--           reconcile gives the save its own sea (from the player's seed), the first boat and no island charted yet
--           (the islands charted before stay counted).
--   6 -> 7: driftlings carry mutations (Data/Traits): each friend from before rolls its own once, from its id and kind
--           (the same save always rolls the same), as a wild one of its rarity would.
--   7 -> 8: the questline (Data/Quests): reconcile starts it at the first quest (any already met can be claimed at
--           once) and the skills used at none.
--   8 -> 9: the sea chart and the boat are gone (GAME_DESIGN 7: the wild places on the island instead): the boat's
--           level and the islands charted go; the count of islands charted stays as places cleared (its charm kept);
--           reconcile brings up the wild places of every tier the island has reached (Logic/Sites).
--   9 -> 10: the Tree of Life (GAME_DESIGN 6: "scrap the entire cave, fighting, level, skill and expedition system"):
--           the wild places, the captain, the snack pouch and every level go; a Training Yard comes down with its
--           whole price back; each driftling moves into a hut the way the nests were filled before (the comfiest
--           first, in the order they came), the rest into the pen; the tips on the old sailing steps go to the hut's
--           step; the questline starts again (its quests changed: any already met can be claimed at once).
--   10 -> 11: no villagers (GAME_DESIGN 1: "remove villagers, only creatures should be enough"): the villagers go,
--           every home comes down with its whole price back, the tips after the old tent step move one back (the
--           tent's step is gone: 4 and 5 to 4, 6 to 5, 7 to 6).
--   11 -> 12: the tide (GAME_DESIGN 6: "you can remove the tree of life, there should now be a steady stream of
--           driftlings, with rarities that players can pick up") and two stores ("remove food as a resource"): the
--           Tree of Life, its levels and its pen go; every driftling waiting in the pen is sold for its price (Logic/Tree
--           .price: shells, counted as sold and earned); the food goes; the driftlings the tree grew count as taken in.
--           The tips' steps keep their numbers (each moves on at once when what it asks is done: IslandService).
--   12 -> 13: the Tree of Life again (GAME_DESIGN 6: "bring back the tree of life and remove the converyer belt
--           system. it now spawns eggs around it"): reconcile plants it (making room as Tree.plant does) and gives it
--           its eggs, laid the moment the player arrives. The driftlings taken in off the tide count as hatched.
--   13 -> 14: the build catalog (GAME_DESIGN 4: "make much, much more building options, like paths and fences"):
--           fences are drawn along the grid lines now, so the old one-piece Picket Fence and Hedge come up with their
--           whole price back. Paths, water and fences each count to their own limit; islands reach further north.
--   14 -> 15: one store (GAME_DESIGN 3: "make shells the main currency, allowing you to buy decor and expansions with
--           it. remove wood as a currency"): the wood the save holds is added to its shells, one for one (after the
--           older steps, which may have paid some back in wood), and the wood goes.
function Schema.migrate(raw: { [string]: any }): { [string]: any }
	local v = if type(raw.v) == "number" then raw.v else 1
	if v < 2 then
		raw.founder = nil
		v = 2
	end
	if v < 5 then
		local keep: { [string]: any } = { founder = raw.founder, settings = raw.settings, createdAt = raw.createdAt }
		table.clear(raw)
		for k, x in keep do
			raw[k] = x
		end
		raw.tut = 1
		v = 5
	end
	if v < 6 then
		if raw.tut == 3 then
			raw.tut = 5
		elseif raw.tut == 4 then
			raw.tut = 6
		end
		v = 6
	end
	if v < 7 then
		if type(raw.pals) == "table" then
			for _, x in raw.pals do
				if type(x) == "table" and type(x.sp) == "string" and x.muts == nil then
					local cd = Creatures.byId[x.sp]
					local rng = Util.newRng(Util.hash32(x.sp .. ":" .. tostring(x.id)))
					x.muts = Traits.roll(rng, if cd then cd.rarity else 1)
				end
			end
		end
		v = 7
	end
	if v < 8 then
		v = 8 -- (reconcile gives the questline and the skills count their starts)
	end
	if v < 9 then
		raw.boat = nil
		raw.chart = nil
		raw.wilds = 0
		v = 9
	end
	if v < 10 then
		for _, k in { "cap", "islets", "sea", "wilds", "pouch" } do
			raw[k] = nil
		end
		-- the yard's price back, the places gone (Data/Buildings has neither now)
		local placed = if type(raw.plot) == "table" and type(raw.plot.placed) == "table" then raw.plot.placed else {}
		local keep: { any } = {}
		local nests: { { uid: number, n: number, comfort: number } } = {}
		for _, q in placed do
			if type(q) == "table" and q.id == "yard" then
				raw.shells = (if type(raw.shells) == "number" then raw.shells else 0) + 450
				raw.wood = (if type(raw.wood) == "number" then raw.wood else 0) + 50
			else
				table.insert(keep, q)
				local d = if type(q) == "table" and type(q.id) == "string" then Buildings.byId[q.id] else nil
				if d and d.kind == "nest" and type(q.uid) == "number" then
					local lvl = if type(q.lvl) == "number" then q.lvl else 1
					table.insert(nests, { uid = q.uid, n = d.slots, comfort = d.comfort + (Tuning.ComfortLvl[lvl] or 0) })
				end
			end
		end
		if type(raw.plot) == "table" then
			raw.plot.placed = keep
		end
		-- the driftlings into the huts as the nests were filled (the comfiest first, then the first built)
		table.sort(nests, function(a, b)
			if math.abs(a.comfort - b.comfort) > 1e-9 then
				return a.comfort > b.comfort
			end
			return a.uid < b.uid
		end)
		local best = 0
		if type(raw.pals) == "table" then
			local i, left = 1, if nests[1] then nests[1].n else 0
			for _, x in raw.pals do
				if type(x) == "table" then
					while nests[i] and left <= 0 do
						i += 1
						left = if nests[i] then nests[i].n else 0
					end
					x.home = if nests[i] then nests[i].uid else 0
					if x.home == 0 then
						x.work = 0
					end
					left -= 1
					local cd = if type(x.sp) == "string" then Creatures.byId[x.sp] else nil
					if cd then
						best = math.max(best, cd.rarity)
					end
				end
			end
		end
		if type(raw.tut) == "number" and raw.tut >= 5 then
			raw.tut = 5
		end
		raw.quest = 1
		local st = if type(raw.stats) == "table" then raw.stats else {}
		raw.stats = st
		st.grown = if type(st.befriended) == "number" then st.befriended else 0
		st.sold = 0
		st.best = best
		v = 10
	end
	if v < 11 then
		raw.folk = nil
		local HOMES: { [string]: { number } } = {
			tent = { 30, 0 },
			hut = { 140, 20 },
			cottage = { 700, 80 },
			longhouse = { 2400, 260 },
			townhouse = { 7000, 700 },
			villa = { 20000, 2000 },
			manor = { 60000, 5000 },
		}
		local placed = if type(raw.plot) == "table" and type(raw.plot.placed) == "table" then raw.plot.placed else {}
		local keep: { any } = {}
		for _, q in placed do
			local price = if type(q) == "table" and type(q.id) == "string" then HOMES[q.id] else nil
			if price then
				raw.shells = (if type(raw.shells) == "number" then raw.shells else 0) + price[1]
				raw.wood = (if type(raw.wood) == "number" then raw.wood else 0) + price[2]
			else
				table.insert(keep, q)
			end
		end
		if type(raw.plot) == "table" then
			raw.plot.placed = keep
		end
		if type(raw.tut) == "number" and raw.tut >= 5 then
			raw.tut -= 1
		end
		if type(raw.stats) == "table" then
			raw.stats.movedIn = nil
		end
		v = 11
	end
	if v < 12 then
		raw.tree = nil
		raw.food = nil
		local placed = if type(raw.plot) == "table" and type(raw.plot.placed) == "table" then raw.plot.placed else nil
		if placed then
			local keep: { any } = {}
			for _, q in placed do
				if not (type(q) == "table" and q.id == "tree") then
					table.insert(keep, q)
				end
			end
			raw.plot.placed = keep
		end
		local st = if type(raw.stats) == "table" then raw.stats else {}
		raw.stats = st
		local got, n = 0, 0
		if type(raw.pals) == "table" then
			local keep: { any } = {}
			for _, x in raw.pals do
				local home = if type(x) == "table" then tonumber(x.home) else nil
				if type(x) == "table" and (home == nil or home == 0) and type(x.sp) == "string" and Creatures.byId[x.sp] then
					got += Tree.price({ id = 0, sp = x.sp, home = 0, work = 0, muts = Traits.clean(x.muts) })
					n += 1
				else
					if type(x) == "table" then
						x.held = nil
					end
					table.insert(keep, x)
				end
			end
			raw.pals = keep
		end
		if n > 0 then
			raw.shells = (if type(raw.shells) == "number" then raw.shells else 0) + got
			st.sold = (if type(st.sold) == "number" then st.sold else 0) + n
			st.earned = (if type(st.earned) == "number" then st.earned else 0) + got
		end
		if type(st.grown) == "number" then
			st.taken = st.grown
		end
		st.grown = nil
		v = 12
	end
	if v < 13 then
		raw.clutch = nil
		v = 13
	end
	if v < 14 then
		-- the old one-piece fence and hedge are drawn now (Fences: Picket Fence, Hedgerow): each one standing comes
		-- up with its whole price back
		local back = { fence = 25, hedge = 120 }
		if type(raw.plot) == "table" and type(raw.plot.placed) == "table" then
			local keep: { any } = {}
			local got = 0
			for _, q in raw.plot.placed do
				local w = if type(q) == "table" then back[q.id] else nil
				if w then
					got += w
				else
					table.insert(keep, q)
				end
			end
			raw.plot.placed = keep
			if got > 0 then
				raw.wood = (if type(raw.wood) == "number" then raw.wood else 0) + got
			end
		end
		v = 14
	end
	if v < 15 then
		local w = raw.wood
		if type(w) == "number" and w == w and w > 0 then
			local sh = raw.shells
			raw.shells = math.min(1e12, (if type(sh) == "number" and sh == sh and sh > 0 then sh else 0) + math.min(w, 1e12))
		end
		raw.wood = nil
		v = 15
	end
	-- 15 -> 16: the store's fields (reconcile fills them in); every founder has the Newcomer title, worn
	if v < 16 then
		raw.titles = { newcomer = true }
		raw.title = "newcomer"
		v = 16
	end
	-- 16 -> 17: offline earnings and the group gift (reconcile fills them in: an older save earns nothing for the time
	-- before it was opened again)
	raw.v = math.max(v, Schema.VERSION)
	return raw
end

------------------------------------------------------------------ reconcile
-- The pieces that exist, up to the island's limit, each with its own uid (where they stand is checked once the profile
-- is whole: Plot.refit moves the ones that do not fit the island's coast, the shape of an older save's island).
local function piecesOf(v: any, tier: number): { Types.Piece }
	local out: { Types.Piece } = {}
	local used: { [number]: boolean } = {}
	if type(v) ~= "table" then
		return out
	end
	-- (each count to its limit: the pieces, the tiles (paths and water), the fences, one tree)
	local counts: { [string]: number } = { piece = 0, tile = 0, fence = 0, fixed = 0 }
	for _, q in v do
		local def = if type(q) == "table" and type(q.id) == "string" then Buildings.byId[q.id] else nil
		local group = if def then Plot.group(def.id) else ""
		if def and counts[group] < Plot.groupLimit(group, tier) then
			local uid = int(q.uid, 0, 0)
			local x, z, rot = int(q.x, 0, -240, 64), int(q.z, 0, -240, 64), int(q.rot, 0)
			-- (a fence runs east or south from an even corner)
			local shape = if group == "fence" then (rot == 0 or rot == 90) and x % 2 == 0 and z % 2 == 0 else (rot == 0 or rot == 90 or rot == 180 or rot == 270)
			-- (an old path tile moved off the even studs: refit clears it with its price back)
			if uid > 0 and not used[uid] and shape then
				used[uid] = true
				counts[group] += 1
				-- a level: the makers' and huts' (from before upgrades were taken out: kept)
				local leveled = Island.works(q.id) or def.kind == "nest"
				local lvl = if leveled then int(q.lvl, 1, 1, #Tuning.UpgradeMult) else 1
				table.insert(out, { uid = uid, id = q.id, x = x, z = z, rot = rot, lvl = lvl })
			end
		end
	end
	return out
end

-- Any table (a save, an older save, garbage) -> a valid Profile: known fields kept when their type and range are
-- right, everything else from the default.
function Schema.reconcile(raw: any, now: number, seed: number): Profile
	local d = Schema.default(now, seed)
	if type(raw) ~= "table" then
		return d
	end
	local r = Schema.migrate(raw)
	local tier = int(r.tier, 1, 1, #Office.plans)
	local placed = piecesOf(if type(r.plot) == "table" then r.plot.placed else nil, tier)
	local byUid: { [number]: Types.Piece } = {}
	local maxId = 0
	for _, q in placed do
		byUid[q.uid] = q
		maxId = math.max(maxId, q.uid)
	end
	local ids: { [number]: boolean } = {}
	for _, q in placed do
		ids[q.uid] = true
	end
	-- driftlings: a species that exists, a hut that stands (else none) with room for it, help only from a hut at a
	-- workplace, any knack (Tuning.HelpMax a building)
	local pals: { Types.Pal } = {}
	local helpers: { [number]: number } = {}
	local inHut: { [number]: number } = {}
	if type(r.pals) == "table" then
		for _, x in r.pals do
			if type(x) == "table" and type(x.sp) == "string" and Creatures.byId[x.sp] and #pals < MAX_PALS then
				local id = int(x.id, 0, 0)
				if id > 0 and not ids[id] then
					ids[id] = true
					maxId = math.max(maxId, id)
					local home = int(x.home, 0, 0)
					local hq = byUid[home]
					local hd = if hq then Buildings.byId[hq.id] else nil
					if hd == nil or hd.kind ~= "nest" or (inHut[home] or 0) >= hd.slots then
						home = 0
					end
					if home ~= 0 then
						inHut[home] = (inHut[home] or 0) + 1
					end
					local work = int(x.work, 0, 0)
					local q = byUid[work]
					local b = if q then Buildings.byId[q.id] else nil
					if home == 0 or b == nil or (b.kind ~= "farm" and b.kind ~= "wood" and b.kind ~= "shop") or (helpers[work] or 0) >= Tuning.HelpMax then
						work = 0
					end
					if work ~= 0 then
						helpers[work] = (helpers[work] or 0) + 1
					end
					-- (`pin`: placed by the player's hand, kept only while it lives in a hut)
					table.insert(pals, { id = id, sp = x.sp, home = home, work = work, muts = Traits.clean(x.muts), pin = if x.pin == true and home ~= 0 then true else nil })
				end
			end
		end
	end
	local seen: { [string]: number } = {}
	if type(r.seen) == "table" then
		for k, n in r.seen do
			if type(k) == "string" and Creatures.byId[k] then
				local c = int(n, 0, 0, 2)
				if c > 0 then
					seen[k] = c
				end
			end
		end
	end
	local best = 0
	for _, x in pals do
		seen[x.sp] = 2
		best = math.max(best, Creatures.byId[x.sp].rarity)
	end
	local st = if type(r.stats) == "table" then r.stats else {}
	local settings = if type(r.settings) == "table" then r.settings else {}
	local pixel = settings.pixel
	local out: Profile = {
		v = Schema.VERSION,
		shells = num(r.shells, d.shells, 0, 1e12),
		day = int(r.day, 1, 1),
		tier = tier,
		founder = d.founder, -- (below, once the cosmetics owned are known)
		pals = pals,
		plot = { placed = placed },
		inv = Plot.cleanInv(r.inv),
		seen = seen,
		eggs = {},
		clutch = { left = 0, list = {}, next = 1 },
		nextId = math.max(int(r.nextId, 1, 1), maxId + 1),
		tut = int(r.tut, 1, 0, 6),
		quest = int(r.quest, 1, 1, #Quests.list + 1),
		stats = {
			days = int(st.days, 0, 0),
			built = int(st.built, #placed, 0),
			earned = num(st.earned, 0, 0, 1e15),
			taken = int(st.taken, 0, 0),
			sold = int(st.sold, 0, 0),
			best = math.max(best, int(st.best, 0, 0, Traits.RMAX)),
			hatched = int(st.hatched, 0, 0),
		},
		settings = {
			pixel = if pixel == "high" or pixel == "medium" or pixel == "low" or pixel == "off" then pixel else "high",
			music = if settings.music == "off" then "off" else "on",
			sfx = if settings.sfx == "off" then "off" else "on",
		},
		createdAt = num(r.createdAt, now),
		passes = {},
		receipts = {},
		gifts = {},
		vipDay = int(r.vipDay, -1, -1),
		bag = {},
		owned = idSet(r.owned, Cosmetics.byId),
		titles = idSet(r.titles, Titles.byId),
		title = "",
		shop = { at = -1, n = 0 },
		track = { s = -1, xp = 0, got = {}, gotP = {} },
		seenAt = num(r.seenAt, 0, 0, 1e11),
		group = {
			member = type(r.group) == "table" and r.group.member == true,
			gift = type(r.group) == "table" and r.group.gift == true,
		},
	}
	-- the store (GAME_DESIGN 14): passes by their keys (MonetizationService checks them again at the join), the last
	-- receipts, the one-time gifts, the bag's eggs, the look with only owned pieces worn, a title earned, the shop's
	-- refreshes, the track's season
	if type(r.passes) == "table" then
		for k, on in r.passes do
			if type(k) == "string" and on == true and Monetization.GamePasses[k] ~= nil then
				out.passes[k] = true
			end
		end
	end
	if type(r.receipts) == "table" then
		for _, id in r.receipts do
			if type(id) == "string" and #id <= 64 and #out.receipts < 50 then
				table.insert(out.receipts, id)
			end
		end
	end
	if type(r.gifts) == "table" then
		for _, k in { "starter", "vip" } do
			if r.gifts[k] == true then
				out.gifts[k] = true
			end
		end
	end
	out.founder = if type(r.founder) == "table" then look(r.founder, out.owned) else d.founder
	out.titles.newcomer = true
	out.title = if type(r.title) == "string" and (r.title == "" or out.titles[r.title]) then r.title else "newcomer"
	if type(r.shop) == "table" then
		out.shop = { at = int(r.shop.at, -1, -1), n = int(r.shop.n, 0, 0, 1000) }
	end
	if type(r.track) == "table" then
		local t = r.track
		out.track = { s = int(t.s, -1, -1), xp = num(t.xp, 0, 0, 1e9), got = levels(t.got, Track.LEVELS), gotP = levels(t.gotP, Track.LEVELS) }
	end
	-- pieces off the island's buildable grass (an older shape) move to the nearest free spot, or come back as shells
	Plot.refit(out)
	-- its Tree of Life (one from before the eggs gets one)
	Tree.plant(out)
	-- the tree's eggs: each a rarity, ids unique, no more than it lays; the time to the next lot in range
	local c = if type(r.clutch) == "table" then r.clutch else {}
	local cl = out.clutch
	cl.left = num(c.left, 0, 0, Tuning.EggSecs)
	local eggIds: { [number]: boolean } = {}
	local top = 0
	if type(c.list) == "table" then
		for _, e in c.list do
			if type(e) == "table" and #cl.list < Tree.count(tier) then
				local id = int(e.id, 0, 0)
				if id > 0 and not eggIds[id] then
					eggIds[id] = true
					top = math.max(top, id)
					-- (the season it was laid in and the weather that touched it, when known: GAME_DESIGN 13; an
					-- older egg has neither)
					local egg: Types.Laid = { id = id, r = int(e.r, 1, 1, Traits.RMAX) }
					if Weather.knownSeason(e.ss) then
						egg.ss = e.ss
					end
					if Weather.mutation(if Weather.known(e.wx) then e.wx else nil, 1) ~= nil then
						egg.wx = e.wx
						egg.wt = int(e.wt, 1, 1, 4)
					end
					table.insert(cl.list, egg)
				end
			end
		end
	end
	cl.next = math.max(int(c.next, 1, 1), top + 1)
	-- the driftlings with no hut into any hut with room
	Tree.settle(out)
	-- the bag's eggs (GAME_DESIGN 14): each a rarity, its id unique among the save's ids, no more than the bag holds
	if type(r.bag) == "table" then
		for _, e in r.bag do
			if type(e) == "table" and #out.bag < Tree.BAG_MAX then
				local id = int(e.id, 0, 0)
				if id > 0 and not ids[id] then
					ids[id] = true
					table.insert(out.bag, { id = id, r = int(e.r, 1, 1, Traits.RMAX) })
					out.nextId = math.max(out.nextId, id + 1)
				end
			end
		end
	end
	-- the eggs: one a Hatchery still standing, a kind that exists, its mutations clean, its turns in range
	local hatcheries: { [number]: boolean } = {}
	for _, q in out.plot.placed do
		local b = Buildings.byId[q.id]
		if b and b.kind == "breed" then
			hatcheries[q.uid] = true
		end
	end
	if type(r.eggs) == "table" then
		local maxTurns = 0
		for _, t in Tuning.BreedTurns do
			maxTurns = math.max(maxTurns, t)
		end
		for _, x in r.eggs do
			if type(x) == "table" and type(x.sp) == "string" and Creatures.byId[x.sp] then
				local uid = int(x.uid, 0, 0)
				if hatcheries[uid] then
					hatcheries[uid] = nil
					-- (no more turns than its kind's rarity takes)
					local turns = Tuning.BreedTurns[Creatures.byId[x.sp].rarity] or maxTurns
					table.insert(out.eggs, { uid = uid, a = int(x.a, 0, 0), b = int(x.b, 0, 0), sp = x.sp, muts = Traits.clean(x.muts), left = int(x.left, 0, 0, turns) })
				end
			end
		end
	end
	return out
end

return Schema
