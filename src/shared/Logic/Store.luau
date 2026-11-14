--!strict
-- The store's rules (GAME_DESIGN 14; docs/ARCHITECTURE.md 6.8). Pure: MonetizationService and IslandService call these
-- with the session's profile and the sea's clock. Actions return (true, data?) or (false, ErrCode) and change the
-- profile only when they succeed. The request (2026-11-14): "make titles. make much more cosmetics, and a rotating
-- shop for cosmetics. make gamepasses for double income, developer products for hatching any rarity of egg, refreshing
-- shop, a starter pack, speeding up hatcheries, a gamepass track with eggs, money and cosmetics along with a premium
-- track, a vip gamepass offering alot of rewards, and cosmetics, a title and a percentage increase to income, a
-- gamepass that speeds up the tree of life refresh to 5 minutes, and a gamepass that allows for decor and paths to be
-- free".
--   Passes (Profile.passes; Config/Monetization.GamePasses): DoubleIncome and VIP multiply the island's shells
--   (Island.passMult), QuickTree lays the tree's eggs every 5 minutes (Tree.secs), FreeDecor makes decor, paths, water
--   and fences free (Plot.price), PremiumTrack opens the pass track's premium side. VIP's welcome gift comes the first
--   time it is owned (`setPass`), its daily gift once every UTC day (`vipDaily`).
--   Products (`product`): an egg of a rarity into the bag, a new set in the rotating shop, the starter pack (once), every
--   Hatchery egg hatched now.
--   The rotating shop (`shopNow`, `buy`): Tuning.ShopSize "shop" pieces of Data/Cosmetics every Tuning.ShopSecs, the same
--   for everyone on the sea's clock unless the player bought a refresh in this rotation; bought with shells.
--   Cosmetics are worn one a slot (`wear`); titles (Data/Titles) are earned by play (`earn`) and one is worn (`setTitle`).
--   The pass track (Data/Track): points from play (`addXp`), a season every Tuning.TrackSecs (`sync` starts a new one),
--   each level's rewards claimed by hand (`claim`).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Titles = require(script.Parent.Parent.Data.Titles)
local Track = require(script.Parent.Parent.Data.Track)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Util = require(script.Parent.Util)
local Island = require(script.Parent.Island)
local Tree = require(script.Parent.Tree)
local Breed = require(script.Parent.Breed)

type Profile = Types.Profile
type ErrCode = Types.ErrCode

local Store = {}

Store.PASSES = { "VIP", "DoubleIncome", "QuickTree", "FreeDecor", "PremiumTrack" }
Store.PRODUCTS = { "EggUncommon", "EggRare", "EggEpic", "EggLegendary", "EggMythic", "EggCelestial", "RefreshShop", "StarterPack", "HatcheryNow" }
-- the egg products' rarities
Store.EGG_R = { EggUncommon = 2, EggRare = 3, EggEpic = 4, EggLegendary = 5, EggMythic = 6, EggCelestial = 7 } :: { [string]: number }
Store.RECEIPTS = 50 -- purchase ids kept (a receipt Roblox sends again is known and not paid twice)

------------------------------------------------------------------ passes
function Store.owns(p: Profile, key: string): boolean
	return p.passes ~= nil and p.passes[key] == true
end

