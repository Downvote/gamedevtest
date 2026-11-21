--!strict
-- Leaderboards and friends (docs/ARCHITECTURE.md 7.8; GAME_DESIGN 16; Logic/Social). The request (2026-11-21): "Make a
-- leaderboard system, along with friend invite bonuses". Every Roblox web call is pcall'd: a failure costs a score
-- write, a board read or a friend check, never a session.
--   The boards: each player's scores (Social.scores) go to the boards' OrderedDataStores (DataService.writeBoards)
--   every Tuning.BoardWriteSec while they play and when they leave, an unchanged score skipped. "lb.get" { board }
--   answers the board's top Tuning.BoardRows (read at most every Tuning.BoardCacheSec, names through
--   Players:GetNameFromUserIdAsync, cached) and the asker's own score and place.
--   The player list: leaderstats "Island" (the island's level) and "Earned" (coins earned in all).
--   A friend invited: at the join, the inviter from Player:GetJoinData (ReferredByPlayerId, else LaunchData
--   {"r": <user id>} or a bare id; asked a few times, it can come a moment late), taken by Social.canJoin / join: the
--   welcome gift (Fx "rewards" from "invited"). The friend's seconds of play count (Social.play); once the inviter's
--   reward is due it goes to the inviter at once when they're on this server (Social.reward, Fx "rewards" from
--   "friend"), else it waits in DataService's queue for their next join (and so does one past today's cap).
--   Friends on the server: each pair checked once with IsFriendsWithAsync (a few tries on a failure); Profile.social
--   .here counts each player's friends here (Island.friendsMult), sent in the view.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Social = require(ReplicatedStorage.Shared.Logic.Social)
local DataService = require(script.Parent.DataService)
local Session = require(script.Parent.Session)
local Router = require(script.Parent.Router)

type S = Session.S
type Cache = { at: number, rows: { Types.BoardRow }, loading: boolean }

local SocialService = {}

local JOIN_TRIES = 3 -- GetJoinData attempts (its LaunchData can arrive a second late)
local PAIR_TRIES = 3 -- failed friend checks of a pair before this server stops asking
local NAME_WAIT = 5 -- seconds a board read waits for the names
local STATS_SEC = 5 -- the player list's numbers kept up this often

local caches: { [string]: Cache } = {}
local names: { [number]: string } = {}
local pairs_: { [string]: boolean } = {} -- "lo:hi" -> friends (answers only)
local pairTries: { [string]: number } = {}
local lastScores: { [Player]: { [string]: number } } = {}
local writeAt: { [Player]: number } = {}
local sending: { [Player]: number } = {} -- an inviter's reward being queued: not tried again before this os.clock()
local acc, statsAcc, retryAcc = 0, 0, 0

------------------------------------------------------------------ helpers
local function alive(s: S): boolean
	return s.ready and s.player.Parent ~= nil and Session.get(s.player) == s
end

local function sessionOf(userId: number): S?
	local player = Players:GetPlayerByUserId(userId)
	local s = if player then Session.get(player) else nil
	return if s and alive(s) then s else nil
end

local function pairKey(a: number, b: number): string
	return string.format("%d:%d", math.min(a, b), math.max(a, b))
end

------------------------------------------------------------------ the boards
local function nameOf(userId: number): string?
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.Name
	end
	return names[userId]
end

-- The names of `ids` in parallel (cached), waiting NAME_WAIT seconds at most.
local function resolveNames(ids: { number })
	local waiting = 0
	for _, id in ids do
		if nameOf(id) == nil then
			waiting += 1
			task.spawn(function()
				local ok, name = pcall(function(): string
					return Players:GetNameFromUserIdAsync(id)
				end)
				if ok and type(name) == "string" and name ~= "" then
					names[id] = name
				end
				waiting -= 1
			end)
		end
	end
	local t0 = os.clock()
	while waiting > 0 and os.clock() - t0 < NAME_WAIT do
		task.wait(0.1)
	end
end

local function readRows(board: string): { Types.BoardRow }?
	local raw = DataService.readBoard(board, Tuning.BoardRows)
	if raw == nil then
		return nil
	end
	local ids: { number } = {}
	for _, r in raw do
		table.insert(ids, r.userId)
	end
	resolveNames(ids)
	local rows: { Types.BoardRow } = {}
	for i, r in raw do
		table.insert(rows, { rank = i, userId = r.userId, name = nameOf(r.userId) or "", value = r.value })
	end
	return rows
end

