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
	GamesKept = 50, -- the profile lists the newest launched games; every one keeps earning (Profile.rate)

	-- the idea team (GAME_DESIGN 3, 4)
	StartCoins = 0,
	TeamSize = 3, -- the idea team (the garage's desks)
	BoardSize = 12, -- ideas the board holds; when full, a rarer idea takes the commonest one's place
	RollBase = 8, -- seconds between two ideas at speed level 0
	RollStep = 0.92, -- each speed level multiplies it by this ...
	RollMin = 1, -- ... down to this
	LuckStep = 0.2, -- each luck level adds this to the luck (x1 at level 0)
	RareOdds = 60, -- ideas and modifiers this rare or rarer roll at luck / odds; rarer than Uncommon: 1 / odds
	CommonOdds = 13, -- ideas commoner than this (their odds below it) are the Commons, sharing what the others leave
	CommonFloor = 0.1, -- the commons always keep at least this share of the rolls, however lucky
	-- the rarity tiers by an idea's combined 1 in N (Common below the first, Mythic from the last)
	TierOneIn = { 20, 250, 3000, 40000, 500000 },
	TierNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	TierColors = { "text_dim", "good", "button", "purple", "accent", "fun" },
	RevealTier = 3, -- ideas of this tier and up get the big reveal

	-- upgrades (GAME_DESIGN 7): price = base x growth ^ level
	SpeedCost = 50,
	SpeedGrowth = 2.5,
	LuckCost = 80,
	LuckGrowth = 2.5,

	-- launched games (GAME_DESIGN 6): an idea earns IdeaValue x odds ^ IdeaValuePow x its modifier's mult a second
	IdeaValue = 0.5,
	IdeaValuePow = 0.35,
	WinBoost = 1 / 3, -- each won minigame adds this to the game's income (all three: x2)
	IncomeTickSec = 1, -- the server pays the games' income this often

	-- microgames (GAME_DESIGN 5)
	MicroSeconds = 6, -- a microgame's clock at difficulty 1 ...
	MicroSecondsMin = 4, -- ... shortening with difficulty to this
	MicroSecondsStep = 0.25,
	MicroIntro = 0.9, -- the instruction word shows this long before the clock starts
	MicroMinSec = 1, -- a win sooner than this after the start counts as a loss
	MicroMaxSec = 60, -- a result later than this counts as a loss
	DiffMax = 8,
	TurboSpeed = 1.35, -- the Turbo modifier: everything this much faster ...
	TurboClock = 0.8, -- ... on a clock this much shorter

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the street and the plot (GAME_DESIGN 8, 9; Data/Street)
	MaxPlots = 6, -- plots along the road (the server's size)
	PlotSpacing = 80, -- studs between plot origins along X
	PlotPieces = { 20, 32, 48 }, -- decor pieces standing on a plot, by office tier
	HomeCooldown = 3, -- s between two "go home" requests
	WalkSpeed = 16,

	-- camera and pixel filter (Random Bakery's values; ARCHITECTURE 9)
	CamYaw = 45,
	CamPitch = 30, -- 2:1 dimetric (pixel-art "isometric"): ground edges at an exact 2:1 slope, verticals vertical
	CamFov = 1, -- Roblox camera FieldOfView while the pixel filter is on (far away, visually orthographic)
	CamOffFov = 8, -- the classic "off" style
	CamPad = 4, -- art px kept free between the office's outline and the screen edges or a HUD block
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
	PixelMaxDyn = 40, -- dynamic models drawn a tick at most
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
