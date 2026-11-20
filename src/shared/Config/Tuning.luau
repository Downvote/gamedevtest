--!strict
-- Every balance and timing number (docs/GAME_DESIGN.md quotes them; this file wins). Pure.
export type PixelTierSpec = { h: number, hz: number, budgetMs: number, minFps: number, shadows: boolean }

-- The pixel scale K (whole screen px per art pixel) is the one pixel size of the world, the UI and the text (Random
-- Bakery's rule): PixelScaleMin plus one for each PixelScaleSides entry that the screen's short side exceeds. A tier
-- only ever makes K coarser: h = the most art px across the short side (K >= ceil(short side / h)); hz = dynamic
-- layer ticks per second; budgetMs / minFps = the watchdog; shadows = sun shadow rays in the static bake.
local PixelTiers: { [string]: PixelTierSpec } = {
	low = { h = 270, hz = 20, budgetMs = 6, minFps = 0, shadows = false },
	medium = { h = 400, hz = 30, budgetMs = 8, minFps = 25, shadows = true },
	high = { h = 540, hz = 30, budgetMs = 10, minFps = 40, shadows = true },
}

local Tuning = {
	-- persistence (never rename a store: the players' saves are there)
	DataStoreName = "BSS_Profile_v1",
	AutosaveSec = 120,
	LockTTL = 330, -- s: a session lock older than this is stale (a crashed server)
	LoadRetries = 4,
	SaveRetries = 3, -- tries at a leaving player's save (2 s, then 4 s between them)

	-- the island (GAME_DESIGN 3-5): it makes and eats by the turn (TurnSeconds while the player is here: every rate is
	-- a turn's); the calendar day (the clock, day and night, the day count) is DaySeconds of the sea's clock, the same
	-- for every island on the server. The driftlings do all the work (no villagers since 2026-11-12). One store since
	-- 2026-11-14 ("make shells the main currency, allowing you to buy decor and expansions with it. remove wood as a
	-- currency"): shells pay for the driftlings, every piece and growing the island
	-- the Work and Huts tabs' buildings (farms, lumber, shops, boosts, huts, the Hatchery) cost this share of the price
	-- Data/Buildings lists for them, to two figures (the request of 2026-11-13: "make it much cheaper to buy work and
	-- hut buildings")
	BuildingPrice = 0.3,
	-- a price that was paid in wood (every piece's, growing the island's: TierCost) costs WoodShells shells for each
	-- wood since 2026-11-14, times WoodTierUp for each tier of the piece (or of the island grown to) past the second,
	-- to two figures: the farms' and shops' shells go to building now too, and a big island's buildings pay for
	-- themselves fast, so building costs more of them than it did of the wood, the more the bigger
	-- (Data/Buildings.shellsFor, Logic/Island.expandCost)
	WoodShells = 5,
	WoodTierUp = 1.8,
	-- ... up to this tier (Moonlit Bay): past it the price rises only as the listed prices and TierCost rise (the
	-- islands past Driftling Haven were priced for that: GAME_DESIGN 4.4), or the last ones would cost thousands of
	-- times more. (3, 1.5 and 10 until the driftlings arranged themselves at their best work, 2026-11-14, and 4 and
	-- 1.75 until eggs cost a quarter the same day: the island
	-- earned a third more and every island came far sooner)
	WoodTierTop = 7,
	-- the tips' buildings (a camp, a patch, a hut, a stall: 405 at BuildingPrice and WoodShells) and room to fill the
	-- first hut with two eggs of the first lot (a rare and a common, or two uncommons), so no tip waits on shells: the
	-- request of 2026-11-14, "the snack store part in the tutorial takes too long. give the player more shells so
	-- every task is completable at the start without needing to wait" (440 before: one common egg and the stall)
	StartShells = 600,
	TurnSeconds = 40,
	DaySeconds = 4 * 3600, -- the request: "it should take a few hours at least for a day to pass"
	-- the sky's own day round the floating islands (UI/SkyBackdrop; the request of 2026-11-20: "polish the skybox more.
	-- it should be of the same quality as the ones in the egg hatching screen, with day and night cycles with moon and
	-- sun rising"): twenty minutes of the sea's clock from midnight to midnight, the sun up from about a quarter past to
	-- three quarters. Only the sky follows it: the island's light stays the bright day (DayLight).
	SkyDaySecs = 20 * 60,
	IdleOutput = 0.3, -- a building with no driftling working there makes this share
	PalWork = 0.6, -- a common driftling at work makes this share of its workplace's rate ...
	RarityWork = { 1, 1.6, 2.5, 4, 7, 11, 17, 26, 40 }, -- ... times this by its rarity ("creatures work faster based on their rarity")
	-- the driftlings one workplace takes, by the tier it opens at (Data/Buildings'
	-- `jobs`). The request of 2026-11-18: "increase the capacity of work buildings by alot, in turn, make a cap for the
	-- amount of work spaces possible in each island expansion. it should match the number of max driftlings possible
	-- for each expansion" (WorkLimit). It was 2 everywhere. The first island's four keep 2: its cap is 8, and the tips
	-- ask for a camp, a patch and a stall there. Since the request of 2026-11-19 ("after an expansion, buff huts and
	-- work buildings such that buying 2 huts and 2 work buildings of the highest tier is enough to fill the cap,
	-- assuming you also maxxed out the caps before expanding") a tier's is what the newest hut an island of that
	-- tier has holds, so two of the newest workplaces fill what the tier adds to the cap (HousingLimit: the Plot
	-- spec holds it). It was { 2, 6, 8, 10, 12, 16, 16, 16, 16, 16, 20, 24, 24, 28, 28, 28, 32, 32, 32, 32 }
	WorkRoom = { 2, 8, 10, 12, 16, 18, 18, 18, 18, 18, 22, 22, 22, 26, 26, 26, 30, 30, 30, 34 },
	-- charm raises every shell the island makes (the request of 2026-11-14: "remove the visitors mechanic, charm simply
	-- increases your shell gain"): times 1 + CharmMax x charm / (charm + CharmHalf), a soft curve: the first decor
	-- counts the most, and the bonus never passes CharmMax
	CharmMax = 1,
	CharmHalf = 200,
	-- every decor piece's charm for each tile of its footprint (w x d), whatever it is, by the island's tier (the
	-- requests of 2026-11-19: "make decor all give the same amount of charm, scaling based on their size instead",
	-- then "in order to match the previous charm decor gives, make it such that the charm they give scale off
	-- expansions as well"): what the old decor gave a tile on average, all of it an island of that tier could have,
	-- weighted by size (0.55, 0.82, 1.24, 1.5, 1.91, 3.15, 3.93, 5, 6.34, 8.18, 8, 10.1, 10.1, 9.86, 12.5, 12.4, 12.2,
	-- 15.4, 15.4, 19.2), whole and rising with every expansion
	DecorCharm = { 1, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19 },
	Refund = 0.5, -- clearing a piece away gives back this share of its price
	UpgradeMult = { 1, 1.6, 2.3 }, -- a building that makes something, by its level (levels from before upgrades
	-- were taken out on 2026-11-11 are kept; no new ones are bought)
	-- growing the island, in shells (wood until 2026-11-14; cheaper early on: "expanding island costs too much, make them cheaper early on"),
	-- ten tiers since "make more island progression and allow the player to expand their land even more"
	-- (GAME_DESIGN 4): the old wall before Harbor Town lower, four bigger islands past Sunspire Capital; twenty since
	-- the request of 2026-11-14 ("allow expansion up to level 20, you can make the previous levels of expansion a bit
	-- cheaper too"): levels 2 to 10 a fifth off, levels 11 to 20 rising on from there. Then the request of
	-- 2026-11-17, "also, make expansion cheaper at lower levels": level 2 half off again, 3 to 7 less off the higher
	-- they are (about 45, 40, 30, 20 and 10%), 8 and up as they were (480, 7200, 48000, 128000, 300000, 640000 before)
	TierCost = {
		0, 240, 4000, 29000, 90000, 240000, 580000, 1280000, 2400000, 4000000,
		5000000, 6000000, 7200000, 8600000, 10200000, 12000000, 14000000, 16500000, 19500000, 23000000,
	},
	-- the huts (GAME_DESIGN 4.1): a resident's comfort (its hut's, plus this by the hut's level) adds to its work
	ComfortLvl = { 0, 0.04, 0.08 },
	BoostMax = 0.7, -- the boost buildings' shares together, at most, before the driftlings' boost share (0.6 until the
	-- boosts of the islands past Driftling Haven; each boosts every workplace since 2026-11-19, the ones for one kind of
	-- work at a little over half their old share, so a tier 6 island reaches it)
	-- a second boost building of a kind gives this share of the first's (the request of 2026-11-15: "make it such that
	-- boost buildings can stack, but with diminishing returns"; a third gave this share of the second's until BoostEach)
	BoostStack = 0.5,
	-- at most this many of each boost building on an island (the request of 2026-11-20: "make the max of each boosts
	-- building to be 2"; Plot.boostLimit). An older save with more keeps them, and builds no more of that one.
	BoostEach = 2,

	-- the Tree of Life's eggs (GAME_DESIGN 6; Logic/Tree: "bring back the tree of life ... it now spawns eggs around it
	-- that the player can choose to hatch for some shells. it spawns in 5 eggs around it, which refreshes every few
	-- minutes to spawn in another 5 eggs, replacing any existing eggs that were not taken. expanding the island
	-- increases the quality of eggs spawned and amount of eggs spawned"): every EggSecs seconds the tree lays
	-- EggCount[tier] eggs round its roots, the ones left unhatched going. Ten minutes the whole game through since the
	-- request of 2026-11-14 ("remove anything that decreases the tree of life refresh, keep it at 10 minutes throughout
	-- the whole game unless a gamepass is bought"): nothing shortens it but the Quick Tree pass (EggSecsPass). Six
	-- minutes and three with the pass since the request of 2026-11-17: "make the default time for egg refresh 6
	-- minutes, and 3 minutes with gamepass"
	EggSecs = 360,
	EggSecsPass = 180,
	-- the eggs a lot by the island's tier: back to the counts from before the 10 minute tree (the request of
	-- 2026-11-14: "use the same amount of eggs each tree refresh had as before"; they had been tripled to keep the eggs
	-- an hour), then two more on every island (the request of 2026-11-14: "increase the amount of eggs produced by the
	-- tree by 2 across all expansions"); the world shows the EggShown rarest of them round the roots (the ring's room),
	-- the tree's panel every one
	EggCount = { 7, 8, 9, 10, 11, 12, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14 },
	EggShown = 12,
	-- an egg's price: shells by its rarity, times EggTier by the island's tier (a bigger island earns more and lays
	-- better eggs), times the huts' cost shares (cheaper, at most HutCost off). About a quarter of what they were since
	-- the request of 2026-11-14, "make eggs much cheaper" (the prices x0.4, the tiers' multipliers x0.6)
	-- (an ancient egg 1,000,000 and an eternal one 6,000,000 since the request of 2026-11-20, "make more higher tier
	-- eggs, about 2 more tiers": the same steps as mythic to celestial; on Everdrift an eternal egg is about half an
	-- hour of a full island's shells)
	EggPrice = { 8, 36, 160, 800, 4000, 24000, 160000, 1000000, 6000000 },
	EggTier = { 1, 2, 5, 12, 27, 54, 96, 160, 250, 380, 460, 540, 640, 750, 880, 1040, 1220, 1440, 1700, 2000 },
	-- an egg's rarity: a rarity r's weight (Data/Traits.RARITY) times (1 + EggLuck by the island's tier + the huts'
	-- luck)^(r - 1); what hatches rolls its mutations as one rarity better every EggMutTier tiers past the first
	EggLuck = { 0, 0.25, 0.5, 0.75, 1.0, 1.3, 1.6, 1.9, 2.2, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0, 4.2, 4.4, 4.6 },
	EggMutTier = 2,
	-- an egg may turn rarer as it hatches (the hatch scene shows it: the request of 2026-11-13, "eggs having a chance to
	-- skip to the next rarity during the cutscene"): an egg of rarity r goes up one with EggUp[r], and on from there with
	-- the next one's share while the rolls hold (never to a rarity the island has no driftlings of); twice what it was
	-- since the request of 2026-11-14, "also, increase the chance of eggs tiering up"
	EggUp = { 0.12, 0.08, 0.05, 0.025, 0.012, 0.006, 0.003, 0.0015 },
	-- the seasons and the weather (Data/Weather, Logic/Weather; GAME_DESIGN 13: "also, make weather and seasons, and eggs
	-- spawns are affected by these with different mutations"): one sea, one calendar for every island, worked out from
	-- the sea's clock (WorldClock) from WeatherEpoch. A season lasts SeasonSecs (2 h 30 min: the four come round every
	-- 10 hours, so any hour of the day sees each of them within a few days); it is WeatherSecs spells of weather (10
	-- minutes each, 15 a season), each spell's weather picked by the season's odds.
	WeatherEpoch = 0,
	SeasonSecs = 9000,
	WeatherSecs = 600,
	-- an egg laid in a weather is touched by it with WeatherTouch[kind] (a plain sunny or breezy spell touches none):
	-- it hatches with that weather's mutation (Data/Traits' weather families), its tier rolled by WeatherTierW (tier
	-- 1 .. 4, better for a rarer egg; a storm's a tier better, at least 2)
	WeatherTouch = { rain = 0.35, snow = 0.35, blossom = 0.35, leaves = 0.35, haze = 0.3, fog = 0.3, storm = 0.2 } :: { [string]: number },
	WeatherTierW = { 52, 30, 13, 5 },
	-- while it storms the tree's eggs come luckier (luck added to the island's: rarer eggs)
	WeatherLuck = { storm = 0.25 } :: { [string]: number },
	-- a season's own kinds of driftling (its islets, Data/Weather) come SeasonFavour times as often out of its eggs
	SeasonFavour = 3,
	-- the tree's model grows grander with the island (its stage by tier, Models/DecorModels)
	TreeStage = { 1, 2, 2, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6 },
	-- selling a driftling (or swapping it out for a new hatchling): shells by its rarity, times 1 + SellTier x its
	-- mutations' tiers, times its sell share
	SellPrice = { 2, 7, 25, 85, 320, 1300, 5500, 24000, 100000 },
	SellTier = 0.25,

	-- the Hatchery (GAME_DESIGN 6.1; Logic/Breed): two driftlings bred for an egg; by the child's rarity
	BreedShells = { 20, 80, 300, 1200, 5000, 22000, 90000, 380000, 1600000 }, -- shells an egg costs
	BreedTurns = { 3, 4, 6, 9, 14, 20, 28, 38, 50 }, -- island turns the egg takes to hatch
	-- (BreedKeep, BreedTierUp and BreedNew, the chances a parent's mutation passed on, came out a tier better or a new
	-- one came, went on 2026-11-19: a child's mutations are decided, shown before the egg is laid, the best tiers of
	-- both parents', one both carry a tier better: Logic/Breed.inherit. The island's lean on a new mutation, MutLean and
	-- MutLeanFloor, went the same day with the kinds of work building.)
	-- the huts' driftlings' Hatchery shares multiply (each takes its share off what is left: the request of 2026-11-19,
	-- "make mutations that decrease hatchery time, with diminishing returns if stacked"), down to this share of the time
	HatchMin = 0.3,
	-- what the huts' driftlings give the whole island (Data/Traits.ISLE, Logic/Island.isle), each at most this
	IsleCap = {
		luck = 0.5, -- egg luck (was HutLuck)
		cost = 0.5, -- off the eggs' price (was HutCost)
		boost = 1, -- the boost buildings at most twice as strong
		charmPct = 2, -- charm at most three times
		all = 0.6, -- the wondrous and fabled ones (Data/Traits: every fabled effect fits under its cap): every shell
		aura = 0.4, -- every driftling at work
		eggs = 3, -- eggs more in each lot
		skip = 0.2, -- added to each step of Tuning.EggUp
		away = 2, -- offline shells (x3 at most)
	} :: { [string]: number },
	-- the tree lays every rarity on every island (the request of 2026-11-19: "Make all eggs obtainable regardless of
	-- expansion level, but at a very low chance if they are higher rarity"): a rarity none of the kinds open at the
	-- island's tier has weighs EggEarly of its weight (mythic short of tier 11, celestial and ancient short of 14,
	-- eternal short of 17), and what hatches from an
	-- egg is one of a kind not open yet with FarKind (any kind of its rarity), else one of the open kinds
	EggEarly = 0.05,
	FarKind = 0.03,
	-- a timed shells boost (a reward: Logic/Rewards) multiplies every shell by 1 + this while it runs, and a timed luck
	-- boost adds this much egg luck
	TimedShells = 0.5,
	TimedLuck = 0.5,

	-- the store (GAME_DESIGN 14; Logic/Store; the request of 2026-11-14: "make gamepasses for double income, developer
	-- products for hatching any rarity of egg, refreshing shop, a starter pack, speeding up hatcheries, a gamepass track
	-- with eggs, money and cosmetics along with a premium track, a vip gamepass offering alot of rewards, and cosmetics, a
	-- title and a percentage increase to income, a gamepass that speeds up the tree of life refresh to 5 minutes, and a
	-- gamepass that allows for decor and paths to be free")
	DoubleIncome = 2, -- the Double Income pass multiplies every shell the island makes by this
	VipIncome = 0.25, -- the VIP pass adds this share to every shell (with Double Income: x2 x 1.25)
	-- a shells reward is minutes of what the island makes now, at least RewardFloor shells a minute times EggTier by
	-- its tier (a new island makes next to nothing)
	RewardFloor = 25,
	StarterMins = 60, -- the starter pack's shells
	StarterEggs = { 4, 5 }, -- its eggs' rarities (an epic and a legendary)
	VipMins = 180, -- VIP's welcome gift: shells, eggs ...
	VipEggs = { 4, 4, 5, 6 },
	VipDailyMins = 20, -- ... and every UTC day after: shells and an egg
	VipDailyEgg = 3,
	FallbackMins = 30, -- a product that can't do its thing (a starter pack bought twice, no Hatchery egg to finish) pays this
	-- the rotating shop: ShopSize pieces every ShopSecs on the sea's clock (everyone sees the same; a refresh bought
	-- deals the player a new set till it turns over), picked by rarity with ShopWeight; a piece costs CosmeticPrice by
	-- its rarity times EggTier by the island's tier
	ShopSecs = 14400,
	ShopSize = 8,
	-- (Mythic and Celestial pieces since the bakery's came, 2026-11-20: its Mythic and Divine Boutique pieces, Weekly
	-- Cup prizes and reward looks)
	-- (one a rarity like every table by rarity: no piece is Ancient or Eternal yet)
	ShopWeight = { 40, 30, 18, 9, 3, 1, 0.4, 0.15, 0.05 },
	CosmeticPrice = { 120, 400, 1500, 6000, 24000, 60000, 150000, 400000, 1000000 },
	MaxOutfits = 10, -- saved outfits (Profile.outfits: the customization screen's Outfits tab)
	-- the pass track (Data/Track): a season lasts TrackSecs on the sea's clock; level L costs TrackBase + TrackStep x
	-- (L - 1) points; points for an egg hatched (the tree's or the bag's), a Hatchery egg, a quest claimed, the island
	-- grown, and every minute on the island
	TrackSecs = 28 * 86400,
	TrackBase = 100,
	TrackStep = 20,
	TrackXp = { egg = 6, breed = 10, quest = 30, expand = 120, minute = 2 } :: { [string]: number },
	-- offline earnings, as Random Bakery pays them (Logic/Store.offline; the request of 2026-11-14: "Add offline earnings
	-- just like the bakery game, and a gamepass which allows for 24h offline earnings"): away at least OfflineMinSec,
	-- the island keeps earning for up to OfflineHours at OfflinePct of its pace; the Offline Pass makes it
	-- OfflinePassHours at OfflinePassPct. "Collect x2" is free for an island's first OfflineDoubleDays days.
	OfflineMinSec = 300,
	OfflineHours = 3,
	OfflinePct = 0.3,
	OfflinePassHours = 24,
	OfflinePassPct = 1,
	OfflineDoubleDays = 3,
	-- the group gift (the request of 2026-11-14: "a group reward which gives a rare egg and some shells and a +10% boost
	-- in earnings"): once, an egg of GroupEgg's rarity and GroupMins minutes of shells; GroupBoost more shells while in it
	GroupEgg = 3,
	GroupMins = 30,
	GroupBoost = 0.1,

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the islands in the sky (GAME_DESIGN 8; Data/Street)
	MaxPlots = 6, -- floating islands in a row (the server's size)
	-- (170 since 2026-11-20: the top tier's island is about 125 studs across, so open sky stays between two neighbours)
	PlotSpacing = 170, -- studs between island origins along X
	-- buildings and decor standing on an island, by its tier (more room since the build catalog grew: GAME_DESIGN 4)
	PlotPieces = { 36, 60, 90, 130, 180, 240, 300, 370, 450, 540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140 },
	-- the driftlings an island's huts may house together, by its tier (GAME_DESIGN 4; the request of 2026-11-14:
	-- "instead of a hut (building) limit per expansion, make it such that the limit of driftling housing is the limit,
	-- such that you can have 2 driftling huts in the place of a cozy burrow at the cost of comfort"): however many huts
	-- that takes; small huts fill it with less comfort. Since the request of 2026-11-19 (WorkRoom, above) each tier adds
	-- two of its newest hut's room (Data/Buildings `slots`: the Cozy Burrow 8, the Den 10, the Roost 12, the Grotto
	-- 16, the Palace 18 from tier 6 to 10, the Loft 22, the Coral Manor 26, the Cloud Keep 30, the Citadel 34), so
	-- an island full before it grew is full again with two of them; the totals stay near the old ones (8, 24, 40, 60,
	-- 96, 168 .. 840, which jumped at the tiers a new hut opened). The work cap is the same (Plot.workLimit)
	HousingLimit = { 8, 24, 44, 68, 100, 136, 172, 208, 244, 280, 324, 368, 412, 464, 516, 568, 628, 688, 748, 816 },
	-- Hatcheries an island may have, by its tier (the request of 2026-11-14: "there should also be a hatchery limit per
	-- expansion. the first expansion where you unlock hatcheries, make the limit 1"): one from Grand Isle, where they
	-- open, a second on the capital, then one more every four tiers
	HatcheryLimit = { 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5 },
	-- path and water tiles together, apart from the pieces; fence lengths, apart again
	PathPieces = { 80, 150, 240, 340, 460, 600, 750, 900, 1050, 1200, 1320, 1440, 1560, 1680, 1800, 1920, 2040, 2160, 2280, 2400 },
	FencePieces = { 40, 80, 130, 180, 240, 300, 370, 440, 520, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200 },
	HomeCooldown = 3, -- s between two "go home" requests
	WalkSpeed = 16,
	JumpHeight = 7.2, -- the founder jumps on the islands (studs; held at 0 in Build mode)

	-- camera and pixel filter (Random Bakery's values; ARCHITECTURE 9)
	CamYaw = 45,
	CamPitch = 30, -- 2:1 dimetric (pixel-art "isometric"): ground edges at an exact 2:1 slope, verticals vertical
	CamFov = 1, -- Roblox camera FieldOfView while the pixel filter is on (far away, visually orthographic)
	CamOffFov = 8, -- the classic "off" style
	CamPad = 4, -- art px kept free between the lodge's outline and the screen edges or a HUD block
	-- the box round the island's heart the view fitted, as a share of its old size (CameraController FRAME): smaller was
	-- closer (since 2026-11-18 the zoom is CamDetail on every screen, and the box only says where the view starts). The requests of 2026-11-14: "zoom into the island more such that there isnt too much sea in the screen"
	-- (0.7: 12 art px a stud, from 8 at 1), then "zoom out abit more. the whole island should still be visible"
	-- (0.95: 9 art px a stud; the grid snaps the zoom to whole steps: 0.85 gives 10, which clips the first island's
	-- far shore), then "zoom in into the island more. it should fit like this, with the playable island as big as the
	-- bakery" (0.75, about 11 art px a stud: the first island's grass fills the screen between the HUD's strips the way
	-- Random Bakery's shop does, the beach running out to the edges)
	CamFrame = 0.75,
	-- the islands' detail: art px a stud on every screen, however big (the request of 2026-11-18: "make it such that
	-- the pixel filter is, by default, on all devices, zoomed in to be at a good level of detail. make it such that
	-- smaller windows or smaller devices will still receive the same amount of detail as bigger ones"). The frame box
	-- above set the zoom until then, fitted to the screen: 11.25 on a 1080p desktop, 12 on a laptop, about 6 on a
	-- phone. Now the box only says where the view starts; a smaller screen shows less of the island at this detail.
	-- The Settings panel's View slider picks one of ten notches (the request of 2026-11-18: "make a view slider for
	-- zooming the camera in and out, with 10 notches"): art px a stud at each, far out to close in, each a clean grid
	-- scale (Raster.gridScale) and each step about the same share closer. A new player starts on CamZoomDefault: the
	-- seventh, 11 a stud (the request of 2026-11-20, a screenshot of the knob on the seventh notch: "also, make the
	-- default view here"). It was the eighth, 12, at first, then the sixth, 10 (2026-11-18, the knob on the sixth:
	-- "default view should be here").
	CamZoomNotches = { 5, 6, 7, 8, 9, 10, 11, 12, 14, 16 },
	CamZoomDefault = 7,
	-- on a phone (the screen's short side 500 px or less) a smaller box: the request of 2026-11-14, "On mobile, zoom in to
	-- fit the island more" (the camera follows the founder round the rest); 0.75 until the desktop view came closer
	-- the same way (0.95 to 0.75)
	CamFramePhone = 0.6,
	-- the founders on the islands are drawn at this share of their built size, about their feet (the request of
	-- 2026-11-14: "make the chacter smaller, about 75% the original size"); the character's own collision is unchanged
	FounderScale = 0.75,
	-- a founder left alone this long dozes off where it stands (the request of 2026-11-15: "like dozing off while afk";
	-- the bakery's 40 s): no key, mouse or touch and no step for the own one, no step for another player's
	DozeSecs = 40,
	CamRayBack = 500, -- studs: orthographic rays start this far behind the view centre (the street's far end still in front)
	CamFollowBox = 0.22, -- the view follows the founder once they come within this share of the screen of an edge
	-- seconds: the follow's smooth time (a critically damped spring, the request of 2026-11-18: "make the camera a smooth
	-- lerp follow the player like most top down games instead of sharply cutting to the player"). A walking founder is
	-- trailed by their speed times this (3.2 studs at 16 a second) and the view settles on them about half a second
	-- after they stop. Smaller: tighter; bigger: looser. (Before, the view moved 18% of the way a 60th of a second, at
	-- least a whole art px a frame, and stopped dead on the founder.)
	CamFollowSecs = 0.2,
	CamBuildPan = 30, -- studs: in Build mode the view may be dragged this far past the plot's edges
	CamBuildRecenter = 0.12, -- share of Build mode's drag the view gives back each frame the founder walks (it eases back onto them)
	CamHudTop = 22, -- art px: the top HUD strip assumed until the HUD reports its blocks
	CamHudBottom = 26, -- art px: the bottom HUD strip assumed until then
	PixelTiers = PixelTiers,
	PixelScaleMin = 2,
	PixelScaleSides = { 820, 1250, 1700, 2100 },
	PixelSnapshotMsPerFrame = 2,
	PixelBakeMsPerFrame = 6,
	PixelMaxRayDist = 1400,
	PixelPanRays = 6000, -- rays a frame for the strips a pan uncovers (a longer pan catches up over frames)
	PixelPanCacheTiles = 768, -- the pan cache's tiles at most (Pixel/PanCache: 32 x 32 art px, 20 bytes a pixel, about 15.7 MB); 0: off
	PixelInvalidateRaysFrame = 4000, -- rays a frame for re-casting the rects of parts that came or went
	-- and at most this long a frame (a slow device or a slow stretch of rays spreads the re-cast over more frames: the
	-- land's chunks an expansion swaps in used to cost one frame 200 ms in the simulator)
	PixelInvalidateMs = 8,
	-- ms a frame of spare time spent casting the next tier's picture ahead of an expansion (PixelRenderer's pre-cast:
	-- the request of 2026-11-20, "make island expansion seamless, with no lag"); 0: off
	PixelPreCastMs = 2,
	-- ms a frame the filter may spend on a bake or on re-casts while the screen is hidden (Build mode's expansion behind
	-- the loading card: PixelRenderer.setHidden; nobody sees the game's frame rate then, so the new land is ready sooner)
	PixelHiddenMs = 40,
	PixelDisplayOrder = -100,
	PixelMaxDyn = 80, -- dynamic models drawn afresh a tick at most (an island's driftlings and founders; the rest show their kept pictures)
	PixelDynMs = 8, -- ms a tick of drawing models afresh, the founders first, then the longest undrawn (a crowd changes less often, the frame stays short)
	PixelIncCompose = 1, -- 1: a compose redoes only the tiles where something changed and a pan shifts the finished frame (PixelRenderer's incremental compose); 0: every pan composes whole
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
