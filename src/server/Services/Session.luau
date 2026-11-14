--!strict
-- Player sessions (docs/ARCHITECTURE.md 7.2): the loaded profile, the plot, the session's Rng, the island's day clock,
-- and what the client is sent. The client mirrors the profile through State messages (the whole ClientView, sent when
-- something changed: Session.dirty) and shows Fx messages (the stores and the time to the tree's next eggs every
-- second, a new day, an egg hatched, the Tree of Life's new eggs). The tree's eggs are the profile's (saved).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Store = require(ReplicatedStorage.Shared.Logic.Store)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
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
	minuteClock: number?, -- seconds toward the pass track's next minute of points (GAME_DESIGN 14)
	shopRot: number?, -- the rotating shop's rotation last sent
	offline: Types.OfflineReport?, -- what the island made while its player was away, waiting to be collected (GAME_DESIGN 14.3)
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
		minuteClock = 0,
		shopRot = (Store.rotation(WorldClock.now())),
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

-- What the client sees: the profile plus what the rules derive from it (the tree's eggs each with its price).
function Session.view(s: S): Types.ClientView
	local p = s.profile
	local r = Island.rates(p)
	local now = WorldClock.now()
	Store.sync(p, now)
	local shopList, shopLeft = Store.shopNow(p, now)
	local lvl, into, need = Store.level(p)
	local _, trackLeft = Store.season(now)
	return {
		shells = p.shells,
		day = p.day,
		dayFrac = WorldClock.dayFrac(),
		clock = WorldClock.now(),
		tier = p.tier,
		founder = p.founder,
		pals = p.pals,
		clutch = Tree.view(p),
		clutchLeft = p.clutch.left,
		clutchSecs = Tree.secs(p),
		plot = s.plot,
		pieces = p.plot.placed,
		inv = p.inv,
		seen = p.seen,
		eggs = p.eggs,
		tut = p.tut,
		quest = p.quest,
		stats = p.stats,
		settings = p.settings,
		rates = { shells = r.shells },
		charm = Island.charm(p),
		charmBonus = Island.charmBonus(Island.charm(p)),
		nests = Island.nests(p),
		-- the store (GAME_DESIGN 14)
		passes = p.passes,
		gifts = p.gifts,
		vipDay = p.vipDay,
		bag = p.bag,
		owned = p.owned,
		titles = p.titles,
		title = p.title,
		shopList = shopList,
		shopLeft = shopLeft,
		shopRefresh = Store.refreshes(p, now),
		track = p.track,
		trackLevel = lvl,
		trackInto = into,
		trackNeed = need,
		trackLeft = trackLeft,
		minuteShells = Store.perMinute(p),
		incomeMult = Island.passMult(p),
		offline = if s.offline then s.offline else false,
		offlineHours = Store.offlineCap(p) / 3600,
		offlinePct = Store.offlinePct(p),
		offlineDouble = Store.offlineDouble(p, now),
		group = p.group,
		groupOn = Monetization.isEnabled(Monetization.Group.Id),
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
