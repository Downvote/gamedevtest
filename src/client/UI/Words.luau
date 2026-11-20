--!strict
-- What the interface says when the server refuses something (docs/ARCHITECTURE.md 10.4): every Types.ErrCode in
-- plain words.
local Words = {}

local ERRORS: { [string]: string } = {
	money = "Not enough coins.",
	no_hut = "Build a hut first.",
	huts = "No more hut room. Grow the island.",
	work = "No more work spots. Grow the island.",
	hatcheries = "No room for another Hatchery. Grow the island.",
	boosts = "Two of each boost building is the most.",
	busy = "Not right now.",
	full = "Huts full. Swap one out or build a hut.",
	max = "Already maxed.",
	locked = "Not open yet.",
	dup = "You saved that one already.",
	cooldown = "Not yet. Try again soon.",
	blocked = "Can't do that here.",
	no_room = "No room for that.",
	not_found = "That egg is gone.",
	fixed = "The tree stays. You can move it.",
	egg = "An egg is still warming there.",
	not_done = "Not done yet.",
	rate = "Slow down a little.",
	not_ready = "One moment, still loading.",
}

function Words.errText(err: string?): string
	return if err then ERRORS[err] or "That didn't work. Try again." else "That didn't work. Try again."
end

return Words
