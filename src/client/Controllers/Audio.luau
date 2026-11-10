--!strict
-- Every sound the game makes, by name (docs/ARCHITECTURE.md 8.2; GAME_DESIGN 15: "more polished and animated"): each
-- event plays one Config/Monetization.Sounds id (0 = silent) at its own volume and a pitch from its range. A repeat
-- inside the event's cooldown is dropped (a burst of popups makes a quick run, not a roar), and each event keeps a
-- couple of voices so overlapping plays do not cut each other off. Client only; never yields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

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
	-- the battles
	whoosh = { id = "Whoosh", vol = 0.4, pitch = { 0.92, 1.1 }, cd = 0.05, voices = 3 },
	whoosh_heavy = { id = "WhooshHeavy", vol = 0.45, pitch = { 0.9, 1 }, cd = 0.1 },
	hit = { id = "Hit", vol = 0.5, pitch = { 0.9, 1.12 }, cd = 0.03, voices = 4 },
	hit_heavy = { id = "HitHeavy", vol = 0.6, pitch = { 0.85, 0.95 }, cd = 0.08 },
	body_fall = { id = "BodyFall", vol = 0.5, pitch = { 0.9, 1.05 }, cd = 0.1 },
	zap = { id = "Zap", vol = 0.35, pitch = { 0.95, 1.1 }, cd = 0.1 },
	heal = { id = "Heal", vol = 0.45, pitch = { 1, 1.1 }, cd = 0.15 },
	shield = { id = "Shield", vol = 0.35, pitch = { 1, 1.15 }, cd = 0.1 },
	poof = { id = "Poof", vol = 0.45, pitch = { 0.95, 1.1 }, cd = 0.1 },
	bite = { id = "Bite", vol = 0.35, pitch = { 1, 1.2 }, cd = 0.05, voices = 3 },
	-- the islands and the sea
	chest = { id = "ChestOpen", vol = 0.5, cd = 0.3 },
	splash = { id = "Splash", vol = 0.4, pitch = { 0.9, 1.1 }, cd = 0.08, voices = 3 },
	hammer = { id = "Hammer", vol = 0.45, pitch = { 0.95, 1.05 }, cd = 0.2 },
	horn = { id = "BoatHorn", vol = 0.3, cd = 2 },
	gull = { id = "Gull", vol = 0.12, pitch = { 0.95, 1.1 }, cd = 4 },
	birds = { id = "Birds", vol = 0.2, cd = 20 },
}
-- the ambience: looped sounds faded toward a volume (Audio.ambience)
local LOOPS: { [string]: string } = { waves = "Waves", crickets = "Crickets" }
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

-- An ambience (`waves`, `crickets`) faded toward `volume` (0: silent) over a second or so; it loops for as long as
-- it is heard. Never yields.
local loops: { [string]: { s: Sound, target: number } } = {}
local fading = false
function Audio.ambience(name: string, volume: number)
	local key = LOOPS[name]
	local id = if key then (Monetization.Sounds :: { [string]: number })[key] else nil
	if type(id) ~= "number" or id <= 0 then
		return
	end
	local l = loops[name]
	if l == nil then
		if volume <= 0 then
			return
		end
		local s = Instance.new("Sound")
		s.Name = "Ambience_" .. name
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.Looped = true
		s.Volume = 0
		s.Parent = holder()
		l = { s = s, target = volume }
		loops[name] = l
		pcall(function()
			s:Play()
		end)
	end
	l.target = volume
	if not fading then
		fading = true
		RunService.Heartbeat:Connect(function(dt: number)
			for _, lp in loops do
				local v = lp.s.Volume
				local t = lp.target
				if v ~= t then
					local step = dt * 0.6
					lp.s.Volume = if math.abs(t - v) <= step then t elseif t > v then v + step else v - step
				end
			end
		end)
	end
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
