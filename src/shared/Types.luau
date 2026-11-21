--!strict
-- Shared types (docs/ARCHITECTURE.md 3). Pure: no requires, no Roblox APIs.

-- The founder's look: indices into Data/Looks' lists (skin, hair colour, hair style, shirt colour), and what they wear
-- in each of Data/Cosmetics' slots (a cosmetic's id, absent or "" for nothing: GAME_DESIGN 14). Since 2026-11-20 the
-- bakery's customization too (GAME_DESIGN 14.1), each absent for its default: `bangs` (Looks.bangs, 1 the style's own),
-- `hair2` (a second hair colour for the middle of the fringe, Looks.hair; 0 none), `eye` and `eye2` (Looks.eyes; eye2
-- 0 the same as eye), `apron` (Looks.aprons, 1 none), `turn` (Looks.turns: what is in the hand turned about the fist,
-- 1 straight) and a tint for each worn slot and the apron (Looks.tints, 1 the piece's own colours).
export type Look = {
	skin: number,
	hair: number,
	style: number,
	shirt: number,
	hat: string?,
	face: string?,
	neck: string?,
	back: string?,
	hand: string?,
	top: string?,
	bangs: number?,
	hair2: number?,
	eye: number?,
	eye2: number?,
	apron: number?,
	turn: number?,
	hatTint: number?,
	faceTint: number?,
	neckTint: number?,
	backTint: number?,
	handTint: number?,
	topTint: number?,
	apronTint: number?,
}

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

-- music, sfx (the sounds: the interface, the island, the weather): "on" (default) | "off" (the Settings panel, 2026-11-14)
-- zoom: the View slider's notch, 1 (far out) .. #Tuning.CamZoomNotches (close in); Tuning.CamZoomDefault (2026-11-18)
-- lang: "auto" (the player's Roblox language when the game has it) or a language's code (Locale/Lang.LIST); text:
-- "pixel" (the pixel font) or "smooth" (Roblox's own font for every word: the request of 2026-11-20, "an option to turn
-- off pixel text")
export type Settings = { pixel: string, music: string?, sfx: string?, zoom: number?, screen: string?, lang: string?, text: string? }

-- days: island days lived; earned: shells made in all; taken: eggs hatched from the Tree of Life (and driftlings taken
-- in before it laid eggs); sold: driftlings sold; best: the rarest driftling had (0 none yet, 1 .. 5); hatched: the
-- Hatcheries' eggs hatched (the questline counts them).
export type Stats = { days: number, built: number, earned: number, taken: number, sold: number, best: number, hatched: number }

-- An egg held in the bag (Logic/Tree.bagAdd; GAME_DESIGN 14): bought, won on the pass track, or from the starter pack
-- or VIP; hatched for nothing whenever the player likes.
export type Bagged = { id: number, r: number }

-- The pass track (Data/Track; Logic/Store): the season these points are for (Logic/Store.season), the points, and the
-- levels whose free and premium rewards were claimed.
export type Track = { s: number, xp: number, got: { number }, gotP: { number } }
-- What the island made while its player was away (Logic/Store.offline): `away` seconds gone, `secs` of them counted
-- (the cap), `shells` to collect.
export type OfflineReport = { away: number, secs: number, shells: number }
-- The group gift (Logic/Store.setGroup): in the group now (as last checked), the gift given.
export type Group = { member: boolean, gift: boolean }

-- Friends (Logic/Social; GAME_DESIGN 16): who invited this player (a user id, 0 none) and whether that friend's reward
-- went out, the seconds played since joining from the invite (counted until then), how many invited friends were
-- rewarded in all and today (refDay: the UTC day refToday counts), and the Roblox friends on this server now (here:
-- live only, 0 again at every load).
export type Social = {
	referredBy: number,
	refPaid: boolean,
	refPlay: number,
	invited: number,
	refDay: number,
	refToday: number,
	here: number,
}
-- A leaderboard's row (SocialService, "lb.get"): its place, the player and their score.
export type BoardRow = { rank: number, userId: number, name: string, value: number }

-- An egg in a Hatchery (Logic/Breed): the hatchery's piece uid, its parents' ids, what hatches (decided when it is laid:
-- the kind and its mutations) and the island turns left (at 0 it is ready and waits till the player taps the Hatchery:
-- Logic/Breed.hatch, into a hut with room).
export type Egg = { uid: number, a: number, b: number, sp: string, muts: { string }, left: number }

-- The rewards for coming back and for playing (Data/Rewards, Logic/Rewards; GAME_DESIGN 15, 2026-11-19). Days are UTC
-- days on the sea's clock (floor(clock / 86400)).
--   daily: the last day the daily reward was claimed (-1 never), the streak then, the best streak, the milestones
--     given (their days)
--   play: the day `secs` (seconds on the island) count for, and the gifts claimed that day (their indices)
--   tasks: the day they were dealt, each { id, n (the goal), at (the counter when dealt) } and whether it was claimed,
--     and the bonus for all three
--   spin: the day the free spin was last used, spins in hand, spins in all
--   codes: the codes redeemed (upper case)
--   index: the Index milestones claimed (their counts)
export type TaskSave = { id: string, n: number, at: number }
export type RewardsSave = {
	daily: { last: number, streak: number, best: number, miles: { number } },
	play: { day: number, secs: number, got: { number } },
	tasks: { day: number, list: { TaskSave }, got: { boolean }, bonus: boolean },
	spin: { day: number, extra: number, total: number },
	codes: { [string]: boolean },
	index: { got: { number } },
}

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
	tut: number, -- the tips' step (1 .. 4, Plot.TIP_HUT .. TIP_LAST; 0 = done)
	quest: number, -- the questline's quest on the go (Data/Quests; one past the last: all done)
	stats: Stats,
	settings: Settings,
	createdAt: number,
	-- Build mode's inventory: pieces taken away, waiting to go down again for nothing (piece id -> how many; Logic/Plot,
	-- GAME_DESIGN 4.5; 2026-11-14)
	inv: { [string]: number },
	-- the store (GAME_DESIGN 14; Logic/Store; 2026-11-14)
	passes: { [string]: boolean }, -- game passes owned (Config/Monetization keys), checked again at every join
	receipts: { string }, -- the last developer product purchases paid (their PurchaseIds: never paid twice)
	gifts: { [string]: boolean }, -- one-time gifts given: "starter", "vip"
	vipDay: number, -- the UTC day VIP's daily gift was last claimed
	bag: { Bagged }, -- eggs held to hatch for nothing
	owned: { [string]: boolean }, -- cosmetics owned (Data/Cosmetics ids)
	titles: { [string]: boolean }, -- titles earned (Data/Titles ids)
	title: string, -- the title worn ("" none)
	-- saved outfits (Data/Looks.encode strings, at most Tuning.MaxOutfits; the customization screen's Outfits tab, the
	-- bakery's: 2026-11-20)
	outfits: { string },
	shop: { at: number, n: number }, -- the rotating shop: the rotation the refreshes are for, and how many were bought
	track: Track,
	-- offline earnings and the group (GAME_DESIGN 14.3; 2026-11-14)
	seenAt: number, -- the sea's clock when the island was last open (0: unknown, nothing earned away)
	group: Group,
	-- the rewards for coming back and playing (2026-11-19), and the timed boosts they give: id ("shells", "luck") ->
	-- seconds left on the island
	rewards: RewardsSave,
	boosts: { [string]: number },
	-- leaderboards and friends (GAME_DESIGN 16; 2026-11-21)
	social: Social,
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
	turnIn: number?, -- seconds to the island's next turn when the view was made (the Hatcheries' timers)
	tut: number,
	quest: number,
	stats: Stats,
	settings: Settings,
	rates: { shells: number }, -- a turn, the charm bonus in
	charm: number,
	charmBonus: number, -- the share charm adds to every shell the island makes (Logic/Island.charmBonus: 0.25 = +25%)
	nests: number, -- the huts' room
	-- the store (GAME_DESIGN 14)
	passes: { [string]: boolean },
	gifts: { [string]: boolean },
	vipDay: number,
	bag: { Bagged },
	owned: { [string]: boolean },
	titles: { [string]: boolean },
	title: string,
	outfits: { string }, -- the saved outfits (Profile.outfits)
	shopList: { string }, -- the rotating shop's pieces now (Logic/Store.shopNow)
	shopLeft: number, -- seconds till the shop turns over
	shopRefresh: number, -- the refreshes bought in this rotation
	track: Track,
	trackLevel: number, -- the levels reached this season (Logic/Store.level)
	trackInto: number, -- points into the next level
	trackNeed: number, -- points the next level costs
	trackLeft: number, -- seconds till the season ends
	minuteShells: number, -- a minute of what the island makes now (the shells rewards: Logic/Store.minutes)
	incomeMult: number, -- what the passes and the group multiply the island's shells by (Logic/Island.passMult)
	-- offline earnings (GAME_DESIGN 14.3): what waits to be collected (false: nothing), the cap and the share of the
	-- island's pace it earns away, whether "Collect x2" is free (an island's first days)
	offline: OfflineReport | false,
	offlineHours: number,
	offlinePct: number,
	offlineDouble: boolean,
	group: Group,
	groupOn: boolean, -- a group is set (Config/Monetization.Group.Id)
	-- the rewards for coming back and playing (Logic/Rewards.view: the daily streak, playtime, tasks, spins, the
	-- Index's milestones, how many wait) and the timed boosts running (id -> seconds left)
	rewards: any,
	boosts: { [string]: number },
	-- friends (Logic/Social.view): friends invited and rewarded, today's left, the Roblox friends here and what they add
	social: { invited: number, todayLeft: number, here: number, boost: number, referred: boolean },
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
	| "work"
	| "hatcheries"
	| "boosts"
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
	| "used"
	| "dup"

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
