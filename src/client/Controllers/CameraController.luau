--!strict
-- The camera (docs/ARCHITECTURE.md 9.2; Random Bakery's whole-shop view and its walk): orthographic, yaw 45°, pitch 30°,
-- the 2:1 pixel-art grid. The player's office is fitted on screen as big as the grid allows, clear of the HUD's blocks
-- (the "home" view). The view's grid (Raster.Grid: `a` art px per ground stud, its phase, the ray plane `l`) depends
-- only on the plot, the office's tier, the screen and K; on it the view pans by whole art px (`pan()`), so the pixel
-- renderer scrolls its picture instead of baking it again:
--   follow (the default): while the founder (the player's character) is home (on their own lot and inside the home
--     view's middle) the view holds the home pan; out on the street it keeps them out of the screen's edges
--     (Tuning.CamFollowBox), gliding a share of the way a frame (Tuning.CamGlide) in whole art px;
--   free (Build mode): the view stays where Build mode drags it (`panBy`), over the own plot.
-- The ray plane sits Tuning.CamRayBack studs behind the plot's origin, so the whole street stays in front of it. In
-- the classic style the Roblox camera shows the same view (CamOffFov), with the pixel filter on it sits far away at
-- CamFov (looks orthographic).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local StateClient = require(script.Parent.StateClient)

export type Room = { x0: number, x1: number, z0: number, z1: number, y1: number }
export type View = {
	rot12: { number },
	center: Vector3, -- the home view's centre on the ground
	look: Vector3,
	viewH: number,
	grid: Raster.Grid, -- px, py: the HOME pan (the pan now: CameraController.pan())
	key: string, -- the grid's identity (a new key = a new bake)
	fullX: number,
	fullY: number,
	K: number,
	tier: number,
	plot: number,
	room: Room, -- the own office's inside in world studs (lit as indoors)
	box: Raster.Rect, -- the own office's outline box on screen at the home pan (full-screen px)
}

local CameraController = {}
CameraController.ViewChanged = Util.Signal() :: Types.Signal<View>

local ROT12 = Raster.rotation(Tuning.CamYaw, Tuning.CamPitch)
local SQRT2 = math.sqrt(2)
local LX, LY, LZ = -ROT12[6], -ROT12[9], -ROT12[12]

local current: View? = nil
local hudRects: { Raster.Rect }? = nil
local pixelLimit = Tuning.PixelTiers.high.h
local classic = false
local plot, tier = 1, 1
local panX, panY = 0, 0 -- the pan now (whole art px)
local free = false -- Build mode: the view stays where it is dragged
local freeX, freeY = 0, 0

local function screenSize(): Vector2
	local cam = Workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	return Vector2.new(math.max(320, v.X), math.max(240, v.Y))
end

function CameraController.pixelK(size: Vector2?): number
	local s = size or screenSize()
	return Raster.pixelScale(s.X, s.Y, Tuning.PixelScaleMin, Tuning.PixelScaleSides, pixelLimit, 1024)
end

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
	local _, _, _, viewH = Raster.fit(ROT12, fx, fy, bl, pad, pts)
	local aFit = (fy / viewH) / (K * SQRT2)
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
	-- the ray plane: CamRayBack behind the plot's origin on the ground (fixed per plot: the HUD moving the home view
	-- only pans the picture)
	local l = ox * LX + 0 * LY + oz * LZ
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
		look = Vector3.new(LX, LY, LZ),
		viewH = fy / (K * q),
		grid = g,
		key = string.format("%d|%d|%g|%.5f|%.5f|%.4f|%dx%d|%d", plot, tier, a, phX, phY, l, fx, fy, K),
		fullX = fx,
		fullY = fy,
		K = K,
		tier = tier,
		plot = plot,
		room = { x0 = ox + plan.minX - 0.1, x1 = ox + plan.maxX + 0.1, z0 = oz + plan.minZ - 0.1, z1 = oz + plan.maxZ + 0.1, y1 = plan.wallH + 0.1 },
		box = { x0 = (bx0 - g.px) * K, y0 = (by0 - g.py) * K, x1 = (bx1 - g.px) * K, y1 = (by1 - g.py) * K },
	}
end

