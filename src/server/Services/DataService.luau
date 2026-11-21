--!strict
-- Saves (docs/ARCHITECTURE.md 7.6): one DataStore key per player, a session lock, retries, autosave, and a memory
-- fallback when DataStores are off (Studio without API access: a warning says so).
-- A saved record is { data = Profile, lock = { job = JobId, t = os.time() }? }. A lock younger than Tuning.LockTTL
-- held by another server means that server may still have the player (a quick rejoin while it saves them on leave):
-- load waits and retries, and on its last attempt (Tuning.LoadRetries, about 10 s in) takes the lock over, since a
-- server that was saving has done so by then and a crashed one never releases it. save never overwrites a record
-- whose lock another server holds, so a late save from the old server is dropped rather than rolling the player
-- back. Never rename Tuning.DataStoreName: the players' saves are there.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local DataService = {}

local store: GlobalDataStore? = nil
local memory: { [string]: any } = {}
local usingMemory = false
local jobId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
-- the saves and unlocks going now (BindToClose waits for them), and the players whose leaving save has gone out: a
-- later save from this server (an autosave that started before they left) never writes or locks their record again
local pending = 0
local released: { [number]: boolean } = {}

function DataService.init()
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Tuning.DataStoreName)
	end)
	if ok and s then
		store = s
	else
		usingMemory = true
		warn("[DataService] DataStores unavailable; saves live in memory only: " .. tostring(s))
	end
end

local function keyOf(userId: number): string
	return "u_" .. tostring(userId)
end

-- UpdateAsync with the memory fallback (and a fall back to memory when the store fails for good in Studio).
local function update(key: string, fn: (any) -> any): (boolean, any)
	if usingMemory or store == nil then
		local out = fn(memory[key])
		if out ~= nil then
			memory[key] = out
		end
		return true, memory[key]
	end
	local s = store :: GlobalDataStore
	return pcall(function()
		return s:UpdateAsync(key, function(old: any)
			return fn(old)
		end)
	end)
end

-- Load and lock a player's save. Returns the raw profile table (nil for a new player) and ok; ok = false when the
-- store could not be read (the caller kicks: playing on would overwrite a save it could not see).
function DataService.load(userId: number): (any, boolean)
	local key = keyOf(userId)
	released[userId] = nil
	for attempt = 1, Tuning.LoadRetries do
		local lockedByOther = false
		local raw: any = nil
		local ok, err = update(key, function(old: any): any
			local rec = if type(old) == "table" then old else {}
			local lock = rec.lock
			if type(lock) == "table" and lock.job ~= jobId and type(lock.t) == "number" and os.time() - lock.t < Tuning.LockTTL and attempt < Tuning.LoadRetries then
				lockedByOther = true
				return nil -- leave it as it is
			end
			raw = rec.data
			rec.lock = { job = jobId, t = os.time() }
			return rec
		end)
		if ok and not lockedByOther then
			return raw, true
		end
		if not ok then
			warn(string.format("[DataService] load %d failed (attempt %d): %s", userId, attempt, tostring(err)))
		end
		task.wait(if lockedByOther then 3 else 1 + attempt)
	end
	return nil, false
end

-- Save a profile; release = also drop the lock (the player left). Returns whether the record now holds it: false when
-- the store failed, when another server holds the player's lock (nothing written: its save is newer), or for a save
-- after the player's leaving one. A leaving save is tried Tuning.SaveRetries times (the store's cooldown on one key
-- after an autosave, a hiccup): it is the last chance, and a lost one rolled the player back to the last autosave.
-- (The server review of 2026-11-19: the leaving save was one try nothing waited for, and a skipped save said ok.)
function DataService.save(userId: number, profile: Types.Profile, release: boolean?): boolean
	if released[userId] and not release then
		return false
	end
	if release then
		released[userId] = true
	end
	local key = keyOf(userId)
	pending += 1
	local wrote = false
	local tries = if release then Tuning.SaveRetries else 1
	for attempt = 1, tries do
		local skipped = false
		local ok, err = update(key, function(old: any): any
			local rec = if type(old) == "table" then old else {}
			local lock = rec.lock
			if type(lock) == "table" and lock.job ~= jobId and type(lock.t) == "number" and os.time() - lock.t < Tuning.LockTTL then
				skipped = true
				return nil -- another server took over: never overwrite its save
			end
			if not release and released[userId] then
				skipped = true
				return nil -- (an autosave finishing after the leaving save: it would lock the record again)
			end
			rec.data = profile
			rec.lock = if release then nil else { job = jobId, t = os.time() }
			return rec
		end)
		if ok then
			wrote = not skipped
			break
		end
		warn(string.format("[DataService] save %d failed (attempt %d): %s", userId, attempt, tostring(err)))
		if attempt < tries then
			task.wait(2 * attempt)
		end
	end
	pending -= 1
	return wrote
end

-- Drop this server's lock on a player's record without saving: a join that stopped before play (the player left while
-- it loaded, or the save is newer than this server), so their next join elsewhere does not wait out the lock.
function DataService.unlock(userId: number)
	pending += 1
	local ok, err = update(keyOf(userId), function(old: any): any
		if type(old) ~= "table" then
			return nil
		end
		local lock = old.lock
		if type(lock) == "table" and lock.job == jobId then
			old.lock = nil
			return old
		end
		return nil
	end)
	if not ok then
		warn(string.format("[DataService] unlock %d failed: %s", userId, tostring(err)))
	end
	pending -= 1
end

