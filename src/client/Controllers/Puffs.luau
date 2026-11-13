--!strict
-- Little bursts of pixels over the world (GAME_DESIGN 4: "add effects and polish when putting down decor and other
-- amenities"): dust, leaves, chips of stone, drops of water, embers, snow, confetti, twinkles and puffs of cloud, drawn
-- on the World canvas at whole UI px ("particles are 1 px") where the pixel layer shows their world point. Each
-- particle moves in world studs (a speed, gravity), so it rises, arcs and falls with the view. Cheap: Frames and a few
-- sprites, no parts, at most MOST at once; nothing while the pixel filter is off.
local RunService = game:GetService("RunService")

local Blocks = require(game:GetService("ReplicatedStorage").Shared.Models.Blocks)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)

local Puffs = {}

type P = { at: Vector3, vel: Vector3, grav: number, born: number, life: number, gui: GuiObject, frames: { GuiObject }?, sway: number }

-- A kind: its colours (palette keys), how fast it leaves (studs a second: up, out), its gravity, how long it lasts,
-- and whether it sways side to side (a leaf, a flake) or is a sprite (frames).
type Kind = { colors: { string }, up: { number }, out: { number }, grav: number, life: { number }, sway: number?, frames: { string }? }
local KINDS: { [string]: Kind } = {
	dust = { colors = { "sand", "sand_dark", "pavement" }, up = { 0.6, 1.4 }, out = { 1.0, 2.2 }, grav = 4, life = { 0.35, 0.6 } },
	chips = { colors = { "rock", "rock_dark", "pavement" }, up = { 2.0, 3.4 }, out = { 0.8, 1.8 }, grav = 12, life = { 0.4, 0.6 } },
	wood = { colors = { "wood", "wood_dark", "sand" }, up = { 1.8, 3.0 }, out = { 0.8, 1.8 }, grav = 11, life = { 0.4, 0.6 } },
	leaf = { colors = { "leaf", "leaf_dark", "green" }, up = { 1.0, 2.0 }, out = { 0.6, 1.4 }, grav = 1.2, life = { 0.8, 1.3 }, sway = 1 },
	petal = { colors = { "pink", "cherry", "yellow", "white" }, up = { 1.0, 2.0 }, out = { 0.6, 1.4 }, grav = 1.2, life = { 0.8, 1.3 }, sway = 1 },
	drop = { colors = { "shallow", "water", "foam" }, up = { 2.2, 3.6 }, out = { 0.6, 1.5 }, grav = 13, life = { 0.35, 0.55 } },
	ember = { colors = { "orange", "yellow", "lava" }, up = { 1.4, 2.6 }, out = { 0.2, 0.7 }, grav = -0.5, life = { 0.6, 1.0 }, sway = 0.6 },
	snow = { colors = { "snow", "white", "ice" }, up = { 0.6, 1.4 }, out = { 0.5, 1.2 }, grav = 1.0, life = { 0.9, 1.4 }, sway = 1 },
	confetti = { colors = { "pink", "yellow", "blue", "green", "orange" }, up = { 2.0, 3.2 }, out = { 0.6, 1.6 }, grav = 4, life = { 0.7, 1.1 }, sway = 0.8 },
	magic = { colors = { "crystal", "purple", "white", "screen_on" }, up = { 0.8, 1.6 }, out = { 0.2, 0.8 }, grav = -0.8, life = { 0.7, 1.1 }, sway = 0.5 },
	glint = { colors = { "white", "yellow" }, up = { 0.4, 1.0 }, out = { 0.1, 0.4 }, grav = 0, life = { 0.3, 0.5 } },
	twinkle = { colors = {}, up = { 0.2, 0.6 }, out = { 0, 0.3 }, grav = 0, life = { 0.5, 0.7 }, frames = { "spark_1", "spark_2", "spark_3" } },
	star = { colors = {}, up = { 0.1, 0.4 }, out = { 0, 0.2 }, grav = 0, life = { 0.45, 0.6 }, frames = { "twinkle_1", "twinkle_2", "twinkle_1" } },
	poof = { colors = {}, up = { 0.3, 0.7 }, out = { 0.2, 0.6 }, grav = 0, life = { 0.4, 0.55 }, frames = { "poof_1", "poof_2", "poof_3" } },
}

local list: { P } = {}
local MOST = 260
local conn: RBXScriptConnection? = nil

local function rand(r: { number }): number
	return r[1] + math.random() * (r[2] - r[1])
end

