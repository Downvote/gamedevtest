--!strict
-- The studio on the server (docs/ARCHITECTURE.md 7.4): every player action and the game clock, as thin wrappers
-- round Logic/Studio (the rules) that mark the session dirty, tell PlotService when the office changes and send the
-- week's events to the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)
local Session = require(script.Parent.Session)
local Router = require(script.Parent.Router)
local PlotService = require(script.Parent.PlotService)

local StudioService = {}

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
	Router.on("tut.next", function(s, _a)
		s.profile.tut = 0
		return true, nil
	end)
	-- the client holds the clock while a full-screen menu is open (the new game wizard, the reviews)
	Router.onSignal("pause", function(s, payload)
		if type(payload) == "table" and type(payload.key) == "string" and #payload.key <= 16 then
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

-- The clock (Main's fixed step): every unpaused, ready session moves on a week every Tuning.WeekSec.
function StudioService.step(dt: number)
	for _, s in Session.all() do
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
