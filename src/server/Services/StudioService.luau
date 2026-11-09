--!strict
-- The studio on the server (docs/ARCHITECTURE.md 7.4): every player action and the two clocks, as thin wrappers round
-- Logic/Studio (the rules) that mark the session dirty and tell the client what happened. The idea team thinks up an
-- idea every Studio.rollEvery seconds (Fx "idea"); the game on sale (Logic/Live) ages with the clock and its coins are
-- paid every Tuning.IncomeTickSec (Fx "coins" with its players, so the whole view is not sent every second; Fx
-- "offsale" when it leaves the shops). Both run while the player is here, whatever they do.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)
local Ideas = require(ReplicatedStorage.Shared.Logic.Ideas)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Live = require(ReplicatedStorage.Shared.Logic.Live)
local Session = require(script.Parent.Session)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local StudioService = {}

local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

function StudioService.init()
	-- making a game (GAME_DESIGN 5): the game on sale leaves the shops
	Router.on("game.make", function(s, a)
		local ok, data = Studio.make(s.profile, a.a, a.b, a.c, s.rng:int(1, 999999))
		if ok then
			s.micro = nil
			s.coinFrac = 0
		end
		return ok, data
	end)
	-- a microgame for slot 1..3: a new start replaces one in play (a retry at any point); its finish must carry the
	-- start's token, and a win sooner than Tuning.MicroMinSec or a result later than Tuning.MicroMaxSec is a loss
	Router.on("micro.start", function(s, a)
		local proj = s.profile.project
		if proj == nil then
			return false, "no_project"
		end
		local micro: Session.Micro = { slot = a.slot, token = s.rng:int(1, 999999), at = os.clock(), seed = s.rng:int(1, 999999) }
		s.micro = micro
		local card = proj.ideas[a.slot]
		return true, { slot = micro.slot, token = micro.token, seed = micro.seed, diff = Ideas.difficulty(card), card = card }
	end)
	Router.on("micro.finish", function(s, a)
		local micro = s.micro
		if micro == nil or micro.token ~= a.token then
			return false, "busy"
		end
		s.micro = nil
		local elapsed = os.clock() - micro.at
		local won = a.won == 1 and elapsed >= Tuning.MicroMinSec and elapsed <= Tuning.MicroMaxSec
		return Studio.result(s.profile, micro.slot, won)
	end)
	Router.on("game.launch", function(s, _a)
		local ok, data = Studio.launch(s.profile, os.time(), s.rng:int(1, 999999))
		if ok then
			s.micro = nil
		end
		return ok, data
	end)
	-- the idea team's upgrades (GAME_DESIGN 7)
	Router.on("upgrade.buy", function(s, a)
		return Studio.buyUpgrade(s.profile, a.k)
	end)
	-- the founder's look (GAME_DESIGN 9): the player's attribute follows on the next sync
	Router.on("founder.set", function(s, a)
		return Studio.setFounder(s.profile, a.skin, a.hair, a.style, a.shirt)
	end)
	Router.on("settings.set", function(s, a)
		if a.k == "pixel" and type(a.v) == "string" and PIXEL_TIERS[a.v] then
			s.profile.settings.pixel = a.v
			return true, nil
		end
		return false, "bad_payload"
	end)
	-- the plot (GAME_DESIGN 9): every change rebuilds the plot's decor by difference
	Router.on("plot.buy", function(s, a)
		return Plot.buy(s.profile, a.id)
	end)
	Router.on("plot.place", function(s, a)
		local ok, data = Plot.place(s.profile, a.id, a.x, a.z, a.rot)
		if ok then
			PlotService.buildDecor(s)
		end
		return ok, data
	end)
	Router.on("plot.move", function(s, a)
		local ok, data = Plot.move(s.profile, a.i, a.x, a.z, a.rot)
		if ok then
			PlotService.buildDecor(s)
		end
		return ok, data
	end)
	Router.on("plot.store", function(s, a)
		local ok, data = Plot.store(s.profile, a.i)
		if ok then
			PlotService.buildDecor(s)
		end
		return ok, data
	end)
	Router.on("char.home", function(s, _a)
		return PlotService.home(s)
	end)
	Router.on("tut.next", function(s, _a)
		s.profile.tut = 0
		return true, nil
	end)
end

-- The idea team's next idea for a session: the rules, then the client is told.
function StudioService.roll(s: Session.S)
	local r = Studio.rollIdea(s.profile, s.rng)
	Session.markDirty(s)
	Session.fx(s, { kind = "idea", card = r.card, slot = r.slot, replaced = r.replaced, oneIn = r.oneIn, tier = r.tier, first = r.first })
end

-- The clocks (Main's fixed step): every ready session's idea team and income. A microgame left open past
-- Tuning.MicroMaxSec is dropped.
function StudioService.step(dt: number)
	local now = os.clock()
	for _, s in Session.all() do
		if not s.ready then
			continue
		end
		local p = s.profile
		s.rollClock += dt
		local every = Studio.rollEvery(p)
		local guard = 0
		while s.rollClock >= every and guard < 4 do
			s.rollClock -= every
			guard += 1
			StudioService.roll(s)
		end
		local coins, ended = Studio.sell(p, dt)
		s.coinFrac += coins
		s.payClock += dt
		if s.payClock >= Tuning.IncomeTickSec then
			s.payClock -= Tuning.IncomeTickSec
			local whole = math.floor(s.coinFrac)
			if whole > 0 then
				s.coinFrac -= whole
				Studio.earn(p, whole)
			end
			local l = p.live
			if whole > 0 or (l and not Live.over(l)) then
				Session.fx(s, { kind = "coins", coins = p.coins, paid = whole, rate = Live.earning(l), live = if l then Live.brief(l) else nil })
			end
		end
		if ended then
			local l = p.live :: any
			Session.markDirty(s)
			Session.fx(s, { kind = "offsale", title = l.title, earned = math.floor(l.earned + 0.5), peak = l.peak })
		end
		local micro = s.micro
		if micro and now - micro.at > Tuning.MicroMaxSec then
			s.micro = nil
		end
	end
end

return StudioService
