-- The island's rules (Logic/Island; GAME_DESIGN 3-6): what it makes (shells from the farms, the wood buildings and the
-- shops; nothing eats), charm and the shells it adds, the driftlings at work (from their huts, faster the rarer: they do
-- all the work, no villagers), expanding (for shells: one store since 2026-11-14).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Island = require("../../build/luautest/shared/Logic/Island")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Plot = require("../../build/luautest/shared/Logic/Plot")

-- (an island with nothing on it)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells = 1e6
	p.plot.placed = {}
	return p
end

-- what charm multiplies every shell by now (Island.charmBonus)
local function cb(p: any): number
	return 1 + Island.charmBonus(Island.charm(p))
end

local function put(p: any, id: string): number
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = 0, z = 0, rot = 0 })
	return uid
end

-- a common driftling living in hut `hut`, working at `work` (0: resting): the three kinds of its old knack's
-- (a Mossbun +15% work, a Pebblit +15%, a Conchy +30%; one kind of work since 2026-11-19)
local KNACK = { farm = "mossbun", wood = "pebblit", shop = "conchy" }
local function worker(p: any, knack: string, hut: number, work: number): any
	local x = { id = p.nextId, sp = KNACK[knack], home = hut, work = work }
	p.nextId += 1
	table.insert(p.pals, x)
	return x
end

