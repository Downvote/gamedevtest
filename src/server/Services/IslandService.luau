--!strict
-- The island on the server (docs/ARCHITECTURE.md 7.4): every player action and the island's clock, as thin wrappers
-- round the shared rules (Logic/Island, Plot, Tree, Breed) that mark the session dirty and tell the client what
-- happened. The island makes shells every step (Island.step); the Tree of Life lays a new lot of eggs every
-- few minutes (Tree.step; Fx "eggs"); the stores and the time to the next lot go to the client every second (Fx "tick",
-- so the whole view is not sent every second); a turn ends every Tuning.TurnSeconds (the eggs; Fx
-- "turn"), and the sea's clock (WorldClock: hours a day) counts the calendar days (Island.newDay; Fx "day").
-- Everything runs while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Undo = require(ReplicatedStorage.Shared.Logic.Undo)
local Layout = require(ReplicatedStorage.Shared.Logic.Layout)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local Quest = require(ReplicatedStorage.Shared.Logic.Quest)
local Weather = require(ReplicatedStorage.Shared.Logic.Weather)
local Store = require(ReplicatedStorage.Shared.Logic.Store)
local Rewards = require(ReplicatedStorage.Shared.Logic.Rewards)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Codes = require(script.Parent.Parent.Config.Codes)
local Session = require(script.Parent.Session)
local WorldClock = require(script.Parent.WorldClock)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local IslandService = {}

local lastKind: string? = nil -- the weather and season last step (a change is told: Fx "weather")
local lastSeason: string? = nil

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

