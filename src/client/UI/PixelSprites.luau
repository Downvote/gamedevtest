--!strict
-- Tiny pixel-art sprites for the interface (docs/ARCHITECTURE.md 10.8): the ideas' icons, the microgames' things,
-- drawn as rows of characters, one UI px (times `scale`) each, from runs of UIKit rects. A sprite's `colors` maps its
-- characters to UIKit colour keys; "." is clear.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PixelFont = require(ReplicatedStorage.Shared.Render.PixelFont)
local UIKit = require(script.Parent.UIKit)

export type Sprite = { rows: { string }, colors: { [string]: string } }

local PixelSprites = {}

local function S(rows: { string }, colors: { [string]: string }): Sprite
	return { rows = rows, colors = colors }
end
PixelSprites.S = S

-- the four arrow keys (Code Rush)
local ARROW_UP = { "...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###.." }
local function rotate(rows: { string }): { string }
	-- a quarter turn clockwise
	local h, w = #rows, #rows[1]
	local out = {}
	for x = 1, w do
		local line = {}
		for y = h, 1, -1 do
			table.insert(line, string.sub(rows[y], x, x))
		end
		table.insert(out, table.concat(line))
	end
	return out
end
local ARROW_RIGHT = rotate(ARROW_UP)
local ARROW_DOWN = rotate(ARROW_RIGHT)
local ARROW_LEFT = rotate(ARROW_DOWN)

PixelSprites.ARROWS = {
	up = ARROW_UP,
	right = ARROW_RIGHT,
	down = ARROW_DOWN,
	left = ARROW_LEFT,
} :: { [string]: { string } }

-- The ideas' icons (8x8, Data/Ideas ids): the board's cards, the Index, the microgames' intros.
PixelSprites.ICONS = {
	action = S({ "....##..", "...#y#..", "..#yy#..", ".#yyyy#.", ".###yy#.", "...#y#..", "..#y#...", "..##...." }, { ["#"] = "ink", y = "yellow" }),
	puzzle = S({ "..##....", ".#bb#...", ".#bb###.", "#bbbbbb#", "#bbbbb#.", ".#bbbbb#", ".#bbbb#.", "..####.." }, { ["#"] = "ink", b = "graphics" }),
	animals = S({ "#......#", "##....##", "#o####o#", "#oooooo#", "#o#oo#o#", "#oooooo#", ".#oppo#.", "..####.." }, { ["#"] = "ink", o = "orange", p = "pink" }),
	space = S({ "...##...", "..#ww#..", "..#wb#..", "..#ww#..", ".#wwww#.", "#r#ww#r#", "#r#rr#r#", "...##..." }, { ["#"] = "ink", w = "white", b = "screen_on", r = "berry_red" }),
	cooking = S({ "........", ".####...", "#yyyy#..", "#yoyy#..", "#yyyy###", ".####.##", "........", "........" }, { ["#"] = "ink", y = "yellow", o = "orange" }),
	school = S({ "....#l..", "...#l...", ".##.##..", "#rrrrr#.", "#rrrwr#.", "#rrrrr#.", ".#rrr#..", "..###..." }, { ["#"] = "ink", l = "leaf", r = "berry_red", w = "white" }),
	adventure = S({ "..####..", ".#gggg#.", "#gg#ggg#", "#g#r#gg#", "#gg#ggg#", "#ggg#gg#", ".#gggg#.", "..####.." }, { ["#"] = "ink", g = "gold", r = "berry_red" }),
	racing = S({ "........", "..####..", ".#rwwr#.", "#rrrrrr#", "#rrrrrr#", "########", ".##..##.", "........" }, { ["#"] = "ink", r = "berry_red", w = "window" }),
	sports = S({ "..####..", ".#ww#w#.", "#w##www#", "#ww#ww##", "##ww#ww#", "#www##w#", ".#w#ww#.", "..####.." }, { ["#"] = "ink", w = "white" }),
	pirates = S({ ".######.", "#wwwwww#", "#w##w##w", "#wwwwwww", ".#ww#ww#", "..#wwww#", "..#w#w#.", "...###.." }, { ["#"] = "ink", w = "cream" }),
	farming = S({ "...#l#l.", "....#l#.", "...##...", "..#oo#..", "..#oo#..", ".#oo#...", ".#o#....", "..#....." }, { ["#"] = "ink", l = "leaf", o = "orange" }),
	ocean = S({ "........", ".####..#", "#bbbb##b", "bwbbbbbb", "bbbbbbbb", "#bbbb##b", ".####..#", "........" }, { ["#"] = "ink", b = "blue", w = "white" }),
	rpg = S({ "......##", ".....#s#", "....#s#.", "...#s#..", "#.#s#...", ".#g#....", ".#g#....", "#..#...." }, { ["#"] = "ink", s = "steel", g = "gold" }),
	fantasy = S({ "....#...", "...#p#..", "...#y#..", "..#ppp#.", "..#ppp#.", ".#ppppp#", "#pppppp#", "########" }, { ["#"] = "ink", p = "purple", y = "yellow" }),
	rhythm = S({ "#......#", ".#....#.", "..####..", ".#rrrr#.", "#wwwwww#", "#rrrrrr#", "#rrrrrr#", ".######." }, { ["#"] = "ink", r = "berry_red", w = "white" }),
	robots = S({ "...#....", "..#r#...", ".######.", "#ssssss#", "#sb##bs#", "#ssssss#", "#s####s#", ".######." }, { ["#"] = "ink", s = "steel", b = "screen_on", r = "berry_red" }),
	ninjas = S({ "...#....", "..#k#...", "###k####", "#kkskkk#", "####k###", "...#k#..", "....#...", "........" }, { ["#"] = "ink", k = "black", s = "steel" }),
	zombies = S({ ".######.", "#gggggg#", "#g#gg#g#", "#gggggg#", "#gg##gg#", "#g#gg#g#", ".#gggg#.", "..####.." }, { ["#"] = "ink", g = "green" }),
	strategy = S({ "#.#..#.#", "########", "#ssssss#", "#ss##ss#", "#ssssss#", "#ss##ss#", "#ss##ss#", "########" }, { ["#"] = "ink", s = "steel" }),
	horror = S({ "..####..", ".#wwww#.", "#w#ww#w#", "#wwwwww#", "#ww##ww#", "#wwwwww#", "#w#ww#w#", ".#.##.#." }, { ["#"] = "ink", w = "white" }),
	dinosaurs = S({ ".#####..", "#gggg#g#", "#gwggggg", "#gggg###", "#ggg#...", "#gggg#..", ".#gg#...", ".####..." }, { ["#"] = "ink", g = "leaf", w = "white" }),
	detectives = S({ "..####..", ".#bbbb#.", "#bwbbbb#", "#bbbbbb#", ".#bbbb#.", "..####..", "....#w#.", ".....##." }, { ["#"] = "ink", b = "window", w = "wood" }),
	simulation = S({ "....###.", "....#b#.", ".###bb#.", ".#bbbb#.", "##bwbbw#", "#bbbbbb#", "#bwbbwb#", "########" }, { ["#"] = "ink", b = "blue", w = "window" }),
	music = S({ "...####.", "...#pp#.", "...#..#.", "...#..#.", ".###.##.", "#pp##pp#", "#pp##pp#", ".##..##." }, { ["#"] = "ink", p = "pink" }),
} :: { [string]: Sprite }

