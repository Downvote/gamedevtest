--!strict
-- Number formatting for the UI and notices. Pure.
local Numbers = {}

-- 1234567 -> "1,234,567"
function Numbers.int(n: number): string
	local neg = n < 0
	local s = string.format("%d", math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if neg then "-" .. out else out
end

-- 950 -> "950", 12340 -> "12.3K", 1500000 -> "1.5M", 2.1e9 -> "2.1B"
function Numbers.short(n: number): string
	local a = math.abs(n)
	local sign = if n < 0 then "-" else ""
	local function fmt(v: number, suffix: string): string
		local s = if v >= 100 then string.format("%d", math.floor(v)) else string.format("%.1f", math.floor(v * 10) / 10)
		s = string.gsub(s, "%.0$", "")
		return sign .. s .. suffix
	end
	if a >= 1e9 then
		return fmt(a / 1e9, "B")
	elseif a >= 1e6 then
		return fmt(a / 1e6, "M")
	elseif a >= 1e4 then
		return fmt(a / 1e3, "K")
	end
	return sign .. Numbers.int(a)
end

-- Money: "$12.3K" (short) or "$12,340" (exact).
function Numbers.money(n: number, exact: boolean?): string
	local body = if exact then Numbers.int(math.abs(n)) else Numbers.short(math.abs(n))
	return (if n < 0 then "-$" else "$") .. body
end

-- Coins: "1.2K" with the coin word's short form left to the caller; rates: "+12.4/s".
function Numbers.coins(n: number): string
	return Numbers.short(math.floor(n))
end

function Numbers.rate(n: number): string
	if n < 100 then
		return "+" .. string.gsub(string.format("%.1f", math.floor(n * 10) / 10), "%.0$", "") .. "/s"
	end
	return "+" .. Numbers.short(n) .. "/s"
end

-- A day's change: "+12/day", "-3/day" (short past ten thousand).
function Numbers.perDay(n: number): string
	local r = math.floor(math.abs(n) + 0.5)
	return (if n < -0.5 then "-" else "+") .. Numbers.short(r) .. "/day"
end

-- A rarity: "1 in 1,250" (short past a million: "1 in 4.5M").
function Numbers.oneIn(n: number): string
	if n >= 1e6 then
		return "1 in " .. Numbers.short(n)
	end
	return "1 in " .. Numbers.int(n)
end

return Numbers
