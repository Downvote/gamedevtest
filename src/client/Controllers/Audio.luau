--!strict
-- Every sound the game makes, by name (docs/ARCHITECTURE.md 8.2; GAME_DESIGN 15: "more polished and animated"): each
-- event plays one Config/Monetization.Sounds id (0 = silent), or one of a few takes picked at random (`ids`), at its own
-- volume and a pitch from its range. A repeat inside the event's cooldown is dropped (a burst of popups makes a quick
-- run, not a roar), and each event keeps a couple of voices so overlapping plays do not cut each other off. Client
-- only; never yields.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)

export type PlayOpts = { volume: number?, pitch: number? }
-- from / len: play only that stretch of the clip (seconds into it, and for how long at normal speed), its last `fade`
-- seconds faded out (else it stops dead); ids: takes picked at random (one voice each; `id` is the first)
type EventDef = { id: string, ids: { string }?, vol: number, pitch: { number }?, cd: number?, voices: number?, from: number?, len: number?, fade: number? }

local Audio = {}

-- stylua: ignore start
local EVENTS: { [string]: EventDef } = {
	-- the interface: wood and bamboo
	click = { id = "Click", vol = 0.4, pitch = { 1.02, 1.12 }, cd = 0.04, voices = 3 },
	open = { id = "Open", vol = 0.22, pitch = { 1.05, 1.15 }, cd = 0.12 },
	close = { id = "Close", vol = 0.18, pitch = { 0.85, 0.95 }, cd = 0.12 },
	deny = { id = "Deny", vol = 0.45, pitch = { 0.6, 0.66 }, cd = 0.25 },
	notice = { id = "Notice", vol = 0.16, pitch = { 0.98, 1.04 }, cd = 0.3 },
	ding = { id = "Ding", vol = 0.2, pitch = { 1, 1.04 }, cd = 0.2 },
	-- the shells and the celebrations: pebbles, a shaker, the conch, island stingers
	coin = { id = "Coin", vol = 0.35, pitch = { 1.05, 1.2 }, cd = 0.08, voices = 3 },
	coins = { id = "CoinsMany", vol = 0.35, pitch = { 0.95, 1.05 }, cd = 0.3 },
	-- the happy moments, each its own small library sound ("use different sounds for newcomer, victory and other
	-- sounds ... use sounds from the free roblox library instead", 2026-11-12; kept short and soft, as asked on
	-- 2026-11-10: "find one with a small short chime instead")
	newcomer = { id = "DoorChime", vol = 1.8, cd = 1, from = 0.3, len = 1.6, fade = 0.3 },
	victory = { id = "BellTree", vol = 2.4, cd = 1, from = 0.7, len = 2.3, fade = 0.6 },
	grow = { id = "BellTreeRun", vol = 2.6, cd = 1, from = 0.3, len = 2.3, fade = 0.6 },
	friend = { id = "ChimeCluster", vol = 1.5, cd = 0.5 },
	egg = { id = "MusicBoxWind", vol = 2.4, cd = 1 },
	rare = { id = "SparklePass", vol = 0.38, cd = 1, from = 0.1, len = 2.2, fade = 0.5 },
	reward = { id = "Triangle", vol = 0.9, pitch = { 0.98, 1.02 }, cd = 0.4, len = 1.4, fade = 0.4 },
	level_up = { id = "SparkleTones", vol = 0.55, cd = 1 },
	combo = { id = "Combo", vol = 0.4, pitch = { 1, 1.1 }, cd = 0.2 },
	sparkle = { id = "Sparkle", vol = 0.45, pitch = { 0.96, 1.08 }, cd = 0.15 },
	cheer = { id = "Cheer", vol = 0.4, pitch = { 0.95, 1.08 }, cd = 0.6 },
	trumpet = { id = "Trumpet", vol = 0.22, pitch = { 0.98, 1.02 }, cd = 1 },
	drumroll = { id = "DrumRoll", vol = 0.4, cd = 1, from = 0.05, len = 1.6, fade = 0.4 },
	tick = { id = "Tick", vol = 0.4, pitch = { 0.95, 1.08 }, cd = 0.03, voices = 3 },
	flip = { id = "CardFlip", vol = 0.35, pitch = { 0.95, 1.08 }, cd = 0.04, voices = 3 },
	pop = { id = "Pop", vol = 0.5, pitch = { 0.95, 1.15 }, cd = 0.04, voices = 3 },
	-- the battles (the blows kept soft: "make a less loud sound for attacking", 2026-11-11)
	whoosh = { id = "Whoosh", vol = 0.18, pitch = { 0.92, 1.1 }, cd = 0.05, voices = 3 },
	whoosh_heavy = { id = "WhooshHeavy", vol = 0.22, pitch = { 0.9, 1 }, cd = 0.1 },
	hit = { id = "Hit", vol = 0.22, pitch = { 0.9, 1.12 }, cd = 0.03, voices = 4 },
	hit_heavy = { id = "HitHeavy", vol = 0.3, pitch = { 0.85, 0.95 }, cd = 0.08 },
	body_fall = { id = "BodyFall", vol = 0.32, pitch = { 0.9, 1.05 }, cd = 0.1 },
	zap = { id = "Zap", vol = 0.22, pitch = { 0.95, 1.1 }, cd = 0.1 },
	heal = { id = "Heal", vol = 0.45, pitch = { 1, 1.1 }, cd = 0.15 },
	shield = { id = "Shield", vol = 0.35, pitch = { 1, 1.15 }, cd = 0.1 },
	poof = { id = "Poof", vol = 0.45, pitch = { 0.95, 1.1 }, cd = 0.1 },
	bite = { id = "Bite", vol = 0.18, pitch = { 1, 1.2 }, cd = 0.05, voices = 3 },
	-- the islands and the sea
	chest = { id = "ChestOpen", vol = 0.5, cd = 0.3 },
	splash = { id = "Splash", vol = 0.4, pitch = { 0.9, 1.1 }, cd = 0.08, voices = 3 },
	hammer = { id = "Hammer", vol = 0.45, pitch = { 0.95, 1.05 }, cd = 0.2, from = 0.24, len = 0.17 },
	horn = { id = "BoatHorn", vol = 0.3, cd = 2 },
	gull = { id = "Gull", vol = 0.12, pitch = { 0.95, 1.1 }, cd = 4 },
	birds = { id = "Birds", vol = 0.2, cd = 20 },
	-- the founder's feet (AvatarView): a step on the lawn, the sand or the boards, a hop, a landing
	step_grass = { id = "StepGrass1", ids = { "StepGrass1", "StepGrass2" }, vol = 1.1, pitch = { 0.9, 1.1 }, cd = 0.12 },
	step_sand = { id = "StepSand1", ids = { "StepSand1", "StepSand2" }, vol = 0.6, pitch = { 0.9, 1.1 }, cd = 0.12 },
	step_wood = { id = "StepWood1", ids = { "StepWood1", "StepWood2", "StepWood3" }, vol = 0.25, pitch = { 0.95, 1.1 }, cd = 0.12 },
	jump = { id = "Hop", vol = 0.16, pitch = { 1, 1.15 }, cd = 0.2 },
	land = { id = "LandSand", vol = 0.19, pitch = { 0.95, 1.05 }, cd = 0.2 },
}
-- the ambience: looped sounds faded toward a volume (Audio.ambience)
local LOOPS: { [string]: string } = { waves = "Waves", crickets = "Crickets" }
-- stylua: ignore end
Audio.EVENTS = EVENTS

