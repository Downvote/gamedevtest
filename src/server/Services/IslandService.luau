--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Expedition) that mark the session dirty and tell the client what
-- happened. The island makes and eats every step (Island.step, those away on an expedition left out); its stores go
-- to the client every second (Fx "tick", so the whole view is not sent every second); a turn ends every
-- Tuning.TurnSeconds (Island.turn: a visitor may move in, the yard trains; Fx "turn"), and the sea's clock
-- (WorldClock: hours a day) counts the calendar days (Island.newDay; Fx "day"). Expeditions live in the
-- session: start, the next node, battle rounds, home (Fx "exp" carries each step's events for the client to play).
-- Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Expedition = require(ReplicatedStorage.Shared.Logic.Expedition)
local Battle = require(ReplicatedStorage.Shared.Logic.Battle)
local Chart = require(ReplicatedStorage.Shared.Logic.Chart)
local Session = require(script.Parent.Session)
local WorldClock = require(script.Parent.WorldClock)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9): 1 food (a farm), 2 wood (a lumber camp), 3 shells (a shop), 4 a home, 5 a nest and
-- set sail (Logic/Expedition moves it on), 6 the last tip (OK ends them). Each moves on once what it asks is built.
local function tips(s: Session.S)
	local p = s.profile
	if p.tut < 1 or p.tut > 4 then
		return
	end
	local has: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			has[d.kind] = true
		end
	end
	for step, kind in { "food", "wood", "shop", "home" } do
		if p.tut == step and has[kind] then
			p.tut = step + 1
		end
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
	-- the boat (GAME_DESIGN 7): a bigger one sails further on the chart; not while it is away
	Router.on("boat.upgrade", function(s, _a)
		if s.exp then
			return false, "busy"
		end
		local ok, data = Chart.upgradeBoat(s.profile)
		if ok then
			PlotService.setBoat(s)
		end
		return ok, data
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
		local ok, e = Chart.sail(s.profile, a.isle, members)
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
	-- the timed battle (GAME_DESIGN 7): the player's moves; the battle itself runs in `step`
	local function battleDone(s: Session.S, data: any)
		if type(data) == "table" and data.result then
			Session.markDirty(s)
		end
	end
	Router.on("exp.snack", function(s, a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		local ok, data = Expedition.snack(s.profile, e, a.target, s.rng)
		if ok then
			battleDone(s, data)
			Session.fx(s, { kind = "exp", step = "act", data = data })
		end
		return ok, data
	end)
	Router.on("exp.skill", function(s, a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		local ok, data = Expedition.skill(s.profile, e, a.who, a.skill, if a.target == "" then nil else a.target, s.rng)
		if ok then
			battleDone(s, data)
			Session.fx(s, { kind = "exp", step = "act", data = data })
		end
		return ok, data
	end)
	Router.on("exp.flee", function(s, _a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		local ok, data = Expedition.flee(s.profile, e, s.rng)
		if ok then
			battleDone(s, data)
			Session.fx(s, { kind = "exp", step = "act", data = data })
		end
		return ok, data
	end)
	Router.on("exp.pause", function(s, a)
		local e = s.exp
		if e == nil then
			return false, "no_exp"
		end
		return Expedition.pause(e, a.on)
	end)
	-- a bigger snack pouch (GAME_DESIGN 7: snacks an expedition, 5 up to 30); not while away
	Router.on("pouch.upgrade", function(s, _a)
		if s.exp then
			return false, "busy"
		end
		return Expedition.upgradePouch(s.profile)
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
		elseif a.k == "music" and (a.v == "on" or a.v == "off") then
			-- the background music (the HUD's note): on or off, kept with the profile
			s.profile.settings.music = a.v
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

-- The clock (Main's fixed step): the sea's clock runs on; every ready session's island makes and eats, a turn ends
-- every TurnSeconds (a visitor may move in, the yard trains: Fx "turn"), and a calendar day's end on the sea's clock
-- counts a day (Fx "day").
function IslandService.step(dt: number)
	WorldClock.advance(dt)
	local today = WorldClock.dayIndex()
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
		s.turnClock += dt
		if s.turnClock >= Tuning.TurnSeconds then
			s.turnClock -= Tuning.TurnSeconds
			local news = Island.turn(p, s.rng, s.away)
			Session.markDirty(s)
			Session.fx(s, { kind = "turn", movedIn = news.movedIn, trained = news.trained })
		end
		if today > s.dayIndex then
			s.dayIndex = today
			Island.newDay(p)
			Session.markDirty(s)
			Session.fx(s, { kind = "day", day = p.day })
		end
		-- the expedition's battle runs on in time (paused while landing, aiming a snack or off the screen); what
		-- happens goes to the client as it happens, the timers as they stand twice a second
		local e = s.exp
		if e and e.battle and not e.over then
			local out = Expedition.tick(p, e, dt, s.rng)
			if out then
				if out.result then
					Session.markDirty(s)
				end
				Session.fx(s, { kind = "exp", step = "act", data = out })
				s.gaugeClock = 0
			else
				s.gaugeClock += dt
				local b = e.battle
				if b and not b.paused and s.gaugeClock >= 0.5 then
					s.gaugeClock = 0
					Session.fx(s, { kind = "exp", step = "timers", data = Battle.gauges(e.party, b) })
				end
			end
		end
		s.tickClock += dt
		if s.tickClock >= 1 then
			s.tickClock -= 1
			Session.fx(s, { kind = "tick", shells = p.shells, food = p.food, wood = p.wood, dayFrac = WorldClock.dayFrac() })
		end
	end
end

return IslandService
