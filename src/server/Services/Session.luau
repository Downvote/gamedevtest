--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the idea team's and
-- the income's clocks, the microgame in play, and what the client is sent. The client mirrors the profile through
-- State messages (the whole ClientView, sent when something changed: Session.dirty) and shows Fx messages (a new
-- idea, the coins the game on sale just paid and its players).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Studio = require(ReplicatedStorage.Shared.Logic.Studio)
local Live = require(ReplicatedStorage.Shared.Logic.Live)

export type S = {
	player: Player,
	profile: Types.Profile,
	plot: number,
	rng: Types.Rng,
	ready: boolean,
	rollClock: number, -- seconds toward the idea team's next idea
	payClock: number, -- seconds toward the next income payment
	coinFrac: number, -- income earned but not yet a whole coin
	dirty: boolean,
	saveAt: number,
	reqTimes: { number },
	micro: Micro?, -- the microgame in play (GAME_DESIGN 5)
}

-- A started microgame: its slot (1..3), the token its finish must carry, when it started (os.clock), its seed.
export type Micro = { slot: number, token: number, at: number, seed: number }

local Session = {}

local sessions: { [Player]: S } = {}

function Session.create(player: Player, profile: Types.Profile, plot: number): S
	local s: S = {
		player = player,
		profile = profile,
		plot = plot,
		rng = Util.newRng(Util.hash32(tostring(player.UserId) .. ":" .. tostring(os.time()))),
		ready = false,
		rollClock = 0,
		payClock = 0,
		coinFrac = 0,
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

-- What the client sees: the profile plus derived fields.
function Session.view(s: S): Types.ClientView
	local p = s.profile
	return {
		coins = p.coins,
		rate = Live.earning(p.live),
		live = p.live,
		ideas = p.ideas,
		found = p.found,
		project = p.project,
		games = p.games,
		upgrades = p.upgrades,
		team = p.team,
		office = p.office,
		tut = p.tut,
		stats = p.stats,
		settings = p.settings,
		plot = s.plot,
		rollEvery = Studio.rollEvery(p),
		luck = Studio.luck(p),
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
