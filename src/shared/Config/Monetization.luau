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
	-- Creator Store library sounds (the same Roblox, ProSoundEffects and APM ids Random Bakery uses)
	Sounds = {
		Click = 15675059323,
		Hover = 17208339919,
		Open = 15675055424,
		Close = 15675081158,
		Deny = 17208353912,
		Notice = 17208361335,
		Ding = 9125485591,
		Coin = 127645268874265,
		CoinsMany = 9113849731,
		LevelUp = 1848271884,
		Reward = 9044781938,
		Fanfare = 9040482556,
		RareFanfare = 9048764753,
		Combo = 1841173364,
		Tick = 9120917813,
		Drumroll = 9120365917,
		Applause = 9113137529,
		Cheer = 9120974507,
		CardFlip = 15675037413,
		TypeKey = 9120299893,
		Pop = 9112751731,
		Sparkle = 9116394876,
		Trumpet = 1840270052,
		SadTrombone = 1840224982,
		Squish = 9117848644,
	} :: { [string]: number },
}

return table.freeze(Monetization)
