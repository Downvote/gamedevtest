--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Tide, Breed) that mark the session dirty and tell the client what
-- happened. The island makes wood and shells every step (Island.step); the tide brings a driftling in every second
-- and each floats past the island and off (Tide.step; Fx "tide"); the stores go to the client every second (Fx "tick",
-- so the whole view is not sent every second); a turn ends every Tuning.TurnSeconds (the eggs; Fx
-- "turn"), and the sea's clock (WorldClock: hours a day) counts the calendar days (Island.newDay; Fx "day").
-- Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Tide = require(ReplicatedStorage.Shared.Logic.Tide)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Session = require(script.Parent.Session)
local WorldClock = require(script.Parent.WorldClock)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9): 1 wood (a lumber camp: wood builds everything), 2 shells (a farm: it sells what it
-- grows), 3 a hut, 4 a driftling off the tide (taken in with shells), 5 a shop (it sells to the visitors), 6 the last
-- tip (OK ends them). Each moves on once what it asks is done (a save from before the tide moves on through the ones
-- it has done at once).
local TIP_KIND: { [number]: string } = { [1] = "wood", [2] = "farm", [3] = "nest", [5] = "shop" }
local function tips(s: Session.S)
	local p = s.profile
	local has: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			has[d.kind] = true
		end
	end
	while p.tut >= 1 and p.tut <= 5 do
		local kind = TIP_KIND[p.tut]
		local done = if kind then has[kind] == true else (p.stats.taken > 0 or #p.pals > 0)
		if not done then
			break
		end
		p.tut += 1
	end
end

-- The tide's news (driftlings that came in, and the ones gone past) go to the client on their own (one a second: the
-- whole view isn't sent for them; StateClient patches its copy), and the plot's Tide attribute follows (Main).
local function tide(s: Session.S, came: { Types.Drift }, gone: { number })
	if #came > 0 or #gone > 0 then
		s.tideDirty = true
		local list = {}
		for _, d in came do
			table.insert(list, Tide.entry(s.profile, d))
		end
		Session.fx(s, { kind = "tide", came = list, gone = gone })
	end
end

function IslandService.init()
	-- building (GAME_DESIGN 4): every change rebuilds the island's pieces by difference
	local function rebuilt(fn: (s: Session.S, a: any) -> (boolean, any)): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local ok, data = fn(s, a)
			if ok then
				-- (a building of a knack: the hut driftlings resting there take a place; a hut built: the ones with no
				-- hut move in)
				Tide.settle(s.profile)
				Tide.fillJobs(s.profile)
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
	-- paths drawn in a line or a box, or erased (GAME_DESIGN 4)
	Router.on(
		"plot.paint",
		rebuilt(function(s, a)
			return Plot.paint(s.profile, a.id, Plot.cells(a.cells))
		end)
	)
	Router.on(
		"plot.unpaint",
		rebuilt(function(s, a)
			return Plot.unpaint(s.profile, Plot.cells(a.cells))
		end)
	)
	Router.on(
		"plot.replace",
		rebuilt(function(s, a)
			return Plot.replace(s.profile, a.i, a.id)
		end)
	)
	Router.on("island.expand", function(s, _a)
		local ok, data = Island.expand(s.profile)
		if ok then
			PlotService.build(s)
		end
		return ok, data
	end)
	-- which driftling works where (GAME_DESIGN 5, 6)
	Router.on("pal.work", function(s, a)
		return Island.setHelp(s.profile, a.id, a.uid)
	end)
	-- the tide and the huts (GAME_DESIGN 6): one off the tide taken in (a swap when every hut is full), a driftling to
	-- another hut, selling
	Router.on("tide.take", function(s, a)
		local ok, data = Tide.take(s.profile, s.tide, a.id, a.swap)
		if ok then
			tips(s)
			Session.fx(s, { kind = "taken", data = data })
		end
		return ok, data
	end)
	Router.on("pal.house", function(s, a)
		return Tide.house(s.profile, a.id, a.uid, a.swap)
	end)
	Router.on("pal.sell", function(s, a)
		return Tide.sell(s.profile, a.id)
	end)
	-- the Hatchery (GAME_DESIGN 6.1): two driftlings and a feast make an egg
	Router.on("breed.start", function(s, a)
		return Breed.start(s.profile, a.uid, a.a, a.b, s.rng)
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
	-- the questline (GAME_DESIGN 9): the quest on the go claimed once its goal is met, its reward paid
	Router.on("quest.claim", function(s, _a)
		local ok, data = Quest.claim(s.profile)
		if ok then
			Session.fx(s, { kind = "quest", data = data })
		end
		return ok, data
	end)
end

-- The clock (Main's fixed step): the sea's clock runs on; every ready session's island makes wood and shells, its tide
-- brings driftlings in, a turn ends every TurnSeconds (the eggs: Fx "turn"), and a calendar day's end on the sea's clock
-- counts a day (Fx "day").
function IslandService.step(dt: number)
	WorldClock.advance(dt)
	local today = WorldClock.dayIndex()
	for _, s in Session.all() do
		if not s.ready then
			continue
		end
		local p = s.profile
		Island.step(p, dt)
		-- the tide, on the server's time (so every client puts each one at the same place): one comes in every second,
		-- each one gone past the island leaves (a long stall is skipped, not caught up)
		local now = workspace:GetServerTimeNow()
		if now - s.tide.clock > 5 then
			s.tide.clock = now - 5
		end
		local came, gone = Tide.step(p, s.tide, math.max(0, now - s.tide.clock), s.rng)
		tide(s, came, gone)
		s.turnClock += dt
		if s.turnClock >= Tuning.TurnSeconds then
			s.turnClock -= Tuning.TurnSeconds
			-- the eggs a turn nearer; the ready ones hatch into a hut with room
			local hatched = Breed.turn(p)
			Session.markDirty(s)
			Session.fx(s, { kind = "turn", hatched = if #hatched > 0 then hatched else nil })
		end
		if today > s.dayIndex then
			s.dayIndex = today
			Island.newDay(p)
			Session.markDirty(s)
			Session.fx(s, { kind = "day", day = p.day })
		end
		s.tickClock += dt
		if s.tickClock >= 1 then
			s.tickClock -= 1
			Session.fx(s, { kind = "tick", shells = p.shells, wood = p.wood, dayFrac = WorldClock.dayFrac(), tideSecs = Tide.secs(p) })
		end
	end
end

return IslandService
