--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the island's day clock,
-- and what the client is sent. The client mirrors the profile through State messages (the whole ClientView, sent when
-- something changed: Session.dirty) and shows Fx messages (the stores and the tree every second, a new day, an egg
-- hatched, the driftlings the Tree of Life grew).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
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

-- What the client sees: the profile plus what the rules derive from it. The driftlings: every one in a hut, and of
-- the pen (no room limit: it can hold tens of thousands) only its best Tuning.PenShown, how many wait there and how
-- many are commons, so the view stays small however big the pen grows.
function Session.view(s: S): Types.ClientView
	local p = s.profile
	local r = Island.rates(p)
	local penTop, penN, penCommons = Tree.penView(p, Tuning.PenShown)
	local pals: { Types.Pal } = {}
	for _, x in p.pals do
		if x.home ~= 0 then
			table.insert(pals, x)
		end
	end
	for _, x in penTop do
		table.insert(pals, x)
	end
	return {
		shells = p.shells,
		food = p.food,
		wood = p.wood,
		day = p.day,
		dayFrac = WorldClock.dayFrac(),
		tier = p.tier,
		founder = p.founder,
		pals = pals,
		penN = penN,
		penCommons = penCommons,
		tree = p.tree,
		plot = s.plot,
		pieces = p.plot.placed,
		seen = p.seen,
		eggs = p.eggs,
		tut = p.tut,
		quest = p.quest,
		stats = p.stats,
		settings = p.settings,
		rates = { food = r.food, wood = r.wood, shells = r.shells },
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
