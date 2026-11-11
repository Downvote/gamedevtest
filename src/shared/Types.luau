--!strict
-- Shared types (docs/ARCHITECTURE.md 3). Pure: no requires, no Roblox APIs.

-- A person's look: indices into Data/Looks' lists (skin, hair colour, hair style, shirt colour).
export type Look = { skin: number, hair: number, style: number, shirt: number }

-- A building or a piece of decor standing on the island (Logic/Plot): `uid` stays the same while it stands (the
-- villagers and driftlings working there point at it), `id` is a Data/Buildings id, (x, z) its footprint's
-- north-west corner in plot-local whole studs, `rot` a quarter turn, `lvl` its upgrade level (1..3: a building that
-- makes something makes Tuning.UpgradeMult times as much).
export type Piece = { uid: number, id: string, x: number, z: number, rot: number, lvl: number }
-- The island's pieces (GAME_DESIGN 4).
export type PlotSave = { placed: { Piece } }

-- A villager (GAME_DESIGN 5): moved in on `day`; works at the building `work` (a Piece uid, 0: idle); their fighting
-- stats come from `seed` and their level (Logic/Battle).
export type Villager = { id: number, name: string, look: Look, work: number, lvl: number, xp: number, seed: number, day: number }

-- A befriended driftling (GAME_DESIGN 6): its species (Data/Creatures), its level, the building it helps at (a Piece
-- uid, 0: resting at its nest).
-- muts: its mutations (Data/Traits ids, at most Traits.MAX), rolled when it was befriended or hatched.
export type Pal = { id: number, sp: string, lvl: number, xp: number, work: number, muts: { string }? }

-- The founder as the expeditions' captain (GAME_DESIGN 7).
export type Captain = { lvl: number, xp: number }

export type Settings = { pixel: string, music: string? } -- music: "on" (default) | "off"

-- days: island days lived; earned: shells made in all; befriended: driftlings that joined; cleared: islands'
-- guardians beaten; battles won; skills used in battle (the questline counts them).
export type Stats = { days: number, built: number, earned: number, befriended: number, battles: number, cleared: number, movedIn: number, hatched: number, skills: number }

-- An egg in a Hatchery (Logic/Breed): the hatchery's piece uid, its parents' ids, what hatches (decided when it is laid:
-- the kind and its mutations) and the island turns left (0: ready, waiting for a free nest).
export type Egg = { uid: number, a: number, b: number, sp: string, muts: { string }, left: number }

export type Profile = {
	v: number,
	shells: number, -- the money
	food: number,
	wood: number,
	day: number, -- the island's day (1 at the start)
	tier: number, -- the island's size and its lodge (Data/Office tier)
	founder: Look, -- the player's chibi (AvatarView)
	cap: Captain,
	folk: { Villager },
	pals: { Pal },
	plot: PlotSave,
	islets: number, -- islands charted: guardians beaten (each a charm, up to Tuning.ChartCharmMax)
	sea: number, -- the seed of the player's own sea chart (Logic/Chart)
	boat: number, -- the boat's level (its range on the chart)
	pouch: number, -- the snack pouch's level (1 .. #Tuning.PouchCost): Tuning.SnackBase snacks an expedition a level
	chart: { number }, -- the chart's islands charted (ids)
	seen: { [string]: number }, -- species id -> 1 met, 2 befriended (the Index)
	eggs: { Egg }, -- the Hatcheries' eggs (one a hatchery)
	nextId: number, -- the next villager, driftling or piece id
	tut: number, -- the tips' step (1 .. 8; 0 = done)
	quest: number, -- the questline's quest on the go (Data/Quests; one past the last: all done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
}

-- Someone in a battle (Logic/Battle): the founder ("f"), a villager ("v<id>"), a driftling ("p<id>") or a wild one
-- ("w<i>"). `charge` counts the actions to its skill; `gauge` is its timer (0 .. 1: full, it acts).
export type Fighter = {
	key: string,
	name: string,
	kind: string, -- "founder" | "villager" | "pal" | "wild"
	sp: string?, -- a driftling's species
	look: Look?, -- a person's look
	lvl: number,
	hp: number,
	maxHp: number,
	atk: number,
	def: number,
	spd: number,
	skill: string,
	charge: number,
	gauge: number,
	muts: { string }?, -- a driftling's mutations (Data/Traits: a wild one's rolled when it appears, kept when befriended)
}

