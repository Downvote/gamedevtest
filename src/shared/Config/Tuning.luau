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
	-- for every island on the server. The driftlings do all the work (no villagers since 2026-11-12). Two stores
	-- ("make wood the main resource for building/expanding and shells the main resource of getting new driftlings.
	-- remove food as a resource"): wood pays for every piece and for growing the island, shells for the driftlings
	StartWood = 300, -- the tips' buildings (a camp, a patch, a hut, a stall) and plenty over
	-- the Work and Huts tabs' buildings (farms, lumber, shops, boosts, huts, the Hatchery) cost this share of the price
	-- Data/Buildings lists for them, to two figures (the request of 2026-11-13: "make it much cheaper to buy work and
	-- hut buildings")
	BuildingPrice = 0.3,
	StartShells = 60, -- the first eggs
	TurnSeconds = 40,
	DaySeconds = 4 * 3600, -- the request: "it should take a few hours at least for a day to pass"
	IdleOutput = 0.3, -- a building with no driftling working there makes this share
	PalWork = 0.6, -- a common driftling working at a building of its knack makes this share of its rate ...
	RarityWork = { 1, 1.6, 2.5, 4, 7 }, -- ... times this by its rarity ("creatures work faster based on their rarity")
	HelpMax = 2, -- driftlings working at one building at most
	VisitorCharm = 15, -- visitors a turn: 1 + charm / this ...
	VisitorsMax = 14, -- ... at most
	ShopVisitors = 4, -- a shop sells its rate with this many visitors a turn (more sell more, up to x2)
	Refund = 0.5, -- clearing a piece away gives back this share of its price
	UpgradeMult = { 1, 1.6, 2.3 }, -- a building that makes something, by its level (levels from before upgrades
	-- were taken out on 2026-11-11 are kept; no new ones are bought)
	-- growing the island, in wood (cheaper early on: "expanding island costs too much, make them cheaper early on"),
	-- ten tiers since "make more island progression and allow the player to expand their land even more"
	-- (GAME_DESIGN 4): the old wall before Harbor Town lower, four bigger islands past Sunspire Capital
	TierCost = { 0, 600, 9000, 60000, 160000, 380000, 800000, 1600000, 3000000, 5000000 },
	-- the huts (GAME_DESIGN 4.1): a resident's comfort (its hut's, plus this by the hut's level) adds to its work
	ComfortLvl = { 0, 0.04, 0.08 },
	BoostMax = 0.6, -- the boost buildings' shares at one knack together, at most

	-- the Tree of Life's eggs (GAME_DESIGN 6; Logic/Tree: "bring back the tree of life ... it now spawns eggs around it
	-- that the player can choose to hatch for some shells. it spawns in 5 eggs around it, which refreshes every few
	-- minutes to spawn in another 5 eggs, replacing any existing eggs that were not taken. expanding the island
	-- increases the quality of eggs spawned and amount of eggs spawned"): every EggSecs seconds (sooner with the huts'
	-- tree shares) the tree lays EggCount[tier] eggs round its roots, the ones left unhatched going
	EggSecs = 180,
	EggCount = { 5, 6, 7, 8, 9, 10, 10, 10, 10, 10 },
	-- an egg's price: shells by its rarity, times EggTier by the island's tier (a bigger island earns more and lays
	-- better eggs), times the huts' cost shares (cheaper, at most HutCost off)
	EggPrice = { 20, 90, 400, 2000, 10000 },
	EggTier = { 1, 3, 8, 20, 45, 90, 160, 270, 420, 640 },
	-- an egg's rarity: a rarity r's weight (Data/Traits.RARITY) times (1 + EggLuck by the island's tier + the huts'
	-- luck)^(r - 1); what hatches rolls its mutations as one rarity better every EggMutTier tiers past the first
	EggLuck = { 0, 0.25, 0.5, 0.75, 1.0, 1.3, 1.6, 1.9, 2.2, 2.6 },
	EggMutTier = 2,
	-- an egg may turn rarer as it hatches (the hatch scene shows it: the request of 2026-11-13, "eggs having a chance to
	-- skip to the next rarity during the cutscene"): an egg of rarity r goes up one with EggUp[r], and on from there with
	-- the next one's share while the rolls hold (never to a rarity the island has no driftlings of)
	EggUp = { 0.06, 0.04, 0.025, 0.012 },
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
	TreeStage = { 1, 2, 2, 3, 3, 4, 4, 4, 4, 4 },
	HutTree = 0.5, -- the huts' driftlings' tree shares together bring the next eggs this much sooner at most ...
	HutLuck = 0.5, -- ... their luck shares add this much luck at most ...
	HutCost = 0.5, -- ... and their cost shares take this much off the eggs' price at most
	-- selling a driftling (or swapping it out for a new hatchling): shells by its rarity, times 1 + SellTier x its
	-- mutations' tiers, times its sell share
	SellPrice = { 2, 7, 25, 85, 320 },
	SellTier = 0.25,

	-- the Hatchery (GAME_DESIGN 6.1; Logic/Breed): two driftlings and a feast make an egg; by the child's rarity
	BreedShells = { 20, 80, 300, 1200, 5000 }, -- shells the feast takes
	BreedTurns = { 3, 4, 6, 9, 14 }, -- island turns the egg takes to hatch
	BreedKeep = 0.5, -- a parent's mutation passes on with this chance (one both parents carry always does)
	BreedTierUp = 0.3, -- one both carry comes out a tier better with this chance (a flaw: its family's first tier)
	BreedNew = 0.15, -- the chance of a new mutation of its own (tier 1 or 2)

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the sea and the islands (GAME_DESIGN 8; Data/Street)
	MaxPlots = 6, -- islands in a row on the sea (the server's size)
	PlotSpacing = 80, -- studs between island origins along X
	-- buildings and decor standing on an island, by its tier (more room since the build catalog grew: GAME_DESIGN 4)
	PlotPieces = { 36, 60, 90, 130, 180, 240, 300, 370, 450, 540 },
	-- huts an island may have, by its tier (GAME_DESIGN 4: "make a limit of huts per island expansion level"): more room
	-- for driftlings comes from growing the island, or a bigger hut in a small one's place (Replace)
	HutLimit = { 4, 6, 8, 10, 12, 14, 16, 18, 20, 22 },
	-- path and water tiles together, apart from the pieces; fence lengths, apart again
	PathPieces = { 80, 150, 240, 340, 460, 600, 750, 900, 1050, 1200 },
	FencePieces = { 40, 80, 130, 180, 240, 300, 370, 440, 520, 600 },
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
	PixelMaxDyn = 80, -- dynamic models drawn a tick at most (an island's driftlings, visitors and founders)
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