-- A minute of shells: what the island makes in a minute now, at least Tuning.RewardFloor times EggTier by its tier.
function Store.perMinute(p: Profile): number
	local r = Island.rates(p).shells * 60 / Tuning.TurnSeconds
	local floor = Tuning.RewardFloor * Tuning.EggTier[math.clamp(p.tier, 1, #Tuning.EggTier)]
	return math.max(r, floor)
end

-- `mins` minutes of shells (Store.perMinute), whole.
function Store.minutes(p: Profile, mins: number): number
	return math.floor(Store.perMinute(p) * mins)
end

------------------------------------------------------------------ rewards
export type Given = { kind: string, n: number?, r: number?, id: string? }

local function addShells(p: Profile, n: number): Given
	p.shells = math.min(1e15, p.shells + n)
	return { kind = "shells", n = n }
end

local function addEgg(p: Profile, r: number): Given
	local e = Tree.bagAdd(p, r)
	if e == nil then
		-- (a full bag: the egg's worth in shells)
		return addShells(p, Store.minutes(p, 10 * r))
	end
	return { kind = "egg", r = e.r, id = tostring(e.id) }
end

local function addLook(p: Profile, id: string): Given
	if Cosmetics.byId[id] == nil then
		return { kind = "none" }
	end
	if p.owned[id] then
		-- (one already owned: shells in its place)
		local g = addShells(p, Store.minutes(p, 10))
		g.id = id
		return g
	end
	p.owned[id] = true
	return { kind = "look", id = id }
end

local function addTitle(p: Profile, id: string): Given
	if Titles.byId[id] == nil then
		return { kind = "none" }
	end
	p.titles[id] = true
	return { kind = "title", id = id }
end

-- Give one reward (Data/Track's shape). Returns what was given.
function Store.give(p: Profile, reward: Track.Reward): Given
	if reward.kind == "shells" then
		return addShells(p, Store.minutes(p, reward.mins or 1))
	elseif reward.kind == "egg" then
		return addEgg(p, reward.r or 1)
	elseif reward.kind == "look" then
		return addLook(p, reward.id or "")
	elseif reward.kind == "title" then
		return addTitle(p, reward.id or "")
	end
	return { kind = "none" }
end

-- A pass found owned (at a join) or bought: Profile.passes[key]. VIP's welcome gift the first time ever. Returns
-- whether it changed and what the gift gave (nil: none).
function Store.setPass(p: Profile, key: string, owned: boolean): (boolean, { Given }?)
	if table.find(Store.PASSES, key) == nil then
		return false, nil
	end
	local was = Store.owns(p, key)
	if owned then
		p.passes[key] = true
	else
		(p.passes :: any)[key] = nil
	end
	local gift: { Given }? = nil
	if owned and key == "VIP" and not p.gifts.vip then
		p.gifts.vip = true
		local g: { Given } = { addShells(p, Store.minutes(p, Tuning.VipMins)) }
		for _, r in Tuning.VipEggs do
			table.insert(g, addEgg(p, r))
		end
		for _, id in Cosmetics.from("vip") do
			table.insert(g, addLook(p, id))
		end
		table.insert(g, addTitle(p, "vip"))
		gift = g
	end
	return was ~= owned, gift
end

-- VIP's daily gift: shells and an egg, once a UTC day (`now`: the sea's clock, seconds). locked (no VIP), cooldown
-- (already today).
function Store.vipDaily(p: Profile, now: number): (boolean, any)
	if not Store.owns(p, "VIP") then
		return false, "locked" :: ErrCode
	end
	local day = math.floor(now / 86400)
	if p.vipDay == day then
		return false, "cooldown" :: ErrCode
	end
	p.vipDay = day
	return true, { given = { addShells(p, Store.minutes(p, Tuning.VipDailyMins)), addEgg(p, Tuning.VipDailyEgg) } }
end

------------------------------------------------------------------ the rotating shop
-- The rotation `now` falls in, and the seconds left in it.
function Store.rotation(now: number): (number, number)
	local i = math.floor(now / Tuning.ShopSecs)
	return i, (i + 1) * Tuning.ShopSecs - now
end

local POOL: { Cosmetics.Piece } = {}
for _, c in Cosmetics.list do
	if c.src == "shop" then
		table.insert(POOL, c)
	end
end
Store.POOL = POOL

-- The pieces on sale in rotation `i` after `n` refreshes: Tuning.ShopSize of the shop's pool, none twice, picked by
-- rarity (Tuning.ShopWeight), from a seed both make (everyone sees the same set in a rotation with no refresh).
function Store.dealt(i: number, n: number): { string }
	local rng = Util.newRng(Util.hash32("shop:" .. tostring(i) .. ":" .. tostring(n)))
	local left = table.clone(POOL)
	local out: { string } = {}
	while #out < Tuning.ShopSize and #left > 0 do
		local w: { number } = {}
		for k, c in left do
			w[k] = Tuning.ShopWeight[c.rarity] or 1
		end
		local k = rng:weighted(w)
		if k < 1 then
			break
		end
		table.insert(out, left[k].id)
		table.remove(left, k)
	end
	return out
end

-- The refreshes the player bought in the rotation now (an older rotation's count no longer).
function Store.refreshes(p: Profile, now: number): number
	local i = Store.rotation(now)
	return if p.shop.at == i then p.shop.n else 0
end

-- What the player's shop holds now, and the seconds till it turns over.
function Store.shopNow(p: Profile, now: number): ({ string }, number)
	local i, left = Store.rotation(now)
	return Store.dealt(i, Store.refreshes(p, now)), left
end

-- A piece's price in shells on this island now.
function Store.price(p: Profile, id: string): number
	local c = Cosmetics.byId[id]
	local r = if c then c.rarity else 1
	return math.floor((Tuning.CosmeticPrice[r] or Tuning.CosmeticPrice[1]) * Tuning.EggTier[math.clamp(p.tier, 1, #Tuning.EggTier)])
end

-- Buy piece `id` from the shop now. not_found (not on sale now), full (owned already), money.
function Store.buy(p: Profile, id: string, now: number): (boolean, any)
	local list = Store.shopNow(p, now)
	if table.find(list, id) == nil then
		return false, "not_found" :: ErrCode
	end
	if p.owned[id] then
		return false, "full" :: ErrCode
	end
	local cost = Store.price(p, id)
	if p.shells < cost then
		return false, "money" :: ErrCode
	end
	p.shells -= cost
	p.owned[id] = true
	return true, { id = id, cost = cost }
end

------------------------------------------------------------------ wearing
-- Wear `id` in `slot` ("" takes it off). bad_payload (no such slot, or a piece of another slot), locked (not owned).
function Store.wear(p: Profile, slot: string, id: string): (boolean, any)
	if Cosmetics.bySlot[slot] == nil then
		return false, "bad_payload" :: ErrCode
	end
	local f = p.founder :: any
	if id == "" then
		f[slot] = nil
		return true, nil
	end
	local c = Cosmetics.byId[id]
	if c == nil or c.slot ~= slot then
		return false, "bad_payload" :: ErrCode
	end
	if not p.owned[id] then
		return false, "locked" :: ErrCode
	end
	f[slot] = id
	return true, nil
end

-- Wear title `id` ("" for none). not_found (no such title), locked (not earned).
function Store.setTitle(p: Profile, id: string): (boolean, any)
	if id == "" then
		p.title = ""
		return true, nil
	end
	if Titles.byId[id] == nil then
		return false, "not_found" :: ErrCode
	end
	if not p.titles[id] then
		return false, "locked" :: ErrCode
	end
	p.title = id
	return true, nil
end

------------------------------------------------------------------ titles
local KINDS = 0
for _ in Creatures.byId do
	KINDS += 1
end

local function count(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Whether title `t` is earned by what the player has done.
function Store.meets(p: Profile, t: Titles.Title): boolean
	local h = t.how
	if h == "start" then
		return true
	elseif h == "tier" then
		return p.tier >= t.n
	elseif h == "taken" then
		return p.stats.taken >= t.n
	elseif h == "best" then
		return p.stats.best >= t.n
	elseif h == "seen" then
		local seen = 0
		for _, c in p.seen do
			if c >= 2 then
				seen += 1
			end
		end
		return seen >= (if t.n > 0 then t.n else KINDS)
	elseif h == "earned" then
		return p.stats.earned >= t.n
	elseif h == "hatched" then
		return p.stats.hatched >= t.n
	elseif h == "days" then
		return p.stats.days >= t.n
	elseif h == "owned" then
		return count(p.owned) >= t.n
	elseif h == "vip" then
		return Store.owns(p, "VIP")
	end
	-- ("starter" and "track" come with what gives them)
	return false
end

-- Titles newly earned (added to Profile.titles), in Data/Titles' order. A new founder wears the first.
function Store.earn(p: Profile): { string }
	local out: { string } = {}
	for _, t in Titles.list do
		if not p.titles[t.id] and Store.meets(p, t) then
			p.titles[t.id] = true
			table.insert(out, t.id)
		end
	end
	return out
end

------------------------------------------------------------------ the pass track
-- The season `now` falls in, and the seconds left in it.
function Store.season(now: number): (number, number)
	local s = math.floor(now / Tuning.TrackSecs)
	return s, (s + 1) * Tuning.TrackSecs - now
end

-- A new season starts the points and the claims again. Returns true when it did.
function Store.sync(p: Profile, now: number): boolean
	local s = Store.season(now)
	if p.track.s ~= s then
		p.track = { s = s, xp = 0, got = {}, gotP = {} }
		return true
	end
	return false
end

-- Points for something done (Tuning.TrackXp's kinds), `k` times.
function Store.addXp(p: Profile, kind: string, k: number?)
	local n = (Tuning.TrackXp[kind] or 0) * (k or 1)
	if n > 0 then
		p.track.xp = math.min(1e9, p.track.xp + n)
	end
end

-- Level L's cost in points.
function Store.levelCost(L: number): number
	return Tuning.TrackBase + Tuning.TrackStep * (L - 1)
end

-- The levels reached, the points into the next one, and its cost (0 at the top).
function Store.level(p: Profile): (number, number, number)
	local xp = p.track.xp
	local L = 0
	while L < Track.LEVELS and xp >= Store.levelCost(L + 1) do
		xp -= Store.levelCost(L + 1)
		L += 1
	end
	return L, (if L < Track.LEVELS then xp else 0), (if L < Track.LEVELS then Store.levelCost(L + 1) else 0)
end

-- Claim level L's reward (the premium one with `prem`). locked (not reached, or no Premium Track pass for the premium
-- side), full (claimed already), bad_payload (no such level).
function Store.claim(p: Profile, L: number, prem: boolean, now: number): (boolean, any)
	Store.sync(p, now)
	local lv = Track.list[L]
	if lv == nil then
		return false, "bad_payload" :: ErrCode
	end
	if L > Store.level(p) or (prem and not Store.owns(p, "PremiumTrack")) then
		return false, "locked" :: ErrCode
	end
	local got = if prem then p.track.gotP else p.track.got
	if table.find(got, L) then
		return false, "full" :: ErrCode
	end
	table.insert(got, L)
	local given = { Store.give(p, if prem then lv.prem else lv.free) }
	if L == Track.LEVELS then
		table.insert(given, Store.give(p, if prem then Track.extra.prem else Track.extra.free))
	end
	return true, { lvl = L, prem = prem, given = given }
end

------------------------------------------------------------------ developer products
-- Pay product `key` (MonetizationService, inside ProcessReceipt). Every product always gives something: one that can't
-- do its thing (a second starter pack, no Hatchery egg to finish) pays Tuning.FallbackMins of shells. Returns true
-- and { key, given, hatched? }, or false and bad_payload for an unknown key.
function Store.product(p: Profile, key: string, now: number): (boolean, any)
	local r = Store.EGG_R[key]
	local given: { Given } = {}
	if r then
		table.insert(given, addEgg(p, r))
	elseif key == "RefreshShop" then
		local i = Store.rotation(now)
		if p.shop.at ~= i then
			p.shop = { at = i, n = 0 }
		end
		p.shop.n += 1
		table.insert(given, { kind = "shop", n = p.shop.n })
	elseif key == "StarterPack" then
		if p.gifts.starter then
			table.insert(given, addShells(p, Store.minutes(p, Tuning.FallbackMins)))
		else
			p.gifts.starter = true
			table.insert(given, addShells(p, Store.minutes(p, Tuning.StarterMins)))
			for _, er in Tuning.StarterEggs do
				table.insert(given, addEgg(p, er))
			end
			for _, id in Cosmetics.from("starter") do
				table.insert(given, addLook(p, id))
			end
			table.insert(given, addTitle(p, "earlybird"))
		end
	elseif key == "HatcheryNow" then
		if #p.eggs == 0 then
			table.insert(given, addShells(p, Store.minutes(p, Tuning.FallbackMins)))
		else
			for _, e in p.eggs do
				e.left = 1
			end
			local born = Breed.turn(p)
			for _, x in born do
				table.insert(given, { kind = "pal", id = x.sp, n = x.id })
				Store.addXp(p, "breed")
			end
		end
	else
		return false, "bad_payload" :: ErrCode
	end
	return true, { key = key, given = given }
end

-- Whether a receipt was paid already; `remember` keeps its id (the last Store.RECEIPTS).
function Store.paid(p: Profile, purchaseId: string): boolean
	return table.find(p.receipts, purchaseId) ~= nil
end
function Store.remember(p: Profile, purchaseId: string)
	table.insert(p.receipts, purchaseId)
	while #p.receipts > Store.RECEIPTS do
		table.remove(p.receipts, 1)
	end
end

-- (the rarity names a product's egg is called by: "a legendary egg")
function Store.eggName(r: number): string
	local rr = Traits.RARITY[math.clamp(r, 1, Traits.RMAX)]
	return rr.name
end

return table.freeze(Store)
