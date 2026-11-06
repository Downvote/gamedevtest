--!strict
-- Every sound the game makes, by name (docs/ARCHITECTURE.md 8.2; GAME_DESIGN 15: "more polished and animated"): each
-- event plays one Config/Monetization.Sounds id (0 = silent) at its own volume and a pitch from its range. A repeat
-- inside the event's cooldown is dropped (a burst of popups makes a quick run, not a roar), and each event keeps a
-- couple of voices so overlapping plays do not cut each other off. Client only; never yields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)

export type PlayOpts = { volume: number?, pitch: number? }
type EventDef = { id: string, vol: number, pitch: { number }?, cd: number?, voices: number? }

local Audio = {}

-- stylua: ignore start
local EVENTS: { [string]: EventDef } = {
	-- the interface
	click = { id = "Click", vol = 0.38, pitch = { 0.97, 1.05 }, cd = 0.04, voices = 3 },
	hover = { id = "Hover", vol = 0.5, pitch = { 0.98, 1.04 }, cd = 0.07 },
	open = { id = "Open", vol = 0.28, pitch = { 0.98, 1.03 }, cd = 0.12 },
	close = { id = "Close", vol = 0.24, pitch = { 0.98, 1.02 }, cd = 0.12 },
	deny = { id = "Deny", vol = 0.37, pitch = { 0.98, 1.02 }, cd = 0.25 },
	notice = { id = "Notice", vol = 0.19, pitch = { 0.98, 1.04 }, cd = 0.3 },
	ding = { id = "Ding", vol = 0.27, pitch = { 1, 1.04 }, cd = 0.2 },
	-- money and celebrations
	coin = { id = "Coin", vol = 0.3, pitch = { 1, 1.04 }, cd = 0.08, voices = 3 },
	coins = { id = "CoinsMany", vol = 0.34, pitch = { 0.94, 0.98 }, cd = 0.3 },
	level_up = { id = "LevelUp", vol = 0.24, cd = 1 },
	reward = { id = "Reward", vol = 0.32, cd = 0.4 },
	fanfare = { id = "Fanfare", vol = 0.33, cd = 0.5 },
	rare_fanfare = { id = "RareFanfare", vol = 0.38, cd = 1 },
	combo = { id = "Combo", vol = 0.3, pitch = { 1, 1.06 }, cd = 0.2 },
	sparkle = { id = "Sparkle", vol = 0.9, pitch = { 0.96, 1.08 }, cd = 0.15 },
	cheer = { id = "Cheer", vol = 0.3, pitch = { 0.95, 1.06 }, cd = 0.6 },
	applause = { id = "Applause", vol = 0.22, pitch = { 0.96, 1.05 }, cd = 0.8 },
	trumpet = { id = "Trumpet", vol = 0.21, cd = 1 },
	sad = { id = "SadTrombone", vol = 0.5, cd = 1 },
	drumroll = { id = "Drumroll", vol = 0.26, cd = 1 },
	-- the minigames
	tick = { id = "Tick", vol = 0.42, pitch = { 0.95, 1.08 }, cd = 0.03, voices = 3 },
	key = { id = "TypeKey", vol = 0.5, pitch = { 0.94, 1.08 }, cd = 0.02, voices = 4 },
	flip = { id = "CardFlip", vol = 0.35, pitch = { 0.95, 1.08 }, cd = 0.04, voices = 3 },
	pop = { id = "Pop", vol = 0.6, pitch = { 0.95, 1.12 }, cd = 0.04, voices = 3 },
	squish = { id = "Squish", vol = 0.34, pitch = { 0.9, 1.1 }, cd = 0.04, voices = 3 },
}
-- stylua: ignore end
Audio.EVENTS = EVENTS

local pools: { [string]: { Sound } } = {}
local next_: { [string]: number } = {}
local lastAt: { [string]: number } = {}
local folder: Folder? = nil

local function holder(): Instance
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "UISounds"
	nf.Parent = SoundService
	folder = nf
	return nf
end

-- Whether `name` would make a sound (a known event with an id).
function Audio.has(name: string): boolean
	local ev = EVENTS[name]
	if ev == nil then
		return false
	end
	local id = (Monetization.Sounds :: { [string]: number })[ev.id]
	return type(id) == "number" and id > 0
end

-- Play a one-shot event. True when it played.
function Audio.play(name: string, opts: PlayOpts?): boolean
	local ev = EVENTS[name]
	if ev == nil or not Audio.has(name) then
		return false
	end
	local now = os.clock()
	if now - (lastAt[name] or -1e9) < (ev.cd or 0.05) then
		return false
	end
	lastAt[name] = now
	local pool = pools[name]
	if pool == nil then
		pool = {}
		pools[name] = pool
	end
	local voices = ev.voices or 2
	local i = (next_[name] or 0) % voices + 1
	next_[name] = i
	local s: Sound? = pool[i]
	if not s or s.Parent == nil then
		local ns = Instance.new("Sound")
		ns.Name = name
		ns.SoundId = "rbxassetid://" .. tostring((Monetization.Sounds :: { [string]: number })[ev.id])
		ns.Parent = holder()
		pool[i] = ns
		s = ns
	end
	local snd = s :: Sound
	local o: PlayOpts = opts or {}
	local lo, hi = 1, 1
	if ev.pitch then
		lo, hi = ev.pitch[1], ev.pitch[2]
	end
	snd.Volume = ev.vol * (o.volume or 1)
	snd.PlaybackSpeed = (lo + (hi - lo) * math.random()) * (o.pitch or 1)
	pcall(function()
		snd.TimePosition = 0
		snd:Play()
	end)
	return true
end

return Audio
