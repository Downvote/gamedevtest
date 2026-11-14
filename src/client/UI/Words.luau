--!strict
-- What the interface says when the server refuses something (docs/ARCHITECTURE.md 10.4): every Types.ErrCode in
-- plain words.
local Words = {}

local ERRORS: { [string]: string } = {
	money = "Not enough shells.",
	no_hut = "Build a hut first. Driftlings need somewhere to live.",
	huts = "Your huts already hold as many driftlings as this island allows. Grow the island for more room.",
	hatcheries = "This island has all the Hatcheries it can hold. Grow it for another.",
	busy = "Not right now.",
	full = "Every hut is full. Swap one out, or build another hut.",
	max = "That's as far as it goes.",
	locked = "Not open yet.",
	cooldown = "Not yet. Try again in a moment.",
	blocked = "That can't be done here.",
	no_room = "There's no room for that.",
	not_found = "That egg is gone. The tree laid new ones.",
	fixed = "The Tree of Life stays on your island. You can move it.",
	egg = "An egg is still warming in that Hatchery.",
	not_done = "That quest isn't done yet.",
	rate = "Slow down a little.",
	not_ready = "One moment, your island is still waking up.",
}

function Words.errText(err: string?): string
	return if err then ERRORS[err] or "That didn't work. Try again." else "That didn't work. Try again."
end

return Words
