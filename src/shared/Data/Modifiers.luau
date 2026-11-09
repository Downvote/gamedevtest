--!strict
-- The modifiers an idea can come with (GAME_DESIGN 4). Pure. Rolled on their own after the idea: odds (1 in N; Plain
-- takes the rest), mult (the idea's income times this), the play effects its minigame gets (UI/MicroUI, UI/MicroGames:
-- "speed" faster on a shorter clock, "ice" a slippery floor, "rival" two more rivals and sharper ones, "more" more of
-- everything (hazards, coins, bombs), "shrink" the arena closes in) and a UIKit colour key for its tag. Each makes the
-- minigame harder in a way to play round, never one that only gets in the way (no shaking or blinking screen, no tiny
-- targets).
export type ModDef = { id: string, name: string, odds: number, mult: number, effects: { string }, color: string, blurb: string }

-- Saved ideas with a modifier from before (GAME_DESIGN 4: the annoying ones went): each became the one with its odds.
local RENAMED: { [string]: string } = { tiny = "icy", shaky = "crowded", glitched = "frenzy", haunted = "shrinking" }

-- stylua: ignore start
local LIST: { ModDef } = {
	{ id = "plain", name = "Plain", odds = 1, mult = 1, effects = {}, color = "text_dim", blurb = "Nothing special." },
	{ id = "turbo", name = "Turbo", odds = 5, mult = 1.2, effects = { "speed" }, color = "orange", blurb = "Faster, on a shorter clock." },
	{ id = "icy", name = "Icy", odds = 12, mult = 1.4, effects = { "ice" }, color = "screen_on", blurb = "A slippery floor: everyone slides." },
	{ id = "crowded", name = "Crowded", odds = 30, mult = 1.7, effects = { "rival" }, color = "yellow", blurb = "Two more rivals, and sharper ones." },
	{ id = "frenzy", name = "Frenzy", odds = 80, mult = 2.2, effects = { "more" }, color = "berry_red", blurb = "More of everything." },
	{ id = "shrinking", name = "Shrinking", odds = 250, mult = 3, effects = { "shrink" }, color = "purple", blurb = "The arena closes in." },
	{ id = "cosmic", name = "Cosmic", odds = 1000, mult = 5, effects = { "speed", "more", "shrink" }, color = "fun", blurb = "Fast, frantic and closing in." },
}
-- stylua: ignore end

local BY_ID: { [string]: ModDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID, renamed = RENAMED })
