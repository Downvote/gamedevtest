--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the island's day clock,
-- the expedition under way, and what the client is sent. The client mirrors the profile through State messages (the
-- whole ClientView, sent when something changed: Session.dirty) and shows Fx messages (the stores every second, a new
-- day and who moved in, an expedition's events).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Expedition = require(ReplicatedStorage.Shared.Logic.Expedition)

export type S = {
	player: Player,
	profile: Types.Profile,
	plot: number,
	rng: Types.Rng,
	ready: boolean,
	dayClock: number, -- seconds into the island's day
	tickClock: number, -- seconds toward the next stores message
	dirty: boolean,
	saveAt: number,
	reqTimes: { number },
	exp: Types.Expedition?, -- the expedition under way (GAME_DESIGN 7)
	away: { [string]: boolean }, -- its party's keys
}

local Session = {}

local sessions: { [Player]: S } = {}

function Session.create(player: Player, profile: Types.Profile, plot: number): S
	local s: S = {
		player = player,
		profile = profile,
		plot = plot,
		rng = Util.newRng(Util.hash32(tostring(player.UserId) .. ":" .. tostring(os.time()))),
		ready = false,
		dayClock = 0,
		tickClock = 0,
		dirty = true,
		saveAt = os.clock() + Tuning.AutosaveSec,
		reqTimes = {},
		exp = nil,
		away = {},
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

-- What the client sees: the profile plus what the rules derive from it.
function Session.view(s: S): Types.ClientView
	local p = s.profile
	local r = Island.rates(p, s.away)
	return {
		shells = p.shells,
		food = p.food,
		wood = p.wood,
		day = p.day,
		dayFrac = s.dayClock / Tuning.DaySeconds,
		tier = p.tier,
		founder = p.founder,
		cap = p.cap,
		folk = p.folk,
		pals = p.pals,
		plot = s.plot,
		pieces = p.plot.placed,
		islets = p.islets,
		sea = p.sea,
		boat = p.boat,
		chart = p.chart,
		seen = p.seen,
		tut = p.tut,
		stats = p.stats,
		settings = p.settings,
		rates = { food = r.food, wood = r.wood, shells = r.shells },
		charm = Island.charm(p),
		beds = Island.beds(p),
		nests = Island.nests(p),
		visitors = Island.visitors(p),
		exp = s.exp,
	}
end

-- The expedition's party now (Island.rates leaves them out).
function Session.setExp(s: S, e: Types.Expedition?)
	s.exp = e
	s.away = Expedition.away(e)
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
