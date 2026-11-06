--!strict
-- ImageMemory: one way to make an EditableImage for every part of the client that draws into one (the world,
-- Pixel/PixelText's text atlas, Pixel/Snapshot's pictures, the Recipe Desk, the contest scene). OWNER: WP8.
--
-- A device has a fixed budget of image memory; past it AssetService:CreateEditableImage fails. That happens in a long
-- session, when pictures and words pile up. So no one fails while another holds images nobody is showing: a part that
-- keeps such spares registers a reclaimer, and when a create fails the others' reclaimers free what they can spare,
-- one after another, until the image fits. Only then does the create fail (and the caller falls back for now: the
-- text atlas shows the label's own text and tries again a little later, a picture asks again when shown).
--
-- API
--   ImageMemory.create(w, h, who?) -> EditableImage?   who: the caller's reclaimer name (its own spares are not asked)
--   ImageMemory.onLow(name, reclaim)   reclaim(): number frees images nobody shows and says how many bytes (or
--       pictures) it freed (0: nothing to spare)
local AssetService = game:GetService("AssetService")

local ImageMemory = {}

local reclaimers: { { name: string, fn: () -> number } } = {}

local function try(w: number, h: number): EditableImage?
	local ok, img = pcall(AssetService.CreateEditableImage, AssetService, { Size = Vector2.new(w, h) })
	if ok and img ~= nil then
		return img
	end
	return nil
end

function ImageMemory.create(w: number, h: number, who: string?): EditableImage?
	local img = try(w, h)
	if img ~= nil then
		return img
	end
	for _, r in reclaimers do
		if r.name ~= who then
			local ok, freed = pcall(r.fn)
			if ok and type(freed) == "number" and freed > 0 then
				img = try(w, h)
				if img ~= nil then
					return img
				end
			end
		end
	end
	return nil
end

function ImageMemory.onLow(name: string, reclaim: () -> number)
	for _, r in reclaimers do
		if r.name == name then
			r.fn = reclaim
			return
		end
	end
	table.insert(reclaimers, { name = name, fn = reclaim })
end

return ImageMemory
