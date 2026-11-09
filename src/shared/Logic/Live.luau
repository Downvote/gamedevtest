--!strict
-- The game on sale (GAME_DESIGN 6; docs/ARCHITECTURE.md 6), Game Dev Tycoon style: its players climb to a peak a
-- fifth of the way through its life, then fall away until it leaves the shops, wobbling on the way (a smooth drift,
-- a little jitter, and a buzz or two: a streamer finds it). Each player earns Tuning.CoinPerPlayer a second. Only the
-- newest game sells: making the next one takes it off (Logic/Studio). Pure: the fluctuation comes from the game's seed
-- and its age, so the same game always draws the same curve; the session's clock ages it (only while its player is
-- here, like every clock in the game).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Util = require(script.Parent.Util)

type Live = Types.Live
type Game = Types.Game

local Live = {}

local TWO32 = 4294967296

-- The curve's shape at x = age / life (0 .. 1): from Tuning.LiveStart up to 1 at Tuning.LivePeakAt (eased), then
-- down to 0 at the end (Tuning.LiveFall: the higher, the faster the fall begins).
function Live.shape(x: number): number
	if x >= 1 or x < 0 then
		return 0
	end
	local p = Tuning.LivePeakAt
	if x < p then
		local r = 1 - x / p
		return Tuning.LiveStart + (1 - Tuning.LiveStart) * (1 - r * r)
	end
	return (1 - (x - p) / (1 - p)) ^ Tuning.LiveFall
end

-- -1 .. 1 from the seed, a stream and a knot.
local function knot(seed: number, stream: number, k: number): number
	return Util.hash32(string.format("%d:%d:%d", seed, stream, k)) / TWO32 * 2 - 1
end

-- Smooth value noise: knots every `every` seconds, eased between.
local function drift(seed: number, stream: number, age: number, every: number): number
	local f = age / every
	local k = math.floor(f)
	local t = f - k
	t = t * t * (3 - 2 * t)
	return knot(seed, stream, k) * (1 - t) + knot(seed, stream, k + 1) * t
end

-- The buzz: Tuning.LiveBuzzes bumps at seeded times on the way down, each lifting the players for a while.
local function buzz(seed: number, age: number, life: number): number
	local b = 0
	for i = 1, Tuning.LiveBuzzes do
		local at = (Tuning.LivePeakAt + 0.1 + (knot(seed, 10 + i, 0) * 0.5 + 0.5) * (0.85 - Tuning.LivePeakAt - 0.1)) * life
		local amp = Tuning.LiveBuzz * (0.5 + 0.5 * (knot(seed, 20 + i, 0) * 0.5 + 0.5))
		local w = life * 0.035
		local d = (age - at) / w
		b += amp * math.exp(-d * d)
	end
	return b
end

-- The fluctuation at an age: around 1, never below Tuning.LiveFloor.
function Live.wobble(seed: number, age: number, life: number): number
	local n = 1 + Tuning.LiveWobble * drift(seed, 1, age, 7) + Tuning.LiveJitter * drift(seed, 2, age, 2) + buzz(seed, age, life)
	return math.max(Tuning.LiveFloor, n)
end

-- The players at an age (whole, 0 once it has left the shops).
function Live.playersAt(l: Live, age: number): number
	if age >= l.life then
		return 0
	end
	return math.max(0, math.floor(l.top * Live.shape(age / l.life) * Live.wobble(l.seed, age, l.life) + 0.5))
end

-- A launched game goes on sale.
function Live.new(g: Game, seed: number): Live
	local l: Live = {
		id = g.id,
		title = g.title,
		top = g.rate / Tuning.CoinPerPlayer,
		life = Tuning.LiveLife,
		age = 0,
		players = 0,
		earned = 0,
		peak = 0,
		seed = math.floor(seed),
		samples = {},
	}
	l.players = Live.playersAt(l, 0)
	l.peak = l.players
	l.samples = { l.players }
	return l
end

function Live.over(l: Live): boolean
	return l.age >= l.life
end

-- Coins a second right now.
function Live.earning(l: Live?): number
	if l == nil or Live.over(l) then
		return 0
	end
	return l.players * Tuning.CoinPerPlayer
end

-- "rising" | "peak" | "falling" | "off"
function Live.phase(l: Live): string
	if Live.over(l) then
		return "off"
	end
	local x = l.age / l.life
	if x < Tuning.LivePeakAt * 0.8 then
		return "rising"
	elseif x < Tuning.LivePeakAt * 1.4 then
		return "peak"
	end
	return "falling"
end

-- dt more seconds on sale: the coins it earned meanwhile (the players' average over the step), its players, its
-- peak, a sample every Tuning.LiveSampleSec (the last one, 0, when it leaves the shops). Returns the coins (a
-- fraction: the server pays whole ones) and whether it left the shops in this step.
function Live.step(l: Live, dt: number): (number, boolean)
	if Live.over(l) or dt <= 0 then
		return 0, false
	end
	local a1 = math.min(l.life, l.age + dt)
	local p = Live.playersAt(l, a1)
	local coins = (l.players + p) * 0.5 * (a1 - l.age) * Tuning.CoinPerPlayer
	l.age = a1
	l.players = p
	l.peak = math.max(l.peak, p)
	l.earned += coins
	local want = math.min(Tuning.LiveSamples, math.floor(a1 / Tuning.LiveSampleSec + 1e-6) + 1)
	while #l.samples < want do
		table.insert(l.samples, p)
	end
	local ended = Live.over(l)
	if ended and l.samples[#l.samples] ~= 0 and #l.samples < Tuning.LiveSamples then
		table.insert(l.samples, 0)
	end
	return coins, ended
end

-- What the coins message carries each second (StateClient patches its view's Live with it).
function Live.brief(l: Live): { [string]: number }
	return { id = l.id, age = l.age, players = l.players, earned = l.earned, peak = l.peak, n = #l.samples, last = l.samples[#l.samples] or 0 }
end

-- The coins a whole life would earn on its curve without the wobble (the Making panel's estimate).
function Live.lifetime(rate: number): number
	local n, sum = 200, 0
	for i = 0, n - 1 do
		sum += Live.shape((i + 0.5) / n)
	end
	return rate * Tuning.LiveLife * sum / n
end

return Live
