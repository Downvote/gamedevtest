-- A sensible player for the Economy spec and the tuning runs: plays a career through Logic/Studio (the server's own
-- rules) and logs what happened year by year.
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Studio = require("../build/luautest/shared/Logic/Studio")
local Minigames = require("../build/luautest/shared/Logic/Minigames")
local Dev = require("../build/luautest/shared/Logic/Dev")
local Crew = require("../build/luautest/shared/Logic/Crew")
local Calendar = require("../build/luautest/shared/Logic/Calendar")
local Util = require("../build/luautest/shared/Logic/Util")
local Genres = require("../build/luautest/shared/Data/Genres")
local Topics = require("../build/luautest/shared/Data/Topics")

local Career = {}

local MATCH_RANK = { great = 4, good = 3, okay = 2, poor = 1 }

-- the best open pair the player has not just made (they read the notebook, and guess "good" for pairs not tried)
local function pickPair(p): (string, string)
	local best, bg, bt = -1, "action", "space"
	for g in p.genres do
		for t in p.topics do
			local known = p.matches[Dev.matchKey(g, t)]
			local rank = if known then MATCH_RANK[known] else 2.5
			if Dev.novelty(g, t, p.releases) < 1 then
				rank -= 2
			end
			rank += (Util.hash32(g .. t .. p.week) % 100) / 1000
			if rank > best then
				best, bg, bt = rank, g, t
			end
		end
	end
	return bg, bt
end

-- `mini`: the score this player gets in every minigame (GAME_DESIGN 14), or nil for one who never plays them.
function Career.play(seed: number, years: number, log: ((string) -> ())?, mini: number?)
	local p = Schema.default(0, seed)
	local rng = Util.newRng(seed * 7 + 1)
	local polishWeeks = 0
	local yearly = {}
	local minMoney = math.huge
	local function say(s: string)
		if log then
			log(s)
		end
	end
	while Calendar.year(p.week) <= years do
		local payroll = Crew.payroll(p.staff) + Tuning.Offices[p.office].rent
		-- start a game
		if p.project == nil then
			local g, t = pickPair(p)
			local year = Studio.year(p)
			local plat, bestScore = "pc", -1
			for _, pl in Dev.platformsIn(year) do
				local score = pl.market * Dev.love(pl.id, g)
				if p.money - pl.licence > payroll * 3 + 3000 and score > bestScore then
					plat, bestScore = pl.id, score
				end
			end
			local size = "small"
			if #p.staff >= 3 and p.money > Dev.startCost("medium", plat) + payroll * 4 then
				size = "medium"
			end
			if #p.staff >= 5 and p.money > Dev.startCost("large", plat) + payroll * 5 then
				size = "large"
			end
			local ok = Studio.start(p, { genre = g, topic = t, platform = plat, size = size, focus = "fun", seed = p.week })
			if not ok then
				Studio.start(p, { genre = g, topic = t, platform = "pc", size = "small", focus = "fun", seed = p.week })
			end
			polishWeeks = 0
		end
		-- release once the bugs are gone or after a few weeks of polish
		local proj = p.project
		if proj and proj.phase == "polish" then
			polishWeeks += 1
			if proj.bugs == 0 or polishWeeks >= 4 then
				local ok, r = Studio.release(p, rng)
				if ok then
					say(string.format("  %s: %s %s/%s on %s (%s) reviews %d %d %d %d = %d %s, peak %d", Calendar.label(p.week), r.title, r.genre, r.topic, r.platform, r.size, r.reviews[1], r.reviews[2], r.reviews[3], r.reviews[4], r.total, r.match, r.peak))
				end
			end
		end
		-- hire when there is room and money
		if Crew.freeDesk(p.staff, Studio.desks(p)) and #p.candidates > 0 and p.money > payroll * 6 then
			local bi, bt = 1, -1
			for i, c in p.candidates do
				if Crew.total(c.skills) > bt then
					bi, bt = i, Crew.total(c.skills)
				end
			end
			Studio.hire(p, bi)
		end
		-- research and training
		for _, list in { Genres.list, Topics.list } do
			for _, d in list :: { any } do
				local isGenre = Genres.byId[d.id] ~= nil and list == Genres.list
				local set = if isGenre then p.genres else p.topics
				local cost = if isGenre then Dev.genreCost(d.id) else Dev.topicCost(d.id)
				if not set[d.id] and p.rp >= cost + Tuning.TrainRp then
					if isGenre then
						Studio.unlockGenre(p, d.id)
					else
						Studio.unlockTopic(p, d.id)
					end
				end
			end
		end
		while p.rp >= Tuning.TrainRp * 2 and p.money > payroll * 4 + Tuning.TrainMoney do
			local weakest, wv = p.staff[1], math.huge
			for _, s in p.staff do
				if Crew.total(s.skills) < wv then
					weakest, wv = s, Crew.total(s.skills)
				end
			end
			local low, lk = math.huge, "code"
			for _, k in Crew.SKILLS do
				if (weakest.skills :: any)[k] < low then
					low, lk = (weakest.skills :: any)[k], k
				end
			end
			if not Studio.train(p, weakest.id, lk) then
				break
			end
		end
		-- pizza when tired
		for _, s in p.staff do
			if s.energy < 30 and Studio.canParty(p) and p.money > payroll * 2 then
				Studio.party(p)
				break
			end
		end
		-- move and advertise
		local nextOffice = Tuning.Offices[p.office + 1]
		if nextOffice and p.fans >= nextOffice.fans and p.money > nextOffice.cost + (payroll + nextOffice.rent) * 8 then
			Studio.move(p)
			say(string.format("  %s: moved to office %d", Calendar.label(p.week), p.office))
		end
		if p.money > 60000 * p.office and Studio.canAd(p) then
			Studio.ad(p)
		end
		-- minigames: spend every push (the four scores in turn), squash bugs whenever allowed
		local cur = p.project
		if mini and cur then
			while cur.pushes > 0 do
				local kind = Minigames.PUSH_ORDER[cur.played % #Minigames.PUSH_ORDER + 1]
				Minigames.start(p, kind)
				Minigames.finish(p, kind, mini)
			end
			if Minigames.canStart(p, "bugs") then
				Minigames.start(p, "bugs")
				Minigames.finish(p, "bugs", mini)
			end
		end
		local events = Studio.week(p, rng)
		for _, e in events do
			if e.kind == "award" then
				say(string.format("  awards %d: %s %s (%d)", e.year or 0, e.award or "", e.title or "", e.total or 0))
			end
		end
		minMoney = math.min(minMoney, p.money)
		if Calendar.isYearEnd(p.week - 1) then
			local y = Calendar.year(p.week - 1)
			local sum, n = 0, 0
			for _, r in p.releases do
				if Calendar.year(r.week) == y then
					sum += r.total
					n += 1
				end
			end
			local row = { year = y, money = p.money, fans = p.fans, staff = #p.staff, office = p.office, games = n, avg = if n > 0 then sum / n else 0, rp = p.rp }
			table.insert(yearly, row)
			say(string.format("Y%d money %.0f fans %.0f staff %d office %d games %d avg total %.1f rp %d", y, p.money, p.fans, #p.staff, p.office, n, row.avg, p.rp))
		end
	end
	return { profile = p, yearly = yearly, minMoney = minMoney }
end

return Career
