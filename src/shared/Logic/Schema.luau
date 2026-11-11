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
local Office = require(script.Parent.Parent.Data.Office)
local Util = require(script.Parent.Util)
local Island = require(script.Parent.Island)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile

local Schema = {}

-- 1: the first shape; 2: the founder's look and the plot; 3: the idea loop; 4: one game on sale at a time;
-- 5: the island (GAME_DESIGN 1: the game studio is gone)
Schema.VERSION = 7

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

local function str(v: any, default: string, maxLen: number?): string
	if type(v) ~= "string" then
		return default
	end
	return string.sub(v, 1, maxLen or 60)
end

local function look(v: any): Types.Look
	local t = if type(v) == "table" then v else {}
	return {
		skin = int(t.skin, 1, 1, #Looks.skin),
		hair = int(t.hair, 1, 1, #Looks.hair),
		style = int(t.style, 1, 1, #Looks.styles),
		shirt = int(t.shirt, 1, 1, #Looks.shirt),
	}
end

local function level(v: any): { lvl: number, xp: number }
	local t = if type(v) == "table" then v else {}
	return { lvl = int(t.lvl, 1, 1, Tuning.LevelMax), xp = int(t.xp, 0, 0) }
end

------------------------------------------------------------------ default
-- A new island: Tuning.StartShells, StartFood and StartWood (enough for the tips' buildings), nobody else yet.
function Schema.default(now: number, seed: number): Profile
	local rng = Util.newRng(seed)
	return {
		v = Schema.VERSION,
		shells = Tuning.StartShells,
		food = Tuning.StartFood,
		wood = Tuning.StartWood,
		day = 1,
		tier = 1,
		founder = Island.randomLook(rng),
		cap = { lvl = 1, xp = 0 },
		folk = {},
		pals = {},
		plot = { placed = {} },
		islets = 0,
		sea = rng:int(1, 2147483646),
		boat = 1,
		pouch = 1,
		chart = {},
		seen = {},
		eggs = {},
		nextId = 1,
		tut = 1,
		stats = { days = 0, built = 0, earned = 0, befriended = 0, battles = 0, cleared = 0, movedIn = 0, hatched = 0 },
		settings = { pixel = "high", music = "on" },
		createdAt = now,
	}
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
	for _, q in v do
		if type(q) == "table" and type(q.id) == "string" and Buildings.byId[q.id] and #out < Plot.limit(tier) then
			local uid = int(q.uid, 0, 0)
			local x, z, rot = int(q.x, 0, -64, 64), int(q.z, 0, -64, 64), int(q.rot, 0)
			if uid > 0 and not used[uid] and (rot == 0 or rot == 90 or rot == 180 or rot == 270) then
				used[uid] = true
				local lvl = if Island.works(q.id) then int(q.lvl, 1, 1, #Tuning.UpgradeMult) else 1
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
	-- villagers: unique ids, a job only at a building that takes one (one villager a building)
	local folk: { Types.Villager } = {}
	local jobTaken: { [number]: boolean } = {}
	if type(r.folk) == "table" then
		for _, v in r.folk do
			if type(v) == "table" and #folk < Tuning.FolkMax then
				local id = int(v.id, 0, 0)
				if id > 0 and not ids[id] then
					ids[id] = true
					maxId = math.max(maxId, id)
					local lv = level(v)
					local work = int(v.work, 0, 0)
					local q = byUid[work]
					if q == nil or not Island.works(q.id) or jobTaken[work] then
						work = 0
					end
					if work ~= 0 then
						jobTaken[work] = true
					end
					table.insert(folk, { id = id, name = str(v.name, "Castaway", 30), look = look(v.look), work = work, lvl = lv.lvl, xp = lv.xp, seed = int(v.seed, id * 97, 0), day = int(v.day, 1, 1) })
				end
			end
		end
	end
	-- driftlings: a species that exists, help only at a building of its knack (one a building)
	local pals: { Types.Pal } = {}
	local helpTaken: { [number]: boolean } = {}
	if type(r.pals) == "table" then
		for _, x in r.pals do
			if type(x) == "table" and type(x.sp) == "string" and Creatures.byId[x.sp] and #pals < Tuning.PalsMax then
				local id = int(x.id, 0, 0)
				if id > 0 and not ids[id] then
					ids[id] = true
					maxId = math.max(maxId, id)
					local lv = level(x)
					local work = int(x.work, 0, 0)
					local q = byUid[work]
					local b = if q then Buildings.byId[q.id] else nil
					if b == nil or b.knack ~= Creatures.byId[x.sp].knack or helpTaken[work] then
						work = 0
					end
					if work ~= 0 then
						helpTaken[work] = true
					end
					table.insert(pals, { id = id, sp = x.sp, lvl = lv.lvl, xp = lv.xp, work = work, muts = Traits.clean(x.muts) })
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
	for _, x in pals do
		seen[x.sp] = 2
	end
	local st = if type(r.stats) == "table" then r.stats else {}
	local settings = if type(r.settings) == "table" then r.settings else {}
	local pixel = settings.pixel
	-- the chart's islands charted: ids on the chart, each once
	local charted: { number } = {}
	if type(r.chart) == "table" then
		for _, id in r.chart do
			if type(id) == "number" and id == math.floor(id) and id >= 1 and id <= Tuning.ChartIslands and not table.find(charted, id) then
				table.insert(charted, id)
			end
		end
	end
	local out: Profile = {
		v = Schema.VERSION,
		shells = num(r.shells, d.shells, 0, 1e12),
		food = num(r.food, d.food, 0, 1e12),
		wood = num(r.wood, d.wood, 0, 1e12),
		day = int(r.day, 1, 1),
		tier = tier,
		founder = if type(r.founder) == "table" then look(r.founder) else d.founder,
		cap = level(r.cap),
		folk = folk,
		pals = pals,
		plot = { placed = placed },
		islets = int(r.islets, 0, 0, 1e6),
		sea = int(r.sea, d.sea, 1, 2147483646),
		boat = int(r.boat, 1, 1, #Tuning.BoatRadius),
		pouch = int(r.pouch, 1, 1, #Tuning.PouchCost),
		chart = charted,
		seen = seen,
		eggs = {},
		nextId = math.max(int(r.nextId, 1, 1), maxId + 1),
		tut = int(r.tut, 1, 0, 8),
		stats = {
			days = int(st.days, 0, 0),
			built = int(st.built, #placed, 0),
			earned = num(st.earned, 0, 0, 1e15),
			befriended = int(st.befriended, #pals, 0),
			battles = int(st.battles, 0, 0),
			cleared = int(st.cleared, 0, 0),
			movedIn = int(st.movedIn, #folk, 0),
			hatched = int(st.hatched, 0, 0),
		},
		settings = {
			pixel = if pixel == "high" or pixel == "medium" or pixel == "low" or pixel == "off" then pixel else "high",
			music = if settings.music == "off" then "off" else "on",
		},
		createdAt = num(r.createdAt, now),
	}
	-- pieces off the island's buildable grass (an older shape) move to the nearest free spot, or come back as shells
	Plot.refit(out)
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
					table.insert(out.eggs, { uid = uid, a = int(x.a, 0, 0), b = int(x.b, 0, 0), sp = x.sp, muts = Traits.clean(x.muts), left = int(x.left, 0, 0, maxTurns) })
				end
			end
		end
	end
	return out
end

return Schema