return function()
	T.it("a new island: one store, nothing built but its tree", function()
		local p = Schema.default(0, 1)
		T.eq(p.shells, Tuning.StartShells)
		T.eq((p :: any).wood, nil, "no wood")
		T.eq((p :: any).food, nil, "no food")
		T.eq(#p.plot.placed, 1)
		T.eq(p.plot.placed[1].id, "tree")
		local r = Island.rates(p)
		T.eq((r :: any).wood, nil)
		T.eq(r.shells, 0)
		T.eq((r :: any).food, nil)
		T.eq(Island.nests(p), 0)
	end)
	T.it("a building makes its share with no driftling there; each driftling makes its share, more the rarer", function()
		local p = fresh()
		local uid = put(p, "patch")
		-- (a farm sells what it grows: shells)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Tuning.IdleOutput * cb(p), 1e-9)
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 99, sp = "mossbun", home = hut, work = uid })
		-- (its share grows with its work share: the mossbun's passive)
		local share = Island.palWork(p, p.pals[1])
		T.truthy(share > 0, "its passive helps at work")
		local one = Tuning.PalWork * Tuning.RarityWork[1] * (1 + share)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one * cb(p), 1e-9, "one common: its share, no idle share")
		-- a second, rarer one adds its own share, bigger by its rarity
		table.insert(p.pals, { id = 98, sp = "bloomoth", home = hut, work = uid })
		local share2 = Island.palWork(p, p.pals[2])
		local two = one + Tuning.PalWork * Tuning.RarityWork[3] * (1 + share2)
		T.truthy(two - one > one, "a rare one makes more than a common")
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * two * cb(p), 1e-9)
		-- with no hut: it doesn't work
		p.pals[2].home = 0
		p.pals[2].work = 0
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one * cb(p), 1e-9)
		table.remove(p.pals, 2)
		-- a mutation for work makes it a better worker still
		p.pals[1].muts = { "busy3" }
		T.truthy(Island.palWork(p, p.pals[1]) > share, "a work mutation adds to it")
	end)
	T.it("wood and shops: a camp sells its wood for shells, a shop its snacks, each at its plain rate", function()
		-- (the request of 2026-11-14: "the wood tab buildings will also now give shells ... remove the visitors mechanic")
		local p = fresh()
		local hut = put(p, "nest")
		local camp = put(p, "lumber")
		local w = worker(p, "wood", hut, camp)
		T.near(Island.rates(p).shells, Buildings.byId.lumber.rate * Island.palBoost(p, w, 0) * cb(p), 1e-9)
		local s = put(p, "stall")
		local v = worker(p, "shop", hut, s)
		local k = Buildings.byId.lumber.rate * Island.palBoost(p, w, 0) + Buildings.byId.stall.rate * Island.palBoost(p, v, 0)
		T.near(Island.rates(p).shells, k * cb(p), 1e-9, "no visitors to wait for")
		T.eq((Island :: any).visitors, nil, "no visitors")
	end)
	T.it("charm raises the shells: the first charm counts the most, never past CharmMax", function()
		-- (the request of 2026-11-14: "charm simply increases your shell gain")
		T.eq(Island.charmBonus(0), 0)
		T.eq(Island.charmBonus(-5), 0, "never below nothing")
		T.near(Island.charmBonus(Tuning.CharmHalf), Tuning.CharmMax / 2, 1e-9, "half the most at CharmHalf")
		T.truthy(Island.charmBonus(10) - Island.charmBonus(0) > Island.charmBonus(1010) - Island.charmBonus(1000), "the first charm counts the most")
		T.truthy(Island.charmBonus(1e9) <= Tuning.CharmMax, "never past CharmMax")
		local p = fresh()
		local farm = put(p, "patch")
		local base = Island.charm(p)
		local plain = Island.rates(p).shells / cb(p)
		T.truthy(farm > 0 and plain > 0)
		put(p, "fountain")
		local fc = Buildings.charmOf(Buildings.byId.fountain, p.tier)
		T.eq(Island.charm(p), base + fc)
		T.near(Island.rates(p).shells, plain * (1 + Island.charmBonus(base + fc)), 1e-9, "more charm, more shells")
		for _ = 1, 30 do
			put(p, "statue")
		end
		T.truthy(Island.rates(p).shells > plain * (1 + Island.charmBonus(base + fc)), "decor pays")
	end)
	T.it("decor: the same charm a tile whatever the piece, more on a bigger island", function()
		-- (the requests of 2026-11-19: "make decor all give the same amount of charm, scaling based on their size
		-- instead", then "make it such that the charm they give scale off expansions as well")
		local fountain, fern = Buildings.byId.fountain, Buildings.byId.fern
		for tier = 1, #Tuning.DecorCharm do
			T.eq(Buildings.charmOf(fountain, tier), Tuning.DecorCharm[tier] * fountain.w * fountain.d)
			T.eq(Buildings.charmOf(fern, tier) * fountain.w * fountain.d, Buildings.charmOf(fountain, tier) * fern.w * fern.d, "a tile is a tile")
			if tier > 1 then
				T.truthy(Tuning.DecorCharm[tier] >= Tuning.DecorCharm[tier - 1], "never less a tile when the island grows")
			end
		end
		T.truthy(Tuning.DecorCharm[#Tuning.DecorCharm] > Tuning.DecorCharm[1], "more at the top")
		T.eq(Buildings.charmOf(Buildings.byId.tree, 5), Buildings.byId.tree.charm, "other pieces keep their own")
		-- an island's decor counts at its tier: the same pieces bring more once it has grown
		local p = fresh()
		put(p, "fountain")
		local before = Island.charm(p)
		p.tier = 10
		T.eq(Island.charm(p) - before, (Tuning.DecorCharm[10] - Tuning.DecorCharm[1]) * fountain.w * fountain.d)
	end)
	T.it("a turn: what it made, the shells counted as earned", function()
		local p = fresh()
		local hut = put(p, "nest")
		local x = worker(p, "farm", hut, put(p, "patch"))
		worker(p, "wood", hut, put(p, "lumber"))
		local shells, earned = p.shells, p.stats.earned
		local r = Island.rates(p)
		Island.step(p, Tuning.TurnSeconds)
		T.near(p.shells, shells + r.shells, 1e-9)
		T.near(p.stats.earned, earned + r.shells, 1e-9)
		T.truthy(r.shells > 0 and x.work ~= 0)
	end)
	T.it("a new calendar day counts the days; a day lasts hours, many turns", function()
		local p = fresh()
		Island.newDay(p)
		T.eq(p.day, 2)
		T.eq(p.stats.days, 1)
		T.truthy(Tuning.DaySeconds >= 3 * 3600, "a few hours at least")
		T.truthy(Tuning.DaySeconds >= Tuning.TurnSeconds * 100)
	end)
	T.it("work: driftlings from a hut, at any workplace, two a building; a free place is the best with room", function()
		local p = fresh()
		local patch = put(p, "patch")
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 70, sp = "mossbun", home = hut, work = 0 })
		table.insert(p.pals, { id = 71, sp = "frondle", home = hut, work = 0 })
		table.insert(p.pals, { id = 72, sp = "hopsprout", home = 0, work = 0 })
		local lumber = put(p, "lumber")
		T.truthy(Island.setHelp(p, 70, lumber), "a farm driftling at the lumber camp: any driftling works anywhere")
		T.eq(p.pals[1].work, lumber)
		T.eq(select(2, Island.setHelp(p, 70, hut)), "bad_payload", "not at a hut: it makes nothing")
		T.eq(select(2, Island.setHelp(p, 999, patch)), "not_found")
		T.truthy(Island.setHelp(p, 70, patch))
		T.truthy(Island.setHelp(p, 71, patch))
		T.eq(p.pals[1].work, patch, "two at one building")
		T.eq(select(2, Island.setHelp(p, 72, patch)), "bad_payload", "one with no hut doesn't work")
		p.pals[3].home = hut
		T.truthy(Island.setHelp(p, 72, patch))
		T.eq(p.pals[1].work, lumber, "a third: the first there goes back to the arrangement, and the lumber camp has room")
		T.truthy(p.pals[1].pin == nil and p.pals[2].pin == true and p.pals[3].pin == true, "the bumped one is the arrangement's again; the picked stay picked")
		T.eq(p.pals[2].work, patch)
		T.eq(Island.freeJob(p), lumber, "the patch is full: the lumber camp has room")
		local patch2 = put(p, "patch")
		T.eq(Island.freeJob(p), patch2, "as good a workplace, emptier")
		put(p, "stall")
		T.eq(Island.freeJob(p), patch2, "a tie: the first built")
		p.tier = 2
		local orchard = put(p, "orchard")
		T.eq(Island.freeJob(p), orchard, "the best workplace with room first")
		T.truthy(Island.setHelp(p, 72, 0))
		T.eq(p.pals[3].work, 0, "back to rest")
	end)
	T.it("the arrangement: each works where it makes the most, the best first; a hand-picked one stays till Auto", function()
		-- (the request of 2026-11-14: "make it such that driftlings will automatically work at whatever they do best in,
		-- at the best work areas")
		local p = fresh()
		p.tier = 2
		local hut = put(p, "burrow") -- (room for four)
		local hut2 = put(p, "burrow") -- (four more: the orchard's places and two)
		local patch = put(p, "patch") -- (rate 36)
		local orchard = put(p, "orchard") -- (rate 102: the better farm)
		local lumber = put(p, "lumber")
		local common = worker(p, "farm", hut, 0) -- a Mossbun, farms +15%
		local rare = { id = p.nextId, sp = "bloomoth", home = hut, work = 0 } -- rare, farms +40%
		p.nextId += 1
		table.insert(p.pals, rare)
		local epic = { id = p.nextId, sp = "sunsprite", home = hut, work = 0 } -- epic, farms +35%
		p.nextId += 1
		table.insert(p.pals, epic)
		-- (more rare farmers, so the orchard's places are all taken by better workers than the Mossbun)
		local more = {}
		for _ = 1, Buildings.byId.orchard.jobs - 2 do
			local x = { id = p.nextId, sp = "bloomoth", home = hut2, work = 0 }
			p.nextId += 1
			table.insert(p.pals, x)
			table.insert(more, x)
		end
		local woody = worker(p, "wood", hut2, 0) -- a Pebblit, +15% work
		Island.arrange(p)
		T.eq(epic.work, orchard, "the best worker at the best workplace")
		T.eq(rare.work, orchard, "the next best with it")
		for _, x in more do
			T.eq(x.work, orchard, "the orchard's other places to the next best")
		end
		T.eq(common.work, patch, "the orchard full: the next best workplace (a tie with the camp: the first built)")
		T.eq(woody.work, patch, "the patch's second place")
		-- a better workplace takes the best workers (one kind of work: no worker is better at one than another)
		local cafe = put(p, "cafe") -- (rate 120: better than the orchard)
		Island.arrange(p)
		T.eq(epic.work, cafe, "the best at the best")
		T.eq(common.work, orchard, "the rest move up one")
		T.eq(woody.work, orchard)
		T.truthy(Island.rates(p).shells > 0)
		-- picked by hand: it stays, the rest arranged round it; Auto hands it back
		T.truthy(Island.setHelp(p, epic.id, patch))
		T.truthy(epic.work == patch and epic.pin == true, "the player's pick stays")
		Island.arrange(p)
		T.eq(epic.work, patch, "and survives the next arrangement")
		local ok, data = Island.autoWork(p, epic.id)
		T.truthy(ok and data.work == cafe and epic.pin == nil, "Auto: back to the best workplace")
		T.eq(select(2, Island.autoWork(p, 999)), "not_found")
		-- resting by hand is a pick too
		T.truthy(Island.setHelp(p, woody.id, 0))
		Island.arrange(p)
		T.truthy(woody.work == 0 and woody.pin == true, "rests while the player wants it to")
		-- a picked place cleared away: back to the arrangement
		Island.setHelp(p, epic.id, patch)
		for i, q in p.plot.placed do
			if q.uid == patch then
				table.remove(p.plot.placed, i)
				break
			end
		end
		Island.arrange(p)
		T.truthy(epic.pin == nil and epic.work == cafe, "its place gone: the arrangement places it")
		-- the same when the rules take the place away (Plot.store): the pin goes with it, where it once stayed with no
		-- work, which reads as resting by hand, for good (the server review of 2026-11-19)
		Island.setHelp(p, epic.id, orchard)
		T.truthy(epic.pin == true and epic.work == orchard)
		local oi = 0
		for i, q in p.plot.placed do
			if q.uid == orchard then
				oi = i
			end
		end
		T.truthy((Plot.store(p, oi)))
		T.truthy(epic.pin == nil and epic.work == 0, "stored away: its pin goes too")
		Island.arrange(p)
		T.truthy(epic.work ~= 0, "and the arrangement puts it to work again")
		-- no hut, no work; no room anywhere, rest
		local homeless = { id = p.nextId, sp = "mossbun", home = 0, work = lumber }
		p.nextId += 1
		table.insert(p.pals, homeless)
		Island.arrange(p)
		T.eq(homeless.work, 0, "no hut: it rests")
	end)
	T.it("one kind of work (2026-11-19): a driftling works as fast at every workplace", function()
		local p = fresh()
		local hut = put(p, "nest")
		local lumber = put(p, "lumber")
		local patch = put(p, "patch")
		local x = { id = 80, sp = "frondle", home = hut, work = patch } -- +18% work
		table.insert(p.pals, x)
		local atFarm = Island.palBoost(p, x)
		T.truthy(Island.setHelp(p, 80, lumber))
		T.near(Island.palBoost(p, x), atFarm, 1e-12, "the same at the camp")
		T.near(Island.palWork(p, x), 0.18, 1e-9)
		T.eq(Buildings.byId.lumber.kind, "work")
		T.eq(Buildings.byId.patch.kind, "work")
		T.eq(Buildings.byId.stall.kind, "work")
	end)
	T.it("expanding: its price in shells, then the next, then no more", function()
		-- (the request of 2026-11-14: "allowing you to buy decor and expansions with it")
		local p = fresh()
		T.truthy(Island.expand(p))
		T.eq(p.tier, 2)
		T.eq(p.shells, 1e6 - (Island.expandCost(1) :: any).shells, "shells")
		p.shells = 0
		T.eq(select(2, Island.expand(p)), "money")
		p.shells = 1e12
		while p.tier < #Tuning.TierCost do
			T.truthy(Island.expand(p))
		end
		T.eq(p.tier, 20, "twenty tiers: a castaway's cay to Everdrift")
		T.eq(select(2, Island.expand(p)), "max")
	end)
	T.it("the expansions' prices: the low levels cheaper, the more the lower; 11 to 20 rising smoothly from there", function()
		-- (the request of 2026-11-14: "allow expansion up to level 20, you can make the previous levels of expansion a
		-- bit cheaper too"; the prices before it: 8 to 10 still a fifth under them)
		local OLD = { 0, 600, 9000, 60000, 160000, 380000, 800000, 1600000, 3000000, 5000000 }
		for t = 8, 10 do
			local k = Tuning.TierCost[t] / OLD[t]
			T.truthy(k >= 0.75 and k <= 0.85, string.format("level %d at %.0f%% of its old price", t, k * 100))
		end
		-- (the request of 2026-11-17: "also, make expansion cheaper at lower levels"; the prices before it: each of 2 to
		-- 7 cheaper, the lower the more, and every level still dearer than the one before)
		local NOV14 = { 0, 480, 7200, 48000, 128000, 300000, 640000 }
		local last = 0
		for t = 2, 7 do
			local k = Tuning.TierCost[t] / NOV14[t]
			T.truthy(k < 0.95 and k >= last - 1e-9 or t == 2, string.format("level %d at %.0f%% of its price before", t, k * 100))
			T.truthy(k <= 0.92, string.format("level %d cheaper: %.0f%%", t, k * 100))
			last = k
		end
		T.truthy(Tuning.TierCost[2] / NOV14[2] <= 0.5, "level 2 at half or less")
		for t = 2, 10 do
			T.truthy(Tuning.TierCost[t] > Tuning.TierCost[t - 1], "level " .. t .. " dearer than " .. (t - 1))
		end
		for t = 11, 20 do
			local k = Tuning.TierCost[t] / Tuning.TierCost[t - 1]
			T.truthy(k > 1.15 and k < 1.6, string.format("level %d at %.2f times the one before", t, k))
		end
	end)
	T.it("huts: a resident's comfort (its hut's and its level's) makes it work more; none with no hut", function()
		local p = fresh()
		p.tier = 6
		local farm = put(p, "patch")
		local den = put(p, "den")
		local x = { id = 500, sp = "mossbun", home = den, work = farm }
		table.insert(p.pals, x)
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort, 1e-9)
		T.near(Island.palBoost(p, x, Buildings.byId.den.comfort), Tuning.PalWork * (1 + Island.palWork(p, x) + Buildings.byId.den.comfort), 1e-9)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Island.palBoost(p, x, Buildings.byId.den.comfort) * cb(p), 1e-9)
		-- a hut's level (from an older save) adds comfort
		p.plot.placed[2].lvl = 3
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort + Tuning.ComfortLvl[3], 1e-9)
		x.home = 0
		T.eq(Island.homes(p).p500, nil, "none with no hut")
	end)
	T.it("charm: each driftling in a hut, with its charm effects; none for one with no hut", function()
		local p = fresh()
		local base = Island.charm(p)
		local hut = put(p, "nest")
		local c0 = Island.charm(p)
		table.insert(p.pals, { id = 80, sp = "pebblit", home = hut, work = 0, muts = { "armor3" } }) -- Rolling Stone +1, Adorable +3
		T.eq(Island.charm(p), c0 + 1 + 1 + 3)
		p.pals[1].home = 0
		T.eq(Island.charm(p), c0)
		T.truthy(c0 >= base)
	end)
	T.it("boosts: every boost building boosts every workplace (2026-11-19); copies of a kind stack, less each time; never past BoostMax", function()
		local p = fresh()
		p.tier = 6
		local farm = put(p, "patch")
		local camp = put(p, "lumber")
		local base = Island.output(p)
		put(p, "windmill")
		local w = Buildings.byId.windmill.boostBy
		T.near(Island.boostRaw(p), w, 1e-9)
		local out = Island.output(p)
		T.near(out[farm], base[farm] * (1 + w), 1e-9, "the farm")
		T.near(out[camp], base[camp] * (1 + w), 1e-9, "and the camp: everything")
		T.near(Island.boostInfo(p, "windmill").more, w * Tuning.BoostStack, 1e-9, "a second would add BoostStack of the first")
		put(p, "windmill")
		T.near(Island.boostRaw(p), w + w * Tuning.BoostStack, 1e-9, "a second windmill: BoostStack of the first")
		-- (two of each at most since the request of 2026-11-20: one more adds nothing on the card)
		local two = Island.boostInfo(p, "windmill")
		T.truthy(two.more == 0 and two.same == Tuning.BoostEach, "two windmills: the most of a kind, one more adds nothing")
		-- (an older save's third, placed before the limit, still counts: BoostStack of the second)
		put(p, "windmill")
		T.near(Island.boostRaw(p), w * (1 + Tuning.BoostStack + Tuning.BoostStack ^ 2), 1e-9, "a third: BoostStack of the second")
		T.truthy(Tuning.BoostStack > 0 and Tuning.BoostStack < 1, "less each time")
		T.near(Island.boostShare("windmill", 4), w * Tuning.BoostStack ^ 3, 1e-9)
		T.eq(Island.boostShare("patch", 1), 0, "a workplace boosts nothing")
		put(p, "smokehouse")
		local raw = w * (1 + Tuning.BoostStack + Tuning.BoostStack ^ 2) + Buildings.byId.smokehouse.boostBy
		T.near(Island.boostRaw(p), raw, 1e-9, "another kind: its whole share")
		local info = Island.boostInfo(p, "windmill")
		T.eq(info.count, 4, "every boost building")
		T.near(info.total, math.min(Tuning.BoostMax, raw), 1e-9)
		T.truthy(info.more == 0 and info.same == 3, "an older save's three: none more to build")
		for _, id in { "watertower", "townhall", "beacon", "market", "toolshed", "townhall", "beacon", "tidebell" } do
			put(p, id)
		end
		T.near(Island.boost(p), Tuning.BoostMax, 1e-9, "never past BoostMax")
		T.eq(Island.boostInfo(p, "patch").count, 0)
		-- the driftlings' boost share makes every boost building stronger, past the cap too (2026-11-19)
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 900, sp = "bumblet", home = hut, work = 0 }) -- Busy Buzz: boost +8%
		T.near(Island.boost(p), Tuning.BoostMax * (1 + 0.08), 1e-9)
		T.near(Island.boostInfo(p, "windmill").mult, 1.08, 1e-9)
		-- what each workplace makes adds up to the island's rate (before the charm bonus and the passes)
		local made, sum = Island.output(p), 0
		for _, q in p.plot.placed do
			sum += made[q.uid] or 0
		end
		T.near(Island.rates(p).shells, sum * (1 + Island.charmBonus(Island.charm(p))) * Island.passMult(p), 1e-6)
		T.truthy((made[farm] or 0) > 0, "the patch makes something")
	end)
	T.it("the island's share of its huts' driftlings (Island.isle): summed and capped; Hatchery time multiplies", function()
		local p = fresh()
		local hut = put(p, "nest")
		local i0 = Island.isle(p)
		T.eq(i0.hatch, 1)
		T.eq(i0.boost, 0)
		T.eq(i0.charmPct, 0)
		local a = { id = 1, sp = "pebblit", home = hut, work = 0, muts = { "grower4", "trader2" } } -- hatch 0.3, charm +8%
		local b = { id = 2, sp = "pebblit", home = hut, work = 0, muts = { "grower4" } }
		table.insert(p.pals, a)
		local i1 = Island.isle(p)
		T.near(i1.hatch, 0.7, 1e-9, "Hatchery eggs 30% sooner")
		T.near(i1.charmPct, 0.08, 1e-9)
		table.insert(p.pals, b)
		T.near(Island.isle(p).hatch, 0.7 * 0.7, 1e-9, "a second takes 30% off what is left: diminishing")
		for k = 3, 12 do
			table.insert(p.pals, { id = k, sp = "pebblit", home = hut, work = 0, muts = { "grower4", "trader4" } })
		end
		local full = Island.isle(p)
		T.near(full.hatch, Tuning.HatchMin, 1e-9, "never below HatchMin")
		T.near(full.charmPct, math.min(Tuning.IsleCap.charmPct, 0.08 + 10 * 0.22), 1e-9)
		-- charm: flat charm and the share (2026-11-19: "a percentage boost to charm, while keeping some as a flat boost")
		local flat = Island.isle(p).charm
		T.near(Island.charm(p), flat * (1 + full.charmPct), 1e-6)
		-- nobody in a hut: nothing counts
		for _, x in p.pals do
			x.home = 0
		end
		T.eq(Island.isle(p).hatch, 1)
		T.eq(Island.isle(p).charmPct, 0)
	end)
	T.it("the wondrous mutations: all shells, work for all, more eggs, rarer hatches, offline shells, each capped", function()
		local p = fresh()
		local hut = put(p, "nest")
		local farm = put(p, "patch")
		local x = { id = 1, sp = "pebblit", home = hut, work = farm, muts = {} }
		table.insert(p.pals, x)
		local plain = Island.rates(p).shells
		local made = Island.output(p)[farm]
		x.muts = { "golden5" }
		T.near(Island.rates(p).shells, plain * 1.15, 1e-6, "Goldtouched: every shell +15%")
		x.muts = { "maestro5" }
		T.truthy(Island.output(p)[farm] > made, "Maestro: every worker better")
		x.muts = { "twin5", "prism5", "dream5" }
		local i = Island.isle(p)
		T.eq(i.eggs, 1)
		T.near(i.skip, 0.06, 1e-9)
		T.near(i.away, 0.5, 1e-9)
		for k = 2, 9 do
			table.insert(p.pals, { id = k, sp = "pebblit", home = hut, work = 0, muts = { "twin5", "golden5" } })
		end
		T.eq(Island.isle(p).eggs, Tuning.IsleCap.eggs, "capped")
		T.near(Island.isle(p).all, Tuning.IsleCap.all, 1e-9)
	end)
	T.it("a timed shells boost (a reward): every shell more while it runs, running down while the player is here", function()
		local p = fresh()
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 1, sp = "pebblit", home = hut, work = put(p, "patch") })
		local plain = Island.rates(p).shells
		p.boosts.shells = 60
		T.near(Island.rates(p).shells, plain * (1 + Tuning.TimedShells), 1e-6)
		Island.step(p, 30)
		T.near(p.boosts.shells, 30, 1e-9)
		Island.step(p, 31)
		T.eq(p.boosts.shells, nil, "run out")
		T.near(Island.rates(p).shells, plain, 1e-6)
	end)
	T.it("expanding: every building stays on the bigger island (moved over where the coast changed), nothing lost", function()
		local Plot = require("../../build/luautest/shared/Logic/Plot")
		local Street = require("../../build/luautest/shared/Data/Street")
		local p = fresh()
		-- the small island filled from its edges in: pieces right up to its coast
		local r = Street.plot(1)
		for _, id in { "patch", "stall", "flowers", "lumber", "pier", "nest", "bush", "torch" } do
			local done = false
			for z = r.z1, r.z0, -1 do
				for x = r.x1, r.x0, -1 do
					if not done and Plot.fits(1, p.plot.placed, id, x, z, 0) then
						T.truthy(Plot.place(p, id, x, z, 0))
						done = true
					end
				end
			end
		end
		local hut = 0
		for _, q in p.plot.placed do
			if q.id == "nest" then
				hut = q.uid
			end
		end
		local x = worker(p, "farm", hut, p.plot.placed[1].uid)
		x.pin = true -- (placed by hand: the arrangement leaves it be)
		local before = #p.plot.placed
		local shells = p.shells
		local ok, data = Island.expand(p)
		T.truthy(ok)
		T.eq(#p.plot.placed, before, "none lost")
		T.eq(data.cleared, 0)
		T.eq(p.shells, shells - (Island.expandCost(1) :: any).shells, "nothing refunded")
		local rest = {}
		for _, q in p.plot.placed do
			T.truthy(Plot.fits(p.tier, rest, q.id, q.x, q.z, q.rot), q.id .. " fits the bigger island")
			table.insert(rest, q)
		end
		T.eq(x.work, p.plot.placed[1].uid, "the worker placed by hand keeps its place (the uid stays)")
		-- the third tier too
		T.truthy(Island.expand(p))
		rest = {}
		for _, q in p.plot.placed do
			T.truthy(Plot.fits(p.tier, rest, q.id, q.x, q.z, q.rot), q.id .. " fits the biggest island")
			table.insert(rest, q)
		end
	end)
end
