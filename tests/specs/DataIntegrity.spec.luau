-- The content tables agree with each other and with Tuning (GAME_DESIGN 5-7).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Genres = require("../../build/luautest/shared/Data/Genres")
local Topics = require("../../build/luautest/shared/Data/Topics")
local Matches = require("../../build/luautest/shared/Data/Matches")
local Platforms = require("../../build/luautest/shared/Data/Platforms")
local Critics = require("../../build/luautest/shared/Data/Critics")
local Office = require("../../build/luautest/shared/Data/Office")
local Palette = require("../../build/luautest/shared/Data/Palette")
local Looks = require("../../build/luautest/shared/Data/Looks")
local Street = require("../../build/luautest/shared/Data/Street")
local Decor = require("../../build/luautest/shared/Data/Decor")
return function()
	T.it("genres and topics: unique ids, names, tiers with a cost, five title words", function()
		for _, list in { Genres.list, Topics.list } do
			local seen = {}
			for _, d in list :: { any } do
				T.truthy(not seen[d.id], "unique " .. d.id)
				seen[d.id] = true
				T.truthy(#d.name > 0 and #d.words == 5, d.id)
				T.truthy(d.tier >= 1 and d.tier <= 3, d.id .. " tier")
			end
		end
		T.eq(#Genres.list, 10)
		T.eq(#Topics.list, 14)
		T.truthy(Palette.colors[Genres.byId.action.color] ~= nil)
		for _, g in Genres.list do
			T.truthy(Palette.colors[g.color] ~= nil, g.id .. " colour")
		end
	end)
	T.it("matches: every genre, real topics, no topic twice", function()
		for _, g in Genres.list do
			local m = Matches.byGenre[g.id]
			T.truthy(m ~= nil, g.id)
			local seen = {}
			for _, list in { m.great, m.good, m.poor } do
				for _, t in list do
					T.truthy(Topics.byId[t] ~= nil, g.id .. ": " .. t)
					T.truthy(not seen[t], g.id .. ": " .. t .. " once")
					seen[t] = true
				end
			end
			T.truthy(#m.great >= 2, g.id .. " has great topics")
		end
		for g in Matches.byGenre do
			T.truthy(Genres.byId[g] ~= nil, "match table genre " .. g)
		end
	end)
	T.it("platforms: real genres, a PC from year 1, colours", function()
		T.eq(Platforms.list[1].id, "pc")
		T.eq(Platforms.list[1].from, 1)
		T.eq(Platforms.list[1].licence, 0)
		for _, p in Platforms.list do
			for _, g in p.loves do
				T.truthy(Genres.byId[g] ~= nil, p.id .. " loves " .. g)
			end
			T.truthy(p.to == 0 or p.to > p.from, p.id .. " years")
			T.truthy(Palette.colors[p.color] ~= nil and Palette.colors[p.accent] ~= nil, p.id .. " colours")
		end
	end)
	T.it("critics: one per score", function()
		local seen = {}
		for _, c in Critics.list do
			seen[c.axis] = true
		end
		T.eq(#Critics.list, 4)
		T.truthy(seen.fun and seen.ideas and seen.graphics and seen.sound)
	end)
	T.it("offices: one plan per Tuning office, its desks, everything inside the room", function()
		T.eq(#Office.plans, #Tuning.Offices)
		for i, plan in Office.plans do
			T.eq(plan.tier, i)
			T.eq(#plan.desks, Tuning.Offices[i].desks, plan.name .. " desks")
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
		T.truthy(Tuning.Offices[1].cost == 0 and Tuning.Offices[1].fans == 0)
		for i = 2, #Tuning.Offices do
			T.truthy(Tuning.Offices[i].desks > Tuning.Offices[i - 1].desks and Tuning.Offices[i].cost > Tuning.Offices[i - 1].cost)
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
		for tier = 1, #Tuning.Offices do
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
	T.it("decor: unique ids, prices, fans, footprints, offices", function()
		local seen = {}
		for _, d in Decor.list do
			T.truthy(not seen[d.id], d.id)
			seen[d.id] = true
			T.truthy(d.price > 0 and d.fans > 0 and d.w >= 1 and d.d >= 1 and d.w == math.floor(d.w) and d.d == math.floor(d.d), d.id)
			T.truthy(d.office >= 1 and d.office <= #Tuning.Offices, d.id .. " office")
		end
	end)
end
