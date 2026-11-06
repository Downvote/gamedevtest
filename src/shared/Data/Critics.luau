--!strict
-- The four critics (GAME_DESIGN 6.3). Pure. Each leans toward one score (Types.Axis). Order = Release.reviews order.
export type CriticDef = { name: string, outlet: string, axis: string }

local LIST: { CriticDef } = {
	{ name = "Pixel Pete", outlet = "Pixel Weekly", axis = "fun" },
	{ name = "Ada Quill", outlet = "The Idea Post", axis = "ideas" },
	{ name = "Max Render", outlet = "Render Mag", axis = "graphics" },
	{ name = "Echo Lane", outlet = "Tune In", axis = "sound" },
}

return table.freeze({ list = LIST })
