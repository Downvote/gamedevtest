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
-- when its hut was cleared away: it waits for room, Logic/Tree.settle), the building it works at (a Piece uid, 0:
-- resting; only a driftling in a hut works).
-- muts: its mutations (Data/Traits ids, at most Traits.MAX), rolled when it hatched.
-- `pin`: the player picked its workplace (or rest) in the work picker, so the automatic arrangement leaves it there
-- (Island.arrange; absent: it works wherever it makes the most, the request of 2026-11-14).
export type Pal = { id: number, sp: string, home: number, work: number, muts: { string }?, pin: boolean? }

-- An egg the Tree of Life laid round its roots (Logic/Tree; GAME_DESIGN 6): its id and its rarity (1 .. 5: its shell's
-- colour); what hatches from it is rolled when the player hatches it. `cost` is on the client's copy only
-- (Session.view: its price on this island now). The weather it was laid in (GAME_DESIGN 13; Logic/Weather): `ss` the
-- season (Data/Weather.SEASONS id), and when the weather touched it `wx` the kind (Data/Weather.KINDS id) and `wt` its
-- mutation's tier (1 .. 4): it hatches with that weather's mutation.
export type Laid = { id: number, r: number, cost: number?, ss: string?, wx: string?, wt: number? }
-- The tree's eggs (saved): seconds till it lays the next lot (they replace the ones left), the eggs, the next egg's id.
export type Clutch = { left: number, list: { Laid }, next: number }

export type Settings = { pixel: string, music: string? } -- music: "on" (default) | "off"

-- days: island days lived; earned: shells made in all; taken: eggs hatched from the Tree of Life (and driftlings taken
-- in before it laid eggs); sold: driftlings sold; best: the rarest driftling had (0 none yet, 1 .. 5); hatched: the
-- Hatcheries' eggs hatched (the questline counts them).
export type Stats = { days: number, built: number, earned: number, taken: number, sold: number, best: number, hatched: number }

-- An egg in a Hatchery (Logic/Breed): the hatchery's piece uid, its parents' ids, what hatches (decided when it is laid:
-- the kind and its mutations) and the island turns left (it hatches into a hut with room at the turn it reaches 0).
export type Egg = { uid: number, a: number, b: number, sp: string, muts: { string }, left: number }

export type Profile = {
	v: number,
	shells: number, -- the one store: driftlings, building and growing the island (GAME_DESIGN 3; wood went 2026-11-14)
	day: number, -- the island's day (1 at the start)
	tier: number, -- the island's size (Data/Office tier)
	founder: Look, -- the player's chibi (AvatarView)
	pals: { Pal },
	plot: PlotSave,
	seen: { [string]: number }, -- species id -> 2 had one (the Index)
	eggs: { Egg }, -- the Hatcheries' eggs (one a hatchery)
	clutch: Clutch, -- the Tree of Life's eggs round its roots
	nextId: number, -- the next driftling or piece id
	tut: number, -- the tips' step (1 .. 6; 0 = done)
	quest: number, -- the questline's quest on the go (Data/Quests; one past the last: all done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
	-- Build mode's inventory: pieces taken away, waiting to go down again for nothing (piece id -> how many; Logic/Plot,
	-- GAME_DESIGN 4.5; 2026-11-14)
	inv: { [string]: number },
}

-- What the client sees (Session.view): the profile plus what the rules derive from it.
export type ClientView = {
	shells: number,
	day: number,
	dayFrac: number, -- how far into the sea's calendar day (0 dawn .. 1; a day is Tuning.DaySeconds: hours)
	clock: number, -- the sea's clock (WorldClock.now: seconds); the season and the weather come from it (Logic/Weather)
	tier: number,
	founder: Look,
	pals: { Pal }, -- every driftling
	clutch: { Laid }, -- the tree's eggs now, each with its price
	clutchLeft: number, -- seconds till the tree lays the next lot
	clutchSecs: number, -- seconds between two lots (Logic/Tree.secs)
	plot: number, -- the plot index on the sea
	pieces: { Piece },
	inv: { [string]: number }, -- Build mode's inventory (Profile.inv)
	seen: { [string]: number },
	eggs: { Egg },
	tut: number,
	quest: number,
	stats: Stats,
	settings: Settings,
	rates: { shells: number }, -- a turn, the charm bonus in
	charm: number,
	charmBonus: number, -- the share charm adds to every shell the island makes (Logic/Island.charmBonus: 0.25 = +25%)
	nests: number, -- the huts' room
}

export type ErrCode =
	"bad_payload"
	| "unknown_action"
	| "rate"
	| "not_ready"
	| "busy"
	| "money"
	| "no_hut"
	| "huts"
	| "hatcheries"
	| "fixed"
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