local function step()
	local t = os.clock()
	local keep: { P } = {}
	for _, p in list do
		local age = t - p.born
		if age >= p.life then
			p.gui:Destroy()
			continue
		end
		local w = p.at + p.vel * age - Vector3.new(0, 0.5 * p.grav * age * age, 0)
		if p.sway ~= 0 then
			w += Vector3.new(math.sin(age * 7 + p.born * 3) * 0.15 * p.sway, 0, 0)
		end
		local px, py, on = PixelRenderer.projectPixel(w)
		local g = p.gui
		local frames = p.frames
		if frames then
			local k = math.clamp(math.floor(age / p.life * #frames) + 1, 1, #frames)
			for i, f in frames do
				f.Visible = i == k
			end
			g.Position = UDim2.fromOffset(math.floor(px) - math.floor(g.Size.X.Offset / 2), math.floor(py) - math.floor(g.Size.Y.Offset / 2))
		else
			g.Position = UDim2.fromOffset(math.floor(px), math.floor(py))
		end
		g.Visible = on
		table.insert(keep, p)
	end
	list = keep
	if #list == 0 then
		local c = conn
		if c then
			c:Disconnect()
			conn = nil
		end
	end
end

-- A burst of `n` particles of `kind` at a world point (spread over `radius` studs round it, flat).
function Puffs.burst(kind: string, at: Vector3, n: number, radius: number?)
	local k = KINDS[kind]
	if k == nil or not PixelRenderer.isActive() then
		return
	end
	local canvas = UIKit.canvas("World")
	local t = os.clock()
	for _ = 1, n do
		if #list >= MOST then
			break
		end
		local a = math.random() * math.pi * 2
		local r = (radius or 0) * math.sqrt(math.random())
		local start = at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local out = rand(k.out)
		local vel = Vector3.new(math.cos(a) * out, rand(k.up), math.sin(a) * out)
		local gui: GuiObject
		local frames: { GuiObject }? = nil
		if k.frames then
			local holder = Instance.new("Frame")
			holder.Name = "Puff"
			holder.BackgroundTransparency = 1
			local w, h = PixelSprites.size(k.frames[1])
			holder.Size = UDim2.fromOffset(w, h)
			holder.ZIndex = 4
			local fs: { GuiObject } = {}
			for i, nm in k.frames do
				local im = PixelSprites.image(holder, nm, UDim2.fromOffset(0, 0), 4)
				im.Visible = i == 1
				fs[i] = im
			end
			holder.Parent = canvas
			gui, frames = holder, fs
		else
			local f = UIKit.rect(canvas, UDim2.fromOffset(1, 1), nil, Blocks.color(k.colors[math.random(1, #k.colors)]), 4)
			f.Name = "Puff"
			gui = f
		end
		gui.Visible = false
		table.insert(list, { at = start, vel = vel, grav = k.grav, born = t, life = rand(k.life), gui = gui, frames = frames, sway = k.sway or 0 })
	end
	if conn == nil and #list > 0 then
		conn = RunService.Heartbeat:Connect(step)
	end
end

-- Text that floats up from a world point and goes (a "+3 charm" over a piece just put down): whole UI px.
function Puffs.float(text: string, at: Vector3, color: Color3, icon: string?)
	if not PixelRenderer.isActive() then
		return
	end
	local canvas = UIKit.canvas("World")
	local w = UIKit.textWidth(text) + (if icon then 12 else 0)
	local holder = Instance.new("Frame")
	holder.Name = "Float"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(w, 10)
	holder.ZIndex = 5
	if icon then
		PixelSprites.image(holder, icon, UDim2.fromOffset(0, 0), 5)
	end
	UIKit.text(holder, text, UDim2.fromOffset(w, 10), UDim2.fromOffset(if icon then 12 else 0, 0), { color = color, z = 5, name = "Words" })
	holder.Parent = canvas
	local t0 = os.clock()
	local c: RBXScriptConnection? = nil
	c = RunService.Heartbeat:Connect(function()
		local age = os.clock() - t0
		if age > 1.1 or holder.Parent == nil then
			holder:Destroy()
			local cc = c
			if cc then
				cc:Disconnect()
			end
			return
		end
		local px, py, on = PixelRenderer.projectPixel(at)
		-- (up 14 px over the first 0.6 s, then it holds; it blinks out at the end)
		local rise = math.floor(14 * math.min(1, age / 0.6))
		holder.Position = UDim2.fromOffset(math.floor(px) - math.floor(w / 2), math.floor(py) - 10 - rise)
		holder.Visible = on and not (age > 0.9 and math.floor(age * 20) % 2 == 0)
	end)
end

-- How many are flying now (sims and previews).
function Puffs.count(): number
	return #list
end

return Puffs
