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
export type Pal = { id: number, sp: string, lvl: number, xp: number, work: number }

-- The founder as the expeditions' captain (GAME_DESIGN 7).
export type Captain = { lvl: number, xp: number }

export type Settings = { pixel: string }

-- days: island days lived; earned: shells made in all; befriended: driftlings that joined; cleared: islands'
-- guardians beaten; battles won.
export type Stats = { days: number, built: number, earned: number, befriended: number, battles: number, cleared: number, movedIn: number }

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
	seen: { [string]: number }, -- species id -> 1 met, 2 befriended (the Index)
	nextId: number, -- the next villager, driftling or piece id
	tut: number, -- the tips' step (0 = done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
}

-- Someone in a battle (Logic/Battle): the founder ("f"), a villager ("v<id>"), a driftling ("p<id>") or a wild one
-- ("w<i>"). `charge` counts the actions to its skill.
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
}

-- A battle in progress: the wild ones, the round, whether it is the islet's guardian.
export type Battle = { foes: { Fighter }, round: number, boss: boolean, shield: number, foeShield: number }

-- An island found at sea (GAME_DESIGN 7; Logic/Expedition.chart): made from its seed and the level the captain
-- picked; its kind (Data/Islets), name, the driftlings living there, its guardian, what its loot and chests hold and
-- the guardian's reward.
export type Isle = {
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
	over: string?, -- "home" | "won" | "lost" (set when it ends)
}

-- What the client sees (Session.view): the profile plus what the rules derive from it.
export type ClientView = {
	shells: number,
	food: number,
	wood: number,
	day: number,
	dayFrac: number, -- how far into the day (0..1)
	tier: number,
	founder: Look,
	cap: Captain,
	folk: { Villager },
	pals: { Pal },
	plot: number, -- the plot index on the sea
	pieces: { Piece },
	islets: number,
	seen: { [string]: number },
	tut: number,
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
	| "cooldown"
	| "max"
	| "blocked"
	| "no_room"
	| "no_exp"
	| "in_battle"
	| "not_found"

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
