--!strict
-- The island's rules (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 6): what it makes and eats a turn, its charm and visitors,
-- villagers moving in, who works where, expanding the island. Pure: IslandService calls these with the session's
-- profile and its Rng; the Economy spec plays whole sessions through the same functions. Actions return
-- (true, data?) or (false, ErrCode) and change the profile only when they succeed.
--
-- A turn (Tuning.TurnSeconds): each building of kind food, wood or shop makes its rate (Data/Buildings) times
--   (a villager working there ? 1 + their home's comfort : IdleOutput)
--   x (1 + the boost of each driftling of its knack helping there, up to Tuning.HelpMax: PalBoost x its rarity's
--   RarityWork x (1 + its work share + its hut's comfort), its work share its passive's and mutations' (Data/Traits:
--   work and the building's knack))
--   x (the food has run out ? Hungry : 1) x (1 + the boost buildings' share at its knack)
-- a shop also times its visitors (visitors a turn / ShopVisitors, at most 2) and eats its `eats` food likewise;
-- villagers eat EatFolk, driftlings in huts EatPal (times their eat share); the pen's eat nothing and don't work.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Looks = require(script.Parent.Parent.Data.Looks)
local Names = require(script.Parent.Parent.Data.Names)
local Util = require(script.Parent.Util)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Piece = Types.Piece
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Island = {}

export type Rates = { food: number, wood: number, shells: number, made: number, eaten: number }

function Island.piece(p: Profile, uid: number): Piece?
	for _, q in p.plot.placed do
		if q.uid == uid then
			return q
		end
	end
	return nil
end

local function count(p: Profile, field: string): number
	local n = 0
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			n += (d :: any)[field]
		end
	end
	return n
end

function Island.beds(p: Profile): number
	return count(p, "beds")
end

function Island.nests(p: Profile): number
	return count(p, "slots")
end

-- A driftling's effects: its passive and its mutations together (Data/Traits).
function Island.fxOf(pal: Types.Pal): Traits.Fx
	local d = Creatures.byId[pal.sp]
	return Traits.sum(if d then d.passive.fx else nil, pal.muts)
end

-- The charm: every piece's, and each driftling living in a hut (visitors like them: one each, and their charm share).
function Island.charm(p: Profile): number
	local n = count(p, "charm")
	for _, x in p.pals do
		if x.home ~= 0 then
			n += 1 + (Island.fxOf(x).charm or 0)
		end
	end
	return math.max(0, n)
end

function Island.visitors(p: Profile): number
	return math.min(Tuning.VisitorsMax, 1 + Island.charm(p) / Tuning.VisitorCharm)
end

-- Who lives where (GAME_DESIGN 4.1): the homes, best first (their comfort and their level's, then the first built),
-- filled with the villagers in the order they came, a bed each. Each villager's home (its piece's uid) and comfort,
-- keyed "v<id>" (nobody left out while beds last); and each driftling's hut, "p<id>" (Pal.home: the Tree of Life's
-- pen sends them there, or the player does; Logic/Tree), none for the pen's.
export type Home = { uid: number, comfort: number }
function Island.homes(p: Profile): { [string]: Home }
	local out: { [string]: Home } = {}
	local hut: { [number]: number } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "nest" then
			hut[q.uid] = d.comfort + (Tuning.ComfortLvl[q.lvl or 1] or 0)
		end
	end
	for _, x in p.pals do
		local c = hut[x.home]
		if c then
			out["p" .. x.id] = { uid = x.home, comfort = c }
		end
	end
	local function fill(kind: string, who: { any }, prefix: string)
		type Slot = { uid: number, n: number, comfort: number }
		local list: { Slot } = {}
		for _, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			if d and d.kind == kind then
				table.insert(list, { uid = q.uid, n = d.beds, comfort = d.comfort + (Tuning.ComfortLvl[q.lvl or 1] or 0) })
			end
		end
		table.sort(list, function(a: Slot, b: Slot): boolean
			if math.abs(a.comfort - b.comfort) > 1e-9 then
				return a.comfort > b.comfort
			end
			return a.uid < b.uid
		end)
		local i = 1
		local left = if list[1] then list[1].n else 0
		for _, x in who do
			while list[i] and left <= 0 do
				i += 1
				left = if list[i] then list[i].n else 0
			end
			local h = list[i]
			if h == nil then
				break
			end
			out[prefix .. x.id] = { uid = h.uid, comfort = h.comfort }
			left -= 1
		end
	end
	fill("home", p.folk, "v")
	return out
end

-- The boost buildings' shares (GAME_DESIGN 4.1), by knack and "all": each kind of boost building counts once.
function Island.boosts(p: Profile): { [string]: number }
	local out: { [string]: number } = { farm = 0, fish = 0, wood = 0, shop = 0, all = 0 }
	local seen: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "gen" and d.boost ~= "" and not seen[d.id] then
			seen[d.id] = true
			out[d.boost] = (out[d.boost] or 0) + d.boostBy
		end
	end
	return out
end

-- The boost at a building of a knack: its own and every building's, `BoostMax` at most.
function Island.boostAt(b: { [string]: number }, knack: string): number
	return math.min(Tuning.BoostMax, (b[knack] or 0) + (b.all or 0))
end

-- Whether a building takes workers (it makes something).
function Island.works(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and (d.kind == "food" or d.kind == "wood" or d.kind == "shop")
end

-- A driftling's work share where it helps (Data/Traits.workAt: its passive's and mutations' work and the building's
-- knack; at its own knack when it helps nowhere).
function Island.palWork(p: Profile, pal: Types.Pal): number
	local d = Creatures.byId[pal.sp]
	local q = if pal.work ~= 0 then Island.piece(p, pal.work) else nil
	local bd = if q then Buildings.byId[q.id] else nil
	return Traits.workAt(Island.fxOf(pal), if bd then bd.knack else (if d then d.knack else ""))
end

-- What a driftling adds to the building it helps at (its share of the building's output): PalBoost x its rarity's
-- RarityWork x (1 + its work share + its hut's comfort). `comfort`: its hut's (Island.homes), 0 in the pen.
function Island.palBoost(p: Profile, pal: Types.Pal, comfort: number?): number
	local d = Creatures.byId[pal.sp]
	local r = if d then d.rarity else 1
	return Tuning.PalBoost * (Tuning.RarityWork[r] or 1) * math.max(0, 1 + Island.palWork(p, pal) + (comfort or 0))
end

-- What a turn makes and eats now.
function Island.rates(p: Profile): Rates
	local out = { food = 0, wood = 0, shells = 0, made = 0, eaten = 0 }
	local homes = Island.homes(p)
	local boosts = Island.boosts(p)
	-- a worker's output: 1 + its home's comfort
	local worker: { [number]: number } = {}
	for _, v in p.folk do
		if v.work ~= 0 then
			local h = homes["v" .. v.id]
			worker[v.work] = 1 + (if h then h.comfort else 0)
		end
	end
	-- the helping driftlings' boosts (each in a hut: the pen's don't work), added up at each building
	local helper: { [number]: number } = {}
	for _, pal in p.pals do
		local h = homes["p" .. pal.id]
		if pal.work ~= 0 and h then
			helper[pal.work] = (helper[pal.work] or 0) + Island.palBoost(p, pal, h.comfort)
		end
	end
	local hungry = p.food <= 0
	local shop = math.min(2, Island.visitors(p) / Tuning.ShopVisitors)
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 then
			local help = helper[q.uid]
			local k = (worker[q.uid] or Tuning.IdleOutput) * (1 + (help or 0)) * (if hungry then Tuning.Hungry else 1) * (Tuning.UpgradeMult[q.lvl] or 1) * (1 + Island.boostAt(boosts, d.knack))
			if d.kind == "food" then
				out.food += d.rate * k
				out.made += d.rate * k
			elseif d.kind == "wood" then
				out.wood += d.rate * k
			elseif d.kind == "shop" and not hungry then
				out.shells += d.rate * k * shop
				out.food -= d.eats * k * shop
				out.eaten += d.eats * k * shop
			end
		end
	end
	local eat = Tuning.EatFolk * #p.folk
	for _, pal in p.pals do
		if pal.home ~= 0 then
			eat += Tuning.EatPal * math.max(0.1, 1 + (Island.fxOf(pal).eat or 0))
		end
	end
	out.food -= eat
	out.eaten += eat
	return out
end

-- dt seconds of the island's turns: what it made and ate (fractions; the food never goes below none). Returns the
-- shells made (the stats count them).
function Island.step(p: Profile, dt: number): Rates
	local r = Island.rates(p)
	local k = dt / Tuning.TurnSeconds
	p.food = math.max(0, p.food + r.food * k)
	p.wood += r.wood * k
	p.shells += r.shells * k
	p.stats.earned += r.shells * k
	return { food = r.food * k, wood = r.wood * k, shells = r.shells * k, made = r.made * k, eaten = r.eaten * k }
end

------------------------------------------------------------------ villagers
function Island.randomLook(rng: Rng): Types.Look
	return { skin = rng:int(1, #Looks.skin), hair = rng:int(1, #Looks.hair), style = rng:int(1, #Looks.styles), shirt = rng:int(1, #Looks.shirt) }
end

-- A building that takes a worker and has none (food first, then wood, then shops), or 0. `forPal`: a driftling's
-- knack: a building of that knack with fewer than Tuning.HelpMax driftlings helping.
function Island.freeJob(p: Profile, forPal: string?): number
	local taken: { [number]: number } = {}
	if forPal then
		for _, pal in p.pals do
			if pal.work ~= 0 then
				taken[pal.work] = (taken[pal.work] or 0) + 1
			end
		end
	else
		for _, v in p.folk do
			if v.work ~= 0 then
				taken[v.work] = 1
			end
		end
	end
	local most = if forPal then Tuning.HelpMax else 1
	for _, kind in { "food", "wood", "shop" } do
		for _, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			if d and d.kind == kind and (taken[q.uid] or 0) < most and (forPal == nil or d.knack == forPal) then
				return q.uid
			end
		end
	end
	return 0
end

-- A new calendar day on the island (the sea's clock passed a day's end while the player was here): the day count.
function Island.newDay(p: Profile)
	p.day += 1
	p.stats.days += 1
end

-- A castaway moves into a free bed and takes a free job (no checks: the callers make them).
function Island.moveIn(p: Profile, rng: Rng): Types.Villager
	local v: Types.Villager = {
		id = p.nextId,
		name = Util.pick(rng, Names.first),
		look = Island.randomLook(rng),
		work = 0,
		day = p.day,
	}
	p.nextId += 1
	v.work = Island.freeJob(p)
	table.insert(p.folk, v)
	p.stats.movedIn += 1
	return v
end

-- The first home on an island with nobody living there yet: a castaway moves in at once (GAME_DESIGN 9), so the
-- first jobs have someone to take them. Returns them, or nil when the island already has villagers or no free bed.
function Island.welcome(p: Profile, rng: Rng): Types.Villager?
	if #p.folk > 0 or Island.beds(p) < 1 or Tuning.FolkMax < 1 then
		return nil
	end
	return Island.moveIn(p, rng)
end

-- A turn's end: a visitor may move into a free bed (the charm high enough). Returns what happened:
-- { movedIn = Villager? }.
function Island.turn(p: Profile, rng: Rng): { [string]: any }
	local news: { [string]: any } = {}
	if #p.folk < math.min(Tuning.FolkMax, Island.beds(p)) and Island.charm(p) >= Tuning.MoveInCharm * #p.folk then
		news.movedIn = Island.moveIn(p, rng)
	end
	return news
end

------------------------------------------------------------------ jobs
-- A villager to a building (uid) or idle (0): one villager a building, buildings that make something.
function Island.setWork(p: Profile, id: number, uid: number): (boolean, any)
	local who: Types.Villager? = nil
	for _, v in p.folk do
		if v.id == id then
			who = v
		end
	end
	if who == nil then
		return false, "not_found" :: ErrCode
	end
	if uid ~= 0 then
		local q = Island.piece(p, uid)
		if q == nil or not Island.works(q.id) then
			return false, "bad_payload" :: ErrCode
		end
		for _, v in p.folk do
			if v ~= who and v.work == uid then
				v.work = 0 -- they swap: the one there goes idle
			end
		end
	end
	who.work = uid
	return true, nil
end

-- A driftling living in a hut to a building of its knack (uid) or resting (0): Tuning.HelpMax a building (a full one
-- sends the helper that came first back to rest). The pen's driftlings don't work (bad_payload).
function Island.setHelp(p: Profile, id: number, uid: number): (boolean, any)
	local who: Types.Pal? = nil
	for _, pal in p.pals do
		if pal.id == id then
			who = pal
		end
	end
	if who == nil then
		return false, "not_found" :: ErrCode
	end
	if uid ~= 0 then
		local q = Island.piece(p, uid)
		local def = Creatures.byId[who.sp]
		local b = if q then Buildings.byId[q.id] else nil
		if q == nil or b == nil or def == nil or b.knack ~= def.knack or who.home == 0 then
			return false, "bad_payload" :: ErrCode
		end
		local there: { Types.Pal } = {}
		for _, pal in p.pals do
			if pal ~= who and pal.work == uid then
				table.insert(there, pal)
			end
		end
		if #there >= Tuning.HelpMax then
			there[1].work = 0
		end
	end
	who.work = uid
	return true, nil
end

-- A villager leaves the island (their bed frees up).
function Island.dismiss(p: Profile, id: number): (boolean, any)
	for i, v in p.folk do
		if v.id == id then
			table.remove(p.folk, i)
			return true, nil
		end
	end
	return false, "not_found" :: ErrCode
end

------------------------------------------------------------------ the island's size
function Island.expandCost(tier: number): { shells: number, wood: number }?
	return Tuning.TierCost[tier + 1]
end

function Island.expand(p: Profile): (boolean, any)
	local cost = Island.expandCost(p.tier)
	if cost == nil then
		return false, "max" :: ErrCode
	end
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < cost.wood then
		return false, "wood" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	p.tier += 1
	-- pieces that no longer fit the bigger island's shape make room (Plot.refit)
	local moved, cleared = Plot.refit(p)
	return true, { tier = p.tier, moved = moved, cleared = cleared }
end

-- The founder's look (free).
function Island.setFounder(p: Profile, skin: number, hair: number, style: number, shirt: number): (boolean, any)
	if skin > #Looks.skin or hair > #Looks.hair or style > #Looks.styles or shirt > #Looks.shirt then
		return false, "bad_payload" :: ErrCode
	end
	p.founder = { skin = skin, hair = hair, style = style, shirt = shirt }
	return true, nil
end

return Island
