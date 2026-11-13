--!strict
-- Shared types (docs/ARCHITECTURE.md 3). Pure: no requires, no Roblox APIs.

-- The founder's look: indices into Data/Looks' lists (skin, hair colour, hair style, shirt colour).
export type Look = { skin: number, hair: number, style: number, shirt: number }

-- A building or a piece of decor standing on the island (Logic/Plot): `uid` stays the same while it stands (the
-- driftlings living or working there point at it), `id` is a Data/Buildings id, (x, z) its footprint's
-- north-west corner in plot-local whole studs, `rot` a quarter turn, `lvl` its level (1..3 from an older save's
-- upgrades: a building that makes something makes Tuning.UpgradeMult times as much).
export type Piece = { uid: number, id: string, x: number, z: number, rot: number, lvl: number }
-- The island's pieces (GAME_DESIGN 4).
export type PlotSave = { placed: { Piece } }

-- A driftling (GAME_DESIGN 6): its species (Data/Creatures), where it lives (`home`: a hut's Piece uid, 0: no hut, as
-- when its hut was cleared away: it waits for room, Logic/Tide.settle), the building it works at (a Piece uid, 0:
-- resting; only a driftling in a hut works).
-- muts: its mutations (Data/Traits ids, at most Traits.MAX), rolled when it drifted in or hatched.
export type Pal = { id: number, sp: string, home: number, work: number, muts: { string }? }

-- A driftling floating past on the tide (Logic/Tide; the session's, never saved): what it is and costs.
-- One on the tide: `at` the tide's clock when it came in (the server's time, workspace:GetServerTimeNow), `life` the
-- seconds it takes to float past (Logic/Tide).
export type Drift = { id: number, sp: string, muts: { string }, cost: number, at: number, life: number }

export type Settings = { pixel: string, music: string? } -- music: "on" (default) | "off"

-- days: island days lived; earned: shells made in all; taken: driftlings taken in off the tide (and the Tree of Life's
-- before it); sold: driftlings sold; best: the rarest driftling had (0 none yet, 1 .. 5) (the questline counts them).
export type Stats = { days: number, built: number, earned: number, taken: number, sold: number, best: number, hatched: number }

-- An egg in a Hatchery (Logic/Breed): the hatchery's piece uid, its parents' ids, what hatches (decided when it is laid:
-- the kind and its mutations) and the island turns left (it hatches into a hut with room at the turn it reaches 0).
export type Egg = { uid: number, a: number, b: number, sp: string, muts: { string }, left: number }

export type Profile = {
	v: number,
	shells: number, -- what driftlings cost (GAME_DESIGN 3)
	wood: number, -- what building costs
	day: number, -- the island's day (1 at the start)
	tier: number, -- the island's size (Data/Office tier)
	founder: Look, -- the player's chibi (AvatarView)
	pals: { Pal },
	plot: PlotSave,
	seen: { [string]: number }, -- species id -> 2 had one (the Index)
	eggs: { Egg }, -- the Hatcheries' eggs (one a hatchery)
	nextId: number, -- the next driftling or piece id
	tut: number, -- the tips' step (1 .. 6; 0 = done)
	quest: number, -- the questline's quest on the go (Data/Quests; one past the last: all done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
}

-- What the client sees (Session.view): the profile plus what the rules derive from it.
export type ClientView = {
	shells: number,
	wood: number,
	day: number,
	dayFrac: number, -- how far into the sea's calendar day (0 dawn .. 1; a day is Tuning.DaySeconds: hours)
	tier: number,
	founder: Look,
	pals: { Pal }, -- every driftling
	tide: { Drift }, -- the driftlings floating past, the oldest (the furthest along) first
	tideSecs: number, -- seconds between two (Logic/Tide.secs)
	plot: number, -- the plot index on the sea
	pieces: { Piece },
	seen: { [string]: number },
	eggs: { Egg },
	tut: number,
	quest: number,
	stats: Stats,
	settings: Settings,
	rates: { wood: number, shells: number }, -- a turn
	charm: number,
	nests: number, -- the huts' room
	visitors: number, -- a turn
}

export type ErrCode =
	"bad_payload"
	| "unknown_action"
	| "rate"
	| "not_ready"
	| "busy"
	| "money"
	| "wood"
	| "no_hut"
	| "locked"
	| "full"
	| "egg"
	| "cooldown"
	| "max"
	| "blocked"
	| "no_room"
	| "not_found"
	| "not_done"

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
