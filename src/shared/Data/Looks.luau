--!strict
-- What a developer can look like (Types.Look indexes these). Pure. Palette keys.
local SKIN: { string } = { "skin1", "skin2", "skin3", "skin4" }
local HAIR: { string } = { "hair_brown", "hair_black", "hair_blond", "hair_red", "hair_blue" }
-- hair styles (Models/CharacterModels draws them): short, long, bun, spiky
local STYLES: { string } = { "short", "long", "bun", "spiky" }
local SHIRT: { string } = { "blue", "green", "orange", "purple", "pink", "berry_red", "yellow", "white" }

return table.freeze({ skin = SKIN, hair = HAIR, styles = STYLES, shirt = SHIRT })
