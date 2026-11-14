-- The store (Logic/Store; GAME_DESIGN 14): the passes' effects (Double Income, VIP, Quick Tree, Free Decor, Premium
-- Track), the products (eggs into the bag, a shop refresh, the starter pack once, the Hatcheries finished), the bag's
-- eggs hatched for nothing, the rotating shop, wearing cosmetics and titles, titles earned, the pass track, the
-- receipts paid once and the save's new fields; offline earnings (the cap, the share, the Offline Pass, Collect x2 on
-- an island's first days) and the group gift (once, with the group's boost while in it).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Store = require("../../build/luautest/shared/Logic/Store")
local Tree = require("../../build/luautest/shared/Logic/Tree")
local Island = require("../../build/luautest/shared/Logic/Island")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Breed = require("../../build/luautest/shared/Logic/Breed")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Util = require("../../build/luautest/shared/Logic/Util")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Cosmetics = require("../../build/luautest/shared/Data/Cosmetics")
local Titles = require("../../build/luautest/shared/Data/Titles")
local Track = require("../../build/luautest/shared/Data/Track")
local Looks = require("../../build/luautest/shared/Data/Looks")

local function fresh(): any
	local p = Schema.default(0, 7)
	p.shells = 1e9
	return p
end

local function build(p: any, id: string): number
	local x, z, rot = Plot.spot(p.tier, p.plot.placed, id, 8, 4, 0)
	assert(x and z and rot, "room for " .. id)
	local ok, data = Plot.place(p, id, x, z, rot)
	assert(ok, tostring(data))
	return data.uid
end

local function earner(): any
	local p = fresh()
	build(p, "lumber")
	build(p, "nest")
	Tree.add(p, "pebblit", {})
	return p
end

