--!strict
-- A cosmetic's picture for the Store, the Looks panel and the reward cards (GAME_DESIGN 14.1; Data/Cosmetics): its
-- 24 x 24 thumbnail, "look_<id>" in UI/CosmeticThumbData, drawn from the piece's own model the way the build catalog's
-- are (sh tools/preview/cosmetic_thumbs.sh; a top on a little body), a 1 px ink outline and tidied to the pixel art
-- rules. A piece with no picture yet shows its slot's mini icon.
--   CosmeticIcons.image(parent, id, pos?, z?) -> GuiObject   the piece's picture (a slot icon for an unknown id)
--   CosmeticIcons.size(id) -> (w, h)                          its size in UI px (24 x 24 for a picture)
--   CosmeticIcons.has(id) -> boolean                          whether the piece has its own picture
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
	local pic = "look_" .. id
	if PixelSprites.has(pic) then
		return pic
	end
	local c = Cosmetics.byId[id]
	return SLOT_ICON[if c then c.slot else "hand"] or "mini_star"
end

function CosmeticIcons.image(parent: Instance?, id: string, pos: UDim2?, z: number?): GuiObject
	return PixelSprites.image(parent, spriteOf(id), pos, z)
end

function CosmeticIcons.size(id: string): (number, number)
	return PixelSprites.size(spriteOf(id))
end

function CosmeticIcons.has(id: string): boolean
	return PixelSprites.has("look_" .. id)
end

return CosmeticIcons
