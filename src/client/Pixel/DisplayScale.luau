--!strict
-- The screen's own scale (docs/ARCHITECTURE.md 9.1): how many of the screen's pixels one GUI offset unit takes. Roblox
-- lays the interface out in density-independent units (Camera.ViewportSize, AbsoluteSize and every Offset are in
-- them) and draws them at the display's scale: 1 on most monitors, 2 on a Mac's Retina screen, 3 on many phones, but
-- 1.25, 1.5 or 1.75 on a laptop with Windows' display scaling on. The game's pixel size K is a whole number of those
-- units, so at 125% an art pixel 2 units wide came out 2.5 of the screen's pixels: columns 2 and 3 pixels wide by
-- turns, outlines broken into dots and steps (the report of 2026-11-20, "the tree still looks like this", with
-- screenshots whose every pixel was 2.5 screen pixels wide).
--
-- No script can ask Roblox for that scale, so it is found from what Roblox reports: at 125% a window 1366 pixels wide
-- is 1092.8 units, and a mouse moved one pixel may move 0.8 of one. Only a value with a fraction says anything: a
-- whole one fits any screen (Roblox may round a mouse position to whole units, and a whole number of units times 1.25
-- is rarely whole, so counting those as evidence kept Auto at 100% on a screen at 125%: the report of 2026-11-20, "its
-- still uneven", with the pixels still 2.5 of the screen's). The scale is the smallest of CANDIDATES above 1 that
-- turns every recent value with a fraction into whole pixels, once there are two of them; 1 while there are none. The
-- player can also set it in Settings ("Screen", settings.screen): Auto finds it, 100% .. 200% say it.
--
-- `fit(K)` then nudges the game's pixel size so an art pixel is a whole number of the screen's pixels: K units at a
-- scale s are K * s pixels, rounded to the nearest whole P, and the pixel size becomes P / s units (2 units at 125%:
-- 3 pixels, 2.4 units). A whole scale (100%, 200%, a phone's 300%) leaves K as it was.
--
-- API: DisplayScale.start() (once, on the client), DisplayScale.factor() -> number (the scale in use),
-- DisplayScale.fit(K) -> number, DisplayScale.setChoice(c: "auto" | "100" | "125" | "150" | "175" | "200"),
-- DisplayScale.choice() -> string, DisplayScale.found() -> number (what Auto found), DisplayScale.observe(v) (a coordinate as Roblox reported it: the sims and previews
-- feed it), DisplayScale.Changed (fires with the new scale), DisplayScale.debugState().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local DisplayScale = {}
DisplayScale.Changed = Util.Signal()

-- the scales a display can have (the smallest that fits the samples wins)
local CANDIDATES = { 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.625, 2.75, 3, 3.5, 4 }
-- the Settings choices ("auto", 0, finds it)
local CHOICES: { [string]: number } = Tuning.ScreenScales
local TOL = 0.02 -- how near a whole pixel a sample must land
local KEEP = 32 -- recent samples with a fraction kept
local NEED = 2 -- samples with a fraction before a scale other than 1 is believed

local choice = "auto"
local detected = 1
local samples: { number } = {}
local started = false

local function fits(d: number): boolean
	for _, v in samples do
		local p = v * d
		if math.abs(p - math.floor(p + 0.5)) > TOL then
			return false
		end
	end
	return true
end

local function current(): number
	local c = CHOICES[choice]
	return if c and c > 0 then c else detected
end

local function redetect()
	local before = current()
	local found = 1
	if #samples >= NEED then
		for _, d in CANDIDATES do
			if d > 1 and fits(d) then
				found = d
				break
			end
		end
	end
	detected = found
	if current() ~= before then
		DisplayScale.Changed:Fire(current())
	end
end

-- A coordinate as Roblox reported it (a mouse or touch position, a viewport size): kept when it has a fraction (a
-- whole one fits every screen) and is new.
function DisplayScale.observe(v: number)
	if v ~= v or math.abs(v) > 1e5 or math.abs(v - math.floor(v + 0.5)) <= TOL then
		return
	end
	for _, s in samples do
		if math.abs(s - v) < 1e-4 then
			return
		end
	end
	table.insert(samples, v)
	if #samples > KEEP then
		table.remove(samples, 1)
	end
	-- (a sample the scale in use fits changes nothing; one it does not, or the first ones, look again)
	if #samples == NEED or detected == 1 or not fits(detected) then
		redetect()
	end
end

-- The screen's scale in use: the Settings choice, else what was found (1 until something says otherwise).
function DisplayScale.factor(): number
	return current()
end

-- The pixel size K units nudged to a whole number of the screen's pixels.
function DisplayScale.fit(k: number): number
	local s = current()
	if math.abs(s - math.floor(s + 0.5)) < 1e-6 then
		return k
	end
	local p = math.max(1, math.floor(k * s + 0.5))
	return p / s
end

function DisplayScale.choice(): string
	return choice
end

-- What Auto found (1 until the samples say otherwise), whatever the choice: Settings shows it beside "Screen".
function DisplayScale.found(): number
	return detected
end

-- The Settings choice ("auto" finds it; an unknown one is taken as "auto").
function DisplayScale.setChoice(c: string)
	local nc = if CHOICES[c] ~= nil then c else "auto"
	if nc == choice then
		return
	end
	local before = current()
	choice = nc
	if current() ~= before then
		DisplayScale.Changed:Fire(current())
	end
end

-- Watch the mouse, touches and the screen's size (once).
function DisplayScale.start()
	if started then
		return
	end
	started = true
	local function vec(p: Vector3 | Vector2)
		DisplayScale.observe(p.X)
		DisplayScale.observe(p.Y)
	end
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			vec(input.Position)
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			vec(input.Position)
		end
	end)
	local cam = Workspace.CurrentCamera
	if cam then
		vec(cam.ViewportSize)
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			vec(cam.ViewportSize)
		end)
	end
end

function DisplayScale.debugState(): { choice: string, detected: number, factor: number, samples: number }
	return { choice = choice, detected = detected, factor = current(), samples = #samples }
end

-- (the sims start each client afresh)
function DisplayScale.debugReset()
	local before = current()
	choice, detected = "auto", 1
	table.clear(samples)
	if current() ~= before then
		DisplayScale.Changed:Fire(current())
	end
end

return DisplayScale
