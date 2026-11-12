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
	-- for every island on the server. The driftlings do all the work (no villagers since 2026-11-12)
	StartShells = 300, -- the tips' buildings (a patch, a camp, a stall, a hut: 250) and a little over
	StartFood = 30,
	StartWood = 24,
	TurnSeconds = 40,
	DaySeconds = 4 * 3600, -- the request: "it should take a few hours at least for a day to pass"
	EatPal = 2, -- food a driftling living in a hut eats a turn (one in the pen eats nothing)
	Hungry = 0.5, -- everything makes this share while the food has run out
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
	TierCost = {
		{ shells = 0, wood = 0 },
		{ shells = 1800, wood = 220 },
		{ shells = 14000, wood = 1600 },
		{ shells = 60000, wood = 5500 },
		{ shells = 180000, wood = 15000 },
		{ shells = 480000, wood = 40000 },
	},
	-- the huts (GAME_DESIGN 4.1): a resident's comfort (its hut's, plus this by the hut's level) adds to its work
	ComfortLvl = { 0, 0.04, 0.08 },
	BoostMax = 0.6, -- the boost buildings' shares at one knack together, at most

	-- the Tree of Life (GAME_DESIGN 6; Logic/Tree): it grows a driftling every TreeSecs[speed level] seconds into the
	-- pen (no room limit: "pens should be infinite"); the pen sends its best into the huts while they have room and a building has a free place for them
	TreeSecs = { 12, 11, 10, 9, 8, 7, 6, 5.2, 4.5, 4 }, -- the request: "it creates a creature every few seconds"
	-- its luck: a rarity r's weight (Data/Traits.RARITY) times (1 + TreeLuck x (level - 1) + the huts' luck)^(r - 1)
	TreeLuck = 0.12,
	-- and a mutation roll as one rarity better every TreeMutLuck levels past the first
	TreeMutLuck = 3,
	-- the upgrades' prices in shells (no wood), by the level bought (index 1: the level every island starts at). The
	-- first ones are cheap: "the first few levels are too expensive, the tutorial phase stalls for too long before
	-- the player can afford the first level" (the tips' buildings leave 50 of the starting shells: Speed 2 is 40)
	TreeSpeedCost = { 0, 40, 120, 380, 1200, 3600, 9500, 24000, 58000, 140000 },
	TreeLuckCost = { 0, 50, 150, 450, 1400, 4200, 11000, 28000, 66000, 155000 },
	-- the pen has no room limit and sells nothing by itself ("remove the pen cap"). The one limit left is the save's:
	-- Roblox keeps at most 4 MB a player (about 37,000 driftlings at their longest), so at this many waiting the tree
	-- rests, ready, till some are sold or sent on. Nothing is lost.
	PenSafe = 30000,
	PenShown = 60, -- the pen's best sent to the client with the view (its panel lists 40); the rest go as a count
	-- the Luck levels the Tree of Life grows bigger at ("make the tree look grander and bigger after certain level
	-- milestones for luck"; Logic/Tree.stage): the same levels its mutation rolls step up at (TreeMutLuck)
	TreeStages = { 1, 4, 7, 10 },
	HutTree = 0.5, -- the huts' driftlings' Tree mutations together make it grow this much faster at most ...
	HutLuck = 0.5, -- ... and their Lucky mutations add this much luck at most
	-- selling a driftling: shells by its rarity, times 1 + SellTier x its mutations' tiers, times its sell share
	SellPrice = { 2, 7, 25, 85, 320 },
	SellTier = 0.25,

	-- the Hatchery (GAME_DESIGN 6.1; Logic/Breed): two driftlings and a feast of food make an egg; by the child's rarity
	BreedFood = { 40, 70, 120, 200, 400 }, -- food the feast takes
	BreedTurns = { 3, 4, 6, 9, 14 }, -- island turns the egg takes to hatch
	BreedKeep = 0.5, -- a parent's mutation passes on with this chance (one both parents carry always does)
	BreedTierUp = 0.3, -- one both carry comes out a tier better with this chance (a flaw: its family's first tier)
	BreedNew = 0.15, -- the chance of a new mutation of its own (tier 1 or 2)

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the sea and the islands (GAME_DESIGN 8; Data/Street)
	MaxPlots = 6, -- islands along the boardwalk (the server's size)
	PlotSpacing = 80, -- studs between island origins along X
	PlotPieces = { 24, 40, 60, 85, 115, 150 }, -- buildings and decor standing on an island, by its tier
	PathPieces = { 60, 120, 200, 300, 400, 500 }, -- path tiles, apart from the pieces
	HomeCooldown = 3, -- s between two "go home" requests
	WalkSpeed = 16,
	JumpHeight = 7.2, -- the founder jumps on the islands (studs; held at 0 in Build mode)

	-- camera and pixel filter (Random Bakery's values; ARCHITECTURE 9)
	CamYaw = 45,
	CamPitch = 30, -- 2:1 dimetric (pixel-art "isometric"): ground edges at an exact 2:1 slope, verticals vertical
	CamFov = 1, -- Roblox camera FieldOfView while the pixel filter is on (far away, visually orthographic)
	CamOffFov = 8, -- the classic "off" style
	CamPad = 4, -- art px kept free between the lodge's outline and the screen edges or a HUD block
	CamRayBack = 500, -- studs: orthographic rays start this far behind the view centre (the street's far end still in front)
	CamFollowBox = 0.22, -- the view follows the founder once they come within this share of the screen of an edge
	CamGlide = 0.18, -- share of the way to its target the view moves a frame (in whole art px)
	CamBuildPan = 30, -- studs: in Build mode the view may be dragged this far past the plot's edges
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
	PixelDisplayOrder = -100,
	PixelMaxDyn = 80, -- dynamic models drawn a tick at most (an island's driftlings, visitors and founders)
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
