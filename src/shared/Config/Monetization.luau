--!strict
-- Every Roblox id (game passes, developer products, badges, sounds). Pure. 0 = not created yet: every call site
-- checks that an id is set before using it. This first version sells nothing (GAME_DESIGN 10).
local Monetization = {
	GamePasses = {} :: { [string]: number },
	DevProducts = {} :: { [string]: number },
	Badges = {
		FirstGame = 0,
		HallOfFame = 0,
		GameOfTheYear = 0,
	} :: { [string]: number },
	Sounds = {
		Click = 0,
		Release = 0,
		Fanfare = 0,
	} :: { [string]: number },
}

return table.freeze(Monetization)
