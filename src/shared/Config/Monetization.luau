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
		-- the happy moments: each its own small, short library sound (never one note pitched up or down to stand in
		-- for another, never a loud sting), measured for length and loudness before going in
		DoorChime = 9125492239, -- Door Chimes Various Tone Sequences Door Bell (its first ding-dong: a newcomer)
		BellTreeRun = 9119447936, -- Sparkle Bell Tree Wind Chimes 1 (the island grows)
		ChimeCluster = 9116394876, -- Magic Glows Soft Clusters Of Chiming Hits 2 (a friend made, an egg hatched)
		SparkleTones = 9126073318, -- Synth Sparkle Tone High Pitch Bell Tone Ding (the longer take: a level up)
		Triangle = 9116224196, -- Large Metal Triangle Single Ringing Hits 9 (a reward)
		MusicBoxWind = 9117044099, -- Music Box Winding Up 4 (an egg laid at the Hatchery)
		SparklePass = 9125635426, -- Magical Exit Sparkling Pass Bys Clinking Chimes (a rare wild one turns up)
		Combo = 9119034605, -- Shaker Pod South American Instrument 6
		Tick = 9120917794, -- Wood Impacts Soft Impacts On Temple Blocks 5
		Cheer = 9119034593, -- Shaker Pod South American Instrument 5
		CardFlip = 9118835802, -- Scrapbook Open And Turn Pages 7
		Pop = 9112872239, -- Small Bubbles Water Surface Float Up Pop 5
		Sparkle = 9116395089, -- Magic Glows Soft Clusters Of Chiming Hits 4
		-- the hatch scene's egg cracking (the request of 2026-11-14: "make sounds when cracking the egg"): measured, the
		-- crunch of each is between about 0.15 s and 0.6 s into the clip
		CrackEgg1 = 9113959343, -- Crack Egg Crunchy 11
		CrackEgg2 = 9113959332, -- Crack Egg Crunchy 9
		CrackEgg3 = 9113958797, -- Crack Egg Crunchy 4
		EggBreak = 9114232663, -- Eggs Break 15 (the shell giving way, from about 0.4 s)
		-- the islands and the sea (Creator Store, free: Roblox's licensed ProSoundEffects library)
		Hammer = 9114756004, -- Hammer Nail Into Wood 7 (Audio plays its first two taps only)
		Gull = 9118858259, -- Seagull Squawks 3
		Birds = 9119383479, -- Sonoma Morning Birds California Chirping 1
		-- the founder's feet (Roblox's own footstep, jump and landing sounds are switched off: RbxCharacterSounds)
		StepGrass1 = 9120062960, -- Tip Toe Of Object Onto Grass 8
		StepGrass2 = 9120062559, -- Tip Toe Of Object Onto Grass 1
		StepSand1 = 9118768256, -- Sand Impacts 4
		StepSand2 = 9118768193, -- Sand Impacts 5
		StepWood1 = 9114523345, -- Foot Stomp 3 (the boardwalk, the jetty, the pier)
		StepWood2 = 9114523358, -- Foot Stomp 4
		StepWood3 = 9114523629, -- Foot Stomp 7
		Hop = 9113819689, -- Cloth Flap 12 (a jump)
		LandSand = 9118768199, -- Sand Impacts 6 (landing)
		Waves = 9126010643, -- Surf Bubbles Wave Bubbles On Sand Ocean Foam (a loop)
		Crickets = 9112764546, -- Crickets Night 1 (a loop)
	} :: { [string]: number },
	-- Background music (Audio.music): APM Music's library on the Creator Store (free), chosen by measuring each track
	-- (downloaded and analysed: notes a second, the percussive share, the beat's strength, the loudness section by
	-- section) for calm, drumless, even music that sits in the background: soft acoustic island guitar by day, soft
	-- piano at night. `gain` evens their loudness out (to about -26 dB).
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
	} :: { [string]: { { id: number, gain: number } } },
}

return table.freeze(Monetization)
