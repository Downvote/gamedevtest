--!strict
-- Every Roblox id (game passes, developer products, badges, sounds). Pure. 0 = not created yet: every call site
-- checks that an id is set before using it (Monetization.isEnabled). The store (GAME_DESIGN 14): create each pass and
-- product on the Creator Dashboard (Monetization > Passes / Developer Products) and put its id here; until then the
-- Store shows it with its suggested price and says it isn't on sale yet.
local Monetization = {
	-- the game passes (Logic/Store.owns reads Profile.passes, set from these at every join and on a purchase)
	GamePasses = {
		VIP = 0, -- +25% shells, a welcome gift (shells, four eggs, six cosmetics, the VIP title) and a gift every day
		DoubleIncome = 0, -- every shell x2
		QuickTree = 0, -- the Tree of Life lays every 5 minutes in place of 10
		FreeDecor = 0, -- decor, paths, water and fences cost nothing
		PremiumTrack = 0, -- the pass track's premium side, this season and every one after
	} :: { [string]: number },
	-- the developer products (MonetizationService: ProcessReceipt, Logic/Store.product)
	DevProducts = {
		EggUncommon = 0, -- an egg of that rarity into the bag, to hatch for nothing (any kind of that rarity)
		EggRare = 0,
		EggEpic = 0,
		EggLegendary = 0,
		EggMythic = 0,
		EggCelestial = 0,
		RefreshShop = 0, -- a new set of pieces in the rotating shop
		StarterPack = 0, -- once: shells, an epic and a legendary egg, the Explorer set and the Early Bird title
		HatcheryNow = 0, -- every egg in the Hatcheries hatches now
	} :: { [string]: number },
	-- what each should cost (set the real price on the Creator Dashboard; the Store shows the live price once it has it)
	SuggestedRobux = {
		VIP = 399,
		DoubleIncome = 299,
		QuickTree = 199,
		FreeDecor = 249,
		PremiumTrack = 349,
		EggUncommon = 15,
		EggRare = 35,
		EggEpic = 75,
		EggLegendary = 159,
		EggMythic = 399,
		EggCelestial = 999,
		RefreshShop = 19,
		StarterPack = 49,
		HatcheryNow = 29,
	} :: { [string]: number },
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
		-- the weather (GAME_DESIGN 13), measured: a quiet drizzle (36 s, about -52 dB mean), a downpour for a storm
		-- (61 s, -41 dB), light gusts (37 s, -47 dB), a distant boom of thunder (6.7 s, -32 dB)
		RainLight = 9112852671, -- Rain Continuous Drizzle 2 (a loop)
		RainHeavy = 9112858162, -- Rainstorm Heavy Summer Downpour 2 (a loop)
		WindGusts = 9114057104, -- Desert Wind Whistley Light Gusts 1 (a loop)
		Thunder = 9120017047, -- Thunder Distant Boom Thud Rapid Hits 5
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

-- Whether an id is set (0: not created yet).
function Monetization.isEnabled(id: number?): boolean
	return type(id) == "number" and id > 0
end

return table.freeze(Monetization)
