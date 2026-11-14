--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Tree, Breed) that mark the session dirty and tell the client what
-- happened. The island makes shells every step (Island.step); the Tree of Life lays a new lot of eggs every
-- few minutes (Tree.step; Fx "eggs"); the stores and the time to the next lot go to the client every second (Fx "tick",
-- so the whole view is not sent every second); a turn ends every Tuning.TurnSeconds (the eggs; Fx
-- "turn"), and the sea's clock (WorldClock: hours a day) counts the calendar days (Island.newDay; Fx "day").
-- Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Weather = require(ReplicatedStorage.Shared.Logic.Weather)
local Session = require(script.Parent.Session)
local WorldClock = require(script.Parent.WorldClock)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local lastKind: string? = nil -- the weather and season last step (a change is told: Fx "weather")
local lastSeason: string? = nil

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9): 1 a lumber camp (it sells what it cuts), 2 a farm (it sells what it grows), 3 a hut, 4 an
-- egg hatched from the Tree of Life (with shells), 5 a shop (it sells snacks), 6 the last
-- tip (OK ends them). Each moves on once what it asks is done (an older save moves on through the ones it has done
-- at once).
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

-- The quest's egg (Logic/Tree.ensure): while the quest on the go asks for a rarity, one egg of it is under the tree.
-- When an egg turns, the client hears of it (Fx "eggs" with `turned`: its rarity) and the view follows.
local function questEgg(s: Session.S)
	local e = Tree.ensure(s.profile)
	if e then
		Session.markDirty(s)
		Session.fx(s, { kind = "eggs", laid = Tree.view(s.profile), more = 0, turned = e.r })
	end
end

function IslandService.init()
	-- building (GAME_DESIGN 4): every change rebuilds the island's pieces by difference
	local function rebuilt(fn: (s: Session.S, a: any) -> (boolean, any)): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local ok, data = fn(s, a)
			if ok then
				-- (a workplace built: the hut driftlings resting take a place there, their knack's first; a hut built:
				-- the ones with no hut move in)
				Tree.settle(s.profile)
				Tree.fillJobs(s.profile)
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
	-- paths and water drawn in a line or a box, or erased; fences drawn along the grid lines or taken down (GAME_DESIGN 4)
	Router.on(
		"plot.paint",
		rebuilt(function(s, a)
			return Plot.paint(s.profile, a.id, Plot.cells(a.cells))
		end)
	)
	Router.on(
		"plot.unpaint",
		rebuilt(function(s, a)
			return Plot.unpaint(s.profile, Plot.cells(a.cells), a.kind)
		end)
	)
	Router.on(
		"plot.fence",
		rebuilt(function(s, a)
			return Plot.fence(s.profile, a.id, Plot.edges(a.edges))
		end)
	)
	Router.on(
		"plot.unfence",
		rebuilt(function(s, a)
			return Plot.unfence(s.profile, Plot.edges(a.edges))
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
			-- (a bigger island: the tree lays its extra eggs at once, in the weather now)
			local laid = Tree.fill(s.profile, s.rng, Weather.at(WorldClock.now()))
			PlotService.build(s)
			if #laid > 0 then
				Session.fx(s, { kind = "eggs", laid = Tree.view(s.profile), more = #laid })
			end
		end
		return ok, data
	end)
	-- which driftling works where (GAME_DESIGN 5, 6)
	Router.on("pal.work", function(s, a)
		return Island.setHelp(s.profile, a.id, a.uid)
	end)
	-- the tree's eggs and the huts (GAME_DESIGN 6): an egg hatched (a swap when every hut is full), a driftling to
	-- another hut, selling
	Router.on("egg.hatch", function(s, a)
		local ok, data = Tree.hatch(s.profile, a.id, a.swap, s.rng)
		if ok then
			tips(s)
			Session.fx(s, { kind = "hatched", data = data })
		end
		return ok, data
	end)
	Router.on("pal.house", function(s, a)
		return Tree.house(s.profile, a.id, a.uid, a.swap)
	end)
	Router.on("pal.sell", function(s, a)
		return Tree.sell(s.profile, a.id)
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
		questEgg(s)
		return true, nil
	end)
	-- the questline (GAME_DESIGN 9): the quest on the go claimed once its goal is met, its reward paid
	Router.on("quest.claim", function(s, _a)
		local ok, data = Quest.claim(s.profile)
		if ok then
			Session.fx(s, { kind = "quest", data = data })
			-- (the next quest may ask for a rarity: its egg under the tree at once)
			questEgg(s)
		end
		return ok, data
	end)
end

-- The clock (Main's fixed step): the sea's clock runs on; every ready session's island makes shells, its tree
-- lays a new lot of eggs when their time comes (Fx "eggs"; the quest's egg checked every second), a turn ends every
-- TurnSeconds (the Hatcheries' eggs: Fx "turn"), and a calendar day's end on the sea's clock counts a day (Fx "day").
function IslandService.step(dt: number)
	WorldClock.advance(dt)
	local today = WorldClock.dayIndex()
	-- the season and the weather (one for the whole sea, from its clock: Logic/Weather); a new spell's weather is
	-- told to every player (Fx "weather"), its eggs laid in it
	local wx = Weather.at(WorldClock.now())
	local turned = lastKind ~= nil and wx.kind ~= lastKind
	local newSeason = lastSeason ~= nil and wx.season ~= lastSeason
	lastKind, lastSeason = wx.kind, wx.season
	for _, s in Session.all() do
		if not s.ready then
			continue
		end
		if turned or newSeason then
			Session.fx(s, { kind = "weather", wx = wx.kind, season = wx.season, newSeason = newSeason, clock = WorldClock.now() })
		end
		local p = s.profile
		Island.step(p, dt)
		-- the tree: a new lot of eggs when its time comes (the ones left go), in the weather now
		local laid = Tree.step(p, dt, s.rng, wx)
		if laid then
			Session.markDirty(s)
			Session.fx(s, { kind = "eggs", laid = Tree.view(p), more = 0 })
		end
		s.turnClock += dt
		if s.turnClock >= Tuning.TurnSeconds then
			s.turnClock -= Tuning.TurnSeconds
			-- the eggs a turn nearer; the ready ones hatch into a hut with room
			local hatched, fresh = Breed.turn(p)
			Session.markDirty(s)
			Session.fx(s, { kind = "turn", hatched = if #hatched > 0 then hatched else nil, fresh = if #fresh > 0 then fresh else nil })
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
			-- (the quest's egg, once a second: a save loaded with such a quest on the go, or anything else that left
			-- the lot without one)
			questEgg(s)
			Session.fx(s, { kind = "tick", shells = p.shells, dayFrac = WorldClock.dayFrac(), clock = WorldClock.now(), clutchLeft = p.clutch.left, clutchSecs = Tree.secs(p) })
		end
	end
end

return IslandService