-- A board's top rows from the cache, read again at most every Tuning.BoardCacheSec (a failed read tried again in 15 s).
-- Yields while it reads; a second asker waits for the first's read.
local function board(name: string): { Types.BoardRow }
	local c = caches[name]
	if c == nil then
		c = { at = -math.huge, rows = {}, loading = false }
		caches[name] = c
	end
	local cache = c :: Cache
	if os.clock() - cache.at < Tuning.BoardCacheSec then
		return cache.rows
	end
	if cache.loading then
		local t0 = os.clock()
		while cache.loading and os.clock() - t0 < 10 do
			task.wait(0.2)
		end
		return cache.rows
	end
	cache.loading = true
	local ok, rows = pcall(readRows, name)
	if ok and rows then
		cache.rows = rows
		cache.at = os.clock()
	else
		if not ok then
			warn("[SocialService] board " .. name .. " read failed: " .. tostring(rows))
		end
		cache.at = os.clock() - Tuning.BoardCacheSec + 15
	end
	cache.loading = false
	return cache.rows
end

-- The player's scores to the boards (the ones that changed). Yields.
local function writeScores(s: S)
	local last = lastScores[s.player]
	if last == nil then
		last = {}
		lastScores[s.player] = last
	end
	DataService.writeBoards(s.player.UserId, Social.scores(s.profile), last :: { [string]: number })
end

------------------------------------------------------------------ the player list
local function statsOf(s: S)
	local player = s.player
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		local isle = Instance.new("IntValue")
		isle.Name = "Island"
		isle.Parent = f
		local earned = Instance.new("IntValue")
		earned.Name = "Earned"
		earned.Parent = f
		f.Parent = player
		folder = f
	end
	local f = folder :: Instance
	local isle = f:FindFirstChild("Island")
	local earned = f:FindFirstChild("Earned")
	if isle and isle:IsA("IntValue") and isle.Value ~= s.profile.tier then
		isle.Value = s.profile.tier
	end
	local coins = Social.score(s.profile, "coins")
	if earned and earned:IsA("IntValue") and earned.Value ~= coins then
		earned.Value = coins
	end
end

------------------------------------------------------------------ friends on the server
-- Checks this player against everyone else here (the pairs not known yet). Yields.
local function checkPairs(s: S)
	local me = s.player.UserId
	for _, other in Session.all() do
		if other ~= s and alive(other) then
			local key = pairKey(me, other.player.UserId)
			if pairs_[key] == nil and (pairTries[key] or 0) < PAIR_TRIES then
				local ok, yes = pcall(function(): boolean
					return s.player:IsFriendsWithAsync(other.player.UserId)
				end)
				if ok then
					pairs_[key] = yes == true
				else
					pairTries[key] = (pairTries[key] or 0) + 1
				end
			end
		end
	end
end

-- Everyone's friends here counted again (Profile.social.here), the views sent where it changed.
local function recount()
	local all: { S } = {}
	for _, s in Session.all() do
		if alive(s) then
			table.insert(all, s)
		end
	end
	for _, s in all do
		local n = 0
		for _, other in all do
			if other ~= s and pairs_[pairKey(s.player.UserId, other.player.UserId)] then
				n += 1
			end
		end
		if s.profile.social.here ~= n then
			s.profile.social.here = n
			Session.markDirty(s)
		end
	end
end

------------------------------------------------------------------ a friend invited
-- The inviter in the join's data: (id, final). final = false when nothing came yet and LaunchData may still arrive.
local function inviterFrom(data: any): (number?, boolean)
	if type(data) ~= "table" then
		return nil, false
	end
	local by = data.ReferredByPlayerId
	if type(by) == "number" and by > 0 then
		return math.floor(by), true
	end
	local launch = data.LaunchData
	if type(launch) == "string" and launch ~= "" then
		if #launch > 200 then
			return nil, true
		end
		local ok, decoded = pcall(function(): any
			return HttpService:JSONDecode(launch)
		end)
		if ok and type(decoded) == "table" and type(decoded.r) == "number" then
			return decoded.r, true
		end
		return tonumber(launch), true
	end
	return nil, false
end

local function findInviter(s: S): number?
	for attempt = 1, JOIN_TRIES do
		local ok, data = pcall(function(): any
			return s.player:GetJoinData()
		end)
		if ok then
			local inviter, final = inviterFrom(data)
			if inviter or final then
				return inviter
			end
		end
		if attempt < JOIN_TRIES then
			task.wait(1)
		end
		if not alive(s) then
			return nil
		end
	end
	return nil
end

