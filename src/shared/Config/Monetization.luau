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
		-- the happy moments: a small music-box chime, one note pitched per moment (Audio's events), never a loud sting
		Chime = 9117043866, -- Music Box Swan Lake Single Notes 20 (a warm note, about 1.5 s of ring)
		ChimeHigh = 9117042092, -- Music Box Swan Lake Single Notes 3 (a higher one)
		Combo = 9119034605, -- Shaker Pod South American Instrument 6
		Tick = 9120917794, -- Wood Impacts Soft Impacts On Temple Blocks 5
		Cheer = 9119034593, -- Shaker Pod South American Instrument 5
		CardFlip = 9118835802, -- Scrapbook Open And Turn Pages 7
		Pop = 9112872239, -- Small Bubbles Water Surface Float Up Pop 5
		Sparkle = 9116395089, -- Magic Glows Soft Clusters Of Chiming Hits 4
		Trumpet = 9113887600, -- Conch Shell Distant Strained Blows Airy 11 (the conch's call)
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
		Hammer = 9114756004, -- Hammer Nail Into Wood 7 (Audio plays its first two taps only)
		BoatHorn = 9113467357, -- Boat Horn Short Long Blasts 1
		Gull = 9118858259, -- Seagull Squawks 3
		Birds = 9119383479, -- Sonoma Morning Birds California Chirping 1
		Waves = 9126010643, -- Surf Bubbles Wave Bubbles On Sand Ocean Foam (a loop)
		Crickets = 9112764546, -- Crickets Night 1 (a loop)
	} :: { [string]: number },
	-- Background music (Audio.music): APM Music's library on the Creator Store (free), chosen by measuring each track
	-- (downloaded and analysed: notes a second, the percussive share, the beat's strength, the loudness section by
	-- section) for calm, drumless, even music that sits in the background: soft acoustic island guitar by day, soft
	-- piano at night, gentle and a little more open at sea. `gain` evens their loudness out (to about -26 dB).
	Music = {
		day = {
			{ id = 1842924737, gain = 0.66 }, -- Campfire Stories (slide guitar, ambient, tender)
			{ id = 1842181663, gain = 0.9 }, -- Tender Reflection (acoustic guitar, harp)
			{ id = 9038622919, gain = 0.55 }, -- Home Camp (Acoustic Guitar Version)
		},
		night = {
			{ id = 9045766377, gain = 1.4 }, -- Gymnopedie No. 1 (solo piano)
			{ id = 137428265678876, gain = 1.4 }, -- Live Piano Stories 11 (Tender & Nostalgic)
			{ id = 140619137413701, gain = 1.6 }, -- Live Piano Stories 06 (Dreamy & Nostalgic)
		},
		sea = {
			{ id = 1848354561, gain = 1.05 }, -- Quietness Sustained (guitar, harp, electric piano)
			{ id = 99990734832720, gain = 0.56 }, -- Daydreaming On A Hammock (new acoustic)
		},
	} :: { [string]: { { id: number, gain: number } } },
}

return table.freeze(Monetization)