return function()
	T.it("Double Income and VIP multiply every shell; Quick Tree lays every 5 minutes", function()
		local p = earner()
		local base = Island.rates(p).shells
		T.truthy(base > 0)
		p.passes.DoubleIncome = true
		T.near(Island.rates(p).shells, base * Tuning.DoubleIncome, 1e-6)
		p.passes.VIP = true
		T.near(Island.rates(p).shells, base * Tuning.DoubleIncome * (1 + Tuning.VipIncome), 1e-6)
		T.eq(Tree.secs(p), Tuning.EggSecs)
		p.passes.QuickTree = true
		T.eq(Tree.secs(p), Tuning.EggSecsPass)
	end)

	T.it("Free Decor: decor, paths, water and fences free to place, and they sell back for nothing", function()
		local p = fresh()
		p.shells = 0
		T.eq(Plot.price(p, "oak"), Buildings.byId.oak.shells)
		p.passes.FreeDecor = true
		T.eq(Plot.price(p, "oak"), 0)
		T.eq(Plot.price(p, "lumber"), Buildings.byId.lumber.shells, "a workplace still costs")
		local x, z, rot = Plot.spot(p.tier, p.plot.placed, "oak", 8, 4, 0)
		local ok = Plot.place(p, "oak", x :: number, z :: number, rot :: number)
		T.truthy(ok, "an oak with no shells")
		T.eq(p.shells, 0)
		local i = #p.plot.placed
		T.truthy(Plot.store(p, i))
		local okSell, sold = Plot.sellHeld(p, "oak", 1)
		T.truthy(okSell and sold.shells == 0, "a free piece never turns into shells")
		T.eq(p.shells, 0)
	end)

	T.it("VIP's welcome gift once: shells, eggs, its cosmetics and title; its daily gift once a UTC day", function()
		local p = fresh()
		local s0 = p.shells
		local changed, gift = Store.setPass(p, "VIP", true)
		T.truthy(changed and gift ~= nil)
		T.truthy(p.shells > s0)
		T.eq(#p.bag, #Tuning.VipEggs)
		for _, id in Cosmetics.from("vip") do
			T.truthy(p.owned[id], id)
		end
		T.truthy(p.titles.vip)
		local again, gift2 = Store.setPass(p, "VIP", true)
		T.truthy(not again and gift2 == nil, "only once")
		local ok = Store.vipDaily(p, 100000)
		T.truthy(ok)
		local ok2, why = Store.vipDaily(p, 100000 + 3600)
		T.truthy(not ok2 and why == "cooldown")
		T.truthy((Store.vipDaily(p, 100000 + 86400)), "the next day")
		local q = fresh()
		local ok3, why3 = Store.vipDaily(q, 0)
		T.truthy(not ok3 and why3 == "locked")
	end)

	T.it("an egg product goes into the bag; a bag egg hatches for nothing, as its rarity, from any land", function()
		local p = fresh()
		build(p, "nest")
		local ok, data = Store.product(p, "EggCelestial", 0)
		T.truthy(ok and data.given[1].kind == "egg" and data.given[1].r == 7)
		T.eq(#p.bag, 1)
		local s0 = p.shells
		local rng = Util.newRng(4)
		local okH, h = Tree.hatchBag(p, p.bag[1].id, 0, rng)
		T.truthy(okH, tostring(h))
		T.eq(p.shells, s0, "no shells")
		T.eq(Creatures.byId[h.sp].rarity, 7, "a celestial one on a tier 1 island")
		T.eq(#p.bag, 0)
		T.truthy(h.bag and h.cost == 0)
		-- no hut: refused, the egg kept
		local q = fresh()
		Store.product(q, "EggRare", 0)
		local okN, why = Tree.hatchBag(q, q.bag[1].id, 0, rng)
		T.truthy(not okN and why == "no_hut")
		T.eq(#q.bag, 1)
	end)

	T.it("the starter pack once (then shells), a shop refresh, the Hatcheries finished now", function()
		local p = fresh()
		local ok, data = Store.product(p, "StarterPack", 0)
		T.truthy(ok and p.gifts.starter)
		T.truthy(p.titles.earlybird and p.owned.explorerhat and p.owned.explorershirt)
		T.eq(#p.bag, #Tuning.StarterEggs)
		local s1 = p.shells
		Store.product(p, "StarterPack", 0)
		T.eq(#p.bag, #Tuning.StarterEggs, "no second set of eggs")
		T.truthy(p.shells > s1, "shells in its place")
		-- the shop: a refresh deals a new set in this rotation only
		local before = Store.shopNow(p, 100)
		Store.product(p, "RefreshShop", 100)
		local after = Store.shopNow(p, 100)
		T.truthy(table.concat(before, ",") ~= table.concat(after, ","), "a new set")
		T.eq(Store.refreshes(p, 100 + Tuning.ShopSecs), 0, "the next rotation is everyone's again")
		-- the Hatcheries
		local q = fresh()
		q.tier = 6
		local h = build(q, "hatchery")
		build(q, "nest")
		local a = Tree.add(q, "pebblit", {})
		local b = Tree.add(q, "pebblit", {})
		T.truthy((Breed.start(q, h, a.id, b.id, Util.newRng(2))))
		T.eq(#q.eggs, 1)
		local n0 = #q.pals
		local okH, dH = Store.product(q, "HatcheryNow", 0)
		T.truthy(okH and #q.eggs == 0 and #q.pals == n0 + 1, "hatched now")
		T.eq(dH.given[1].kind, "pal")
		local s2 = q.shells
		Store.product(q, "HatcheryNow", 0)
		T.truthy(q.shells > s2, "nothing to finish: shells")
		T.truthy(not (Store.product(q, "Nope", 0)))
	end)

	T.it("the rotating shop: the same set for everyone in a rotation, bought with shells, owned once", function()
		local p = fresh()
		local list, left = Store.shopNow(p, 5000)
		T.eq(#list, Tuning.ShopSize)
		T.near(left, Tuning.ShopSecs - 5000, 1e-9)
		local seen: { [string]: boolean } = {}
		for _, id in list do
			T.truthy(not seen[id] and Cosmetics.byId[id] and Cosmetics.byId[id].src == "shop", id)
			seen[id] = true
		end
		T.deepEq(Store.shopNow(fresh(), 5001), list, "everyone's the same")
		local id = list[1]
		local cost = Store.price(p, id)
		T.eq(cost, math.floor(Tuning.CosmeticPrice[Cosmetics.byId[id].rarity] * Tuning.EggTier[1]))
		local s0 = p.shells
		T.truthy((Store.buy(p, id, 5000)))
		T.eq(p.shells, s0 - cost)
		T.truthy(p.owned[id])
		local ok, why = Store.buy(p, id, 5000)
		T.truthy(not ok and why == "full")
		local other = "goldcrown" -- never in the shop
		local ok2, why2 = Store.buy(p, other, 5000)
		T.truthy(not ok2 and why2 == "not_found")
		p.shells = 0
		local ok3, why3 = Store.buy(p, list[2], 5000)
		T.truthy(not ok3 and why3 == "money")
	end)

	T.it("wearing: owned pieces only, one a slot; a title earned only; the look string", function()
		local p = fresh()
		local ok, why = Store.wear(p, "hat", "strawhat")
		T.truthy(not ok and why == "locked")
		p.owned.strawhat = true
		T.truthy((Store.wear(p, "hat", "strawhat")))
		T.eq(p.founder.hat, "strawhat")
		local okB, whyB = Store.wear(p, "face", "strawhat")
		T.truthy(not okB and whyB == "bad_payload", "a hat isn't worn on the face")
		T.truthy((Store.wear(p, "hat", "")))
		T.eq(p.founder.hat, nil)
		local okT, whyT = Store.setTitle(p, "vip")
		T.truthy(not okT and whyT == "locked")
		T.truthy((Store.setTitle(p, "newcomer")))
		-- the attribute: the old four numbers alone when nothing is worn, the slots after them when something is
		local f = p.founder
		T.eq(Looks.encode(f), string.format("%d.%d.%d.%d", f.skin, f.hair, f.style, f.shirt))
		Store.wear(p, "hat", "strawhat")
		local s = Looks.encode(f)
		local back = Looks.decode(s) :: any
		T.eq(back.hat, "strawhat")
		T.eq(back.skin, f.skin)
		T.eq(Looks.decode("garbage"), nil)
	end)

	T.it("titles come with play: the island's tier, eggs hatched, the rarest had", function()
		local p = fresh()
		T.truthy(p.titles.newcomer and p.title == "newcomer")
		T.deepEq(Store.earn(p), {})
		p.tier = 5
		p.stats.taken = 120
		local got = Store.earn(p)
		T.truthy(table.find(got, "settler") and table.find(got, "islander") and table.find(got, "townfounder"))
		T.truthy(table.find(got, "eggfinder") and table.find(got, "egghunter"))
		T.truthy(table.find(got, "baykeeper") == nil)
		T.deepEq(Store.earn(p), {}, "once")
		for _, t in Titles.list do
			T.truthy(t.name ~= "" and string.find(t.name, "%-") == nil, t.id)
		end
	end)

	T.it("the pass track: levels from points, rewards claimed once, the premium side with its pass, a new season", function()
		local p = fresh()
		local now = 1000
		Store.sync(p, now)
		T.eq(Store.level(p), 0)
		local ok, why = Store.claim(p, 1, false, now)
		T.truthy(not ok and why == "locked")
		Store.addXp(p, "expand") -- 120: level 1
		T.eq(Store.level(p), 1)
		local okC, d = Store.claim(p, 1, false, now)
		T.truthy(okC and #d.given == 1)
		local okD, whyD = Store.claim(p, 1, false, now)
		T.truthy(not okD and whyD == "full")
		local okP, whyP = Store.claim(p, 1, true, now)
		T.truthy(not okP and whyP == "locked", "the premium side needs its pass")
		p.passes.PremiumTrack = true
		T.truthy((Store.claim(p, 1, true, now)))
		-- the whole track
		local total = 0
		for L = 1, Track.LEVELS do
			total += Store.levelCost(L)
		end
		p.track.xp = total
		local L, into, need = Store.level(p)
		T.truthy(L == Track.LEVELS and into == 0 and need == 0)
		local okL, dL = Store.claim(p, Track.LEVELS, false, now)
		T.truthy(okL and #dL.given == 2, "the last level's title and its egg")
		T.truthy(p.titles.firstmate)
		-- a new season: points and claims start again, what was won stays
		T.truthy(Store.sync(p, now + Tuning.TrackSecs))
		T.eq(p.track.xp, 0)
		T.eq(#p.track.got, 0)
		T.truthy(p.titles.firstmate)
	end)

	T.it("a receipt is paid once; the save keeps the store's fields and cleans them", function()
		local p = fresh()
		T.truthy(not Store.paid(p, "abc"))
		Store.remember(p, "abc")
		T.truthy(Store.paid(p, "abc"))
		for i = 1, Store.RECEIPTS + 5 do
			Store.remember(p, "r" .. i)
		end
		T.eq(#p.receipts, Store.RECEIPTS)
		-- a version 15 save
		local old = Schema.reconcile({ v = 15, shells = 10, founder = { skin = 2, hair = 1, style = 1, shirt = 1, hat = "strawhat" } }, 0, 1)
		T.truthy(old.titles.newcomer and old.title == "newcomer")
		T.eq(old.founder.hat, nil, "a piece not owned isn't worn")
		T.eq(#old.bag, 0)
		-- this version, with garbage in it
		local raw = {
			v = 16,
			passes = { VIP = true, Nope = true, DoubleIncome = "yes" },
			owned = { strawhat = true, nothing = true },
			titles = { vip = true, x = true },
			title = "x",
			founder = { skin = 1, hair = 1, style = 1, shirt = 1, hat = "strawhat", face = "strawhat" },
			bag = { { id = 9000, r = 7 }, { id = 9000, r = 3 }, { id = 9001, r = 99 }, "x" },
			track = { s = 3, xp = 250, got = { 1, 1, 99, 2 }, gotP = "x" },
			shop = { at = 4, n = 2 },
			receipts = { "a", 5, "b" },
			gifts = { vip = true, starter = 1 },
		}
		local q = Schema.reconcile(raw, 0, 1)
		T.truthy(q.passes.VIP and q.passes.Nope == nil and q.passes.DoubleIncome == nil)
		T.truthy(q.owned.strawhat and q.owned.nothing == nil)
		T.truthy(q.titles.vip and q.titles.x == nil and q.titles.newcomer)
		T.eq(q.title, "newcomer", "an unknown title worn: back to Newcomer")
		T.eq(q.founder.hat, "strawhat")
		T.eq(q.founder.face, nil, "a hat isn't worn on the face")
		T.eq(#q.bag, 2)
		T.eq(q.bag[2].r, 7, "a rarity in range")
		T.truthy(q.nextId > 9001)
		T.deepEq(q.track.got, { 1, 2 })
		T.deepEq(q.track.gotP, {})
		T.eq(q.track.xp, 250)
		T.deepEq(q.receipts, { "a", "b" })
		T.truthy(q.gifts.vip and q.gifts.starter == nil)
	end)

	T.it("every cosmetic in a slot, a rarity, a known source; the track's and the gifts' pieces exist", function()
		T.truthy(#Cosmetics.list >= 80, tostring(#Cosmetics.list))
		local SRC = { shop = true, track = true, trackp = true, vip = true, starter = true }
		for _, c in Cosmetics.list do
			T.truthy(c.rarity >= 1 and c.rarity <= 5 and SRC[c.src] and Cosmetics.bySlot[c.slot], c.id)
			T.truthy(string.find(c.name, "%-") == nil, c.id .. ": no dashes")
		end
		for _, lv in Track.list do
			for _, r in { lv.free, lv.prem } do
				if r.kind == "look" then
					T.truthy(Cosmetics.byId[r.id] ~= nil and (Cosmetics.byId[r.id].src == "track" or Cosmetics.byId[r.id].src == "trackp"), r.id)
				elseif r.kind == "title" then
					T.truthy(Titles.byId[r.id] ~= nil, r.id)
				end
			end
		end
		T.truthy(#Store.POOL >= Tuning.ShopSize * 4, "enough for the shop to rotate")
	end)

	T.it("offline earnings: nothing under five minutes, 3 h at 30% of the pace, 24 h at full pace with the pass", function()
		local p = earner()
		local perSec = Island.rates(p).shells / Tuning.TurnSeconds
		T.truthy(perSec > 0)
		p.seenAt = 0
		T.eq(Store.offline(p, 1e6), nil) -- (unknown: an older save)
		p.seenAt = 1000
		T.eq(Store.offline(p, 1000 + Tuning.OfflineMinSec - 1), nil)
		-- two hours away: all of it counts, at OfflinePct
		local r = Store.offline(p, 1000 + 7200) :: any
		T.truthy(r ~= nil)
		T.eq(r.away, 7200)
		T.eq(r.secs, 7200)
		T.eq(r.shells, math.floor(perSec * 7200 * Tuning.OfflinePct + 1e-9))
		-- a day away: only OfflineHours count
		r = Store.offline(p, 1000 + 86400) :: any
		T.eq(r.secs, Tuning.OfflineHours * 3600)
		T.eq(r.shells, math.floor(perSec * Tuning.OfflineHours * 3600 * Tuning.OfflinePct + 1e-9))
		-- the Offline Pass: OfflinePassHours at OfflinePassPct
		p.passes.OfflinePass = true
		T.eq(Store.offlineCap(p), Tuning.OfflinePassHours * 3600)
		r = Store.offline(p, 1000 + 86400) :: any
		T.eq(r.secs, 86400)
		T.eq(r.shells, math.floor(perSec * 86400 * Tuning.OfflinePassPct + 1e-9))
		r = Store.offline(p, 1000 + 3 * 86400) :: any
		T.eq(r.secs, Tuning.OfflinePassHours * 3600)
		-- collected: the shells and the stats; x2 free in the island's first days only
		local s0, e0 = p.shells, p.stats.earned
		T.eq(Store.collect(p, r, 2), r.shells * 2)
		T.eq(p.shells, s0 + r.shells * 2)
		T.eq(p.stats.earned, e0 + r.shells * 2)
		p.createdAt = 0
		T.truthy(Store.offlineDouble(p, Tuning.OfflineDoubleDays * 86400 - 1))
		T.truthy(not (Store.offlineDouble(p, Tuning.OfflineDoubleDays * 86400)))
		-- an island that makes nothing earns nothing away
		local q = fresh()
		q.seenAt = 1
		T.eq(Store.offline(q, 1e5), nil)
	end)

	T.it("the group: the gift once (a rare egg and shells), more shells while in it, none after leaving", function()
		local p = earner()
		local base = Island.rates(p).shells
		local bag0, sh0 = #p.bag, p.shells
		local changed, gift = Store.setGroup(p, true)
		T.truthy(changed)
		T.truthy(gift ~= nil and #(gift :: any) == 2)
		T.eq(#p.bag, bag0 + 1)
		T.eq(p.bag[#p.bag].r, Tuning.GroupEgg)
		T.truthy(p.shells > sh0)
		T.truthy(p.group.member and p.group.gift)
		T.near(Island.rates(p).shells, base * (1 + Tuning.GroupBoost), 1e-6)
		-- (checked again: no second gift)
		local c2, g2 = Store.setGroup(p, true)
		T.truthy(not (c2))
		T.eq(g2, nil)
		-- left the group: the boost goes, the gift stays had
		local c3, g3 = Store.setGroup(p, false)
		T.truthy(c3)
		T.eq(g3, nil)
		T.near(Island.rates(p).shells, base, 1e-6)
		local c4, g4 = Store.setGroup(p, true)
		T.truthy(c4)
		T.eq(g4, nil)
		-- the save keeps both, and an older save starts out of the group with nothing earned away
		local raw = Util.deepCopy(p)
		raw.seenAt = 12345
		local back = Schema.reconcile(raw, 99999, 7)
		T.truthy(back.group.member and back.group.gift)
		T.eq(back.seenAt, 12345)
		local old = Util.deepCopy(p)
		old.v = 16
		old.group = nil
		old.seenAt = nil
		local up = Schema.reconcile(old, 99999, 7)
		T.truthy(not (up.group.member or up.group.gift))
		T.eq(up.seenAt, 0)
		T.eq(Store.offline(up, 99999 + 7200), nil)
	end)
end
