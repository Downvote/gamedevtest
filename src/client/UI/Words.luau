--!strict
-- What the interface says when the server refuses something (docs/ARCHITECTURE.md 10.4): every Types.ErrCode in
-- plain words.
local Words = {}

local ERRORS: { [string]: string } = {
	money = "Not enough coins.",
	busy = "Finish the game you're making first.",
	no_project = "Make a game first.",
	not_built = "Play all three minigames first.",
	full = "The plot is full.",
	max = "That's maxed out.",
	locked = "You don't own that yet.",
	cooldown = "Not yet: try again in a moment.",
	blocked = "It doesn't fit there.",
	rate = "Slow down a little.",
	not_ready = "One moment: your studio is still opening.",
}

function Words.errText(err: string?): string
	return if err then ERRORS[err] or "That didn't work. Try again." else "That didn't work. Try again."
end

return Words