local pools: { [string]: { Sound } } = {}
local next_: { [string]: number } = {}
local lastAt: { [string]: number } = {}
local fades: { [Sound]: Tween } = {}
local counts: { [string]: number } = {} -- plays an event made (Audio.playCount: the sims)
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

-- How many voices an event keeps (one a take when it has several).
local function voicesOf(ev: EventDef): number
	return if ev.ids then #ev.ids else ev.voices or 2
end

-- An event's voice `i` (made the first time: a take's own sound when the event has several).
local function voiceOf(name: string, ev: EventDef, i: number): Sound
	local pool = pools[name]
	if pool == nil then
		pool = {}
		pools[name] = pool
	end
	local s = pool[i]
	if s and s.Parent then
		return s
	end
	local key = if ev.ids then ev.ids[i] or ev.id else ev.id
	local ns = Instance.new("Sound")
	ns.Name = name
	ns.SoundId = "rbxassetid://" .. tostring((Monetization.Sounds :: { [string]: number })[key])
	ns.Parent = holder()
	pool[i] = ns
	return ns
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

-- Background music (GAME_DESIGN 15: "find cozy background music"): a mood's playlist from
-- Config/Monetization.Music ("day", "night", "sea"; nil: quiet), shuffled and played track after track; a change of
-- mood, and each track's last seconds, crossfade over MUSIC_FADE seconds. Audio.setMusicOn(false) fades it away (the
-- settings' Music switch). Never yields.
local MUSIC_VOL = 0.2
local MUSIC_FADE = 3
type Track = { s: Sound, mood: string, target: number, handed: boolean, gain: number }
local mood: string? = nil
local musicOn = true
local tracks: { Track } = {}
type Song = { id: number, gain: number }
local order: { [string]: { Song } } = {}
local nextIdx: { [string]: number } = {}
local musicFader = false

local function nextTrack(m: string)
	local list = ((Monetization :: any).Music or {})[m] :: { Song }?
	if list == nil or #list == 0 then
		return
	end
	local o = order[m]
	if o == nil then
		-- a shuffle per mood, played round
		o = table.clone(list)
		for i = #o, 2, -1 do
			local j = math.random(1, i)
			o[i], o[j] = o[j], o[i]
		end
		order[m] = o
		nextIdx[m] = 1
	end
	local i = nextIdx[m] or 1
	nextIdx[m] = i % #o + 1
	local snd = Instance.new("Sound")
	snd.Name = "Music_" .. m
	local song = o[i]
	snd.SoundId = "rbxassetid://" .. tostring(song.id)
	snd.Looped = #o == 1
	snd.Volume = 0
	snd.Parent = holder()
	local t: Track = { s = snd, mood = m, target = 0, handed = false, gain = song.gain or 1 }
	table.insert(tracks, t)
	snd.Ended:Connect(function()
		-- (a track that ran out before its crossfade: the next one starts now)
		if not t.handed then
			t.handed = true
			if t.mood == mood then
				nextTrack(t.mood)
			end
		end
	end)
	pcall(function()
		snd:Play()
	end)
