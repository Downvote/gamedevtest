--!strict
-- The modifiers an idea can come with (GAME_DESIGN 4). Pure. Rolled on their own after the idea: odds (1 in N; Plain
-- takes the rest), mult (the idea's income times this), the play effects its microgame gets (UI/MicroUI: "speed"
-- faster on a shorter clock, "tiny" small targets, "shake" the screen shakes, "glitch" it blinks out, "dark" only a
-- roving spotlight shows it) and a UIKit colour key for its tag.
export type ModDef = { id: string, name: string, odds: number, mult: number, effects: { string }, color: string, blurb: string }

-- stylua: ignore start
local LIST: { ModDef } = {
	{ id = "plain", name = "Plain", odds = 1, mult = 1, effects = {}, color = "text_dim", blurb = "Nothing special." },
	{ id = "turbo", name = "Turbo", odds = 5, mult = 1.2, effects = { "speed" }, color = "orange", blurb = "Faster, on a shorter clock." },
	{ id = "tiny", name = "Tiny", odds = 12, mult = 1.4, effects = { "tiny" }, color = "green", blurb = "Everything is tiny." },
	{ id = "shaky", name = "Shaky", odds = 30, mult = 1.7, effects = { "shake" }, color = "yellow", blurb = "The screen shakes." },
	{ id = "glitched", name = "Glitched", odds = 80, mult = 2.2, effects = { "glitch" }, color = "screen_code", blurb = "It blinks out." },
	{ id = "haunted", name = "Haunted", odds = 250, mult = 3, effects = { "dark" }, color = "purple", blurb = "Only a spotlight shows it." },
	{ id = "cosmic", name = "Cosmic", odds = 1000, mult = 5, effects = { "speed", "shake", "glitch" }, color = "fun", blurb = "Fast, shaky and glitched." },
}
-- stylua: ignore end

local BY_ID: { [string]: ModDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
