--!strict
-- The game's words (GAME_DESIGN 10): English only in this version. Every player-visible string a module shows goes
-- through Lang.t, so other languages can be added the Random Bakery way (a table per language, generated from
-- locale/<code>.json) without touching the callers. Pure.
local Lang = {}

-- The text in the player's language (English: as written). {n}-style templates are filled by Lang.fmt.
function Lang.t(s: string): string
	return s
end

-- Lang.fmt("{n} copies", { n = "1,200" }) -> "1,200 copies"
function Lang.fmt(s: string, args: { [string]: string | number }): string
	return (string.gsub(Lang.t(s), "{(%w+)}", function(k: string): string
		local v = args[k]
		return if v ~= nil then tostring(v) else "{" .. k .. "}"
	end))
end

return Lang
