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

-- Save a profile; release = also drop the lock (the player left).
function DataService.save(userId: number, profile: Types.Profile, release: boolean?): boolean
	local key = keyOf(userId)
	local ok, err = update(key, function(old: any): any
		local rec = if type(old) == "table" then old else {}
		local lock = rec.lock
		if type(lock) == "table" and lock.job ~= jobId and type(lock.t) == "number" and os.time() - lock.t < Tuning.LockTTL then
			return nil -- another server took over: never overwrite its save
		end
		rec.data = profile
		rec.lock = if release then nil else { job = jobId, t = os.time() }
		return rec
	end)
	if not ok then
		warn(string.format("[DataService] save %d failed: %s", userId, tostring(err)))
	end
	return ok
end

function DataService.usingMemory(): boolean
	return usingMemory
end

return DataService