-- The grid at a pan (a copy of the view's).
function CameraController.gridAt(px: number, py: number): Raster.Grid
	local g = CameraController.view().grid
	return { a = g.a, q = g.q, phX = g.phX, phY = g.phY, l = g.l, px = px, py = py }
end

-- The view's centre on the ground at the pan now (world studs).
function CameraController.centerWorld(): Vector3
	local v = CameraController.view()
	local cx, cy, cz = Raster.gridCenter(ROT12, CameraController.gridAt(panX, panY), v.fullX, v.fullY, v.K)
	if math.abs(LY) > 1e-6 then
		local t = (0 - cy) / LY
		cx, cy, cz = cx + LX * t, cy + LY * t, cz + LZ * t
	end
	return Vector3.new(cx, cy, cz)
end

-- Poses the Roblox camera on the view at the pan now.
local function pose(v: View)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local fov = if classic then Tuning.CamOffFov else Tuning.CamFov
	local dist = v.viewH / (2 * math.tan(math.rad(fov) / 2))
	local c = CameraController.centerWorld()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(c - v.look * dist, c)
end

function CameraController.refit()
	local v = build()
	local old = current
	current = v
	if old == nil or old.key ~= v.key or old.plot ~= v.plot then
		panX, panY = v.grid.px, v.grid.py
		freeX, freeY = panX, panY
		CameraController.ViewChanged:Fire(v)
	end
	pose(v)
end

function CameraController.view(): View
	if current == nil then
		CameraController.refit()
	end
	return current :: View
end

-- The pan now: the global art pixel of the screen's top-left pixel.
function CameraController.pan(): (number, number)
	return panX, panY
end

function CameraController.setHudRects(rects: { Raster.Rect }?)
	hudRects = rects
	CameraController.refit()
end

function CameraController.setPixelLimit(h: number, isClassic: boolean)
	pixelLimit = h
	classic = isClassic
	CameraController.refit()
end

------------------------------------------------------------------ follow and free pan
-- A new character appears where Roblox drops it (the world's origin, mid-street) and the server moves it to its own
-- footpath a moment later: until it has stood on its own lot once, or SPAWN_SETTLE seconds have passed, the view
-- ignores it (it never chases a character down the street and back, which would bake the picture twice).
local SPAWN_SETTLE = 3
local seenChar: Model? = nil
local seenAt = 0
local settledChar: Model? = nil

local function founderRoot(v: View): BasePart?
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if char == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	if char ~= settledChar then
		if char ~= seenChar then
			seenChar, seenAt = char, os.clock()
		end
		if Street.plotAt(root.Position.X, root.Position.Z) == v.plot or os.clock() - seenAt > SPAWN_SETTLE then
			settledChar = char
		else
			return nil
		end
	end
	return root
end

-- Where the view should be this frame.
local function target(v: View): (number, number)
	if free then
		return freeX, freeY
	end
	local root = founderRoot(v)
	if root == nil then
		return v.grid.px, v.grid.py
	end
	local p = root.Position
	local gx, gy = Raster.gridPoint(ROT12, v.grid, p.X, p.Y, p.Z)
	local W, H = v.fullX / v.K, v.fullY / v.K
	local mx, my = W * Tuning.CamFollowBox, H * Tuning.CamFollowBox
	local hx, hy = v.grid.px, v.grid.py
	-- home: on the own lot and in the home view's middle
	local own = Street.plotAt(p.X, p.Z) == v.plot
	if own and gx - hx >= mx and gx - hx <= W - mx and gy - hy >= my and gy - hy <= H - my then
		return hx, hy
	end
	-- out: the least move that keeps them inside the box
	local tx = math.clamp(panX, gx - (W - mx), gx - mx)
	local ty = math.clamp(panY, gy - (H - my), gy - my)
	return math.floor(tx + 0.5), math.floor(ty + 0.5)
end

local function step()
	local v = current
	if v == nil then
		return
	end
	local tx, ty = target(v)
	-- a far jump (home from the other end of the street) snaps: the renderer bakes once at the new pan
	local W, H = v.fullX / v.K, v.fullY / v.K
	if math.abs(tx - panX) > W * 0.75 or math.abs(ty - panY) > H * 0.75 then
		panX, panY = tx, ty
		pose(v)
		return
	end
	local function toward(cur: number, to: number): number
		local d = to - cur
		if d == 0 then
			return cur
		end
		local move = math.max(1, math.ceil(math.abs(d) * Tuning.CamGlide))
		return cur + math.sign(d) * math.min(move, math.abs(d))
	end
	local nx, ny = toward(panX, tx), toward(panY, ty)
	if nx ~= panX or ny ~= panY then
		panX, panY = nx, ny
		pose(v)
	end
end

-- Build mode: the view stays where it is dragged (true) or follows the founder again (false).
function CameraController.setFree(on: boolean)
	free = on
	freeX, freeY = panX, panY
	if on then
		-- start from home: the own plot in view
		local v = CameraController.view()
		freeX, freeY = v.grid.px, v.grid.py
	end
end

function CameraController.isFree(): boolean
	return free
end

-- Build mode's drag: the world follows the pointer by (dx, dy) full-screen px, the view's centre kept over the own
-- plot (Tuning.CamBuildPan studs past its edges at most).
function CameraController.panBy(dx: number, dy: number)
	local v = CameraController.view()
	local nx = freeX - math.floor(dx / v.K + 0.5)
	local ny = freeY - math.floor(dy / v.K + 0.5)
	-- clamp: the centre's ground point inside the plot grown by CamBuildPan
	local ox, oz = Office.origin(v.plot)
	local pr = Street.plot(v.tier)
	local m = Tuning.CamBuildPan
	local corners = { { pr.x0 - m, pr.z0 - m }, { pr.x1 + m, pr.z0 - m }, { pr.x0 - m, pr.z1 + m }, { pr.x1 + m, pr.z1 + m } }
	local gx0, gy0, gx1, gy1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in corners do
		local gx, gy = Raster.gridPoint(ROT12, v.grid, ox + c[1], Street.LAWN_Y, oz + c[2])
		gx0, gy0, gx1, gy1 = math.min(gx0, gx), math.min(gy0, gy), math.max(gx1, gx), math.max(gy1, gy)
	end
	local W, H = v.fullX / v.K, v.fullY / v.K
	freeX = math.clamp(nx, math.floor(gx0 - W / 2), math.ceil(gx1 - W / 2))
	freeY = math.clamp(ny, math.floor(gy0 - H / 2), math.ceil(gy1 - H / 2))
end

function CameraController.init() end

function CameraController.start()
	local function fromView(cv: Types.ClientView)
		if cv.plot ~= plot or cv.office ~= tier then
			plot, tier = cv.plot, cv.office
			CameraController.refit()
		end
	end
	StateClient.Changed:Connect(fromView)
	local cv = StateClient.view()
	if cv then
		fromView(cv)
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			CameraController.refit()
		end)
		-- Roblox moves the camera back on a respawn: keep it ours
		cam:GetPropertyChangedSignal("CameraType"):Connect(function()
			if current and cam.CameraType ~= Enum.CameraType.Scriptable then
				pose(current)
			end
		end)
	end
	RunService.RenderStepped:Connect(step)
	CameraController.refit()
end

return CameraController
