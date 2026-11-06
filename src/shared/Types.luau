--!strict
-- Shared types (docs/ARCHITECTURE.md 3). Pure: no requires, no Roblox APIs.

export type Axis = "fun" | "ideas" | "graphics" | "sound"
export type SkillKey = "code" | "design" | "art" | "sound"
export type Match = "great" | "good" | "okay" | "poor"
export type Phase = "build" | "polish"

export type Skills = { code: number, design: number, art: number, sound: number }
export type Scores = { fun: number, ideas: number, graphics: number, sound: number }

-- A developer's look: indices into Data/Looks' lists (skin, hair colour, hair style, shirt colour).
export type Look = { skin: number, hair: number, style: number, shirt: number }

export type Staff = {
	id: number,
	name: string,
	skills: Skills,
	energy: number, -- 0..100
	salary: number, -- per month
	look: Look,
	desk: number, -- 1..desks of the office
	trained: number, -- training sessions so far
}

export type Candidate = { name: string, skills: Skills, salary: number, look: Look }

export type Project = {
	title: string,
	genre: string,
	topic: string,
	platform: string,
	size: string, -- Data/Sizes id
	focus: Axis,
	startWeek: number,
	buildWeeks: number,
	weeksDone: number,
	phase: Phase,
	scores: Scores,
	bugs: number,
	rp: number, -- research points earned by this project so far
	sparks: number,
	cost: number, -- what starting it cost (size + licence)
	pushes: number, -- minigame pushes banked (GAME_DESIGN 14: one at each build milestone)
	nextPush: number, -- milestones reached so far (Logic/Minigames.milestones)
	squashWeek: number, -- the week Bug Squash can be played again
	played: number, -- minigames played on this game
}

export type Release = {
	id: number,
	title: string,
	genre: string,
	topic: string,
	platform: string,
	size: string,
	focus: Axis,
	week: number, -- the week it came out (absolute)
	scores: Scores,
	bugs: number,
	reviews: { number }, -- one per critic (Data/Critics order), 1..10
	total: number,
	match: Match,
	hof: boolean, -- Hall of Fame (total >= Tuning.HallOfFame)
	peak: number, -- week-one copies
	decay: number,
	weeks: number, -- weeks on sale so far
	last: number, -- copies sold last week
	copies: number, -- copies so far
	revenue: number, -- money so far
	fans: number, -- fans won so far
	onSale: boolean,
}

export type Award = { year: number, kind: string, title: string, total: number }

-- A piece of decor standing on the plot (Logic/Plot): plot-local north-west corner and a quarter turn.
export type Piece = { id: string, x: number, z: number, rot: number }
-- The plot (GAME_DESIGN 13): the decor bought (once each) and where copies stand.
export type PlotSave = { owned: { [string]: boolean }, placed: { Piece } }

export type Settings = { pixel: string }

export type Stats = { games: number, copies: number, revenue: number, hof: number, best: number }

export type Profile = {
	v: number,
	money: number,
	fans: number,
	rp: number,
	week: number, -- absolute game week (0 = Year 1, Month 1, Week 1)
	office: number, -- Data/Office tier
	staff: { Staff },
	nextStaff: number,
	candidates: { Candidate },
	candMonth: number, -- the month index the candidates are for (-1 = none yet)
	project: Project?,
	releases: { Release }, -- newest last, at most Tuning.ReleasesKept
	nextRelease: number,
	genres: { [string]: boolean },
	topics: { [string]: boolean },
	matches: { [string]: Match }, -- "genre|topic" -> what a release taught
	lastAd: number, -- month index of the last ad campaign (-1 = never)
	lastParty: number, -- month index of the last pizza party (-1 = never)
	awards: { Award },
	tut: number, -- tips banner step (0 = done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
	founder: Look, -- the player's chibi on the street (AvatarView)
	plot: PlotSave,
}

-- What the client sees (Session.view): the profile plus derived fields.
export type ClientView = {
	money: number,
	fans: number,
	rp: number,
	week: number,
	office: number,
	staff: { Staff },
	candidates: { Candidate },
	project: Project?,
	releases: { Release },
	genres: { [string]: boolean },
	topics: { [string]: boolean },
	matches: { [string]: Match },
	awards: { Award },
	tut: number,
	stats: Stats,
	settings: Settings,
	plot: number,
	canAd: boolean,
	canParty: boolean,
	paused: boolean,
	founder: Look,
	decor: PlotSave,
}

export type ErrCode =
	"bad_payload"
	| "unknown_action"
	| "rate"
	| "not_ready"
	| "busy"
	| "no_project"
	| "not_built"
	| "money"
	| "rp"
	| "locked"
	| "unavailable"
	| "full"
	| "cooldown"
	| "fans"
	| "max"
	| "last"
	| "blocked"

export type Response = { ok: boolean, data: any?, err: ErrCode? }

-- One popup over a developer's head (Fx "work"): staff id, the score, the points, a spark.
export type WorkPop = { id: number, axis: Axis, n: number, spark: boolean }

------------------------------------------------------------------ utility object types (implemented in Logic/Util)
export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}
export type Rng = {
	state: number,
	next: (self: Rng) -> number, -- [0, 1)
	int: (self: Rng, lo: number, hi: number) -> number, -- inclusive
	range: (self: Rng, lo: number, hi: number) -> number, -- [lo, hi)
	chance: (self: Rng, p: number) -> boolean,
	weighted: (self: Rng, w: { number }) -> number, -- index; 0 if all weights <= 0
}
export type PixelTier = "off" | "low" | "medium" | "high"

return {}
