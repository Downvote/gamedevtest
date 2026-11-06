--!strict
-- The one hue-shifted colour ramp every code-drawn sprite shades with (UI/PixelArt for the UI's sprites, the desk's
-- marks, the dice and the WorldHud label icons; Render/Shading for the pixel layer's effect sprites). OWNER: WP9. Pure.
--
-- A colour becomes four tones { dark, shadow, base, light }:
-- * shadow: the hue turns 14 degrees toward blue-violet (the short way round: golds and reds pass through orange and
--   crimson), it loses a little saturation and 20 % of its brightness;
-- * dark (the anti-aliasing next to the outline and every coloured inner line): 30 degrees, 52 % of the brightness;
-- * light: the hue turns 12 degrees toward yellow-orange, it gains brightness and loses some saturation.
-- Near-greys (whites, creams, steel) turn further, so their shadows read lavender rather than brown.
local Ramp = {}

local COOL, WARM = 250 / 360, 50 / 360

local function toHSV(r: number, g: number, b: number): (number, number, number)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end

local function fromHSV(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i %= 6
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- Hue h moved toward `target` by at most `amount` (all in turns), the short way round.
local function toward(h: number, target: number, amount: number): number
	local d = (target - h + 0.5) % 1 - 0.5
	return (h + math.clamp(d, -amount, amount)) % 1
end

export type RGB = { number } -- { r, g, b }, each 0..1

-- The four tones of a colour (r, g, b in 0..1): { dark, shadow, base, light }, each { r, g, b }.
function Ramp.rgb(r: number, g: number, b: number): { RGB }
	local h, s, v = toHSV(r, g, b)
	local neutral = math.max(0, 1 - s / 0.2)
	local function cool(deg: number, smul: number, sadd: number, vmul: number): RGB
		local h2 = toward(h, COOL, (deg + 90 * neutral) / 360)
		local r2, g2, b2 = fromHSV(h2, math.clamp(s * smul + sadd + 0.04 * neutral, 0, 1), math.clamp(v * vmul, 0, 1))
		return { r2, g2, b2 }
	end
	local lr, lg, lb = fromHSV(toward(h, WARM, 12 / 360), s * 0.7, math.min(1, v + (1 - v) * 0.6 + 0.04))
	return { cool(30, 0.82, 0.1, 0.52), cool(14, 0.9, 0.05, 0.8), { r, g, b }, { lr, lg, lb } }
end

-- The same for a 0xRRGGBB colour: { dark, shadow, base, light } as 0xRRGGBB.
function Ramp.hex(n: number): { number }
	local tones = Ramp.rgb(bit32.rshift(n, 16) % 256 / 255, bit32.rshift(n, 8) % 256 / 255, n % 256 / 255)
	local out: { number } = {}
	for i, c in tones do
		local function q(x: number): number
			return math.clamp(math.floor(x * 255 + 0.5), 0, 255)
		end
		out[i] = q(c[1]) * 65536 + q(c[2]) * 256 + q(c[3])
	end
	return out
end

return Ramp
