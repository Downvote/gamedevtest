--!strict
-- The codes a player can redeem (GAME_DESIGN 15.4; Logic/Rewards.redeem). Server only, so nobody reads them out of the
-- client. Each is upper case (what a player types is trimmed and made upper case first), with what it gives (Data/Rewards'
-- reward shapes) and an optional end (`ends`: the sea's clock, seconds; past it the code is gone). Once a player.
-- Add a code here, ship, and post it.
local Codes: { [string]: { give: { { kind: string, mins: number?, r: number?, id: string?, n: number? } }, ends: number? } } = {
	WELCOME = { give = { { kind = "shells", mins = 6 }, { kind = "boost", id = "luck", mins = 30 } } },
	DRIFTLING = { give = { { kind = "shells", mins = 12 }, { kind = "egg", r = 3 } } },
	HATCHDAY = { give = { { kind = "egg", r = 4 } } },
	SPINME = { give = { { kind = "spin", n = 3 } } },
}

return table.freeze(Codes)
