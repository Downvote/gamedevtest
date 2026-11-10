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
	-- a turn's), and at each turn's end a visitor may move in and the yard trains; the calendar day (the clock, day and
	-- night, the day count) is DaySeconds of the sea's clock, the same for every island on the server
	StartShells = 300, -- the tips' buildings (a patch, a camp, a stall, a tent, a nest: 280) and a little over
	StartFood = 30,
	StartWood = 24,
	TurnSeconds = 40,
	DaySeconds = 4 * 3600, -- the request: "it should take a few hours at least for a day to pass"
	EatFolk = 3, -- food a villager eats a turn
	EatPal = 2, -- food a driftling eats a turn
	Hungry = 0.5, -- everything makes this share while the food has run out
	IdleOutput = 0.5, -- a building with nobody working there makes this share
	PalBoost = 0.5, -- a driftling helping at a building of its knack adds this share
	VisitorCharm = 15, -- visitors a turn: 1 + charm / this ...
	VisitorsMax = 14, -- ... at most
	ShopVisitors = 4, -- a shop sells its rate with this many visitors a turn (more sell more, up to x2)
	MoveInCharm = 6, -- a visitor moves into a free bed when the charm is at least this x the villagers + 1
	FolkMax = 24,
	PalsMax = 30,
	Refund = 0.5, -- clearing a piece away gives back this share of its price
	UpgradeMult = { 1, 1.6, 2.3 }, -- a building that makes something, by its level ...
	UpgradeCost = { 0, 3, 8 }, -- ... and the price of each level (times its own price)
	TierCost = { { shells = 0, wood = 0 }, { shells = 1800, wood = 220 }, { shells = 14000, wood = 1600 } },

	-- driftlings, villagers, the captain and battles (GAME_DESIGN 6, 7; Logic/Battle)
	LevelGrow = 0.12, -- stats grow by this share of their level-1 values a level
	LevelMax = 60,
	XpBase = 12, -- the xp to the next level: XpBase x level ^ XpPow
	XpPow = 1.35,
	XpPerFoe = 6, -- xp a beaten wild one gives (times its level), shared by the party
	TrainXp = 2, -- xp a day for each villager or driftling resting at a Training Yard
	PartyMax = 3, -- members beside the captain
	Supplies = 4, -- food each member takes on an expedition
	TreatFood = 3, -- food a treat costs in battle
	SkillEvery = 3, -- a fighter's skill fires every this many actions
	GuardTake = 0.5, -- damage taken while guarding
	ShieldTake = 0.6, -- damage taken under a Shell Guard skill
	FleeBase = 0.55,
	BossBoost = 1.7, -- a guardian's stats times this
	RestHeal = 0.5,
	StageWait = 6, -- seconds the expedition's curtain waits at most for the island's picture
	-- the islands found at sea (GAME_DESIGN 7; Logic/Expedition.chart), by the level the captain picks (1 .. theirs)
	IsleFoodBase = 5, -- a loot node's food: base + per level x the level ...
	IsleFoodLvl = 3.3,
	IsleWoodBase = 2, -- ... its wood ...
	IsleWoodLvl = 3.8,
	IsleChestBase = 25, -- ... a chest's shells: base + per level x the level squared
	IsleChestLvl2 = 2,
	IsleRewardBase = 100, -- the guardian's reward: base + per level x the level squared
	IsleRewardLvl2 = 19,
	-- an island never ends (GAME_DESIGN 7): stops in blocks, the last of each a guardian; harder every stage
	BossEvery = 7, -- a guardian every this many stages (six stops, then the guardian)
	StageLvl = 0.5, -- the wild ones' level: this much more every stage (a level every other stage) ...
	StageBoost = 0.02, -- ... and their health and attack this share more every stage (harder every stage)
	StageLoot = 0.12, -- a stage's loot and chests: the island's times (1 + this x the stages before it)
	BossRewardGrow = 0.6, -- the n-th guardian's reward: the island's times (1 + this x (n - 1))
	-- the sea chart (Logic/Chart): every player's islands round their home, in leagues; the level grows with distance
	ChartIslands = 40,
	ChartNear = 3, -- this many within the first boat's range
	ChartMinDist = 1.6,
	ChartMaxDist = 16,
	ChartSpacing = 2.1, -- islands at least this far apart
	ChartLvlPerLeague = 2, -- an island's level: 1 at ChartMinDist, this much more a league further out
	-- the boat (the chart's range): its range by level and the price of each level (shells and wood)
	BoatRadius = { 3.6, 5.8, 8.4, 11.3, 13.8, 16.2 },
	BoatCost = { { shells = 0, wood = 0 }, { shells = 500, wood = 60 }, { shells = 1800, wood = 200 }, { shells = 7000, wood = 800 }, { shells = 18000, wood = 1800 }, { shells = 40000, wood = 4000 } },
	ChartCharm = 3, -- charm for each island charted (its guardian beaten) ...
	ChartCharmMax = 15, -- ... up to this

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the sea and the islands (GAME_DESIGN 8; Data/Street)
	MaxPlots = 6, -- islands along the boardwalk (the server's size)
	PlotSpacing = 80, -- studs between island origins along X
	PlotPieces = { 24, 40, 60 }, -- buildings and decor standing on an island, by its tier
	HomeCooldown = 3, -- s between two "go home" requests
	WalkSpeed = 16,

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
	PixelStageBakeMs = 14, -- more ms a frame for an islet stage's bake (the expedition's curtain covers it)
	PixelMaxRayDist = 1400,
	PixelPanRays = 6000, -- rays a frame for the strips a pan uncovers (a longer pan catches up over frames)
	PixelInvalidateRaysFrame = 4000, -- rays a frame for re-casting the rects of parts that came or went
	PixelDisplayOrder = -100,
	PixelMaxDyn = 80, -- dynamic models drawn a tick at most (an island's villagers and driftlings, an islet's party)
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
