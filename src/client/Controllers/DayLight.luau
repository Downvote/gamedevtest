--!strict
-- The day and night (GAME_DESIGN 8; docs/ARCHITECTURE.md 9.3): the island's clock (the view's dayFrac, ticked every
-- second and run on smoothly between ticks) sets the pixel filter's colour grade (PixelRenderer.setGrade): a rosy
-- dawn, the plain day, a golden dusk, a violet twilight and a blue night with the lamps, torches and fires lit in
-- pools of warm light, then the dawn again. The grade steps (a few steps a change, never a smear); the islands at
-- sea (an islet's screen) follow the same clock. With the filter off, Roblox's own clock follows instead.
--   start(), at(frac) -> Grade? (nil: daylight), frac(), hold(grade?) (a grade over the clock's: grey while aiming),
--   debugSet(frac?) (previews: a fixed time), debugState()
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local StateClient = require(script.Parent.StateClient)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local Audio = require(script.Parent.Audio)

type Grade = PixelRenderer.Grade
type Key = { f: number, mr: number, mg: number, mb: number, lift: number, sat: number, lamps: number }

local DayLight = {}

-- the day's keys (dayFrac: 0 a new day at dawn; the HUD's moon from 0.75)
local DAWN: Key = { f = 0, mr = 0.9, mg = 0.78, mb = 0.86, lift = 8, sat = 0.92, lamps = 0.45 }
local KEYS: { Key } = {
	DAWN,
	{ f = 0.07, mr = 1, mg = 1, mb = 1, lift = 0, sat = 1, lamps = 0 }, -- morning
	{ f = 0.6, mr = 1, mg = 1, mb = 1, lift = 0, sat = 1, lamps = 0 }, -- the afternoon
	{ f = 0.68, mr = 1.02, mg = 0.85, mb = 0.66, lift = 0, sat = 1.04, lamps = 0.25 }, -- a golden dusk
	{ f = 0.75, mr = 0.64, mg = 0.54, mb = 0.8, lift = 8, sat = 0.86, lamps = 0.75 }, -- twilight
	{ f = 0.81, mr = 0.36, mg = 0.42, mb = 0.66, lift = 16, sat = 0.7, lamps = 1 }, -- night
	{ f = 0.95, mr = 0.36, mg = 0.42, mb = 0.66, lift = 16, sat = 0.7, lamps = 1 },
	{ f = 1, mr = DAWN.mr, mg = DAWN.mg, mb = DAWN.mb, lift = DAWN.lift, sat = DAWN.sat, lamps = DAWN.lamps },
}
local STEPS = 6 -- a change between two keys goes in this many steps

local frac0, at0 = 0, os.clock() -- the last tick's dayFrac and when it came
local forced: number? = nil
local held: Grade? = nil -- a grade held over the clock's (DayLight.hold)

-- The grade at a time of day (nil: plain daylight).
function DayLight.at(frac: number): Grade?
	local f = frac % 1
	local a, b = KEYS[1], KEYS[2]
	for i = 1, #KEYS - 1 do
		if f >= KEYS[i].f and f < KEYS[i + 1].f then
			a, b = KEYS[i], KEYS[i + 1]
			break
		end
	end
	local t = math.floor((f - a.f) / math.max(1e-6, b.f - a.f) * STEPS + 0.5) / STEPS
	local function lerp(x: number, y: number): number
		return x + (y - x) * t
	end
	local g: Grade = {
		mr = lerp(a.mr, b.mr),
		mg = lerp(a.mg, b.mg),
		mb = lerp(a.mb, b.mb),
		lift = lerp(a.lift, b.lift),
		sat = lerp(a.sat, b.sat),
		lamps = lerp(a.lamps, b.lamps),
	}
	if math.abs(g.mr - 1) < 0.005 and math.abs(g.mg - 1) < 0.005 and math.abs(g.mb - 1) < 0.005 and g.lift < 0.5 and math.abs(g.sat - 1) < 0.005 then
		return nil
	end
	return g
end

local function now(): number
	if forced then
		return forced :: number
	end
	return (frac0 + (os.clock() - at0) / Tuning.DaySeconds) % 1
end

-- Roblox's own clock (the filter off): 6 am at dawn, 6 pm at dusk, midnight in the night's middle.
local function clockHours(f: number): number
	if f < 0.72 then
		return 6 + f / 0.72 * 12
	end
	return (18 + (f - 0.72) / 0.28 * 12) % 24
end

function DayLight.start()
	local v = StateClient.view()
	if v then
		frac0, at0 = v.dayFrac, os.clock()
	end
	local function took(view: any)
		if type(view) == "table" and type(view.dayFrac) == "number" then
			frac0, at0 = view.dayFrac, os.clock()
		end
	end
	StateClient.Tick:Connect(took)
	StateClient.Changed:Connect(took)
	local dawnSung = -1
	RunService.Heartbeat:Connect(function()
		local f = now()
		-- the sound of the hour: the surf always, crickets through the night, birds at dawn
		Audio.ambience("waves", 0.14)
		Audio.ambience("crickets", if f >= 0.77 and f < 0.98 then 0.12 else 0)
		local day = math.floor(frac0 + (os.clock() - at0) / Tuning.DaySeconds)
		if f < 0.05 and dawnSung ~= day then
			dawnSung = day
			Audio.play("birds")
		end
		if PixelRenderer.tier() == "off" then
			PixelRenderer.setGrade(nil)
			pcall(function()
				Lighting.ClockTime = clockHours(f)
			end)
			return
		end
		-- every island shares the clock; a held grade over it
		PixelRenderer.setGrade(held or DayLight.at(f))
	end)
end

-- The time of day now (0 a new day at dawn .. 1; the HUD's music follows it).
function DayLight.frac(): number
	return now()
end

-- Hold a grade over the day's (nothing holds one since the fights went); nil lets go.
function DayLight.hold(g: Grade?)
	held = g
end

-- Previews: hold the clock at a time of day (nil: the island's own again).
function DayLight.debugSet(frac: number?)
	forced = frac
end

function DayLight.debugState(): { frac: number, grade: string, clock: number }
	local ok, c = pcall(function()
		return Lighting.ClockTime
	end)
	return { frac = now(), grade = PixelRenderer.debugGrade(), clock = if ok and type(c) == "number" then c else -1 }
end

return DayLight