end

local function startFader()
	if musicFader then
		return
	end
	musicFader = true
	RunService.Heartbeat:Connect(function(dt: number)
		for i = #tracks, 1, -1 do
			local t = tracks[i]
			local step = dt * MUSIC_VOL * t.gain / MUSIC_FADE
			local s = t.s
			-- near its end the next track of the mood fades in over it
			if not t.handed and t.mood == mood and not s.Looped and s.TimeLength > MUSIC_FADE * 2 and s.TimePosition >= s.TimeLength - MUSIC_FADE then
				t.handed = true
				t.target = 0
				nextTrack(t.mood)
			end
			local v = s.Volume
			local want = if t.mood == mood and musicOn and not t.handed then MUSIC_VOL * t.gain else 0
			t.target = want
			if v ~= want then
				s.Volume = if math.abs(want - v) <= step then want elseif want > v then v + step else v - step
			end
			-- gone quiet for good (another mood, or handed on to the next track): away with it
			if want <= 0 and s.Volume <= 0 and (t.mood ~= mood or t.handed) then
				s:Destroy()
				table.remove(tracks, i)
			end
		end
	end)
end

function Audio.music(m: string?)
	if m == mood then
		return
	end
	mood = m
	startFader()
	if m then
		-- back to a mood still fading out: it fades in again, else its next track starts
		for _, t in tracks do
			if t.mood == m and not t.handed then
				return
			end
		end
		nextTrack(m)
	end
end

function Audio.setMusicOn(on: boolean)
	musicOn = on
end

function Audio.musicState(): { mood: string?, on: boolean, tracks: number }
	return { mood = mood, on = musicOn, tracks = #tracks }
end

-- Play a one-shot event. True when it played.
-- Every voice of these events made and loaded now, so the first plays are on time (UI/ExpeditionUI: the battle's
-- swings and blows). Never yields: the loading runs on its own thread.
function Audio.preload(names: { string })
	local list: { Instance } = {}
	for _, name in names do
		local ev = EVENTS[name]
		if ev == nil or not Audio.has(name) then
			continue
		end
		for i = 1, voicesOf(ev) do
			table.insert(list, voiceOf(name, ev, i))
		end
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)
end

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
	-- the next voice in turn, or a take at random (never the same one twice running)
	local voices = voicesOf(ev)
	local i
	if ev.ids and voices > 1 then
		i = math.random(1, voices - 1)
		if i >= (next_[name] or 0) then
			i += 1
		end
	else
		i = (next_[name] or 0) % voices + 1
	end
	next_[name] = i
	local snd = voiceOf(name, ev, i)
	if not snd.IsLoaded then
		-- (a voice not loaded yet starts late, behind what it goes with: it is asked to load now so the next play is on
		-- time; Audio.preload loads the battle's sounds ahead so this is rare)
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ snd })
			end)
		end)
	end
	local o: PlayOpts = opts or {}
	local lo, hi = 1, 1
	if ev.pitch then
		lo, hi = ev.pitch[1], ev.pitch[2]
	end
	-- (a fade still running from this voice's last play would carry on over this one)
	local tw = fades[snd]
	if tw then
		tw:Cancel()
		fades[snd] = nil
	end
	snd.Volume = ev.vol * (o.volume or 1)
	local speed = (lo + (hi - lo) * math.random()) * (o.pitch or 1)
	snd.PlaybackSpeed = speed
	pcall(function()
		snd.TimePosition = ev.from or 0
		snd:Play()
	end)
	counts[name] = (counts[name] or 0) + 1
	local len = ev.len
	if len then
		-- only a stretch of the clip: it fades over its last `fade` seconds and stops when the stretch is over
		-- (unless the voice was played again since)
		local token = os.clock()
		snd:SetAttribute("PlayedAt", token)
		local real = len / math.max(0.05, speed)
		local fade = math.min(real, (ev.fade or 0) / math.max(0.05, speed))
		if fade > 0 then
			task.delay(real - fade, function()
				if snd.Parent and snd:GetAttribute("PlayedAt") == token then
					local t = TweenService:Create(snd, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 })
					fades[snd] = t
					t:Play()
				end
			end)
		end
		task.delay(real, function()
			if snd.Parent and snd:GetAttribute("PlayedAt") == token then
				snd:Stop()
			end
		end)
	end
	return true
end

-- How many times an event has played on this client (sims and checks: "the footsteps are heard").
function Audio.playCount(name: string): number
	return counts[name] or 0
end

return Audio
