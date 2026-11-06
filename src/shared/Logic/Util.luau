--!strict
-- Pure helpers. OWNER: WP0. No Roblox globals.
local Types = require(script.Parent.Parent.Types)

type Signal<T...> = Types.Signal<T...>
type Connection = Types.Connection
type Rng = Types.Rng

local Util = {}

local TWO32 = 4294967296

------------------------------------------------------------------ hashing (deterministic everywhere)
-- FNV-1a 32-bit over the decimal string of an integer, or over a string. Exact in doubles.
function Util.hash32(x: number | string): number
	local s: string = if type(x) == "number" then string.format("%d", math.floor(x)) else x
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		-- h * 16777619 mod 2^32, computed without losing precision (16777619 = 2^24 + 403)
		h = (h * 403 + bit32.lshift(h, 24)) % TWO32
	end
	return h
end

------------------------------------------------------------------ RNG (xorshift32)
local RngMethods = {}
RngMethods.__index = RngMethods

function RngMethods.next(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / TWO32
end
function RngMethods.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end
function RngMethods.range(self: Rng, lo: number, hi: number): number
	return lo + self:next() * (hi - lo)
end
function RngMethods.chance(self: Rng, p: number): boolean
	return self:next() < p
end
function RngMethods.weighted(self: Rng, w: { number }): number
	local total = 0
	for _, x in w do
		if x > 0 then
			total += x
		end
	end
	if total <= 0 then
		return 0
	end
	local r = self:next() * total
	local last = 0
	for i, x in w do
		if x > 0 then
			last = i
			r -= x
			if r < 0 then
				return i
			end
		end
	end
	return last
end

function Util.newRng(seed: number): Rng
	local s = math.floor(seed) % TWO32
	if s == 0 then
		s = 0x9E3779B9
	end
	return (setmetatable({ state = s }, RngMethods) :: any) :: Rng
end

function Util.pick<T>(rng: Rng, arr: { T }): T
	return arr[rng:int(1, #arr)]
end

function Util.shuffle<T>(rng: Rng, arr: { T })
	for i = #arr, 2, -1 do
		local j = rng:int(1, i)
		arr[i], arr[j] = arr[j], arr[i]
	end
end

------------------------------------------------------------------ Signal
function Util.Signal<T...>(): Signal<T...>
	local handlers: { (T...) -> () } = {}
	local signal = {}
	local function connect(fn: (T...) -> ()): Connection
		table.insert(handlers, fn)
		local conn = { Connected = true }
		function conn.Disconnect(self: any)
			if not self.Connected then
				return
			end
			self.Connected = false
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end
		return (conn :: any) :: Connection
	end
	function signal.Connect(_self: any, fn: (T...) -> ()): Connection
		return connect(fn)
	end
	function signal.Once(_self: any, fn: (T...) -> ()): Connection
		local c: Connection
		c = connect(function(...: T...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function signal.Fire(_self: any, ...: T...)
		local snapshot = table.clone(handlers)
		for _, fn in snapshot do
			local f: any = fn
			local ok, err = pcall(f, ...)
			if not ok then
				print("[Signal] handler error: " .. tostring(err))
			end
		end
	end
	function signal.DisconnectAll(_self: any)
		table.clear(handlers)
	end
	return (signal :: any) :: Signal<T...>
end

------------------------------------------------------------------ numbers / tables
function Util.round(x: number): number
	return math.floor(x + 0.5)
end
function Util.clamp(x: number, lo: number, hi: number): number
	return if x < lo then lo elseif x > hi then hi else x
end
function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
function Util.isFinite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
-- round to 2 significant digits (prices): 1234 -> 1200, 87 -> 87, 5 -> 5
function Util.sig2(x: number): number
	if x < 100 then
		return math.floor(x + 0.5)
	end
	local p = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / p + 0.5) * p
end
function Util.deepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t :: any do
		out[k] = Util.deepCopy(v)
	end
	return (out :: any) :: T
end
function Util.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

return Util