-- The friend side: a new save joining from an invite takes it, and its welcome gift.
local function applyInvite(s: S)
	local p = s.profile
	if p.social.referredBy ~= 0 or os.time() - p.createdAt >= Tuning.ReferralMaxAgeSec then
		return
	end
	local inviter = findInviter(s)
	if not alive(s) or not Social.canJoin(p, inviter, s.player.UserId, os.time()) then
		return
	end
	local given = Social.join(p, inviter :: number)
	Session.markDirty(s)
	Session.fx(s, { kind = "rewards", from = "invited", given = given })
end

-- The inviter side, on this server: their reward (false: today's are taken).
local function rewardHere(inviter: S): boolean
	local ok, given = Social.reward(inviter.profile, os.time())
	if not ok then
		return false
	end
	Session.markDirty(inviter)
	Session.fx(inviter, { kind = "rewards", from = "friend", given = given })
	return true
end

-- The friend has played long enough: the inviter's reward live, or queued for their next join. Yields.
local function settle(s: S)
	local p = s.profile
	if not Social.due(p) or os.clock() < (sending[s.player] or 0) then
		return
	end
	local inviterId = p.social.referredBy
	local here = sessionOf(inviterId)
	if here and here ~= s and rewardHere(here) then
		p.social.refPaid = true
		Session.markDirty(s)
		return
	end
	sending[s.player] = math.huge
	if DataService.queueReferral(inviterId, s.player.UserId) then
		p.social.refPaid = true
		Session.markDirty(s)
		sending[s.player] = nil
	else
		sending[s.player] = os.clock() + 30 -- (the store failed: again in 30 s)
	end
end

-- The inviter joins: the friends waiting for them, as many as today allows (the rest stay queued). Yields.
local function drain(s: S)
	local left = Social.todayLeft(s.profile, os.time())
	local list = DataService.takeReferrals(s.player.UserId, left)
	for _, e in list do
		if not alive(s) or not rewardHere(s) then
			DataService.queueReferral(s.player.UserId, e.invitee)
		end
	end
end

------------------------------------------------------------------ lifecycle
function SocialService.init()
	Router.on("lb.get", function(s: S, a: any): (boolean, any)
		local name = a.board :: string
		local rows = board(name)
		local mine: number? = nil
		for _, r in rows do
			if r.userId == s.player.UserId then
				mine = r.rank
				break
			end
		end
		return true, { board = name, rows = rows, you = { value = Social.score(s.profile, name), rank = mine } }
	end)
end

-- The join's checks (Main spawns it once the session is ready; yields): the player list, friends here, an invite taken
-- by a new save, friends who played while this inviter was away.
function SocialService.join(s: S)
	writeAt[s.player] = os.clock() + Tuning.BoardWriteSec
	s.profile.social.here = 0
	statsOf(s)
	checkPairs(s)
	if not alive(s) then
		return
	end
	recount()
	applyInvite(s)
	if not alive(s) then
		return
	end
	drain(s)
end

-- Leaving: the scores written once more, the others' friends here counted again.
function SocialService.leave(s: S)
	local player = s.player
	writeAt[player] = nil
	sending[player] = nil
	task.spawn(function()
		writeScores(s)
		lastScores[player] = nil
	end)
	recount()
end

-- The fixed step (Main, Tuning.StepHz): each second the friends' play time and the rewards due; the player list every
-- STATS_SEC; scores written on their timer; friend checks that failed asked again every 30 s.
function SocialService.step(dt: number)
	acc += dt
	statsAcc += dt
	retryAcc += dt
	if acc >= 1 then
		local secs = acc
		acc = 0
		local now = os.clock()
		for player, s in Session.all() do
			if alive(s) then
				if Social.play(s.profile, secs) or Social.due(s.profile) then
					task.spawn(settle, s)
				end
				local at = writeAt[player]
				if at and now >= at then
					writeAt[player] = now + Tuning.BoardWriteSec
					task.spawn(writeScores, s)
				end
			end
		end
	end
	if statsAcc >= STATS_SEC then
		statsAcc = 0
		for _, s in Session.all() do
			if alive(s) then
				statsOf(s)
			end
		end
	end
	if retryAcc >= 30 then
		retryAcc = 0
		task.spawn(function()
			local missing = false
			for _, s in Session.all() do
				for _, other in Session.all() do
					local key = pairKey(s.player.UserId, other.player.UserId)
					if other ~= s and pairs_[key] == nil and (pairTries[key] or 0) < PAIR_TRIES then
						missing = true
					end
				end
			end
			if missing then
				for _, s in Session.all() do
					if alive(s) then
						checkPairs(s)
					end
				end
				recount()
			end
		end)
	end
end

return SocialService
