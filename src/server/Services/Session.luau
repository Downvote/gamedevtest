--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the island's day clock,
-- and what the client is sent. The client mirrors the profile through State messages (the whole ClientView, sent when
-- something changed: Session.dirty) and shows Fx messages (the stores and the tide's clock every second, a new day, an
-- egg hatched, the driftlings that drifted in and off). The tide (Logic/Tide.State) is the session's, never saved.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tide = require(ReplicatedStorage.Shared.Logic.Tide)
local WorldClock = require(script.Parent.WorldClock)

export type S = {
	player: Player,
	profile: Types.Profile,
	plot: number,
	rng: Types.Rng,
	ready: boolean,
	turnClock: number, -- seconds into the island's turn
	dayIndex: number, -- the sea's calendar day when this island last counted one (WorldClock.dayIndex)
	tickClock: number, -- seconds toward the next stores message
	tide: Tide.State, -- the driftlings bobbing at the jetty (IslandService steps it)
	dirty: boolean,
	saveAt: number,
	reqTimes: { number },
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
		turnClock = 0,
		dayIndex = WorldClock.dayIndex(),
		tickClock = 0,
		tide = Tide.new(),
		dirty = true,
		saveAt = os.clock() + Tuning.AutosaveSec,
		reqTimes = {},
	}
	-- (the jetty has a few bobbing there already when the player arrives)
	Tide.start(profile, s.tide, s.rng)
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

-- What the client sees: the profile plus what the rules derive from it, and the tide (each one's cost on this island).
function Session.view(s: S): Types.ClientView
	local p = s.profile
	local r = Island.rates(p)
	return {
		shells = p.shells,
		wood = p.wood,
		day = p.day,
		dayFrac = WorldClock.dayFrac(),
		tier = p.tier,
		founder = p.founder,
		pals = p.pals,
		tide = Tide.view(p, s.tide),
		tideT = s.tide.t,
		tideSecs = Tide.secs(p),
		plot = s.plot,
		pieces = p.plot.placed,
		seen = p.seen,
		eggs = p.eggs,
		tut = p.tut,
		quest = p.quest,
		stats = p.stats,
		settings = p.settings,
		rates = { wood = r.wood, shells = r.shells },
		charm = Island.charm(p),
		nests = Island.nests(p),
		visitors = Island.visitors(p),
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
