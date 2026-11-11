-- The wild places on the island (Data/Sites, Logic/Sites, Logic/Plot's rings; GAME_DESIGN 7): a new island's first
-- ones, each expansion's (higher in level), where they come up, the ring round a wild one that nothing new may enter,
-- and a cleared one as an ordinary piece.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Island = require("../../build/luautest/shared/Logic/Island")
local Sites = require("../../build/luautest/shared/Logic/Sites")
local SiteData = require("../../build/luautest/shared/Data/Sites")
local Street = require("../../build/luautest/shared/Data/Street")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

local function overlaps(a: any, b: any): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end

local function wilds(p: any): { any }
	local out = {}
	for _, q in p.plot.placed do
		if Plot.isSite(q.id) then
			table.insert(out, q)
		end
	end
	return out
end

-- Every wild place stands whole on the buildable grass, off the plaza and the path, its ring clear of the others'.
local function sound(p: any, label: string)
	local ws = wilds(p)
	for i, q in ws do
		local r = Plot.rect(q.id, q.x, q.z, q.rot)
		for z = r.z0, r.z1 - 1 do
			for x = r.x0, r.x1 - 1 do
				T.truthy(Street.buildable(p.tier, x, z), label .. ": " .. q.id .. " on the grass")
			end
		end
		T.truthy(not overlaps(r, Street.PLAZA) and not overlaps(r, Street.PATH), label .. ": off the plaza and the path")
		for j, o in ws do
			if j > i then
				T.truthy(not overlaps(Plot.zone(q), Plot.zone(o)), label .. ": rings apart")
			end
		end
	end
end

return function()
	T.it("a new island: a tide pool and some tall grass, low in level, on the grass and apart; the same seed, the same", function()
		local p = Schema.default(0, 1)
		local ws = wilds(p)
		T.eq(#ws, 2)
		T.eq(ws[1].id, SiteData.wildId("tidepool"))
		T.eq(ws[1].lvl, 1)
		T.eq(ws[2].id, SiteData.wildId("tallgrass"))
		T.eq(ws[2].lvl, 3)
		T.eq(p.wilds, 1)
		sound(p, "new")
		T.deepEq(Schema.default(0, 1).plot.placed, p.plot.placed, "the same seed, the same places")
		local other = Schema.default(0, 2)
		T.truthy(other.plot.placed[1].x ~= ws[1].x or other.plot.placed[1].z ~= ws[1].z or other.plot.placed[2].x ~= ws[2].x, "another seed, other spots")
		T.eq(#Sites.spawn(p), 0, "nothing more till the island grows")
		-- a wild place isn't counted in the piece limit
		T.eq((Plot.used(p, "patch")), 0)
	end)
	T.it("each expansion brings more, higher in level, on the land gained; every kind turns up", function()
		local p = Schema.default(0, 3)
		p.shells, p.wood = 1e9, 1e9
		local kinds: { [string]: boolean } = {}
		local top = 0
		for _, q in wilds(p) do
			top = math.max(top, q.lvl)
		end
		for t = 2, #Tuning.TierCost do
			local before = #wilds(p)
			local ok, data = Island.expand(p)
			T.truthy(ok)
			T.eq(p.wilds, t)
			local fresh = {}
			for i = before + 1, #wilds(p) do
				table.insert(fresh, wilds(p)[i])
			end
			T.eq(data.sites, #fresh)
			T.eq(#fresh, #SiteData.spawnAt(t), "tier " .. t .. ": all of its places came up")
			for _, q in fresh do
				T.truthy(q.lvl > top, string.format("tier %d: higher (%d over %d)", t, q.lvl, top))
			end
			for _, q in fresh do
				top = math.max(top, q.lvl)
			end
			sound(p, "tier " .. t)
		end
		for _, q in wilds(p) do
			local sd = SiteData.of(q.id)
			kinds[(sd :: any).id] = true
		end
		for _, sd in SiteData.list do
			T.truthy(kinds[sd.id], sd.id .. " turned up")
		end
	end)
	T.it("the ring: nothing new inside it (pieces, paths); a wild place can't be moved, cleared away, bought or replaced", function()
		local p = Schema.default(0, 1)
		p.shells, p.wood = 1e6, 1e6
		local q = wilds(p)[1]
		local i = table.find(p.plot.placed, q) :: number
		local zr = Plot.zone(q)
		-- a patch just inside the ring's edge, then just outside it
		local inside, outside = nil, nil
		for z = zr.z0 - 4, zr.z1 + 3 do
			for x = zr.x0 - 4, zr.x1 + 3 do
				local okIn, why = Plot.fits(p.tier, p.plot.placed, "flowers", x, z, 0)
				if not okIn and why == "wild" and inside == nil then
					inside = { x, z }
				end
				if okIn and outside == nil then
					outside = { x, z }
				end
			end
		end
		T.truthy(inside ~= nil, "a spot in the ring")
		T.truthy(outside ~= nil, "a spot outside it")
		local inn = inside :: { number }
		T.eq(select(2, Plot.place(p, "flowers", inn[1], inn[2], 0)), "wild", "refused inside the ring")
		T.truthy(Plot.fits(p.tier, p.plot.placed, "flowers", inn[1], inn[2], 0, nil, true), "it would fit but for the ring")
		local cell: { number }? = nil
		for z = zr.z0 - 4, zr.z1 + 3 do
			for x = zr.x0 - 4, zr.x1 + 3 do
				if cell == nil and x % 2 == 0 and z % 2 == 0 and select(2, Plot.fits(p.tier, p.plot.placed, "dirtpath", x, z, 0)) == "wild" then
					cell = { x, z }
				end
			end
		end
		T.eq(select(2, Plot.paint(p, "dirtpath", { cell :: { number } })), "wild", "no path in it either")
		T.eq(select(2, Plot.move(p, i, q.x + 1, q.z, 0)), "wild", "a wild place stays put")
		T.eq(select(2, Plot.store(p, i)), "wild", "and can't be cleared away")
		T.eq(select(2, Plot.place(p, q.id, 0, 0, 0)), "bad_payload", "never bought")
		T.eq(#Plot.replacements(q, 6), 0, "nothing replaces it")
		T.eq(select(2, Plot.replace(p, i, SiteData.wildId("cave"))), "bad_payload")
		-- cleared: the ring is gone, it moves and clears away like any piece (for nothing back)
		local sd = SiteData.of(q.id) :: any
		q.id = SiteData.doneId(sd.id)
		T.truthy(Plot.fits(p.tier, p.plot.placed, "flowers", inn[1], inn[2], 0), "the ring gone")
		T.truthy(Buildings.byId[q.id].charm > 0, "a cleared place adds charm")
		local spotX, spotZ = nil, nil
		local land = Street.plot(p.tier)
		for z = math.floor(land.z0), math.floor(land.z1) do
			for x = math.floor(land.x0), math.floor(land.x1) do
				if spotX == nil and (x ~= q.x or z ~= q.z) and Plot.fits(p.tier, p.plot.placed, q.id, x, z, 0, i) then
					spotX, spotZ = x, z
				end
			end
		end
		T.truthy(Plot.move(p, i, spotX :: number, spotZ :: number, 0), "moved")
		local shells = p.shells
		T.truthy(Plot.store(p, i), "cleared away")
		T.eq(p.shells, shells, "for nothing back")
	end)
	T.it("standing pieces are never moved by a ring; a crowded island passes over a place with no room", function()
		local p = Schema.default(0, 1)
		p.shells, p.wood = 1e9, 1e9
		-- fill the island with flower beds wherever they fit (rings aside)
		local land = Street.plot(p.tier)
		for z = math.floor(land.z0), math.floor(land.z1) do
			for x = math.floor(land.x0), math.floor(land.x1) do
				if Plot.fits(p.tier, p.plot.placed, "flowers", x, z, 0, nil, true) then
					table.insert(p.plot.placed, { uid = p.nextId, id = "flowers", x = x, z = z, rot = 0, lvl = 1 })
					p.nextId += 1
				end
			end
		end
		local n = #p.plot.placed
		local moved, cleared = Plot.refit(p)
		T.eq(moved, 0, "nothing moved")
		T.eq(cleared, 0)
		p.wilds = 0 -- (as an older save would come in)
		local before = #wilds(p)
		Sites.spawn(p)
		T.eq(#p.plot.placed, n + (#wilds(p) - before), "only what fitted came up")
		T.eq(p.wilds, 1)
	end)
end
