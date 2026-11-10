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
		-- the battles, the islands and the sea (Creator Store, free: Roblox's licensed ProSoundEffects library)
		Whoosh = 9119741493, -- Swoosh Pack High End Multiple Variations 8
		WhooshHeavy = 9120728815, -- Whoosh Heavy Punches 1
		Hit = 9117969687, -- Punch Kit Beefy Hit 2
		HitHeavy = 9117970193, -- Punch Kit Beefy Hit 7
		BodyFall = 9113480917, -- Body Fall Thud 1
		Zap = 9114277757, -- Electric Zaps 12
		Heal = 9116394545, -- Magic Glows Soft Clusters Of Chiming Hits 1
		Shield = 9119072660, -- Shield Clang As Hit Metal Sword Hubcap 1
		Poof = 9116406610, -- Magic Poofs Thumpy Wheezy Exhale 1
		Bite = 9119055432, -- Shark Bite Smaller Teeth Snaps 6
		ChestOpen = 9120873789, -- Wooden Chest Open Close Cedar Box 9
		Splash = 9125703162, -- Mud Puddle Splash Shallow Water Impacts Hits
		Hammer = 9114756004, -- Hammer Nail Into Wood 7
		BoatHorn = 9113467357, -- Boat Horn Short Long Blasts 1
		Gull = 9118858259, -- Seagull Squawks 3
		Birds = 9119383479, -- Sonoma Morning Birds California Chirping 1
		Waves = 9126010643, -- Surf Bubbles Wave Bubbles On Sand Ocean Foam (a loop)
		Crickets = 9112764546, -- Crickets Night 1 (a loop)
	} :: { [string]: number },
}

return table.freeze(Monetization)
