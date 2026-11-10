--!strict
-- The island's rules (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 6): what it makes and eats a turn, its charm and visitors,
-- villagers moving in, who works where, expanding the island. Pure: IslandService calls these with the session's
-- profile and its Rng; the Economy spec plays whole sessions through the same functions. Actions return
-- (true, data?) or (false, ErrCode) and change the profile only when they succeed.
--
-- A turn (Tuning.TurnSeconds): each building of kind food, wood or shop makes its rate (Data/Buildings) times
--   (a villager working there ? 1 : IdleOutput) x (a driftling of its knack helping ? 1 + PalBoost : 1)
--   x (the food has run out ? Hungry : 1)
-- a shop also times its visitors (visitors a turn / ShopVisitors, at most 2) and eats its `eats` food likewise;
-- villagers eat EatFolk, driftlings EatPal. Villagers and driftlings away on an expedition neither work nor eat.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
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

-- The charm: every piece's, a little for each driftling (visitors like them) and for each islet opened.
function Island.charm(p: Profile): number
	return count(p, "charm") + #p.pals + math.min(Tuning.ChartCharm * p.islets, Tuning.ChartCharmMax)
end

function Island.visitors(p: Profile): number
	return math.min(Tuning.VisitorsMax, 1 + Island.charm(p) / Tuning.VisitorCharm)
end

-- Whether a building takes workers (it makes something).
function Island.works(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and (d.kind == "food" or d.kind == "wood" or d.kind == "shop")
end

-- What a day makes and eats now (`away`: the keys "v<id>" / "p<id>" of those on an expedition).
function Island.rates(p: Profile, away: { [string]: boolean }?): Rates
	local out = { food = 0, wood = 0, shells = 0, made = 0, eaten = 0 }
	local gone = away or {}
	local worker: { [number]: boolean } = {}
	for _, v in p.folk do
		if v.work ~= 0 and not gone["v" .. v.id] then
			worker[v.work] = true
		end
	end
	local helper: { [number]: boolean } = {}
	for _, pal in p.pals do
		if pal.work ~= 0 and not gone["p" .. pal.id] then
			helper[pal.work] = true
		end
	end
	local hungry = p.food <= 0
	local shop = math.min(2, Island.visitors(p) / Tuning.ShopVisitors)
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 then
			local k = (if worker[q.uid] then 1 else Tuning.IdleOutput) * (if helper[q.uid] then 1 + Tuning.PalBoost else 1) * (if hungry then Tuning.Hungry else 1) * (Tuning.UpgradeMult[q.lvl] or 1)
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
	local eat = 0
	for _, v in p.folk do
		if not gone["v" .. v.id] then
			eat += Tuning.EatFolk
		end
	end
	for _, pal in p.pals do
		if not gone["p" .. pal.id] then
			eat += Tuning.EatPal
		end
	end
	out.food -= eat
	out.eaten += eat
	return out
end

-- dt seconds of the island's turns: what it made and ate (fractions; the food never goes below none). Returns the
-- shells made (the stats count them).
function Island.step(p: Profile, dt: number, away: { [string]: boolean }?): Rates
	local r = Island.rates(p, away)
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

-- A building that takes a worker and has none (food first, then wood, then shops), or 0.
function Island.freeJob(p: Profile, forPal: string?): number
	local taken: { [number]: boolean } = {}
	if forPal then
		for _, pal in p.pals do
			if pal.work ~= 0 then
				taken[pal.work] = true
			end
		end
	else
		for _, v in p.folk do
			if v.work ~= 0 then
				taken[v.work] = true
			end
		end
	end
	for _, kind in { "food", "wood", "shop" } do
		for _, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			if d and d.kind == kind and not taken[q.uid] and (forPal == nil or d.knack == forPal) then
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
		lvl = 1,
		xp = 0,
		seed = rng:int(1, 999999),
		day = p.day,
	}
	p.nextId += 1
	v.work = Island.freeJob(p)
	table.insert(p.folk, v)
	p.stats.movedIn += 1
	return v
end

-- The first home on an island with nobody living there yet: a castaway moves in at once (GAME_DESIGN 9: "a party
-- member that instantly moves in after a tent is built"), so the first expedition has someone to take along. Returns
-- them, or nil when the island already has villagers or no free bed.
function Island.welcome(p: Profile, rng: Rng): Types.Villager?
	if #p.folk > 0 or Island.beds(p) < 1 or Tuning.FolkMax < 1 then
		return nil
	end
	return Island.moveIn(p, rng)
end

-- A turn's end: a visitor may move into a free bed (the charm high enough), the training yard trains the resting.
-- Returns what happened: { movedIn = Villager?, trained = n }.
function Island.turn(p: Profile, rng: Rng, away: { [string]: boolean }?): { [string]: any }
	local news: { [string]: any } = {}
	local gone = away or {}
	if #p.folk < math.min(Tuning.FolkMax, Island.beds(p)) and Island.charm(p) >= Tuning.MoveInCharm * #p.folk then
		news.movedIn = Island.moveIn(p, rng)
	end
	local yards = 0
	for _, q in p.plot.placed do
		if q.id == "yard" then
			yards += 1
		end
	end
	if yards > 0 then
		local n = 0
		local xp = Tuning.TrainXp * yards
		for _, v in p.folk do
			if v.work == 0 and not gone["v" .. v.id] then
				Island.gain(v, xp)
				n += 1
			end
		end
		for _, pal in p.pals do
			if pal.work == 0 and not gone["p" .. pal.id] then
				Island.gain(pal, xp)
				n += 1
			end
		end
		news.trained = n
	end
	return news
end

------------------------------------------------------------------ levels
function Island.xpTo(lvl: number): number
	return math.floor(Tuning.XpBase * lvl ^ Tuning.XpPow + 0.5)
end

-- Experience for a villager, a driftling or the captain ({ lvl, xp }): the levels it went up.
function Island.gain(who: { lvl: number, xp: number }, xp: number): number
	if xp <= 0 then
		return 0
	end
	who.xp += xp
	local ups = 0
	while who.lvl < Tuning.LevelMax and who.xp >= Island.xpTo(who.lvl) do
		who.xp -= Island.xpTo(who.lvl)
		who.lvl += 1
		ups += 1
	end
	if who.lvl >= Tuning.LevelMax then
		who.xp = 0
	end
	return ups
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

-- A driftling to a building of its knack (uid) or resting (0): one driftling a building.
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
		if q == nil or b == nil or def == nil or b.knack ~= def.knack then
			return false, "bad_payload" :: ErrCode
		end
		for _, pal in p.pals do
			if pal ~= who and pal.work == uid then
				pal.work = 0
			end
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

-- A driftling goes back to the wild.
function Island.release(p: Profile, id: number): (boolean, any)
	for i, pal in p.pals do
		if pal.id == id then
			table.remove(p.pals, i)
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
	-- the bigger lodge may stand where buildings were: they make room (Plot.refit)
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
