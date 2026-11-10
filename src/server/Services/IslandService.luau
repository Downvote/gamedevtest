--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Expedition) that mark the session dirty and tell the client what
-- happened. The island makes and eats every step (Island.step, those away on an expedition left out); its stores go
-- to the client every second (Fx "tick", so the whole view is not sent every second); a day turns every
-- Tuning.DaySeconds (Island.newDay: a visitor may move in, the yard trains; Fx "day"). Expeditions live in the
-- session: start, the next node, battle rounds, home (Fx "exp" carries each step's events for the client to play).
-- Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Expedition = require(ReplicatedStorage.Shared.Logic.Expedition)
local Session = require(script.Parent.Session)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9): 1 build food, 2 build a home, 3 build a nest and sail, 4 the last tip (OK ends them).
local function tips(s: Session.S)
	local p = s.profile
	if p.tut < 1 or p.tut > 3 then
		return
	end
	local has: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			has[d.kind] = true
		end
	end
	if p.tut == 1 and has.food then
		p.tut = 2
	end
	if p.tut == 2 and has.home then
		p.tut = 3
	end
end

-- An expedition's end: the loot comes home, the party back to work.
local function goHome(s: Session.S): { [string]: any }
	local e = s.exp
	if e == nil then
		return {}
	end
	local got = Expedition.home(s.profile, e)
	Session.setExp(s, nil)
	Session.markDirty(s)
	return { got = got, over = e.over, befriended = e.befriended, isle = e.isle.name }
end

function IslandService.init()
	-- building (GAME_DESIGN 4): every change rebuilds the island's pieces by difference
	local function rebuilt(fn: (s: Session.S, a: any) -> (boolean, any)): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local ok, data = fn(s, a)
			if ok then
				PlotService.buildDecor(s)
				tips(s)
			end
			return ok, data
		end
	end
	Router.on(
		"plot.place",
		rebuilt(function(s, a)
			return Plot.place(s.profile, a.id, a.x, a.z, a.rot)
		end)
	)
	Router.on(
		"plot.move",
		rebuilt(function(s, a)
			return Plot.move(s.profile, a.i, a.x, a.z, a.rot)
		end)
	)
	Router.on(
		"plot.store",
		rebuilt(function(s, a)
			return Plot.store(s.profile, a.i)
		end)
	)
	Router.on(
		"plot.upgrade",
		rebuilt(function(s, a)
			return Plot.upgrade(s.profile, a.i)
		end)
	)
	Router.on("island.expand", function(s, _a)
		local ok, data = Island.expand(s.profile)
		if ok then
			PlotService.build(s)
		end
		return ok, data
	end)
	-- who works where (GAME_DESIGN 5, 6)
	Router.on("folk.work", function(s, a)
		return Island.setWork(s.profile, a.id, a.uid)
	end)
	Router.on("folk.dismiss", function(s, a)
		if s.away["v" .. a.id] then
			return false, "busy"
		end
		return Island.dismiss(s.profile, a.id)
	end)
	Router.on("pal.work", function(s, a)
		return Island.setHelp(s.profile, a.id, a.uid)
	end)
	Router.on("pal.release", function(s, a)
		if s.away["p" .. a.id] then
			return false, "busy"
		end
		return Island.release(s.profile, a.id)
	end)
	-- expeditions (GAME_DESIGN 7)
	Router.on("exp.start", function(s, a)
		if s.exp then
			return false, "busy"
		end
		local members: { string } = {}
		for part in string.gmatch(a.party, "[^,]+") do
			table.insert(members, part)
		end
		-- the island is made up here, from a seed of the server's own
		local ok, e = Expedition.start(s.profile, a.lvl, members, s.rng:int(1, 2147483646))
		if not ok then
			return false, e
		end
		Session.setExp(s, e)
		return true, { isle = e.isle }
	end)
	Router.on("exp.next", function(s, _a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		local ok, data = Expedition.next(s.profile, e, s.rng)
		if ok then
			Session.fx(s, { kind = "exp", step = "node", data = data })
		end
		return ok, data
	end)
	Router.on("exp.act", function(s, a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		local ok, data = Expedition.act(s.profile, e, a.act, if a.target == "" then nil else a.target, s.rng)
		if ok then
			Session.fx(s, { kind = "exp", step = "round", data = data })
		end
		return ok, data
	end)
	Router.on("exp.home", function(s, _a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		if e.battle and not e.over then
			return false, "in_battle"
		end
		local data = goHome(s)
		Session.fx(s, { kind = "exp", step = "home", data = data })
		return true, data
	end)
	-- the founder's look (GAME_DESIGN 9): the player's attribute follows on the next sync
	Router.on("founder.set", function(s, a)
		return Island.setFounder(s.profile, a.skin, a.hair, a.style, a.shirt)
	end)
	Router.on("settings.set", function(s, a)
		if a.k == "pixel" and type(a.v) == "string" and PIXEL_TIERS[a.v] then
			s.profile.settings.pixel = a.v
			return true, nil
		end
		return false, "bad_payload"
	end)
	Router.on("char.home", function(s, _a)
		return PlotService.home(s)
	end)
	Router.on("tut.next", function(s, _a)
		s.profile.tut = 0
		return true, nil
	end)
end

-- An expedition under way ends when its player leaves (the loot kept).
function IslandService.leaving(s: Session.S)
	if s.exp then
		goHome(s)
	end
end

-- The clock (Main's fixed step): every ready session's island makes and eats, a day turns now and then.
function IslandService.step(dt: number)
	for _, s in Session.all() do
		if not s.ready then
			continue
		end
		local p = s.profile
		local hungry = p.food <= 0
		Island.step(p, dt, s.away)
		if (p.food <= 0) ~= hungry then
			Session.markDirty(s)
		end
		s.dayClock += dt
		if s.dayClock >= Tuning.DaySeconds then
			s.dayClock -= Tuning.DaySeconds
			local news = Island.newDay(p, s.rng, s.away)
			Session.markDirty(s)
			Session.fx(s, { kind = "day", day = p.day, movedIn = news.movedIn, trained = news.trained })
		end
		s.tickClock += dt
		if s.tickClock >= 1 then
			s.tickClock -= 1
			Session.fx(s, { kind = "tick", shells = p.shells, food = p.food, wood = p.wood, dayFrac = s.dayClock / Tuning.DaySeconds })
		end
	end
end

return IslandService
