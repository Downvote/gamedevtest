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
		-- the interface, the shells and the celebrations: all from the Creator Store, free (Roblox's licensed
		-- ProSoundEffects library, and APM Music's stingers), chosen for the island: wood, bamboo, pebbles, water
		Click = 9120917438, -- Wood Impacts Soft Impacts On Temple Blocks 1
		Open = 9125495923, -- Dowel Swish Bamboo Thick Midrange
		Close = 9125496394, -- Dowel Swish Bamboo Thick Midrange (another)
		Deny = 9120917861, -- Wood Impacts Soft Impacts On Temple Blocks 7 (played low)
		Notice = 9120752412, -- Wind Chimes Random Metal Ceramic Clinks 6
		Ding = 9126073001, -- Synth Sparkle Tone High Pitch Bell Tone Ding
		Coin = 9117268552, -- Pebbles Movement 3 (a shell or two)
		CoinsMany = 9117270219, -- Pebbles Movement 5 (a handful)
		LevelUp = 1837716769, -- APM: Ukulele Fun (sting)
		Reward = 1841485188, -- APM: Desert Island Delight Sting c
		Fanfare = 1837924652, -- APM: Island Fun Sting
		RareFanfare = 1841485135, -- APM: Desert Island Delight Sting a
		Combo = 9119034605, -- Shaker Pod South American Instrument 6
		Tick = 9120917794, -- Wood Impacts Soft Impacts On Temple Blocks 5
		Drumroll = 1842083006, -- APM: Island Chase (sting) (a guardian steps up)
		Cheer = 9119034593, -- Shaker Pod South American Instrument 5
		CardFlip = 9118835802, -- Scrapbook Open And Turn Pages 7
		Pop = 9112872239, -- Small Bubbles Water Surface Float Up Pop 5
		Sparkle = 9116395089, -- Magic Glows Soft Clusters Of Chiming Hits 4
		Trumpet = 9113887600, -- Conch Shell Distant Strained Blows Airy 11 (the conch's call)
		SadTrombone = 9042992801, -- APM: Are You Sad? (sting)
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
	-- Background music (Audio.music): APM Music's library on the Creator Store (free), played one after another,
	-- crossfaded: easygoing island tunes by day, softer ones at night, a light adventure on the islets at sea.
	Music = {
		day = {
			1837879082, -- Paradise Falls
			1837465295, -- Marimba Paradise (alternate no woodwind)
			9038622067, -- Lakefront Days (Ukulele Version)
			1837157487, -- Pineapples & Coconuts
			1839638511, -- Island Beach
		},
		night = {
			9047138975, -- Kona Sunset D
			9047791135, -- Calypso Ballad (No Rhythmic)
			1845934054, -- Steel Drum Atmosphere E
			1846655891, -- Peaceful Creatures B
		},
		sea = {
			1846751054, -- High Sea Adventure (A)
			132571655932359, -- Explore The Rainforest
			1835893953, -- Explorer
		},
	} :: { [string]: { number } },
}

return table.freeze(Monetization)
