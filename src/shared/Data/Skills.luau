--!strict
-- The skills the party learns (GAME_DESIGN 7: "you can select a menu in battle anytime that opens a skill window. you
-- can choose different skills that act like the snack interface, doing so causes your teammates to do something like
-- rally, heal team, heal selected member, do aoe damage, etc. they learn these skills on level up, including the
-- leader as well. however, these cost skill points, which charge up over time in battle. stronger skills will cost
-- more skill points"). Pure data.
--   Each fighter learns a family of skills by level: the leader (the founder) its own, the others the family of
--   their own battle skill (a villager's bash, heal or shell; a driftling's species skill). A skill costs `cost` of
--   the party's skill points (Logic/Battle: they charge up in battle), is used by the one who knows it (their timer
--   starts again) and aims at nobody (`target` "none": the team or every foe), a standing member ("ally"), a member
--   who is down ("down") or a wild one ("foe"). `move` is how it plays on screen (a strike's kind, or "cast").
--   Effects (Logic/Battle.useSkill): dmg (times an attack, on the target or every foe with `all`, `hits` times),
--   heal (a share of max health: the target, or the team with `all`), revive (a downed member back at a share),
--   rally (the team's attack times it), shield (the team's guard for `secs` seconds), haste (every ally's timer
--   forward by it), dizzy (every foe's timer back to it).
export type Skill = {
	id: string,
	name: string,
	cost: number,
	target: string, -- "none" | "ally" | "down" | "foe"
	move: string, -- "attack" | "bash" | "quick" | "zap" | "cast"
	blurb: string,
	dmg: number?,
	hits: number?,
	all: boolean?,
	heal: number?,
	revive: number?,
	rally: number?,
	shield: number?,
	haste: number?,
	dizzy: number?,
}

local LIST: { Skill } = {
	-- the leader's
	{ id = "cry", name = "Rally Cry", cost = 3, target = "none", move = "cast", rally = 1.2, blurb = "The team hits harder." },
	{ id = "aid", name = "First Aid", cost = 3, target = "ally", move = "cast", heal = 0.4, blurb = "Mends one member." },
	{ id = "hug", name = "Group Hug", cost = 5, target = "none", move = "cast", heal = 0.25, all = true, blurb = "Mends the whole team." },
	{ id = "charge", name = "Charge!", cost = 7, target = "none", move = "cast", haste = 1, blurb = "Every ally acts at once." },
	-- bash
	{ id = "pbonk", name = "Power Bonk", cost = 3, target = "foe", move = "bash", dmg = 2.2, blurb = "A heavy blow on one." },
	{ id = "spin", name = "Spin Swipe", cost = 5, target = "none", move = "zap", dmg = 1.0, all = true, blurb = "Hits every wild one." },
	{ id = "mbonk", name = "Mega Bonk", cost = 8, target = "foe", move = "bash", dmg = 3.6, blurb = "A huge blow on one." },
	-- quick
	{ id = "flurry", name = "Flurry", cost = 4, target = "foe", move = "quick", dmg = 0.8, hits = 3, blurb = "Three quick hits." },
	{ id = "zoom", name = "Zoom Zoom", cost = 6, target = "none", move = "quick", dmg = 0.75, hits = 2, all = true, blurb = "Two dashes past every wild one." },
	{ id = "wind", name = "Tailwind", cost = 6, target = "none", move = "cast", haste = 0.5, blurb = "Every ally's timer jumps ahead." },
	-- zap
	{ id = "spark", name = "Spark", cost = 3, target = "foe", move = "zap", dmg = 1.9, blurb = "A jolt on one." },
	{ id = "tide", name = "Tide Wave", cost = 6, target = "none", move = "zap", dmg = 1.25, all = true, blurb = "A wave over every wild one." },
	{ id = "storm", name = "Squall", cost = 9, target = "none", move = "zap", dmg = 2.1, all = true, blurb = "A storm on every wild one." },
	-- heal
	{ id = "mend", name = "Mend", cost = 3, target = "ally", move = "cast", heal = 0.45, blurb = "Mends one member a lot." },
	{ id = "rain", name = "Soothing Rain", cost = 6, target = "none", move = "cast", heal = 0.3, all = true, blurb = "Mends the whole team." },
	{ id = "revive", name = "Revive", cost = 8, target = "down", move = "cast", revive = 0.5, blurb = "Brings a fallen member back." },
	-- shell
	{ id = "shellup", name = "Shell Up", cost = 3, target = "none", move = "cast", shield = 8, blurb = "The team takes less harm." },
	{ id = "wall", name = "Coral Wall", cost = 5, target = "none", move = "cast", shield = 10, heal = 0.15, all = true, blurb = "A long guard and a little mending." },
	{ id = "dizzy", name = "Dizzy Shell", cost = 7, target = "none", move = "cast", dizzy = 0, blurb = "Every wild one's timer starts over." },
}

-- Who learns what, at which level: the leader's family, and one for each battle skill.
local LINES: { [string]: { { id: string, lvl: number } } } = {
	lead = { { id = "cry", lvl = 1 }, { id = "aid", lvl = 3 }, { id = "hug", lvl = 6 }, { id = "charge", lvl = 10 } },
	bash = { { id = "pbonk", lvl = 1 }, { id = "spin", lvl = 5 }, { id = "mbonk", lvl = 10 } },
	quick = { { id = "flurry", lvl = 1 }, { id = "zoom", lvl = 5 }, { id = "wind", lvl = 9 } },
	zap = { { id = "spark", lvl = 1 }, { id = "tide", lvl = 4 }, { id = "storm", lvl = 9 } },
	heal = { { id = "mend", lvl = 1 }, { id = "rain", lvl = 4 }, { id = "revive", lvl = 8 } },
	shell = { { id = "shellup", lvl = 1 }, { id = "wall", lvl = 5 }, { id = "dizzy", lvl = 9 } },
}

local BY_ID: { [string]: Skill } = {}
for _, s in LIST do
	BY_ID[s.id] = s
end

local Skills = {}
Skills.list = LIST
Skills.byId = BY_ID
Skills.LINES = LINES

-- A fighter's family: the leader's, else its own battle skill's (rally and unknown ones: the leader's).
function Skills.lineOf(kind: string, skill: string): string
	if kind == "founder" then
		return "lead"
	end
	return if LINES[skill] then skill else "lead"
end

-- The skills a fighter of this family knows at this level, in the order learnt.
function Skills.known(line: string, lvl: number): { Skill }
	local out: { Skill } = {}
	local list: { { id: string, lvl: number } } = LINES[line] or {}
	for _, l in list do
		if lvl >= l.lvl then
			table.insert(out, BY_ID[l.id])
		end
	end
	return out
end

-- Whether a fighter of this family knows the skill at this level.
function Skills.knows(line: string, lvl: number, id: string): boolean
	local list: { { id: string, lvl: number } } = LINES[line] or {}
	for _, l in list do
		if l.id == id and lvl >= l.lvl then
			return true
		end
	end
	return false
end

-- The skills learnt between two levels (a level up: the alert names them).
function Skills.learnt(line: string, from: number, to: number): { Skill }
	local out: { Skill } = {}
	local list: { { id: string, lvl: number } } = LINES[line] or {}
	for _, l in list do
		if l.lvl > from and l.lvl <= to then
			table.insert(out, BY_ID[l.id])
		end
	end
	return out
end

return Skills
