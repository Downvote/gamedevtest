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
	StartShells = 440, -- the tips' buildings (a camp, a patch, a hut, a stall: 405 at BuildingPrice and WoodShells), the first eggs and a little over
	TurnSeconds = 40,
	DaySeconds = 4 * 3600, -- the request: "it should take a few hours at least for a day to pass"
	IdleOutput = 0.3, -- a building with no driftling working there makes this share
	PalWork = 0.6, -- a common driftling working at a building of its knack makes this share of its rate ...
	RarityWork = { 1, 1.6, 2.5, 4, 7, 11, 17 }, -- ... times this by its rarity ("creatures work faster based on their rarity")
	HelpMax = 2, -- driftlings working at one building at most
	-- charm raises every shell the island makes (the request of 2026-11-14: "remove the visitors mechanic, charm simply
	-- increases your shell gain"): times 1 + CharmMax x charm / (charm + CharmHalf), a soft curve: the first decor
	-- counts the most, and the bonus never passes CharmMax
	CharmMax = 1,
	CharmHalf = 200,
	Refund = 0.5, -- clearing a piece away gives back this share of its price
	UpgradeMult = { 1, 1.6, 2.3 }, -- a building that makes something, by its level (levels from before upgrades
	-- were taken out on 2026-11-11 are kept; no new ones are bought)
	-- growing the island, in shells (wood until 2026-11-14; cheaper early on: "expanding island costs too much, make them cheaper early on"),
	-- ten tiers since "make more island progression and allow the player to expand their land even more"
	-- (GAME_DESIGN 4): the old wall before Harbor Town lower, four bigger islands past Sunspire Capital; twenty since
	-- the request of 2026-11-14 ("allow expansion up to level 20, you can make the previous levels of expansion a bit
	-- cheaper too"): levels 2 to 10 a fifth off, levels 11 to 20 rising on from there
	TierCost = {
		0, 480, 7200, 48000, 128000, 300000, 640000, 1280000, 2400000, 4000000,
		5000000, 6000000, 7200000, 8600000, 10200000, 12000000, 14000000, 16500000, 19500000, 23000000,
	},
	-- the huts (GAME_DESIGN 4.1): a resident's comfort (its hut's, plus this by the hut's level) adds to its work
	ComfortLvl = { 0, 0.04, 0.08 },
	BoostMax = 0.7, -- the boost buildings' shares at one knack together, at most (0.6 until the boosts of the islands past
	-- Driftling Haven: no island short of them reaches it)

	-- the Tree of Life's eggs (GAME_DESIGN 6; Logic/Tree: "bring back the tree of life ... it now spawns eggs around it
	-- that the player can choose to hatch for some shells. it spawns in 5 eggs around it, which refreshes every few
	-- minutes to spawn in another 5 eggs, replacing any existing eggs that were not taken. expanding the island
	-- increases the quality of eggs spawned and amount of eggs spawned"): every EggSecs seconds the tree lays
	-- EggCount[tier] eggs round its roots, the ones left unhatched going. Ten minutes the whole game through since the
	-- request of 2026-11-14 ("remove anything that decreases the tree of life refresh, keep it at 10 minutes throughout
	-- the whole game unless a gamepass is bought"): nothing shortens it but the Quick Tree pass (EggSecsPass)
	EggSecs = 600,
	EggSecsPass = 300,
	-- three times the eggs a lot since the same request (a lot every 10 minutes in place of every 3: about as many eggs
	-- an hour as before, so the island grows at the pace GAME_DESIGN 10 promises); the world shows the EggShown rarest
	-- of them round the roots (the ring's room), the tree's panel every one
	EggCount = { 14, 16, 19, 22, 25, 27, 27, 27, 27, 27, 27, 27, 30, 30, 30, 30, 33, 33, 33, 33 },
	EggShown = 12,
	-- an egg's price: shells by its rarity, times EggTier by the island's tier (a bigger island earns more and lays
	-- better eggs), times the huts' cost shares (cheaper, at most HutCost off). About a quarter of what they were since
	-- the request of 2026-11-14, "make eggs much cheaper" (the prices x0.4, the tiers' multipliers x0.6)
	EggPrice = { 8, 36, 160, 800, 4000, 24000, 160000 },
	EggTier = { 1, 2, 5, 12, 27, 54, 96, 160, 250, 380, 460, 540, 640, 750, 880, 1040, 1220, 1440, 1700, 2000 },
	-- an egg's rarity: a rarity r's weight (Data/Traits.RARITY) times (1 + EggLuck by the island's tier + the huts'
	-- luck)^(r - 1); what hatches rolls its mutations as one rarity better every EggMutTier tiers past the first
	EggLuck = { 0, 0.25, 0.5, 0.75, 1.0, 1.3, 1.6, 1.9, 2.2, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0, 4.2, 4.4, 4.6 },
	EggMutTier = 2,
	-- an egg may turn rarer as it hatches (the hatch scene shows it: the request of 2026-11-13, "eggs having a chance to
	-- skip to the next rarity during the cutscene"): an egg of rarity r goes up one with EggUp[r], and on from there with
	-- the next one's share while the rolls hold (never to a rarity the island has no driftlings of); twice what it was
	-- since the request of 2026-11-14, "also, increase the chance of eggs tiering up"
	EggUp = { 0.12, 0.08, 0.05, 0.025, 0.012, 0.006 },
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
	HutLuck = 0.5, -- the huts' driftlings' luck shares add this much luck at most ...
	HutCost = 0.5, -- ... and their cost shares take this much off the eggs' price at most
	-- selling a driftling (or swapping it out for a new hatchling): shells by its rarity, times 1 + SellTier x its
	-- mutations' tiers, times its sell share
	SellPrice = { 2, 7, 25, 85, 320, 1300, 5500 },
	SellTier = 0.25,

	-- the Hatchery (GAME_DESIGN 6.1; Logic/Breed): two driftlings and a feast make an egg; by the child's rarity
	BreedShells = { 20, 80, 300, 1200, 5000, 22000, 90000 }, -- shells the feast takes
	BreedTurns = { 3, 4, 6, 9, 14, 20, 28 }, -- island turns the egg takes to hatch
	BreedKeep = 0.5, -- a parent's mutation passes on with this chance (one both parents carry always does)
	BreedTierUp = 0.3, -- one both carry comes out a tier better with this chance (a flaw: its family's first tier)
	BreedNew = 0.15, -- the chance of a new mutation of its own (tier 1 or 2)

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
	ShopSize = 6,
	ShopWeight = { 40, 30, 18, 9, 3 },
	CosmeticPrice = { 120, 400, 1500, 6000, 24000 },
	-- the pass track (Data/Track): a season lasts TrackSecs on the sea's clock; level L costs TrackBase + TrackStep x
	-- (L - 1) points; points for an egg hatched (the tree's or the bag's), a Hatchery egg, a quest claimed, the island
	-- grown, and every minute on the island
	TrackSecs = 28 * 86400,
	TrackBase = 100,
	TrackStep = 20,
	TrackXp = { egg = 6, breed = 10, quest = 30, expand = 120, minute = 2 } :: { [string]: number },

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the sea and the islands (GAME_DESIGN 8; Data/Street)
	MaxPlots = 6, -- islands in a row on the sea (the server's size)
	PlotSpacing = 80, -- studs between island origins along X
	-- buildings and decor standing on an island, by its tier (more room since the build catalog grew: GAME_DESIGN 4)
	PlotPieces = { 36, 60, 90, 130, 180, 240, 300, 370, 450, 540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140 },
	-- the driftlings an island's huts may house together, by its tier (GAME_DESIGN 4; the request of 2026-11-14:
	-- "instead of a hut (building) limit per expansion, make it such that the limit of driftling housing is the limit,
	-- such that you can have 2 driftling huts in the place of a cozy burrow at the cost of comfort"): however many huts
	-- that takes. Each tier's is what its old hut limit held in its biggest huts (4 Driftling Huts, 6 Cozy Burrows, 8
	-- Dens ... 42 Driftling Citadels), so the room is the same; small huts fill it with less comfort
	HousingLimit = { 8, 24, 40, 60, 96, 168, 192, 216, 240, 264, 336, 364, 392, 480, 512, 544, 648, 684, 720, 840 },
	-- Hatcheries an island may have, by its tier (the request of 2026-11-14: "there should also be a hatchery limit per
	-- expansion. the first expansion where you unlock hatcheries, make the limit 1"): one from Grand Isle, where they
	-- open, a second on the capital, then one more every four tiers
	HatcheryLimit = { 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5 },
	-- path and water tiles together, apart from the pieces; fence lengths, apart again
	PathPieces = { 80, 150, 240, 340, 460, 600, 750, 900, 1050, 1200, 1320, 1440, 1560, 1680, 1800, 1920, 2040, 2160, 2280, 2400 },
	FencePieces = { 40, 80, 130, 180, 240, 300, 370, 440, 520, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200 },
	HomeCooldown = 3, -- s between two "go home" requests
	WalkSpeed = 16,
	SwimSpeed = 11, -- studs a second in the sea (the founders swim between the islands)
	JumpHeight = 7.2, -- the founder jumps on the islands (studs; held at 0 in Build mode)

	-- camera and pixel filter (Random Bakery's values; ARCHITECTURE 9)
	CamYaw = 45,
	CamPitch = 30, -- 2:1 dimetric (pixel-art "isometric"): ground edges at an exact 2:1 slope, verticals vertical
	CamFov = 1, -- Roblox camera FieldOfView while the pixel filter is on (far away, visually orthographic)
	CamOffFov = 8, -- the classic "off" style
	CamPad = 4, -- art px kept free between the lodge's outline and the screen edges or a HUD block
	-- the box round the island's heart the view fits, as a share of its old size (CameraController FRAME): smaller is
	-- closer. The requests of 2026-11-14: "zoom into the island more such that there isnt too much sea in the screen"
	-- (0.7: 12 art px a stud, from 8 at 1), then "zoom out abit more. the whole island should still be visible"
	-- (0.95: 9 art px a stud; the grid snaps the zoom to whole steps: 0.85 gives 10, which clips the first island's
	-- far shore)
	CamFrame = 0.95,
	-- on a phone (the screen's short side 500 px or less) a smaller box: the request of 2026-11-14, "On mobile, zoom in to
	-- fit the island more" (the camera follows the founder round the rest)
	CamFramePhone = 0.75,
	-- the founders on the islands are drawn at this share of their built size, about their feet (the request of
	-- 2026-11-14: "make the chacter smaller, about 75% the original size"); the character's own collision is unchanged
	FounderScale = 0.75,
	CamRayBack = 500, -- studs: orthographic rays start this far behind the view centre (the street's far end still in front)
	CamFollowBox = 0.22, -- the view follows the founder once they come within this share of the screen of an edge
	CamGlide = 0.18, -- share of the way to its target the view moves a frame (in whole art px)
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
	PixelInvalidateRaysFrame = 4000, -- rays a frame for re-casting the rects of parts that came or went
	-- the island growing into its next tier (Pixel/Grow; GAME_DESIGN 4: "could you make a transition such that it feels
	-- like the island grows out the new land smoothly?")
	GrowSecs = 1.9, -- seconds the coast takes to move out from the old shore to the new one (eased out)
	GrowArmSecs = 3, -- seconds an armed growth waits for the bigger island's bake to begin before it lapses
	PixelDisplayOrder = -100,
	PixelMaxDyn = 80, -- dynamic models drawn a tick at most (an island's driftlings and founders)
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
