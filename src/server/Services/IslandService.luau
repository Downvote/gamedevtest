--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Tree, Breed) that mark the session dirty and tell the client what
-- happened. The island makes and eats every step (Island.step); the Tree of Life grows its driftlings into the pen and
-- the pen sends its best to the huts (Tree.step; Fx "tree"); the stores and the tree's growth go to the client every
-- second (Fx "tick", so the whole view is not sent every second); a turn ends every Tuning.TurnSeconds (the eggs; Fx
-- "turn"), and the sea's clock (WorldClock: hours a day) counts the calendar days
-- (Island.newDay; Fx "day"). Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Session = require(script.Parent.Session)
local WorldClock = require(script.Parent.WorldClock)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9): 1 food (a farm), 2 wood (a lumber camp), 3 shells (a shop), 4 a hut (the pen sends its
-- best driftlings there to work), 5 the Tree of Life (a level of its luck or speed: `tree.upgrade` moves it on), 6 the
-- last tip (OK ends them). Each moves on once what it asks is done.
local function tips(s: Session.S)
	local p = s.profile
	if p.tut == 5 and (p.tree.luck > 1 or p.tree.speed > 1) then
		p.tut = 6
	end
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
	for step, kind in { "food", "wood", "shop", "nest" } do
		if p.tut == step and has[kind] then
			p.tut = step + 1
		end
	end
end

-- The driftlings that moved (the pen sending its best on, or the player's pick) go to the client with the view.
local function moved(s: Session.S, grown: { any }?, sent: { number }?)
	if (grown and #grown > 0) or (sent and #sent > 0) then
		Session.markDirty(s)
		Session.fx(s, { kind = "tree", grown = grown, sent = sent })
	end
end

function IslandService.init()
	-- building (GAME_DESIGN 4): every change rebuilds the island's pieces by difference
	local function rebuilt(fn: (s: Session.S, a: any) -> (boolean, any)): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local ok, data = fn(s, a)
			if ok then
				-- (a building of a knack: the hut driftlings resting there take a place first; a hut built or gone, or a
				-- place free: the pen sends its best on)
				Tree.fillJobs(s.profile)
				moved(s, nil, Tree.settle(s.profile))
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
	-- the Tree of Life and its pen (GAME_DESIGN 6): a driftling to a hut or the pen, selling, the tree's upgrades
	Router.on("pal.house", function(s, a)
		return Tree.house(s.profile, a.id, a.uid, a.swap)
	end)
	Router.on("pal.sell", function(s, a)
		return Tree.sell(s.profile, a.id)
	end)
	Router.on("pen.sell", function(s, a)
		return Tree.sellPen(s.profile, a.r)
	end)
	Router.on("tree.upgrade", function(s, a)
		local stage = Tree.stage(s.profile)
		local ok, data = Tree.upgrade(s.profile, a.what)
		if ok then
			tips(s)
			-- a Luck milestone: the tree grows bigger (its model built again at the new stage)
			if Tree.stage(s.profile) ~= stage then
				PlotService.buildDecor(s)
				Session.fx(s, { kind = "treegrew", stage = Tree.stage(s.profile) })
			end
		end
		return ok, data
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

-- The clock (Main's fixed step): the sea's clock runs on; every ready session's island makes and eats, its tree grows,
-- a turn ends every TurnSeconds (the eggs: Fx "turn"), and a calendar day's end on the sea's clock counts a day
-- (Fx "day").
function IslandService.step(dt: number)
	WorldClock.advance(dt)
	local today = WorldClock.dayIndex()
	for _, s in Session.all() do
		if not s.ready then
			continue
		end
		local p = s.profile
		local hungry = p.food <= 0
		Island.step(p, dt)
		if (p.food <= 0) ~= hungry then
			Session.markDirty(s)
		end
		-- the Tree of Life: what grew into the pen, and the best of it sent on to the huts (the pen has no room limit;
		-- at the save's limit the tree rests)
		local grown, sent = Tree.step(p, dt, s.rng)
		moved(s, grown, sent)
		s.turnClock += dt
		if s.turnClock >= Tuning.TurnSeconds then
			s.turnClock -= Tuning.TurnSeconds
			-- the eggs a turn nearer; the ready ones hatch into the pen
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
			Session.fx(s, { kind = "tick", shells = p.shells, food = p.food, wood = p.wood, dayFrac = WorldClock.dayFrac(), grow = p.tree.t, secs = Tree.secs(p) })
		end
	end
end

return IslandService
