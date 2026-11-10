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
	cooldown = "Not yet: try again in a moment.",
	blocked = "That can't be done here.",
	no_room = "Build more homes or nests first.",
	no_exp = "There's no expedition under way.",
	in_battle = "Finish the battle first.",
	not_found = "They're not here any more.",
	far = "Too far for your boat: upgrade it to sail further.",
	rate = "Slow down a little.",
	not_ready = "One moment: your island is still waking up.",
}

function Words.errText(err: string?): string
	return if err then ERRORS[err] or "That didn't work. Try again." else "That didn't work. Try again."
end

return Words
