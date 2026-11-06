--!strict
-- The studio on the server (docs/ARCHITECTURE.md 7.4): every player action and the game clock, as thin wrappers
-- round Logic/Studio (the rules) that mark the session dirty, tell PlotService when the office changes and send the
-- week's events to the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Minigames = require(ReplicatedStorage.Shared.Logic.Minigames)
local Session = require(script.Parent.Session)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local StudioService = {}

local MINI_KEY: string = "mini" -- the clock's hold while a minigame is in play (the server's own pause key)
local PIXEL_TIERS: { [string]: boolean } = { high = true, medium = true, low = true, off = true }

function StudioService.init()
	Router.on("project.start", function(s, a)
		return Studio.start(s.profile, a)
	end)
	Router.on("project.release", function(s, _a)
		return Studio.release(s.profile, s.rng)
	end)
	Router.on("staff.hire", function(s, a)
		return Studio.hire(s.profile, a.i)
	end)
	Router.on("staff.fire", function(s, a)
		return Studio.fire(s.profile, a.id)
	end)
	Router.on("staff.train", function(s, a)
		return Studio.train(s.profile, a.id, a.skill)
	end)
	Router.on("staff.party", function(s, _a)
		return Studio.party(s.profile)
	end)
	Router.on("research.genre", function(s, a)
		return Studio.unlockGenre(s.profile, a.id)
	end)
	Router.on("research.topic", function(s, a)
		return Studio.unlockTopic(s.profile, a.id)
	end)
	Router.on("office.move", function(s, _a)
		local ok, data = Studio.move(s.profile)
		if ok then
			PlotService.build(s)
		end
		return ok, data
	end)
	Router.on("office.ad", function(s, _a)
		return Studio.ad(s.profile)
	end)
	Router.on("settings.set", function(s, a)
		if a.k == "pixel" and type(a.v) == "string" and PIXEL_TIERS[a.v] then
			s.profile.settings.pixel = a.v
			return true, nil
		end
		return false, "bad_payload"
	end)
	-- the plot (GAME_DESIGN 13): every change rebuilds the plot's decor by difference
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
	-- minigames (GAME_DESIGN 14): start spends the push (or starts Bug Squash's cooldown) and holds the clock; the
	-- finish must carry the start's token. One finished sooner than Tuning.MiniMinSec or later than Tuning.MiniMaxSec
	-- counts as a score of 0 (a quit, or a game left open).
	Router.on("mini.start", function(s, a)
		if s.mini then
			return false, "busy"
		end
		local ok, err = Minigames.start(s.profile, a.kind)
		if not ok then
			return false, err
		end
		local mini: Session.Mini = { kind = a.kind, token = s.rng:int(1, 999999), at = os.clock(), seed = s.rng:int(1, 999999) }
		s.mini = mini
		s.paused[MINI_KEY] = true
		return true, { kind = mini.kind, token = mini.token, seed = mini.seed, seconds = Tuning.MiniSeconds }
	end)
	Router.on("mini.finish", function(s, a)
		local mini = s.mini
		if mini == nil or mini.token ~= a.token then
			return false, "busy"
		end
		s.mini = nil
		s.paused[MINI_KEY] = nil
		local elapsed = os.clock() - mini.at
		local score = if elapsed < Tuning.MiniMinSec or elapsed > Tuning.MiniMaxSec then 0 else a.score
		return Minigames.finish(s.profile, mini.kind, score)
	end)
	Router.on("tut.next", function(s, _a)
		s.profile.tut = 0
		return true, nil
	end)
	-- the client holds the clock while a full-screen menu is open (the new game wizard, the reviews)
	Router.onSignal("pause", function(s, payload)
		-- "mini" is the server's own key (a minigame in play)
		if type(payload) == "table" and type(payload.key) == "string" and #payload.key <= 16 and payload.key ~= MINI_KEY then
			if payload.on == true then
				local n = 0
				for _ in s.paused do
					n += 1
				end
				if n < 4 then
					s.paused[payload.key] = true
				end
			else
				s.paused[payload.key] = nil
			end
			Session.markDirty(s)
		end
	end)
end

-- One game week for a session: the rules, then its events to the client.
function StudioService.week(s: Session.S)
	local events = Studio.week(s.profile, s.rng)
	Session.markDirty(s)
	Session.fx(s, { kind = "week", week = s.profile.week, events = events })
end

-- The clock (Main's fixed step): every unpaused, ready session moves on a week every Tuning.WeekSec. A minigame left
-- open past Tuning.MiniMaxSec is dropped (its push stays spent) and the clock runs again.
function StudioService.step(dt: number)
	local now = os.clock()
	for _, s in Session.all() do
		local mini = s.mini
		if mini and now - mini.at > Tuning.MiniMaxSec then
			s.mini = nil
			s.paused[MINI_KEY] = nil
			Session.markDirty(s)
		end
		if s.ready and not Session.isPaused(s) then
			s.clock += dt
			if s.clock >= Tuning.WeekSec then
				s.clock -= Tuning.WeekSec
				StudioService.week(s)
			end
		end
	end
end

return StudioService
