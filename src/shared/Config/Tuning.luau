--!strict
-- Every balance and timing number (docs/GAME_DESIGN.md quotes them; this file wins). Pure.
export type PixelTierSpec = { h: number, hz: number, budgetMs: number, minFps: number, shadows: boolean }
export type SizeSpec = { weeks: number, cost: number, price: number, expect: number, sales: number }
export type OfficeSpec = { desks: number, rent: number, cost: number, fans: number }

-- The pixel scale K (whole screen px per art pixel) is the one pixel size of the world, the UI and the text (Random
-- Bakery's rule): PixelScaleMin plus one for each PixelScaleSides entry that the screen's short side exceeds. A tier
-- only ever makes K coarser: h = the most art px across the short side (K >= ceil(short side / h)); hz = dynamic
-- layer ticks per second; budgetMs / minFps = the watchdog; shadows = sun shadow rays in the static bake.
local PixelTiers: { [string]: PixelTierSpec } = {
	low = { h = 270, hz = 20, budgetMs = 6, minFps = 0, shadows = false },
	medium = { h = 400, hz = 30, budgetMs = 8, minFps = 25, shadows = true },
	high = { h = 540, hz = 30, budgetMs = 10, minFps = 40, shadows = true },
}

-- Game sizes (GAME_DESIGN 6.1): build weeks, cost to start, price per copy, the critics' expectation factor and the
-- sales factor.
local Sizes: { [string]: SizeSpec } = {
	small = { weeks = 8, cost = 2000, price = 10, expect = 1, sales = 1 },
	medium = { weeks = 14, cost = 12000, price = 18, expect = 1.8, sales = 1.5 },
	large = { weeks = 22, cost = 40000, price = 30, expect = 3, sales = 2.2 },
}

-- Offices (GAME_DESIGN 7), by tier: desks, rent a month, the move's price, fans needed.
local Offices: { OfficeSpec } = {
	{ desks = 3, rent = 1000, cost = 0, fans = 0 },
	{ desks = 5, rent = 3000, cost = 120000, fans = 3000 },
	{ desks = 8, rent = 8000, cost = 500000, fans = 25000 },
}

local Tuning = {
	-- persistence (never rename a store: the players' saves are there)
	DataStoreName = "BSS_Profile_v1",
	AutosaveSec = 120,
	LockTTL = 330, -- s: a session lock older than this is stale (a crashed server)
	LoadRetries = 4,
	ReleasesKept = 60, -- the profile keeps the newest releases; older ones live on in stats
	ViewReleases = 30, -- the client view's newest releases

	-- time (GAME_DESIGN 3)
	WeekSec = 4, -- real seconds per game week
	WeeksPerMonth = 4,
	MonthsPerYear = 12,

	-- money, fans, research (GAME_DESIGN 4)
	StartMoney = 40000,
	StartFans = 0,
	StartRp = 0,
	StartStaff = 2,
	RescueSize = "small", -- a broke studio (money < 0) can always start a game of this size on the RescuePlatform, free
	RescuePlatform = "pc",

	-- crew (GAME_DESIGN 5)
	SalaryBase = 300,
	SalaryPerSkill = 12,
	SkillMax = 250,
	CandidateMin = 4,
	CandidateMax = 40,
	CandidateYearly = 3, -- every skill of a candidate +this per year after Year 1
	Candidates = 3,
	EnergyMax = 100,
	EnergyWork = 6, -- per week of work
	EnergyRest = 12, -- per idle week
	EnergyTired = 25, -- under this a developer works at half speed (and dozes)
	TiredRate = 0.5,
	PartyPerStaff = 400,
	TrainRp = 15,
	TrainMoney = 2000,
	TrainEnergy = 20,
	TrainMin = 4, -- +skill for a skill at SkillMax ... TrainMax for a skill at 0
	TrainMax = 6,

	-- development (GAME_DESIGN 6.2)
	WorkRate = 0.5, -- points per skill point per week
	TeamPower = 0.75, -- a crew of n works like n ^ TeamPower developers (they talk, they wait for each other)
	WorkSpread = 0.3, -- each week's output times 1 +- this
	SparkChance = 0.08,
	SparkMult = 3,
	SparkRp = 2,
	RpPerWeek = 1,
	FocusBoost = 1.3,
	FocusOther = 0.9,
	BugBase = 1, -- a developer adds a bug a week with chance BugBase - Code / BugCode, at least BugMin
	BugCode = 150,
	BugMin = 0.1,
	FixBase = 1, -- bugs fixed a week while polishing: FixBase + Code / FixCode (rounded down)
	FixCode = 30,
	PolishRate = 0.2, -- share of the build rate a developer still adds while polishing

	-- reviews (GAME_DESIGN 6.3)
	QualityWeights = { fun = 1, ideas = 0.8, graphics = 0.8, sound = 0.6 },
	BugPenalty = 25,
	MatchMult = { great = 1.3, good = 1.1, okay = 1, poor = 0.8 },
	LoveMult = 1.1,
	NoveltyMult = 0.85,
	NoveltyLookback = 3,
	ExpectBase = 600,
	ExpectYearly = 0.3,
	CriticLean = 1, -- the most a critic's favourite score moves their review
	CriticWobble = 0.6,
	HallOfFame = 32,

	-- sales (GAME_DESIGN 6.4)
	SalesBase = 800, -- week-one copies of an average game on a market-1 platform, before fans
	FanBuy = 0.1, -- share of the fans who buy a game in its first week (times the game's quality factor)
	SalesPivot = 5, -- average review that sells the base amount
	SalesPower = 2,
	DecayBase = 0.7,
	DecayPerPoint = 0.025,
	SalesMinWeek = 5, -- a game leaves the shelves after a week under this many copies
	SalesMaxWeeks = 40,
	StudioCut = 0.7,
	FanPerCopy = 0.08,
	FanHofMult = 1.25,

	-- office, ads, awards (GAME_DESIGN 7, 8)
	AdCost = 4000, -- times the office tier
	AdFans = 250, -- times the office tier (a flat amount: a share of the fans would compound every month)
	GotyTotal = 34,
	GotyFans = 0.3,
	GotyMoney = 20000, -- times the year
	PickTotal = 28,
	PickFans = 0.1,
	PickMoney = 5000, -- times the year

	-- research costs (GAME_DESIGN 6.1), by the genre's or topic's tier (1 = open at the start)
	GenreRp = { 0, 30, 60 },
	TopicRp = { 0, 20, 40 },

	Sizes = Sizes,
	Offices = Offices,

	-- server
	StepHz = 10,
	RateLimitPerSec = 12, -- requests per player per second (more are refused with "rate")

	-- the street and the plot (GAME_DESIGN 12, 13; Data/Street)
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