-- The tips (GAME_DESIGN 9; the request of 2026-11-21): 1 a hut (Plot.TIP_HUT), 2 an egg hatched from the Tree of Life
-- (Plot.TIP_HATCH), 3 a workplace (Plot.TIP_WORK: the tips light up the best one the island has, free meanwhile:
-- Plot.price; any workplace moves them on), 4 the last tip (Plot.TIP_LAST: OK ends them). Each moves on once what it
-- asks is done (an older save moves on through the ones it has done at once, at the join too).
local function tips(s: Session.S)
	local p = s.profile
	local has: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			has[d.kind] = true
		end
	end
	while p.tut >= 1 and p.tut < Plot.TIP_LAST do
		local done = if p.tut == Plot.TIP_HUT
			then has.nest == true
			elseif p.tut == Plot.TIP_HATCH then (p.stats.taken > 0 or #p.pals > 0)
			else has.work == true
		if not done then
			break
		end
		p.tut += 1
	end
end

-- The quest's egg (Logic/Tree.ensure): while the quest on the go asks for a rarity, one egg of it is under the tree.
-- When an egg turns (or is laid, with none to turn), the client hears of it (Fx "eggs" with `turned`: its rarity) and
-- the view follows.
local function questEgg(s: Session.S)
	local e = Tree.ensure(s.profile, Weather.at(WorldClock.now()))
	if e then
		Session.markDirty(s)
		Session.fx(s, { kind = "eggs", laid = Tree.view(s.profile), more = 0, turned = e.r })
	end
end

-- Many eggs hatched at once (the bulk hatch, Auto Hatch: Logic/Tree.bulk): each counts as an egg hatched (the pass
-- track's points), the tips move on, and the world's burst plays for the rarest of them (Fx "hatched").
local function hatchedMany(s: Session.S, data: Tree.Bulk)
	local best: any = nil
	for _, x in data.list do
		Store.addXp(s.profile, "egg")
		if best == nil or (x.hr or x.r or 0) > (best.hr or best.r or 0) then
			best = x
		end
	end
	tips(s)
	if best then
		Session.fx(s, { kind = "hatched", data = best })
	end
end

-- Auto Hatch (the AutoHatch pass; the request of 2026-11-22, "make an auto buy gamepass, which lets you auto buy eggs
-- that appear above a rarity of your choosing"): a new lot's eggs at the player's floor or rarer hatch as they are
-- laid, coins and huts allowing (Logic/Tree.autoIds, bulk). The client hears what hatched, or why none could (Fx
-- "auto": the hatches in `list`, the coins paid, the eggs left for coins and for room, and why).
local function autoHatch(s: Session.S, laid: { Types.Laid })
	local ids = Tree.autoIds(s.profile, laid)
	if #ids == 0 then
		return
	end
	local ok, data = Tree.bulk(s.profile, ids, false, s.rng)
	if ok then
		hatchedMany(s, data)
		Session.fx(s, { kind = "auto", list = data.list, cost = data.cost, short = data.short, room = data.room, why = data.why })
	else
		Session.fx(s, { kind = "auto", list = {}, cost = 0, short = if data == "money" then #ids else 0, room = if data == "full" or data == "no_hut" then #ids else 0, why = data })
	end
end

function IslandService.init()
	-- building (GAME_DESIGN 4): every change rebuilds the island's pieces by difference, and is one step Build mode's
	-- Undo can take back (Logic/Undo: what the action changed, taken once the huts and the work have settled round it)
	local function recorded(what: string, fn: (s: Session.S, a: any) -> (boolean, any)): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local before = Undo.capture(s.profile)
			local ok, data = fn(s, a)
			if ok then
				local step = Undo.diff(before, s.profile, what)
				if step then
					Undo.push(s.undo, step)
				end
			end
			return ok, data
		end
	end
	local function rebuilt(what: string, fn: (s: Session.S, a: any) -> (boolean, any), record: boolean?): (s: Session.S, a: any) -> (boolean, any)
		return function(s: Session.S, a: any): (boolean, any)
			local before = if record == false then nil else Undo.capture(s.profile)
			local ok, data = fn(s, a)
			if ok then
				-- (a workplace built: the hut driftlings resting take a place there, their knack's first; a hut built:
				-- the ones with no hut move in)
				Tree.settle(s.profile)
				Tree.fillJobs(s.profile)
				if before then
					local step = Undo.diff(before, s.profile, what)
					if step then
						Undo.push(s.undo, step)
					end
				end
				PlotService.buildDecor(s)
				tips(s)
			end
			return ok, data
		end
	end
	local function build(action: string, fn: (s: Session.S, a: any) -> (boolean, any))
		Router.on(action, rebuilt(action, fn))
	end
	build("plot.place", function(s, a)
		return Plot.place(s.profile, a.id, a.x, a.z, a.rot)
	end)
	build("plot.move", function(s, a)
		return Plot.move(s.profile, a.i, a.x, a.z, a.rot)
	end)
	build("plot.store", function(s, a)
		return Plot.store(s.profile, a.i)
	end)
	-- paths and water drawn in a line or a box, or erased; fences drawn along the grid lines or taken down (GAME_DESIGN 4)
	build("plot.paint", function(s, a)
		return Plot.paint(s.profile, a.id, Plot.cells(a.cells))
	end)
	build("plot.unpaint", function(s, a)
		return Plot.unpaint(s.profile, Plot.cells(a.cells), a.kind)
	end)
	build("plot.fence", function(s, a)
		return Plot.fence(s.profile, a.id, Plot.edges(a.edges))
	end)
	build("plot.unfence", function(s, a)
		return Plot.unfence(s.profile, Plot.edges(a.edges))
	end)
	build("plot.replace", function(s, a)
		return Plot.replace(s.profile, a.i, a.id)
	end)
	-- Build mode's inventory (GAME_DESIGN 4.5): Remove all (a group into the inventory at once), and selling what waits
	-- there (an Undo step too: the coins go back and the pieces return)
	build("plot.clear", function(s, a)
		return Plot.clear(s.profile, a.what)
	end)
	Router.on(
		"inv.sell",
		recorded("inv.sell", function(s, a)
			return Plot.sellHeld(s.profile, a.id, a.n)
		end)
	)
	-- Build mode's Select tool (GAME_DESIGN 4.7): a group moved (and turned), put away or copied, all or nothing
	build("plot.moveMany", function(s, a)
		return Plot.moveMany(s.profile, Plot.uids(a.uids), a.dx, a.dz, a.rot)
	end)
	build("plot.storeMany", function(s, a)
		return Plot.storeMany(s.profile, Plot.uids(a.uids))
	end)
	build("plot.copyMany", function(s, a)
		return Plot.copyMany(s.profile, Plot.uids(a.uids), a.dx, a.dz, a.rot)
	end)
	-- Undo: the last step taken back (refused with why when the island no longer allows it; the step stays then)
	Router.on(
		"plot.undo",
		rebuilt("plot.undo", function(s, _a)
			local step = s.undo[#s.undo]
			if step == nil then
				return false, "not_found"
			end
			local ok, data = Undo.apply(s.profile, step)
			if ok then
				table.remove(s.undo)
			end
			return ok, data
		end, false)
	)
	-- saved layouts (Logic/Layout): save the island into a slot, what loading one would do, and loading it (one Undo
	-- step)
	Router.on("layout.save", function(s, a)
		return Layout.save(s.profile, a.slot, os.time())
	end)
	Router.on("layout.quote", function(s, a)
		return Layout.plan(s.profile, a.slot)
	end)
	build("layout.load", function(s, a)
		return Layout.load(s.profile, a.slot)
	end)
	Router.on("island.expand", function(s, _a)
		local ok, data = Island.expand(s.profile)
		if ok then
			-- (a bigger island: what Undo held is for the island before it grew)
			table.clear(s.undo)
			Store.addXp(s.profile, "expand")
			-- (a bigger island: the tree lays its extra eggs at once, in the weather now)
			local laid = Tree.fill(s.profile, s.rng, Weather.at(WorldClock.now()))
			autoHatch(s, laid)
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
	-- (the work picker's Auto: back to the arrangement, where it makes the most: Island.arrange)
	Router.on("pal.auto", function(s, a)
		return Island.autoWork(s.profile, a.id)
	end)
	-- the tree's eggs and the huts (GAME_DESIGN 6): an egg hatched (a swap when every hut is full), a driftling to
	-- another hut, selling
	Router.on("egg.hatch", function(s, a)
		local ok, data = Tree.hatch(s.profile, a.id, a.swap, s.rng)
		if ok then
			Store.addXp(s.profile, "egg")
			tips(s)
			Session.fx(s, { kind = "hatched", data = data })
		end
		return ok, data
	end)
	-- many at once (the request of 2026-11-22: "make a bulk open eggs button, where you open all eggs at once in the
	-- tree", "selecting as in: bulk buy over a certain rarity"): every egg of rarity `min` or rarer, the tree's for
	-- their price or the bag's for nothing, the rarest first, coins and huts allowing (Logic/Tree.bulk)
	Router.on("egg.bulk", function(s, a)
		local p = s.profile
		local bag = a.bag == true
		local ids = Tree.atLeast((if bag then p.bag else p.clutch.list) :: any, a.min)
		local ok, data = Tree.bulk(p, ids, bag, s.rng)
		if ok then
			hatchedMany(s, data)
		end
		return ok, data
	end)
	-- Auto Hatch's floor (a rarity, 0 off; the AutoHatch pass)
	Router.on("egg.auto", function(s, a)
		return Tree.setAuto(s.profile, a.r)
	end)
	Router.on("pal.house", function(s, a)
		return Tree.house(s.profile, a.id, a.uid, a.swap)
	end)
	Router.on("pal.sell", function(s, a)
		return Tree.sell(s.profile, a.id)
	end)
	-- every driftling of one rarity sold (the request of 2026-11-22: "make a bulksell by rarity option for creatures")
	Router.on("pal.sellAll", function(s, a)
		return Tree.sellRarity(s.profile, a.r)
	end)
	-- the Hatchery (GAME_DESIGN 6.1): two driftlings bred for an egg
	Router.on("breed.start", function(s, a)
		return Breed.start(s.profile, a.uid, a.a, a.b)
	end)
	-- a ready egg hatched from its Hatchery (a tap on it: the client plays the hatch scene with what came out)
	Router.on("breed.hatch", function(s, a)
		local ok, data = Breed.hatch(s.profile, a.uid)
		if ok then
			Store.addXp(s.profile, "breed")
		end
		return ok, data
	end)
	-- every ready egg at once (the request of 2026-11-22: "and hatchery as well, make a open all hatchery eggs"): no
	-- hatch scene for each, the client shows what came out of them all
	Router.on("breed.hatchAll", function(s, _a)
		local ok, data = Breed.hatchAll(s.profile)
		if ok then
			for _ in data.list do
				Store.addXp(s.profile, "breed")
			end
		end
		return ok, data
	end)
	-- the founder's look (GAME_DESIGN 9): the player's attribute follows on the next sync
	Router.on("founder.set", function(s, a)
		return Island.setFounder(s.profile, a.skin, a.hair, a.style, a.shirt)
	end)
	-- the store (GAME_DESIGN 14): a cosmetic or a title worn (the attributes follow on the next sync), a piece bought
	-- from the rotating shop, a pass track reward claimed, a bag egg hatched (no shells), VIP's daily gift
	Router.on("look.wear", function(s, a)
		return Store.wear(s.profile, a.slot, a.id)
	end)
	-- the customization screen's Save (a whole look) and its Outfits tab (GAME_DESIGN 14.1)
	Router.on("look.set", function(s, a)
		return Store.setLook(s.profile, a.look)
	end)
	Router.on("outfit.set", function(s, a)
		return Store.setOutfit(s.profile, a.i, a.look)
	end)
	Router.on("title.set", function(s, a)
		return Store.setTitle(s.profile, a.id)
	end)
	Router.on("shop.buy", function(s, a)
		return Store.buy(s.profile, a.id, WorldClock.now())
	end)
	Router.on("track.claim", function(s, a)
		local ok, data = Store.claim(s.profile, a.lvl, a.prem, WorldClock.now())
		if ok then
			Session.fx(s, { kind = "rewards", from = "track", given = data.given })
		end
		return ok, data
	end)
	Router.on("bag.hatch", function(s, a)
		local ok, data = Tree.hatchBag(s.profile, a.id, a.swap, s.rng)
		if ok then
			Store.addXp(s.profile, "egg")
			tips(s)
			Session.fx(s, { kind = "hatched", data = data })
		end
		return ok, data
	end)
	Router.on("vip.daily", function(s, _a)
		local ok, data = Store.vipDaily(s.profile, WorldClock.now())
		if ok then
			Session.fx(s, { kind = "rewards", from = "vip", given = data.given })
		end
		return ok, data
	end)
	-- the rewards for coming back and playing (GAME_DESIGN 15; Logic/Rewards): each claim tells the player what came
	-- (Fx "rewards", the panel's notice and the flying shells)
	local function reward(s: Session.S, from: string, ok: boolean, data: any): (boolean, any)
		if ok then
			Session.markDirty(s)
			Session.fx(s, { kind = "rewards", from = from, given = data.given })
		end
		return ok, data
	end
	Router.on("reward.daily", function(s, _a)
		return reward(s, "daily", Rewards.claimDaily(s.profile, WorldClock.now()))
	end)
	Router.on("reward.play", function(s, a)
		return reward(s, "play", Rewards.claimPlay(s.profile, a.i, WorldClock.now()))
	end)
	Router.on("reward.task", function(s, a)
		return reward(s, "task", Rewards.claimTask(s.profile, a.i, WorldClock.now()))
	end)
	Router.on("reward.bonus", function(s, _a)
		return reward(s, "bonus", Rewards.claimBonus(s.profile, WorldClock.now()))
	end)
	Router.on("reward.spin", function(s, _a)
		return reward(s, "spin", Rewards.spin(s.profile, s.rng, WorldClock.now()))
	end)
	Router.on("reward.index", function(s, a)
		return reward(s, "index", Rewards.claimIndex(s.profile, a.i))
	end)
	Router.on("code.redeem", function(s, a)
		return reward(s, "code", Rewards.redeem(s.profile, a.code, Codes :: any, WorldClock.now()))
	end)
	-- offline earnings (GAME_DESIGN 14.3): the welcome-back card's Collect (or Collect x2, free in an island's first days)
	Router.on("offline.collect", function(s, a)
		local report = s.offline
		if report == nil then
			return false, "not_found"
		end
		local p = s.profile
		if a.mode == "double" and not Store.offlineDouble(p, WorldClock.now()) then
			return false, "locked"
		end
		s.offline = nil
		local n = Store.collect(p, report, if a.mode == "double" then 2 else 1)
		Session.markDirty(s)
		return true, { shells = n }
	end)
	Router.on("settings.set", function(s, a)
		if a.k == "pixel" and type(a.v) == "string" and PIXEL_TIERS[a.v] then
			s.profile.settings.pixel = a.v
			return true, nil
		elseif (a.k == "music" or a.k == "sfx" or a.k == "pals") and (a.v == "on" or a.v == "off") then
			-- the background music, the sounds and the islands' driftlings (the Settings panel; driftlings since
			-- 2026-11-22: "also, add an option to hide driftlings"): on or off, kept with the profile
			s.profile.settings[a.k] = a.v
			return true, nil
		elseif a.k == "zoom" and type(a.v) == "number" and a.v == math.floor(a.v) and a.v >= 1 and a.v <= #Tuning.CamZoomNotches then
			-- the View slider's notch (the Settings panel, 2026-11-18): kept with the profile
			s.profile.settings.zoom = a.v
			return true, nil
		elseif a.k == "lang" and type(a.v) == "string" and (a.v == "auto" or Lang.byCode[a.v] ~= nil) then
			-- the language (the Settings panel, 2026-11-20: "like the bakery game, make translations for different
			-- languages"): "auto" (the player's Roblox language) or a code the game has, kept with the profile
			s.profile.settings.lang = a.v
			return true, nil
		elseif a.k == "text" and (a.v == "pixel" or a.v == "smooth") then
			-- the pixel font or Roblox's own for every word (the Settings panel, 2026-11-20: "an option to turn off
			-- pixel text"), kept with the profile
			s.profile.settings.text = a.v
			return true, nil
		end
		return false, "bad_payload"
	end)
	Router.on("char.home", function(s, _a)
		return PlotService.home(s)
	end)
	Router.on("char.visit", function(s, a)
		return PlotService.visit(s, a.plot)
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
			Store.addXp(s.profile, "quest")
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
			autoHatch(s, laid)
			Session.markDirty(s)
			Session.fx(s, { kind = "eggs", laid = Tree.view(p), more = 0 })
		end
		s.turnClock += dt
		if s.turnClock >= Tuning.TurnSeconds then
			s.turnClock -= Tuning.TurnSeconds
			-- the eggs a turn nearer; the ready ones wait for a tap on their Hatchery (breed.hatch)
			local ready = Breed.turn(p)
			Session.markDirty(s)
			Session.fx(s, { kind = "turn", ready = if #ready > 0 then ready else nil })
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
			-- the store (GAME_DESIGN 14): titles earned by play (Fx "titles"), a new season of the pass track, a minute's
			-- points, a new set in the rotating shop
			local now = WorldClock.now()
			-- (the island is open: offline earnings count from the last second it was)
			p.seenAt = now
			-- today's playtime (a new day starts it again and deals the day's tasks: the whole view goes out)
			if Rewards.sync(p, now) then
				Session.markDirty(s)
			end
			Rewards.tick(p, now, 1)
			local titles = Store.earn(p)
			if #titles > 0 then
				Session.markDirty(s)
				Session.fx(s, { kind = "titles", ids = titles })
			end
			if Store.sync(p, now) then
				Session.markDirty(s)
			end
			local mc = (s.minuteClock or 0) + 1
			s.minuteClock = mc
			if mc >= 60 then
				-- (no whole view for it: the track's points go out with the next one)
				s.minuteClock = mc - 60
				Store.addXp(p, "minute")
			end
			local rot = Store.rotation(now)
			if s.shopRot ~= rot then
				s.shopRot = rot
				Session.markDirty(s)
			end
			Session.fx(s, { kind = "tick", shells = p.shells, dayFrac = WorldClock.dayFrac(), clock = now, clutchLeft = p.clutch.left, clutchSecs = Tree.secs(p), turnIn = Tuning.TurnSeconds - s.turnClock, play = p.rewards.play.secs })
		end
	end
end

-- A player arrives (Main, before the session is ready): what their island made while they were away waits on the
-- welcome-back card (Logic/Store.offline: from Profile.seenAt to now, capped), and the clock of being here starts.
function IslandService.join(s: Session.S)
	local now = WorldClock.now()
	s.offline = Store.offline(s.profile, now)
	s.profile.seenAt = now
	-- (an older save's tips move on through what it has done already: a hut, a driftling, a workplace)
	tips(s)
end

-- A player leaves (Main, before the save): offline earnings not collected yet are paid as shown (Collect), not lost.
function IslandService.leave(s: Session.S)
	local report = s.offline
	if report then
		s.offline = nil
		Store.collect(s.profile, report, 1)
	end
	s.profile.seenAt = WorldClock.now()
end

return IslandService
