-- tests/specs/Weather.spec.luau: the seasons and the weather (Data/Weather, Logic/Weather; GAME_DESIGN 13, the request
-- of 2026-11-14: "also, make weather and seasons, and eggs spawns are affected by these with different mutations"):
-- the seasons come round in order on the sea's clock, a spell never crosses a season's end, every spell's weather is
-- one of its season's own and the odds hold over many spells, no storm runs twice, the same clock gives the same
-- weather; eggs laid in a weather are touched about as often as Tuning says and only by weathers with a mutation,
-- storms touch at tier 2 or better; the weather families never come from a plain roll; and the tree's eggs carry
-- their weather into the driftling that hatches.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Data = require("../../build/luautest/shared/Data/Weather")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Weather = require("../../build/luautest/shared/Logic/Weather")
local Tree = require("../../build/luautest/shared/Logic/Tree")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Util = require("../../build/luautest/shared/Logic/Util")

local E = Tuning.WeatherEpoch

return function()
	T.it("the seasons come round in order, each SeasonSecs long", function()
		local order = {}
		for i, s in Data.SEASONS do
			order[s.id] = i
		end
		local last = nil
		for k = 0, 11 do
			local t = E + k * Tuning.SeasonSecs + 1
			local sid, left = Weather.season(t)
			T.near(left, Tuning.SeasonSecs - 1, 1e-6, "time left at the start of season " .. k)
			if last then
				T.eq(order[sid], order[last] % #Data.SEASONS + 1, "the next season")
			end
			last = sid
		end
		T.eq(Tuning.SeasonSecs % Tuning.WeatherSecs, 0, "a whole number of spells a season")
	end)

	T.it("every spell's weather is its season's own, the odds hold, no storm twice running, the same clock agrees", function()
		local tally: { [string]: { [string]: number } } = {}
		local spells: { [string]: number } = {}
		local prev = ""
		for k = 0, 40000 do
			local t = E + k * Tuning.WeatherSecs + 7
			local st = Weather.at(t)
			local again = Weather.at(t)
			T.truthy(st.kind == again.kind and st.season == again.season, "deterministic")
			local own = false
			for _, o in Data.seasonById[st.season].odds do
				own = own or o.kind == st.kind
			end
			T.truthy(own, st.kind .. " is a " .. st.season .. " weather")
			T.truthy(not (prev == "storm" and st.kind == "storm"), "no storm twice running")
			prev = st.kind
			T.truthy(st.kindLeft > 0 and st.kindLeft <= Tuning.WeatherSecs, "time left in the spell")
			T.truthy(st.kindLeft <= st.seasonLeft + 1e-6, "a spell ends by its season's end")
			tally[st.season] = tally[st.season] or {}
			tally[st.season][st.kind] = (tally[st.season][st.kind] or 0) + 1
			spells[st.season] = (spells[st.season] or 0) + 1
		end
		for _, s in Data.SEASONS do
			local total = 0
			for _, o in s.odds do
				total += o.w
			end
			for _, o in s.odds do
				local want = o.w / total
				local got = (tally[s.id][o.kind] or 0) / spells[s.id]
				-- (a storm after a storm becomes the season's first kind: storms a little rarer, that one a little commoner)
				T.truthy(math.abs(got - want) < 0.05, string.format("%s %s: %.3f vs %.3f", s.id, o.kind, got, want))
			end
		end
	end)

	T.it("an egg is touched about as often as Tuning says, only by a weather with a mutation, storms at tier 2 or more", function()
		local rng = Util.newRng(99)
		for _, def in Data.KINDS do
			local st = { season = "spring", seasonLeft = 100, kind = def.id, kindLeft = 100, spell = 0, year = 0 }
			local n, touched, low = 20000, 0, 9
			for i = 1, n do
				local kind, tier = Weather.touch(rng, st, (i % 5) + 1)
				if kind then
					touched += 1
					T.eq(kind, def.id)
					T.truthy(tier ~= nil and tier >= 1 and tier <= 4, "a tier 1 .. 4")
					low = math.min(low, tier :: number)
					T.truthy(Weather.mutation(kind, tier) ~= nil, "its mutation exists")
				end
			end
			local want = Tuning.WeatherTouch[def.id] or 0
			if def.family == nil then
				T.eq(touched, 0, def.id .. " touches no egg")
			else
				T.truthy(math.abs(touched / n - want) < 0.02, string.format("%s: %.3f vs %.3f", def.id, touched / n, want))
			end
			if def.id == "storm" then
				T.truthy(low >= 2, "a storm's mutations are tier 2 or more")
			end
		end
		T.eq(Weather.touch(rng, nil, 3), nil, "no weather, no touch")
		T.eq(Weather.luck(nil), 0)
		T.truthy(Weather.luck({ season = "summer", seasonLeft = 1, kind = "storm", kindLeft = 1, spell = 0, year = 0 }) > 0, "a storm adds luck")
	end)

	T.it("the weather families: four tiers each, better as they go, never in a plain roll", function()
		T.truthy(#Traits.weather >= 6, "a family for each touching weather")
		local fams: { [string]: boolean } = {}
		for _, f in Traits.weather do
			fams[f.family] = true
			T.truthy(Data.byId[f.weather] and Data.byId[f.weather].family == f.family, f.family .. " is its weather's")
			for tier = 1, 4 do
				local m = Traits.byId[f.family .. tier]
				T.truthy(m ~= nil and m.tier == tier and m.blurb ~= "", f.family .. tier)
				if tier > 1 then
					T.truthy(math.abs(m.fx[f.key]) > math.abs(Traits.byId[f.family .. (tier - 1)].fx[f.key]), "tier " .. tier .. " beats " .. (tier - 1))
				end
			end
		end
		local rng = Util.newRng(5)
		for _ = 1, 4000 do
			for _, id in Traits.roll(rng, rng:int(1, 5)) do
				T.truthy(not fams[Traits.byId[id].family], "a plain roll has no weather mutation")
			end
		end
	end)

	T.it("the tree's eggs: laid in a weather they keep its season and maybe its touch, and hatch with its mutation", function()
		local p = Schema.default(0, 7)
		p.stats.taken = 3 -- (not a new island: no tips' commons)
		p.shells = 1e9
		p.tier = 3
		table.insert(p.plot.placed, { uid = 900, id = "nest", x = 6, z = 6, rot = 0 })
		local rng = Util.newRng(31)
		local wx = { season = "winter", seasonLeft = 999, kind = "snow", kindLeft = 300, spell = 1, year = 0 }
		local touched, laid = 0, 0
		for _ = 1, 300 do
			for _, e in Tree.lay(p, rng, wx) do
				laid += 1
				T.eq(e.ss, "winter", "the season it was laid in")
				if e.wx then
					touched += 1
					T.eq(e.wx, "snow")
				end
			end
		end
		T.truthy(math.abs(touched / laid - Tuning.WeatherTouch.snow) < 0.04, string.format("touched %.3f", touched / laid))
		-- the view and the save keep it
		local egg = nil
		for _, e in p.clutch.list do
			if e.wx then
				egg = e
			end
		end
		T.truthy(egg ~= nil, "a touched egg in the last lot")
		local seen = nil
		for _, v in Tree.view(p) do
			if v.id == egg.id then
				seen = v
			end
		end
		T.truthy(seen ~= nil and seen.wx == "snow" and seen.wt == egg.wt and seen.ss == "winter", "the client sees its weather")
		local again = Schema.reconcile(Schema.migrate(table.clone(p)), 0, 7)
		local back = nil
		for _, e in again.clutch.list do
			if e.id == egg.id then
				back = e
			end
		end
		T.truthy(back ~= nil and back.wx == "snow" and back.wt == egg.wt and back.ss == "winter", "a save keeps its weather")
		-- hatching it: the driftling has the snow's mutation at the egg's tier
		local want = Weather.mutation(egg.wx, egg.wt)
		local ok, data = Tree.hatch(p, egg.id, 0, rng)
		T.truthy(ok, "hatched: " .. tostring(data))
		T.truthy(data.wm == want and table.find(data.muts, want) ~= nil, "with the weather's mutation " .. tostring(want))
		T.truthy(#data.muts <= Traits.MAX, "never more than MAX")
		-- a lot laid with no weather (the career, an old server) touches nothing
		for _ = 1, 20 do
			for _, e in Tree.lay(p, rng, nil) do
				T.truthy(e.wx == nil and e.ss == nil, "no weather: a plain egg")
			end
		end
	end)

	T.it("a new island's first lot keeps its two plain commons; the season's kinds come more often", function()
		local p = Schema.default(0, 9)
		local rng = Util.newRng(3)
		local laid = Tree.lay(p, rng, { season = "spring", seasonLeft = 9, kind = "rain", kindLeft = 9, spell = 0, year = 0 })
		local plain = 0
		for _, e in laid do
			if e.r == 1 and e.wx == nil and e.ss == nil then
				plain += 1
			end
		end
		T.truthy(plain >= 2, "the tips' two commons, untouched")
		-- winter favours the snowfield's and the grotto's kinds
		local q = Schema.default(0, 11)
		q.tier = 6
		local Creatures = require("../../build/luautest/shared/Data/Creatures")
		local fav, plainFav = 0, 0
		local r2 = Util.newRng(77)
		for _ = 1, 3000 do
			local sp = Tree.roll(q, r2, 1, nil, "winter")
			local isl = Creatures.byId[sp].islet
			if isl == 4 or isl == 7 then
				fav += 1
			end
			local sp2 = Tree.roll(q, r2, 1, nil, nil)
			local isl2 = Creatures.byId[sp2].islet
			if isl2 == 4 or isl2 == 7 then
				plainFav += 1
			end
		end
		T.truthy(fav > plainFav * 1.4, string.format("winter's kinds: %d with the season, %d without", fav, plainFav))
	end)

	T.it("the status lines' words for time left", function()
		T.eq(Weather.left(3 * 3600 - 5), "3 h")
		T.eq(Weather.left(2 * 3600), "2 h")
		T.eq(Weather.left(2 * 3600 + 1), "2 h 1 min")
		T.eq(Weather.left(90 * 60), "1 h 30 min")
		T.eq(Weather.left(59 * 60 + 1), "1 h")
		T.eq(Weather.left(45 * 60), "45 min")
		T.eq(Weather.left(5), "1 min")
		T.eq(Weather.left(-3), "1 min")
	end)
end
