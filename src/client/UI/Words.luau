--!strict
-- What the interface says when the server refuses something (docs/ARCHITECTURE.md 10.4): every Types.ErrCode in
-- plain words.
local Words = {}

local ERRORS: { [string]: string } = {
	money = "Not enough shells.",
	wood = "Not enough wood.",
	food = "Not enough food.",
	busy = "They're away on an expedition.",
	full = "There's no room for more.",
	max = "That's as far as it goes.",
	locked = "Not open yet.",
	cooldown = "Not yet. Try again in a moment.",
	blocked = "That can't be done here.",
	no_room = "Build more homes or nests first.",
	no_exp = "There's no expedition under way.",
	in_battle = "Finish the battle first.",
	not_found = "They're not here any more.",
	egg = "An egg is still warming in that Hatchery.",
	far = "Too far for your boat. A bigger one could make it.",
	no_snacks = "Out of snacks for this trip. A bigger pouch holds more.",
	not_done = "That quest isn't done yet.",
	sp = "Not enough skill points yet. They build up as the fight goes on.",
	rate = "Slow down a little.",
	not_ready = "One moment, your island is still waking up.",
}

function Words.errText(err: string?): string
	return if err then ERRORS[err] or "That didn't work. Try again." else "That didn't work. Try again."
end

return Words
