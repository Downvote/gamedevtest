--!strict
-- The island's light (GAME_DESIGN 8; docs/ARCHITECTURE.md 9.3). The request of 2026-11-14: "remove the day night
-- cycle, and make everything brighter". So there is no night any more: the light is one bright, clear day all the
-- time, a grade over the pixel filter's picture (`BRIGHT`: everything a little lighter, the shadows lifted, the
-- colours a touch richer). The calendar still counts days (the HUD's "Day 12", WorldClock), but the light doesn't
-- follow them. The hatch scene holds its own grades over this one while it plays (`hold`). With the filter off,
-- Roblox's own clock stays at early afternoon.
--   start(), at(frac) -> Grade (the same bright grade at any time), frac() (always the day's middle), hold(grade?),
--   debugSet(frac?) (kept for the previews: it changes nothing now), debugState()
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
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

-- The grade at any time (the same bright day).
function DayLight.at(_frac: number): Grade
	return BRIGHT
end

function DayLight.start()
	local sung = os.clock() - BIRDS_EVERY + 6
	RunService.Heartbeat:Connect(function()
		-- the sound of the island: the surf always, the birds now and then
		Audio.ambience("waves", 0.14)
		Audio.ambience("crickets", 0)
		if os.clock() - sung >= BIRDS_EVERY then
			sung = os.clock()
			Audio.play("birds")
		end
		if PixelRenderer.tier() == "off" then
			PixelRenderer.setGrade(nil)
			pcall(function()
				Lighting.ClockTime = 13.5
			end)
			return
		end
		PixelRenderer.setGrade(held or BRIGHT)
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

-- (Previews: once held the clock at a time of day; the light no longer follows the clock.)
function DayLight.debugSet(_frac: number?) end

function DayLight.debugState(): { frac: number, grade: string, clock: number }
	local ok, c = pcall(function()
		return Lighting.ClockTime
	end)
	return { frac = MIDDAY, grade = PixelRenderer.debugGrade(), clock = if ok and type(c) == "number" then c else -1 }
end

return DayLight
