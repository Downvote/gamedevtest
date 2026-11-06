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
end
