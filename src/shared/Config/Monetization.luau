--!strict
-- Every Roblox id (game passes, developer products, badges, sounds). Pure. 0 = not created yet: every call site
-- checks that an id is set before using it (Monetization.isEnabled). The store (GAME_DESIGN 14): create each pass and
-- product on the Creator Dashboard (Monetization > Passes / Developer Products) and put its id here; until then the
-- Store shows it with its suggested price and says it isn't on sale yet. Each one's icon to upload with it is
-- art/products/<key>.png (512 x 512, pixel art from the game's own models: sh tools/preview/product_icons.sh).
local Monetization = {
	-- the game passes (Logic/Store.owns reads Profile.passes, set from these at every join and on a purchase)
	GamePasses = {
		VIP = 2092889006, -- +25% shells, a welcome gift (shells, four eggs, six cosmetics, the VIP title) and a gift every day
		DoubleIncome = 2094155115, -- every shell x2
		QuickTree = 2096880957, -- the Tree of Life lays every 3 minutes in place of 6 (Tuning.EggSecsPass, EggSecs)
		FreeDecor = 2093795165, -- decor, paths, water and fences cost nothing
		PremiumTrack = 2097202898, -- the pass track's premium side, this season and every one after
		OfflinePass = 2095793183, -- the island earns for up to 24 hours while the player is away, at its full pace (not 3 at 30%)
		-- each new lot's eggs at the player's chosen rarity or rarer hatch by themselves, coins and huts allowing
		-- (Logic/Tree.autoIds; the request of 2026-11-22), made on the Creator Dashboard the same day
		AutoHatch = 2092272160,
	} :: { [string]: number },
	-- the Roblox group (Community) whose members get the group gift once (a rare egg and shells) and 10% more shells
	-- while they stay in it (Logic/Store.setGroup; MonetizationService checks at every join and on the Store's Claim).
	-- The game's group since 2026-11-21 (the user's "make the group id this 255554513"); 0 would mean no group (the
	-- Store's group card says so and its button waits).
	Group = { Id = 255554513 } :: { Id: number },
	-- the developer products (MonetizationService: ProcessReceipt, Logic/Store.product)
	DevProducts = {
		EggUncommon = 3734112045, -- an egg of that rarity into the bag, to hatch for nothing (any kind of that rarity)
		EggRare = 3734112072,
		EggEpic = 3734112096,
		EggLegendary = 3734112122,
		EggMythic = 3734112177,
		EggCelestial = 3734112209,
		RefreshShop = 3734111924, -- a new set of pieces in the rotating shop
		StarterPack = 3734111893, -- once: shells, an epic and a legendary egg, the Explorer set and the Early Bird title
		HatcheryNow = 3734111996, -- every egg warming in the Hatcheries ready now
		RefreshEggs = 3734111951, -- the Tree of Life lays a fresh lot of eggs now (the request of 2026-11-14: "make a developer product to refresh eggs in the tree of life")
	} :: { [string]: number },
	-- what each costs on the Creator Dashboard (2026-11-21); the Store shows the live price once Roblox gives it, these meanwhile
	SuggestedRobux = {
		VIP = 199,
		DoubleIncome = 199,
		QuickTree = 99,
		FreeDecor = 249,
		PremiumTrack = 249,
		OfflinePass = 199,
		AutoHatch = 149,
		EggUncommon = 19,
		EggRare = 29,
		EggEpic = 49,
		EggLegendary = 99,
		EggMythic = 159,
		EggCelestial = 199,
		RefreshShop = 19,
		StarterPack = 49,
		HatcheryNow = 19,
		RefreshEggs = 19,
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
	-- (downloaded and analysed: notes a second, the percussive share, the beat's strength, the low end, the loudness
	-- section by section) for calm, drumless, even music that sits in the background. By day, since the request of
	-- 2026-11-21 ("find a more fitting, calm track for the music in the roblox library"), slow airy music written for
	-- aerial scenery and a soft solo piano, for islands floating in the sky (the acoustic guitar of an island in the
	-- sea went); soft piano at night. `gain` evens their loudness out (to about -27 dB with Audio's own volume).
	Music = {
		day = {
			{ id = 1837580927, gain = 0.85 }, -- Pastoral Meditation (Scenic Flight / Above and About)
			{ id = 1837580622, gain = 0.85 }, -- Northern Lights (Scenic Flight / Above and About)
			{ id = 86521961943604, gain = 1.05 }, -- Blooming Moments (Solo Piano Version, Drifting Spaces)
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
