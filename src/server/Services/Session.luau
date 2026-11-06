--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the clock, and what
-- the client is sent. The client mirrors the profile through State messages (the whole ClientView, sent when
-- something changed: Session.dirty) and shows Fx messages (a week's events).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)

export type S = {
	player: Player,
	profile: Types.Profile,
	plot: number,
	rng: Types.Rng,
	ready: boolean,
	clock: number, -- seconds toward the next game week
	paused: { [string]: boolean }, -- the client's reasons to hold the clock (a full-screen menu)
	dirty: boolean,
	saveAt: number,
	reqTimes: { number },
	mini: Mini?, -- the minigame in play (GAME_DESIGN 14): its clock is held until it finishes
}

-- A started minigame: what it is, the token its finish must carry, when it started (os.clock) and its content seed.
export type Mini = { kind: string, token: number, at: number, seed: number }

local Session = {}

local sessions: { [Player]: S } = {}

function Session.create(player: Player, profile: Types.Profile, plot: number): S
	local s: S = {
		player = player,
		profile = profile,
		plot = plot,
		rng = Util.newRng(Util.hash32(tostring(player.UserId) .. ":" .. tostring(os.time()))),
		ready = false,
		clock = 0,
		paused = {},
		dirty = true,
		saveAt = os.clock() + Tuning.AutosaveSec,
		reqTimes = {},
	}
	sessions[player] = s
	return s
end

function Session.get(player: Player): S?
	return sessions[player]
end

function Session.remove(player: Player)
	sessions[player] = nil
end

function Session.all(): { [Player]: S }
	return sessions
end

function Session.isPaused(s: S): boolean
	return next(s.paused) ~= nil
end

-- What the client sees: the profile minus the old releases, plus derived fields.
function Session.view(s: S): Types.ClientView
	local p = s.profile
	local releases = {}
	local n = #p.releases
	for i = math.max(1, n - Tuning.ViewReleases + 1), n do
		table.insert(releases, p.releases[i])
	end
	return {
		money = p.money,
		fans = p.fans,
		rp = p.rp,
		week = p.week,
		office = p.office,
		staff = p.staff,
		candidates = p.candidates,
		project = p.project,
		releases = releases,
		genres = p.genres,
		topics = p.topics,
		matches = p.matches,
		awards = p.awards,
		tut = p.tut,
		stats = p.stats,
		settings = p.settings,
		plot = s.plot,
		canAd = Studio.canAd(p),
		canParty = Studio.canParty(p),
		paused = Session.isPaused(s),
		founder = p.founder,
		decor = p.plot,
	}
end

function Session.markDirty(s: S)
	s.dirty = true
end

-- Send the view if it changed (Main calls it every step; requests mark the session dirty).
function Session.flush(s: S)
	if s.dirty and s.ready then
		s.dirty = false
		Net.get().State:FireClient(s.player, Session.view(s))
	end
end

function Session.fx(s: S, msg: { [string]: any })
	if s.ready then
		Net.get().Fx:FireClient(s.player, msg)
	end
end

-- Requests per second (Router's rate limit): true when this one is allowed.
function Session.allow(s: S, now: number): boolean
	local times = s.reqTimes
	while #times > 0 and now - times[1] > 1 do
		table.remove(times, 1)
	end
	if #times >= Tuning.RateLimitPerSec then
		return false
	end
	table.insert(times, now)
	return true
end

return Session
