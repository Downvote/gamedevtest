--!strict
-- The name tags over the founders (GAME_DESIGN 14.1; docs/ARCHITECTURE.md 10.6). The request (2026-11-14): "make the
-- player be outlined white like the bakery game, with the name and title on top". Every founder, the player's own too,
-- has a tag over its head: the player's display name and, under it, the title they wear (the "Title" Player attribute,
-- a Data/Titles id; "" or an unknown id: no title line) in that title's colour. Drawn in the pixel font on the "World"
-- canvas (hidden with it during the hatch scene), placed at whole UI px over the rig's head every frame by AvatarView.
-- API
--   NameTags.make(pl) -> Tag           a tag for a player (the canvas holds it)
--   NameTags.refresh(tag, pl)          re-read the name and the title (cheap when nothing changed)
--   NameTags.place(tag, top)           put it over a world point (the top of the head); hidden when off the view
--   NameTags.drop(tag)
--   NameTags.texts(tag) -> (name, title, visible)   CLI checks only
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Titles = require(ReplicatedStorage.Shared.Data.Titles)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local NameTags = {}

export type Tag = { frame: Frame, name: TextLabel, title: TextLabel, key: string }

local LINE = 10 -- UI px a line

-- The title a player wears: its words and colour key, or nil.
local function titleOf(pl: Player): (string?, string?)
	local id = pl:GetAttribute("Title")
	local t = if type(id) == "string" and id ~= "" then Titles.byId[id] else nil
	if t == nil then
		return nil, nil
	end
	return t.name, t.color
end

local function layout(tag: Tag, name: string, title: string?, color: string?)
	local wName = UIKit.textWidth(name) + 4
	local wTitle = if title then UIKit.textWidth(title) + 4 else 0
	local w = math.max(wName, wTitle)
	local h = if title then LINE * 2 else LINE
	tag.frame.Size = UDim2.fromOffset(w, h)
	UIKit.setText(tag.name, name)
	tag.name.Size = UDim2.fromOffset(w, LINE)
	tag.name.Position = UDim2.fromOffset(0, 0)
	tag.title.Visible = title ~= nil
	if title then
		UIKit.setText(tag.title, title)
		UIKit.setTextColor(tag.title, UIKit.color(color or "text"))
		tag.title.Size = UDim2.fromOffset(w, LINE)
		tag.title.Position = UDim2.fromOffset(0, LINE)
	end
end

function NameTags.make(pl: Player): Tag
	local frame = Instance.new("Frame")
	frame.Name = "NameTag_" .. pl.UserId
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(10, LINE)
	frame.Parent = UIKit.canvas("World")
	local name = UIKit.text(frame, pl.DisplayName, UDim2.fromOffset(10, LINE), nil, { x = "center", kind = "outline", name = "Name", color = UIKit.color("white") })
	local title = UIKit.text(frame, "", UDim2.fromOffset(10, LINE), UDim2.fromOffset(0, LINE), { x = "center", kind = "outline", name = "Title" })
	local tag: Tag = { frame = frame, name = name, title = title, key = "" }
	NameTags.refresh(tag, pl)
	return tag
end

function NameTags.refresh(tag: Tag, pl: Player)
	local title, color = titleOf(pl)
	local key = pl.DisplayName .. "|" .. (title or "") .. "|" .. (color or "")
	if key ~= tag.key then
		tag.key = key
		layout(tag, pl.DisplayName, title, color)
	end
end

-- Over world point `top` (the top of the founder's head): the tag's bottom a couple of px above it, centred, at
-- whole UI px.
function NameTags.place(tag: Tag, top: Vector3)
	local i, j, on = PixelRenderer.projectPixel(top)
	tag.frame.Visible = on
	if on then
		local s = tag.frame.Size
		tag.frame.Position = UDim2.fromOffset(i - math.floor(s.X.Offset / 2), j - s.Y.Offset - 2)
	end
end

function NameTags.drop(tag: Tag)
	tag.frame:Destroy()
end

function NameTags.texts(tag: Tag): (string, string?, boolean)
	return tag.name.Text, if tag.title.Visible then tag.title.Text else nil, tag.frame.Visible
end

return NameTags
