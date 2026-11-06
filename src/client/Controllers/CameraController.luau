--!strict
-- The camera (docs/ARCHITECTURE.md 9.2; Random Bakery's whole-shop view): orthographic, yaw 45°, pitch 30°, the
-- 2:1 pixel-art grid. The player's whole office is fitted on screen, as big as the grid allows, clear of the HUD's
-- blocks and centred, and held still. The view is on a world-anchored art grid (Raster.Grid): a ground stud is `a`
-- art px, every 1/80-stud lattice edge stays off the pixel centres (Raster.gridPhase), so the office's edges step
-- exactly two pixels across for one down. The pixel renderer draws the view; in the classic style the Roblox
-- camera shows it (CamOffFov), with the pixel filter on it sits far away at CamFov (looks orthographic).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local StateClient = require(script.Parent.StateClient)

export type Room = { x0: number, x1: number, z0: number, z1: number, y1: number }
export type View = {
	rot12: { number },
	center: Vector3,
	look: Vector3,
	viewH: number,
	grid: Raster.Grid,
	key: string,
	fullX: number,
	fullY: number,
	K: number,
	tier: number,
	plot: number,
	room: Room, -- the office's inside in world studs (the renderer lights it as indoors)
	box: Raster.Rect, -- the office's outline box on screen (full-screen px)
}

local CameraController = {}
CameraController.ViewChanged = Util.Signal() :: Types.Signal<View>

local ROT12 = Raster.rotation(Tuning.CamYaw, Tuning.CamPitch)
local SQRT2 = math.sqrt(2)

local current: View? = nil
local hudRects: { Raster.Rect }? = nil
local pixelLimit = Tuning.PixelTiers.high.h -- the renderer's tier: the most art px across the short side
local classic = false
local plot, tier = 1, 1

local function screenSize(): Vector2
	local cam = Workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	return Vector2.new(math.max(320, v.X), math.max(240, v.Y))
end

-- The K the view uses: the game's one pixel size (Random Bakery's rule, coarsened by the renderer's tier).
function CameraController.pixelK(size: Vector2?): number
	local s = size or screenSize()
	return Raster.pixelScale(s.X, s.Y, Tuning.PixelScaleMin, Tuning.PixelScaleSides, pixelLimit, 1024)
end

-- The HUD's blocks (full-screen px) until the HUD reports its own: a strip at the top and one at the bottom.
local function blocks(size: Vector2, K: number): { Raster.Rect }
	if hudRects then
		return hudRects
	end
	return {
		{ x0 = 0, y0 = 0, x1 = size.X, y1 = Tuning.CamHudTop * K + 36 },
		{ x0 = 0, y0 = size.Y - Tuning.CamHudBottom * K, x1 = size.X, y1 = size.Y },
	}
end

local function build(): View
	local size = screenSize()
	local fx, fy = size.X, size.Y
	local K = CameraController.pixelK(size)
	local ox, oz = Office.origin(plot)
	local pts = Office.outlinePts(tier, ox, oz)
	local bl = blocks(size, K)
	local pad = Tuning.CamPad * K
	local cx, cy, cz, viewH = Raster.fit(ROT12, fx, fy, bl, pad, pts)
	local aFit = (fy / viewH) / (K * SQRT2)
	-- the largest clean grid scale that fits, placed where the outline's box centre is clear and nearest the middle
	local a = Raster.gridScale(aFit, 1, false)
	local sx, sy = fx / 2, fy / 2
	local cand = a
	while cand >= 1 do
		local x, y = Raster.place(ROT12, fx, fy, bl, pad, pts, cand * K * SQRT2)
		if x ~= nil and y ~= nil then
			a, sx, sy = cand, x, y
			break
		end
		cand = Raster.gridScale(cand - 0.25, 1, false)
	end
	local q = a * SQRT2
	local phX, phY = Raster.gridPhase(a)
	local lx, ly, lz = -ROT12[6], -ROT12[9], -ROT12[12]
	local l = cx * lx + cy * ly + cz * lz
	local g: Raster.Grid = { a = a, q = q, phX = phX, phY = phY, l = l, px = 0, py = 0 }
	local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
	for i = 1, #pts, 3 do
		local gx, gy = Raster.gridPoint(ROT12, g, pts[i], pts[i + 1], pts[i + 2])
		bx0, by0, bx1, by1 = math.min(bx0, gx), math.min(by0, gy), math.max(bx1, gx), math.max(by1, gy)
	end
	g.px = math.floor((bx0 + bx1) / 2 - sx / K + 0.5)
	g.py = math.floor((by0 + by1) / 2 - sy / K + 0.5)
	local ccx, ccy, ccz = Raster.gridCenter(ROT12, g, fx, fy, K)
	local plan = Office.plan(tier)
	return {
		rot12 = ROT12,
		center = Vector3.new(ccx, ccy, ccz),
		look = Vector3.new(lx, ly, lz),
		viewH = fy / (K * q),
		grid = g,
		key = string.format("%d|%d|%g|%d|%d|%dx%d|%d", plot, tier, a, g.px, g.py, fx, fy, K),
		fullX = fx,
		fullY = fy,
		K = K,
		tier = tier,
		plot = plot,
		room = { x0 = ox + plan.minX - 0.1, x1 = ox + plan.maxX + 0.1, z0 = oz + plan.minZ - 0.1, z1 = oz + plan.maxZ + 0.1, y1 = plan.wallH + 0.1 },
		box = { x0 = (bx0 - g.px) * K, y0 = (by0 - g.py) * K, x1 = (bx1 - g.px) * K, y1 = (by1 - g.py) * K },
	}
end

-- Poses the Roblox camera on the view: far along the look direction at CamFov with the filter on, near at
-- CamOffFov in the classic style.
local function pose(v: View)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local fov = if classic then Tuning.CamOffFov else Tuning.CamFov
	local dist = v.viewH / (2 * math.tan(math.rad(fov) / 2))
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(v.center - v.look * dist, v.center)
end

function CameraController.refit()
	local v = build()
	local old = current
	current = v
	pose(v)
	if old == nil or old.key ~= v.key then
		CameraController.ViewChanged:Fire(v)
	end
end

function CameraController.view(): View
	if current == nil then
		CameraController.refit()
	end
	return current :: View
end

-- The HUD's blocks in full-screen px (the office is fitted clear of them); nil = the default strips.
function CameraController.setHudRects(rects: { Raster.Rect }?)
	hudRects = rects
	CameraController.refit()
end

-- The renderer's tier limit (Tuning.PixelTiers[t].h) and whether the classic style shows the Roblox camera.
function CameraController.setPixelLimit(h: number, isClassic: boolean)
	pixelLimit = h
	classic = isClassic
	CameraController.refit()
end

function CameraController.init() end

function CameraController.start()
	local function fromView(v: Types.ClientView)
		if v.plot ~= plot or v.office ~= tier then
			plot, tier = v.plot, v.office
			CameraController.refit()
		end
	end
	StateClient.Changed:Connect(fromView)
	local v = StateClient.view()
	if v then
		fromView(v)
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			CameraController.refit()
		end)
	end
	-- Roblox moves a Scriptable camera back now and then (a respawn, a reset): keep it posed
	task.spawn(function()
		while true do
			task.wait(1)
			if current then
				pose(current)
			end
		end
	end)
	CameraController.refit()
end

return CameraController
