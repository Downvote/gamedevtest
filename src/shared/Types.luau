--!strict
-- Shared types (docs/ARCHITECTURE.md 3). Pure: no requires, no Roblox APIs.

-- A developer's look: indices into Data/Looks' lists (skin, hair colour, hair style, shirt colour).
export type Look = { skin: number, hair: number, style: number, shirt: number }

-- A member of the idea team: they sit at a desk and think up ideas (GAME_DESIGN 3).
export type Member = { id: number, name: string, look: Look, desk: number }

-- An idea on the board: one of Data/Ideas with one of Data/Modifiers (GAME_DESIGN 4).
export type Card = { id: string, mod: string }

-- The game being made (GAME_DESIGN 5): three ideas and each one's minigame result (-1 not played yet, 0 lost, 1 won).
export type Making = { title: string, ideas: { Card }, won: { number }, seed: number }

-- A launched game (GAME_DESIGN 6): it earns `rate` coins a second for good.
export type Game = { id: number, title: string, ideas: { Card }, rate: number, wins: number, at: number }

export type Upgrades = { speed: number, luck: number }

-- A piece of decor standing on the plot (Logic/Plot): plot-local north-west corner and a quarter turn.
export type Piece = { id: string, x: number, z: number, rot: number }
-- The plot (GAME_DESIGN 9): the decor bought (once each) and where copies stand.
export type PlotSave = { owned: { [string]: boolean }, placed: { Piece } }

export type Settings = { pixel: string }

-- rolls: ideas the team thought of; best: the rarest idea's 1 in N; earned: every coin the games made.
export type Stats = { games: number, rolls: number, best: number, earned: number }

export type Profile = {
	v: number,
	coins: number,
	rate: number, -- coins a second from every launched game
	ideas: { Card }, -- the idea board (at most Tuning.BoardSize)
	found: { [string]: number }, -- "idea|mod" -> how many times the team thought of it (the Index)
	project: Making?,
	games: { Game }, -- the newest launched games, at most Tuning.GamesKept (the rate keeps every one)
	nextGame: number,
	upgrades: Upgrades,
	team: { Member },
	office: number, -- Data/Office tier (the room the team sits in)
	tut: number, -- tips banner step (0 = done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
	founder: Look, -- the player's chibi on the street (AvatarView)
	plot: PlotSave,
}

-- What the client sees (Session.view): the profile plus derived fields.
export type ClientView = {
	coins: number,
	rate: number,
	ideas: { Card },
	found: { [string]: number },
	project: Making?,
	games: { Game },
	upgrades: Upgrades,
	team: { Member },
	office: number,
	tut: number,
	stats: Stats,
	settings: Settings,
	plot: number,
	rollEvery: number, -- seconds between two ideas
	luck: number,
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
	| "locked"
	| "full"
	| "cooldown"
	| "max"
	| "blocked"

export type Response = { ok: boolean, data: any?, err: ErrCode? }

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