------------------------------------------------------------------ leaderboards and friends (GAME_DESIGN 16)
-- The boards are OrderedDataStores (Tuning.BoardStores: never rename them, the scores are there), one entry per player
-- ("u_<id>" -> a whole score). The friends invited wait in Tuning.ReferralStoreName under the inviter's key ("u_<id>"
-- -> { { invitee, at } }) until the inviter's next join. With DataStores off, both live in memory too.
local boardStores: { [string]: OrderedDataStore } = {}
local memBoards: { [string]: { [string]: number } } = {}
local refStore: GlobalDataStore? = nil

local function boardStore(board: string): OrderedDataStore?
	local name = Tuning.BoardStores[board]
	if usingMemory or name == nil then
		return nil
	end
	local hit = boardStores[board]
	if hit then
		return hit
	end
	local ok, ods = pcall(function(): OrderedDataStore
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok and ods then
		boardStores[board] = ods
		return ods
	end
	warn("[DataService] board store " .. board .. " unavailable: " .. tostring(ods))
	return nil
end

-- Write a player's scores (board -> whole number) where they changed since `last` (board -> the score last written,
-- updated as each write lands). Yields; BindToClose waits for it.
function DataService.writeBoards(userId: number, scores: { [string]: number }, last: { [string]: number })
	pending += 1
	local key = keyOf(userId)
	for board, value in scores do
		local v = math.max(0, math.floor(value))
		if last[board] ~= v and Tuning.BoardStores[board] ~= nil then
			if usingMemory then
				local t = memBoards[board] or {}
				memBoards[board] = t
				t[key] = v
				last[board] = v
			else
				local ods = boardStore(board)
				if ods then
					local ok, err = pcall(function()
						(ods :: OrderedDataStore):SetAsync(key, v)
					end)
					if ok then
						last[board] = v
					else
						warn(string.format("[DataService] board %s write for %d failed: %s", board, userId, tostring(err)))
					end
				end
			end
		end
	end
	pending -= 1
end

-- A board's top n, best first: { { userId, value } }; nil when it couldn't be read. Yields.
function DataService.readBoard(board: string, n: number): { { userId: number, value: number } }?
	local out: { { userId: number, value: number } } = {}
	local function add(key: any, value: any)
		local id = if type(key) == "string" then tonumber(string.match(key, "^u_(%d+)$")) else nil
		if id and type(value) == "number" then
			table.insert(out, { userId = id, value = value })
		end
	end
	if usingMemory then
		local t: { [string]: number } = memBoards[board] or {}
		for key, value in t do
			add(key, value)
		end
		table.sort(out, function(a, b)
			return if a.value ~= b.value then a.value > b.value else a.userId < b.userId
		end)
		while #out > n do
			table.remove(out)
		end
		return out
	end
	local ods = boardStore(board)
	if ods == nil then
		return nil
	end
	local ok, entries = pcall(function(): any
		return (ods :: OrderedDataStore):GetSortedAsync(false, math.clamp(n, 1, 100)):GetCurrentPage()
	end)
	if not ok or type(entries) ~= "table" then
		warn("[DataService] board " .. board .. " read failed: " .. tostring(entries))
		return nil
	end
	for _, e in entries do
		if type(e) == "table" then
			add(e.key, e.value)
		end
	end
	return out
end

local function refUpdate(key: string, fn: (any) -> any): (boolean, any)
	if usingMemory then
		local out = fn(memory["ref:" .. key])
		if out ~= nil then
			memory["ref:" .. key] = out
		end
		return true, memory["ref:" .. key]
	end
	if refStore == nil then
		local ok, st = pcall(function(): GlobalDataStore?
			return DataStoreService:GetDataStore(Tuning.ReferralStoreName)
		end)
		if not ok or st == nil then
			return false, st
		end
		refStore = st :: GlobalDataStore
	end
	local st = refStore :: GlobalDataStore
	return pcall(function()
		return st:UpdateAsync(key, function(old: any)
			return fn(old)
		end)
	end)
end

-- A friend invited by an inviter who isn't on this server played long enough: noted for the inviter's next join (once
-- per friend; at most 100 waiting). True when it was written. Yields.
function DataService.queueReferral(inviterId: number, inviteeId: number): boolean
	pending += 1
	local ok, err = refUpdate(keyOf(inviterId), function(old: any): any
		local list = if type(old) == "table" then old else {}
		for _, e in list do
			if type(e) == "table" and e.invitee == inviteeId then
				return list -- (already waiting)
			end
		end
		if #list >= 100 then
			return nil
		end
		table.insert(list, { invitee = inviteeId, at = os.time() })
		return list
	end)
	if not ok then
		warn(string.format("[DataService] queueReferral %d for %d failed: %s", inviteeId, inviterId, tostring(err)))
	end
	pending -= 1
	return ok
end

-- Take up to `max` of an inviter's waiting friends (the rest stay for another time). Yields; {} on failure.
function DataService.takeReferrals(userId: number, max: number): { { invitee: number, at: number } }
	if max <= 0 then
		return {}
	end
	local taken: { { invitee: number, at: number } } = {}
	pending += 1
	local ok, err = refUpdate(keyOf(userId), function(old: any): any
		table.clear(taken)
		if type(old) ~= "table" or #old == 0 then
			return nil
		end
		local rest = {}
		for _, e in old do
			if type(e) == "table" and type(e.invitee) == "number" then
				if #taken < max then
					table.insert(taken, { invitee = e.invitee, at = tonumber(e.at) or 0 })
				else
					table.insert(rest, e)
				end
			end
		end
		return rest
	end)
	pending -= 1
	if not ok then
		warn(string.format("[DataService] takeReferrals %d failed: %s", userId, tostring(err)))
		return {}
	end
	return taken
end

-- How many saves and unlocks are going (BindToClose waits for none).
function DataService.pending(): number
	return pending
end

function DataService.usingMemory(): boolean
	return usingMemory
end

return DataService
