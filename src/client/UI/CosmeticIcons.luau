--!strict
-- A cosmetic's picture for the Store, the Looks panel and the reward cards (GAME_DESIGN 14; Data/Cosmetics). For now
-- each slot's own mini icon; Models/CharacterModels' pieces drawn small replace it (the 24 x 24 thumbnails, drawn from
-- each piece's model like the build catalog's: tools/preview/thumbs).
--   CosmeticIcons.image(parent, id, pos?, z?) -> GuiObject   the piece's picture (a slot icon for an unknown id)
--   CosmeticIcons.size(id) -> (w, h)                          its size in UI px
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local PixelSprites = require(script.Parent.PixelSprites)

local CosmeticIcons = {}

local SLOT_ICON: { [string]: string } = {
	hat = "mini_visitor",
	face = "mini_search",
	neck = "mini_charm",
	back = "mini_boat",
	hand = "mini_star",
	top = "mini_folk",
}

local function spriteOf(id: string): string
	local c = Cosmetics.byId[id]
	return SLOT_ICON[if c then c.slot else "hand"] or "mini_star"
end

function CosmeticIcons.image(parent: Instance?, id: string, pos: UDim2?, z: number?): GuiObject
	return PixelSprites.image(parent, spriteOf(id), pos, z)
end

function CosmeticIcons.size(id: string): (number, number)
	return PixelSprites.size(spriteOf(id))
end

return CosmeticIcons