-- Bug Squash's bug and its splat (8x7)
PixelSprites.BUG = S({ "#..##..#", ".#.##.#.", "..####..", "#gggggg#", ".#gggg#.", "#.gggg.#", "..#..#.." }, { ["#"] = "ink", g = "green" })
PixelSprites.SPLAT = S({ "g..g...g", ".g.gg.g.", "..gggg..", "ggggggg.", ".gggggg.", "g.g..g.g", "........" }, { g = "leaf" })

-- Beat Keeper's note (6x6)
PixelSprites.NOTE = S({ ".####.", "#nnnn#", "#nwnn#", "#nnnn#", "#nnnn#", ".####." }, { ["#"] = "ink", n = "sound", w = "white" })

-- A letter of the pixel font as sprite rows ("#" ink), for a letter drawn big (the minigames' grade).
function PixelSprites.glyphRows(ch: string, big: boolean?): { string }
	local g = PixelFont.glyph(if big then PixelFont.BIG else PixelFont.SMALL, ch)
	local out = {}
	for _, bits in g.rows do
		local line = table.create(g.w, ".")
		for x = 0, g.w - 1 do
			if (bits // 2 ^ x) % 2 == 1 then
				line[x + 1] = "#"
			end
		end
		table.insert(out, table.concat(line))
	end
	if #out == 0 then
		table.insert(out, ".")
	end
	return out
end

-- A sprite's size in its own px.
function PixelSprites.size(rows: { string }): (number, number)
	return #rows[1], #rows
end

-- Draw `rows` (one colour per character from `colors`, "." clear) into a new frame at `pos`, `scale` UI px per
-- sprite px.
function PixelSprites.draw(parent: Instance?, rows: { string }, colors: { [string]: string }, pos: UDim2?, scale: number?, z: number?): Frame
	local k = math.max(1, math.floor(scale or 1))
	local w, h = PixelSprites.size(rows)
	local f = Instance.new("Frame")
	f.Name = "Sprite"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(w * k, h * k)
	f.Position = pos or UDim2.new()
	f.ZIndex = z or 3
	for y, row in rows do
		local x = 1
		while x <= w do
			local ch = string.sub(row, x, x)
			local run = 1
			while x + run <= w and string.sub(row, x + run, x + run) == ch do
				run += 1
			end
			local key = colors[ch]
			if ch ~= "." and key then
				local r = UIKit.rect(f, UDim2.fromOffset(run * k, k), UDim2.fromOffset((x - 1) * k, (y - 1) * k), UIKit.color(key), z or 3)
				r.Name = "Px"
			end
			x += run
		end
	end
	f.Parent = parent
	return f
end

-- A sprite record drawn (PixelSprites.draw with its own colours).
function PixelSprites.sprite(parent: Instance?, s: Sprite, pos: UDim2?, scale: number?, z: number?): Frame
	return PixelSprites.draw(parent, s.rows, s.colors, pos, scale, z)
end

-- Recolour every pixel of a drawn single-colour sprite (an arrow lighting up).
function PixelSprites.tint(f: Instance, c: Color3)
	for _, r in f:GetChildren() do
		if r:IsA("Frame") and r.Name == "Px" then
			r.BackgroundColor3 = c
		end
	end
end

return PixelSprites
