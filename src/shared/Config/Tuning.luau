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
	GamesKept = 50, -- the profile lists the newest launched games (only the newest one sells: Profile.live)

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
	SpeedCost = 40,
	SpeedGrowth = 1.8,
	LuckCost = 60,
	LuckGrowth = 1.8,

	-- launched games (GAME_DESIGN 6): at its peak a game earns the sum of its ideas' worth, IdeaValue x odds ^
	-- IdeaValuePow x its modifier's mult each, a second
	IdeaValue = 1.5,
	IdeaValuePow = 0.7,
	WinBoost = 1 / 3, -- each won minigame adds this to the game's sales (all three: x2)
	IncomeTickSec = 1, -- the server pays the game on sale's coins this often
	-- the game on sale (Logic/Live): its players' curve over its life
	CoinPerPlayer = 0.05, -- coins a player earns a second
	LiveLife = 300, -- seconds on sale (a whole number of LiveSampleSec)
	LivePeakAt = 0.2, -- the players peak this share of the way through ...
	LiveStart = 0.15, -- ... from this share of the peak at the launch ...
	LiveFall = 1.6, -- ... and fall away to none by the end (higher: the fall starts faster)
	LiveWobble = 0.16, -- the slow drift up and down (share of the curve)
	LiveJitter = 0.08, -- the second-to-second jitter
	LiveBuzzes = 2, -- bumps of buzz on the way down (a streamer finds it) ...
	LiveBuzz = 0.35, -- ... lifting the players by up to this share
	LiveFloor = 0.3, -- the wobble never takes the players below this share of the curve
	LiveSampleSec = 3, -- the graph's step
	LiveSamples = 120, -- samples kept at most (LiveLife / LiveSampleSec + 2 fits)

	-- microgames (GAME_DESIGN 5)
	MicroSeconds = 30, -- a minigame round's clock (an engine's `clock` scales it; last one standing ends it sooner)
	MicroIntro = 0.9, -- the instruction word shows this long on the curtain at least
	MicroCountdown = 3, -- then 3, 2, 1, GO! on the stage before the clock starts
	MicroStageWait = 6, -- seconds the curtain waits at most for a microgame stage's picture
	MicroMinSec = 1, -- a win sooner than this after the start counts as a loss
	MicroMaxSec = 150, -- a result later than this counts as a loss
	DiffMax = 8,
	TurboSpeed = 1.35, -- the Turbo modifier: everything this much faster ...
	TurboClock = 0.8, -- ... on a clock this much shorter
	FrenzyMore = 1.6, -- the Frenzy modifier: hazards and pickups this many times as often

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
	PixelStageBakeMs = 14, -- more ms a frame for a microgame stage's bake (the play overlay's curtain covers it)
	PixelMaxRayDist = 1400,
	PixelPanRays = 6000, -- rays a frame for the strips a pan uncovers (a longer pan catches up over frames)
	PixelInvalidateRaysFrame = 4000, -- rays a frame for re-casting the rects of parts that came or went
	PixelDisplayOrder = -100,
	PixelMaxDyn = 64, -- dynamic models drawn a tick at most (a microgame stage has a few dozen)
	PixelInvalidateRays = 3000, -- rays a tick for re-casting changed rects
}

return table.freeze(Tuning)