-- A battle in progress (GAME_DESIGN 7: timed): the wild ones, the actions so far, whether it is the islet's guardian,
-- the shields' seconds left, the action playing (`lock`: seconds every timer waits), paused (landing, aiming a snack,
-- off the screen), its clock, the party's skill points (they charge while it runs: Data/Skills).
-- `undo`: while an automatic action plays (lock > 0), how things stood before it (a snack thrown then cancels it).
export type Battle = { foes: { Fighter }, acts: number, boss: boolean, shield: number, foeShield: number, lock: number, paused: boolean, clock: number, sp: number, undo: Undo? }
export type Undo = { by: string, charge: number, shield: number, foeShield: number, hp: { [string]: number }, atk: { [string]: number } }

-- An island found at sea (GAME_DESIGN 7; Logic/Expedition.chart): made from its seed and the level the captain
-- picked; its kind (Data/Islets), name, the driftlings living there, its guardian, what its loot and chests hold and
-- the guardian's reward.
export type Isle = {
	id: number?, -- its place on the sea chart (Logic/Chart)
	seed: number,
	lvl: number,
	kind: number,
	name: string,
	wild: { string },
	boss: string,
	bossName: string,
	loot: { food: number, wood: number, shells: number },
	reward: number,
}

-- An expedition (GAME_DESIGN 7): the island, the node the party stands on (1 = the landing), its path of nodes
-- ("start" "loot" "chest" "wild" "rest" "boss"), what each node held once visited, the party, what it has gathered,
-- a battle.
export type Expedition = {
	isle: Isle,
	node: number,
	nodes: { string },
	done: { boolean },
	party: { Fighter },
	loot: { shells: number, food: number, wood: number },
	battle: Battle?,
	befriended: { string }, -- species that joined on this trip
	gained: { xp: number, ups: { [string]: number } }, -- the trip's xp for the party and each member's levels gained
	snacks: number, -- snacks left to throw on this trip (Tuning.SnackBase a pouch level: 5 .. 30)
	beaten: number?, -- the guardians beaten on this trip (the path never ends: a guardian every Tuning.BossEvery stages)
	over: string?, -- "home" | "won" | "lost" (set when it ends: "won" only by a player that sails home after a guardian)
}

-- What the client sees (Session.view): the profile plus what the rules derive from it.
export type ClientView = {
	shells: number,
	food: number,
	wood: number,
	day: number,
	dayFrac: number, -- how far into the sea's calendar day (0 dawn .. 1; a day is Tuning.DaySeconds: hours)
	tier: number,
	founder: Look,
	cap: Captain,
	folk: { Villager },
	pals: { Pal },
	plot: number, -- the plot index on the sea
	pieces: { Piece },
	islets: number,
	sea: number,
	boat: number,
	pouch: number, -- the snack pouch's level (snacks an expedition: Tuning.SnackBase x it)
	chart: { number },
	seen: { [string]: number },
	eggs: { Egg },
	tut: number,
	quest: number,
	stats: Stats,
	settings: Settings,
	rates: { food: number, wood: number, shells: number }, -- a day, after eating
	charm: number,
	beds: number,
	nests: number,
	visitors: number, -- a day
	exp: Expedition?,
}

export type ErrCode =
	"bad_payload"
	| "unknown_action"
	| "rate"
	| "not_ready"
	| "busy"
	| "money"
	| "wood"
	| "food"
	| "locked"
	| "full"
	| "egg"
	| "cooldown"
	| "max"
	| "blocked"
	| "no_room"
	| "no_exp"
	| "in_battle"
	| "not_found"
	| "far"
	| "no_snacks"
	| "not_done"
	| "sp"

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
