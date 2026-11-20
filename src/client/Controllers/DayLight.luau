--!strict
-- The island's light (GAME_DESIGN 8; docs/ARCHITECTURE.md 9.3). The request of 2026-11-14: "remove the day night
-- cycle, and make everything brighter". So there is no night any more: the light is one bright, clear day all the
-- time, a grade over the pixel filter's picture (`BRIGHT`: everything a little lighter, the shadows lifted, the
-- colours a touch richer). The calendar still counts days (the HUD's "Day 12", WorldClock), but the light doesn't
-- follow them. The hatch scene holds its own grades over this one while it plays (`hold`). With the filter off,
-- Roblox's own clock stays at early afternoon.
-- The sky round the floating islands has its own day since 2026-11-20 ("polish the skybox more. it should be of the
-- same quality as the ones in the egg hatching screen, with day and night cycles with moon and sun rising"): the sea's
-- clock round `Tuning.SkyDaySecs`, the same on every client of a server, drawn by UI/SkyBackdrop. Only the sky and
-- the sounds follow it (crickets at night, the birds' songs by day, a soft wind always since the surf went with the
-- sea); the island keeps its bright light.
--   start(), at(frac) -> Grade (the same bright grade at any time), frac() (always the day's middle), hold(grade?),
--   debugSet(frac?) (kept for the previews: it changes nothing now), debugState(),
--   skyHour() -> 0 .. 1 (0 midnight, about 0.25 sunrise, 0.5 noon, about 0.75 sunset), skyNight() -> whole number
--   (which night it is, changing at noon: the moon's phase), night(h?) -> 0 .. 1 (how far into the night),
--   debugSky(h?, night?) (previews and sims: hold the sky at an hour and a night; nil lets it run)
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local StateClient = require(script.Parent.StateClient)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local Audio = require(script.Parent.Audio)

type Grade = PixelRenderer.Grade

local DayLight = {}

-- the light all day: a little lighter, the shadows lifted a touch, no lamp pools (toned down after "tone down the
-- brightness abit, it should be around this brightness level", with a picture of Random Bakery's bright snowy street)
local BRIGHT: Grade = { mr = 1.035, mg = 1.035, mb = 1.025, lift = 3, sat = 1.02, lamps = 0 }
DayLight.BRIGHT = BRIGHT
local MIDDAY = 0.35 -- (what frac() says: anything that asks the hour finds it bright day)
local BIRDS_EVERY = 80 -- seconds between the birds' songs

local held: Grade? = nil -- a grade held over the day's (the hatch scene's)
-- the weather's light over the day's (Controllers/WeatherView; GAME_DESIGN 13): its multipliers times BRIGHT's, its
-- lift added; nil: the plain bright day
type WeatherGrade = { mr: number, mg: number, mb: number, lift: number, sat: number }
local weather: Grade? = nil

-- The grade at any time (the same bright day).
function DayLight.at(_frac: number): Grade
	return BRIGHT
end

-- The weather's light over the day's (nil: the plain day). The caller steps it (a few steps a change, never a smear:
-- every new grade re-uploads the picture).
function DayLight.setWeather(w: WeatherGrade?)
	if w == nil then
		weather = nil
		return
	end
	weather = { mr = BRIGHT.mr * w.mr, mg = BRIGHT.mg * w.mg, mb = BRIGHT.mb * w.mb, lift = BRIGHT.lift + w.lift, sat = BRIGHT.sat * w.sat, lamps = 0 }
end

function DayLight.start()
	local sung = os.clock() - BIRDS_EVERY + 6
	RunService.Heartbeat:Connect(function()
		-- the sound of the island: crickets at night, the birds now and then by day (the wind is WeatherView's; no
		-- surf since the sea went)
		local nt = DayLight.night()
		Audio.ambience("waves", 0)
		Audio.ambience("crickets", 0.12 * nt)
		if os.clock() - sung >= BIRDS_EVERY then
			sung = os.clock()
			if nt < 0.5 then
				Audio.play("birds")
			end
		end
		if PixelRenderer.tier() == "off" then
			PixelRenderer.setGrade(nil)
			pcall(function()
				Lighting.ClockTime = 13.5
			end)
			return
		end
		PixelRenderer.setGrade(held or weather or BRIGHT)
	end)
end

-- The hour (always the day's middle: there is no night).
function DayLight.frac(): number
	return MIDDAY
end

-- Hold a grade over the day's (the hatch scene's light by rarity); nil lets go.
function DayLight.hold(g: Grade?)
	held = g
end

------------------------------------------------------------------ the sky's day
local skyHeld: number? = nil
local nightHeld = 0

local function seaNow(): number
	local t = StateClient.seaClock()
	return if t > 0 then t else os.clock()
end

-- The sky's hour: 0 midnight, about 0.25 sunrise, 0.5 noon, about 0.75 sunset.
function DayLight.skyHour(): number
	local h = skyHeld
	if h then
		return h % 1
	end
	return (seaNow() % Tuning.SkyDaySecs) / Tuning.SkyDaySecs
end

-- Which night it is (a whole number, changing at noon), for the moon's phase.
function DayLight.skyNight(): number
	if skyHeld then
		return nightHeld
	end
	return math.floor(seaNow() / Tuning.SkyDaySecs + 0.5)
end

-- How far into the night the sky is at hour h (now when nil): 0 all day, 1 from dusk's end to the first light,
-- ramps between.
function DayLight.night(h: number?): number
	local x = if h then h % 1 else DayLight.skyHour()
	if x >= 0.25 and x <= 0.75 then
		return 0
	elseif x > 0.75 then
		return math.clamp((x - 0.75) / 0.08, 0, 1)
	end
	return math.clamp((0.25 - x) / 0.08, 0, 1)
end

-- Hold the sky at an hour (previews, sims), and at a night (the moon's phase: night % 8, 0 full); nil lets it run on
-- the clock again.
function DayLight.debugSky(h: number?, night: number?)
	skyHeld = h
	nightHeld = night or 0
end

-- (Previews: once held the clock at a time of day; the light no longer follows the clock.)
function DayLight.debugSet(_frac: number?) end

function DayLight.debugState(): { frac: number, grade: string, clock: number }
	local ok, c = pcall(function()
		return Lighting.ClockTime
	end)
	return { frac = MIDDAY, grade = PixelRenderer.debugGrade(), clock = if ok and type(c) == "number" then c else -1 }
end

return DayLight
