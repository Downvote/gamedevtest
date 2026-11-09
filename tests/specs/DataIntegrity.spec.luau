-- The content tables agree with each other and with Tuning (GAME_DESIGN 4, 5, 9).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local IdeasData = require("../../build/luautest/shared/Data/Ideas")
local Modifiers = require("../../build/luautest/shared/Data/Modifiers")
local Office = require("../../build/luautest/shared/Data/Office")
local Palette = require("../../build/luautest/shared/Data/Palette")
local Looks = require("../../build/luautest/shared/Data/Looks")
local Street = require("../../build/luautest/shared/Data/Street")
local Decor = require("../../build/luautest/shared/Data/Decor")
return function()
	T.it("ideas: unique ids, names, kinds, odds, engines, words, colours", function()
		local seen = {}
		local engines = { bombs = 1, collect = 1, tiles = 1, quiz = 1, sweep = 1, sumo = 1, zone = 1, barrage = 1, horde = 1, sneak = 1, paint = 1 }
		local used: { [string]: number } = {}
		for _, d in IdeasData.list do
			T.truthy(not seen[d.id] and string.match(d.id, "^%w+$") ~= nil, d.id)
			seen[d.id] = true
			T.truthy(#d.name > 0 and (d.kind == "Genre" or d.kind == "Theme"), d.id .. " name and kind")
			T.truthy(d.odds >= 2 and d.odds == math.floor(d.odds), d.id .. " odds")
			T.truthy(engines[d.micro] ~= nil and #d.variant > 0 and #d.word > 0, d.id .. " microgame")
			T.truthy(d.reuse >= 0 and d.reuse <= 2, d.id .. " reuse")
			T.truthy(#d.words >= 2, d.id .. " title words")
			T.truthy(Palette.ui[d.color] or Palette.colors[d.color] or Palette.axis[d.color], d.id .. " colour")
			used[d.micro] = (used[d.micro] or 0) + 1
		end
		T.eq(#IdeasData.list, 24)
		for e in engines do
			T.truthy((used[e] or 0) >= 1, "engine " .. e .. " used")
		end
		-- an idea that shares its engine with a commoner one plays it harder (GAME_DESIGN 5)
		local first: { [string]: number } = {}
		for _, d in IdeasData.list do
			if first[d.micro] then
				T.truthy(d.reuse >= 1, d.id .. " reuses " .. d.micro .. " a step harder")
			else
				first[d.micro] = d.odds
			end
		end
	end)
	T.it("modifiers: Plain first, rarer ones pay more, known effects", function()
		local effects = { speed = true, ice = true, rival = true, more = true, shrink = true }
		T.eq(Modifiers.list[1].id, "plain")
		T.eq(Modifiers.list[1].odds, 1)
		for i, m in Modifiers.list do
			if i > 1 then
				T.truthy(m.odds > Modifiers.list[i - 1].odds and m.mult > Modifiers.list[i - 1].mult, m.id .. " rarer pays more")
				T.truthy(#m.effects >= 1, m.id .. " changes play")
			end
			for _, e in m.effects do
				T.truthy(effects[e], m.id .. " effect " .. e)
			end
			T.truthy(Palette.ui[m.color] or Palette.colors[m.color] or Palette.axis[m.color], m.id .. " colour")
		end
	end)
	T.it("tiers: names and colours for every tier", function()
		T.eq(#Tuning.TierNames, #Tuning.TierOneIn + 1)
		T.eq(#Tuning.TierColors, #Tuning.TierNames)
		for i = 2, #Tuning.TierOneIn do
			T.truthy(Tuning.TierOneIn[i] > Tuning.TierOneIn[i - 1])
		end
	end)
	T.it("offices: a plan per tier, desks for the idea team, everything inside the room", function()
		T.truthy(#Office.plans >= 1)
		T.truthy(#Office.plans[1].desks >= Tuning.TeamSize, "the garage seats the idea team")
		for i, plan in Office.plans do
			T.eq(plan.tier, i)
			T.truthy(Palette.themes[plan.theme] ~= nil, plan.name .. " theme")
			local hw, hd = Office.DESK_W / 2, Office.DESK_D / 2
			for k, a in plan.desks do
				T.truthy(a.x - hw >= plan.minX and a.x + hw <= plan.maxX and a.z - Office.SEAT_BACK - 0.8 >= plan.minZ and a.z + hd <= plan.maxZ, plan.name .. " desk " .. k .. " inside")
				for j, b in plan.desks do
					if j > k then
						local apart = math.abs(a.x - b.x) >= Office.DESK_W + 0.5 or math.abs(a.z - b.z) >= Office.DESK_D + Office.SEAT_BACK + 0.9
						T.truthy(apart, plan.name .. " desks " .. k .. " and " .. j .. " apart")
					end
				end
			end
			for _, p in plan.props do
				T.truthy(p.x >= plan.minX and p.x <= plan.maxX and p.z >= plan.minZ and p.z <= plan.maxZ, plan.name .. " " .. p.kind .. " inside")
			end
			T.truthy(#Office.outlinePts(i, 0, 0) == #plan.OUTLINE * 24)
		end
	end)
	T.it("looks: palette keys", function()
		for _, list in { Looks.skin, Looks.hair, Looks.shirt } do
			for _, k in list do
				T.truthy(Palette.colors[k] ~= nil, k)
			end
		end
		for _, a in { "fun", "ideas", "graphics", "sound" } do
			T.truthy(Palette.axis[a] ~= nil, a)
		end
	end)
	T.it("the street: plots inside their lots, the office on its plot, the door's path to the road", function()
		T.eq(Street.MAX, Tuning.MaxPlots)
		local lot = Street.LOT
		for tier = 1, #Office.plans do
			local p = Street.plot(tier)
			local plan = Office.plan(tier)
			T.truthy(p.x0 >= lot.x0 and p.x1 <= lot.x1 and p.z0 >= lot.z0 and p.z1 <= lot.z1, "plot " .. tier .. " inside the lot")
			T.truthy(p.z1 == Street.PAVE_N.z0, "plot " .. tier .. " runs down to the pavement")
			T.truthy(plan.minX - Office.WALL_T > p.x0 and plan.maxX < p.x1 and plan.minZ - Office.WALL_T > p.z0 and plan.maxZ < p.z1, "office " .. tier .. " on its plot")
			if tier > 1 then
				local q = Street.plot(tier - 1)
				T.truthy(p.x0 <= q.x0 and p.x1 >= q.x1 and p.z0 <= q.z0, "plot " .. tier .. " grows")
			end
			local fp = Street.footpath(plan.maxX, plan.maxZ)
			T.truthy(fp.z0 == plan.maxZ and fp.z1 == Street.PAVE_N.z0 and fp.x0 > plan.minX and fp.x1 < plan.maxX, "path " .. tier)
			local sx = Street.sign(plan.maxX, plan.maxZ)
			local mx = Street.mailbox(plan.maxX, plan.maxZ)
			T.truthy(sx - 1.5 > p.x0 and mx + 0.75 < p.x1, "sign and mailbox on plot " .. tier)
		end
		T.truthy(Street.ROAD.z0 == Street.PAVE_N.z1 and Street.ROAD.z1 == Street.PAVE_S.z0 and Street.VERGE.z0 == Street.PAVE_S.z1)
		-- neighbouring lots meet edge to edge, plot origins in a row centred on x = 0
		local a = Street.origin(1)
		local b = Street.origin(2)
		T.eq(b - a, Street.SPACING)
		T.eq(lot.x1 - lot.x0, Street.SPACING)
		T.eq(Street.origin(1) + Street.origin(Street.MAX), 0)
		for i = 1, Street.MAX do
			local ox, oz = Street.origin(i)
			T.eq(Street.plotAt(ox + 1, oz + 1), i)
		end
		T.eq(Street.plotAt(0, 200), 0)
	end)
	T.it("decor: unique ids, prices, footprints", function()
		local seen = {}
		for _, d in Decor.list do
			T.truthy(not seen[d.id], d.id)
			seen[d.id] = true
			T.truthy(d.price > 0 and d.w >= 1 and d.d >= 1 and d.w == math.floor(d.w) and d.d == math.floor(d.d), d.id)
		end
	end)
end
