--!strict
-- The camera (docs/ARCHITECTURE.md 9.2; Random Bakery's view and its walk): orthographic, yaw 45°, pitch 30°, the 2:1
-- pixel-art grid. Its zoom is fixed: a box round the island's heart (FRAME, the same on every tier) is fitted on screen
-- as big as the grid allows, clear of the HUD's blocks (the "home" view). The view's grid (Raster.Grid: `a` art px per
-- ground stud, its phase, the ray plane `l`) depends only on the plot, the screen and K; on it the view pans by whole
-- art px (`pan()`), so the pixel renderer scrolls its picture instead of baking it again:
--   follow (the default): the view keeps the founder (the player's character) in the middle of the screen between
--     the HUD's strips, wherever they walk, gliding a share of the way a frame (Tuning.CamGlide) in whole art px (at
--     most what the renderer can scroll in a frame);
--   free (Build mode): the view stays where Build mode drags it (`panBy`), over the own plot;
--   stage (`setStage`): the view frames a stage far from the street over the whole screen, clear of an overlay's
--     top and bottom strips; it holds still (nothing opens one since the expeditions went).
-- The ray plane sits Tuning.CamRayBack studs behind the plot's origin, so the whole street stays in front of it. In
-- the classic style the Roblox camera shows the same view (CamOffFov), with the pixel filter on it sits far away at
-- CamFov (looks orthographic).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local StateClient = require(script.Parent.StateClient)

export type Room = { x0: number, x1: number, z0: number, z1: number, y1: number }
-- A microgame's stage: its origin on the ground (the ray plane's anchor), the points its picture must show (x, y, z
-- triples), the overlay's strips (art px) and a name for the view's key.
-- (`tight`: a smaller frame for a short screen, a phone held sideways: the band the action is in, drawn bigger)
export type Stage = { name: string, origin: Vector3, pts: { number }, tight: { number }?, top: number, bottom: number }
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
	room: Room, -- an inside lit as indoors (none any more: kept for the renderer)
	box: Raster.Rect, -- the framing box on screen at the home pan (full-screen px)
	stage: boolean, -- a microgame's stage (setStage), not the street
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
local focus: Vector3? = nil -- a cutscene's point to follow instead of the founder (setFocus)
local stage: Stage? = nil
local stageShift = Vector3.zero -- an endless islet's camera: how far along the stage looks (setStageShift)

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

-- The box the zoom is fitted to (plot-local, round the island's heart): about the old hut and its yard.
local FRAME = { x0 = -12, z0 = -6, x1 = 14, z1 = 18, y1 = 6 }

local function framePts(ox: number, oz: number): { number }
	local f = Street.CENTER
	local pts = {}
	for _, x in { FRAME.x0, FRAME.x1 } do
		for _, y in { Street.LAWN_Y, FRAME.y1 } do
			for _, z in { FRAME.z0, FRAME.z1 } do
				table.insert(pts, ox + f.x + x)
				table.insert(pts, y)
				table.insert(pts, oz + f.z + z - 6)
			end
		end
	end
	return pts
end

local function build(): View
	local size = screenSize()
	local fx, fy = size.X, size.Y
	local K = CameraController.pixelK(size)
	local ox, oz = Street.origin(plot)
	local pts = framePts(ox, oz)
	local bl = blocks(size, K)
	local st = stage
	if st then
		ox, oz = st.origin.X, st.origin.Z
		pts = if st.tight and fy < 600 then st.tight :: { number } else st.pts
		bl = {
			{ x0 = 0, y0 = 0, x1 = fx, y1 = st.top * K },
			{ x0 = 0, y0 = fy - st.bottom * K, x1 = fx, y1 = fy },
		}
	end
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
	local room = { x0 = 1, x1 = 0, z0 = 1, z1 = 0, y1 = 0 } -- everything is outdoors: no indoor tint
	return {
		rot12 = ROT12,
		center = Vector3.new(ccx, ccy, ccz),
		look = Vector3.new(LX, LY, LZ),
		viewH = fy / (K * q),
		grid = g,
		key = (if st then "stage:" .. st.name .. "|" else "") .. string.format("%d|%g|%.5f|%.5f|%.4f|%dx%d|%d", plot, a, phX, phY, l, fx, fy, K),
		fullX = fx,
		fullY = fy,
		K = K,
		tier = tier,
		plot = plot,
		room = room,
		box = { x0 = (bx0 - g.px) * K, y0 = (by0 - g.py) * K, x1 = (bx1 - g.px) * K, y1 = (by1 - g.py) * K },
		stage = st ~= nil,
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

local targetOf: (v: View) -> (number, number) -- (where the view should be: below)

function CameraController.refit()
	local v = build()
	local old = current
	current = v
	if old == nil or old.key ~= v.key or old.plot ~= v.plot then
		-- a new view starts where it should look (a cutscene's focus, the founder), never on the island's middle first
		-- and gliding over: the stage closing on the way home must not swing the view across the land to the boat
		panX, panY = v.grid.px, v.grid.py
		freeX, freeY = panX, panY
		panX, panY = targetOf(v)
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
-- island a moment later: until it has stood on its own lot once, or SPAWN_SETTLE seconds have passed, the view
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

-- The HUD's strips across the top and the bottom of the screen (art px): the follow keeps the founder clear of them.
local function hudStrips(v: View): (number, number)
	local top, bottom = 0, 0
	local rects: { Raster.Rect } = hudRects or {}
	for _, r in rects do
		if r.x1 - r.x0 >= v.fullX * 0.3 then
			if r.y0 <= 1 then
				top = math.max(top, r.y1)
			elseif r.y1 >= v.fullY - 1 then
				bottom = math.max(bottom, v.fullY - r.y0)
			end
		end
	end
	-- (the tips banner stands just above the bottom strip)
	return top / v.K, bottom / v.K + 20
end

-- Where the view should be this frame.
local function target(v: View): (number, number)
	if v.stage then
		local st = stage
		if st == nil or stageShift == Vector3.zero then
			return v.grid.px, v.grid.py
		end
		-- along the stage: the same framing that much further on (the renderer scrolls there, never re-bakes)
		local o = st.origin
		local gx0, gy0 = Raster.gridPoint(ROT12, v.grid, o.X, o.Y, o.Z)
		local p = o + stageShift
		local gx1, gy1 = Raster.gridPoint(ROT12, v.grid, p.X, p.Y, p.Z)
		return v.grid.px + math.floor(gx1 - gx0 + 0.5), v.grid.py + math.floor(gy1 - gy0 + 0.5)
	end
	if free then
		return freeX, freeY
	end
	local p: Vector3
	if focus then
		p = focus :: Vector3
	else
		local root = founderRoot(v)
		if root == nil then
			return v.grid.px, v.grid.py
		end
		p = root.Position
	end
	-- the founder (or a cutscene's focus) in the middle of the screen between the HUD's strips (the ground under
	-- them: their feet)
	local gx, gy = Raster.gridPoint(ROT12, v.grid, p.X, Street.LAWN_Y + 1.5, p.Z)
	local W, H = v.fullX / v.K, v.fullY / v.K
	local top, bottom = hudStrips(v)
	local tx = gx - W / 2
	local ty = gy - (top + (H - bottom + 20)) / 2
	return math.floor(tx + 0.5), math.floor(ty + 0.5)
end

targetOf = target

-- The most the view moves a frame: what the renderer can scroll in one (its strips within Tuning.PixelPanRays rays,
-- about 1.5 rays a pixel with the sun's), so its picture never falls behind into a re-bake.
local function panCaps(v: View): (number, number)
	local W, H = v.fullX / v.K, v.fullY / v.K
	return math.max(1, math.floor(Tuning.PixelPanRays / (H * 1.5))), math.max(1, math.floor(Tuning.PixelPanRays / (W * 1.5)))
end

local function step()
	local v = current
	if v == nil then
		return
	end
	local tx, ty = target(v)
	-- a far jump (home from the other end of the street) snaps: the renderer bakes once at the new pan (on a stage the
	-- view always glides: an endless islet's next area is a scroll away)
	local W, H = v.fullX / v.K, v.fullY / v.K
	if not v.stage and (math.abs(tx - panX) > W * 0.75 or math.abs(ty - panY) > H * 0.75) then
		panX, panY = tx, ty
		pose(v)
		return
	end
	local capX, capY = panCaps(v)
	local function toward(cur: number, to: number, cap: number): number
		local d = to - cur
		if d == 0 then
			return cur
		end
		local move = math.min(cap, math.max(1, math.ceil(math.abs(d) * Tuning.CamGlide)))
		return cur + math.sign(d) * math.min(move, math.abs(d))
	end
	local nx, ny = toward(panX, tx, capX), toward(panY, ty, capY)
	if nx ~= panX or ny ~= panY then
		panX, panY = nx, ny
		pose(v)
	end
end

-- Build mode: the view stays where it is dragged (true) or follows the founder again (false). It starts where the
-- view is (the founder in the middle), lowered by `down` art px (Build mode's tray covers the bottom of the screen).
-- A cutscene's point to keep in the middle instead of the founder (nil: the founder again); the view glides to it
-- like a walk (UI/Voyage: the founder boarding, the boat sailing off), or is put there at once (`snap`: behind closed
-- blinds, so the picture they open on is already the right one).
function CameraController.setFocus(p: Vector3?, snap: boolean?)
	focus = p
	local v = current
	if snap and v and not v.stage then
		local tx, ty = target(v)
		if tx ~= panX or ty ~= panY then
			panX, panY = tx, ty
			pose(v)
		end
	end
end

-- Whether the view is where it should be (a cutscene waits for it before opening its blinds).
function CameraController.settled(): boolean
	local v = current
	if v == nil then
		return true
	end
	local tx, ty = target(v)
	return tx == panX and ty == panY
end

function CameraController.setFree(on: boolean, down: number?)
	free = on
	freeX, freeY = panX, panY
	if on then
		freeY = panY + math.floor((down or 0) / 2)
	end
end

-- A microgame's stage takes the view (nil: back to the street; the renderer keeps the street's picture meanwhile).
function CameraController.setStage(s: Stage?)
	stage = s
	stageShift = Vector3.zero
	CameraController.refit()
end

-- A stage's framing moved by `shift` (world studs); the view glides there a frame at a
-- time (the renderer scrolls), or is put there at once (`snap`: behind the curtain, before the
-- first picture).
function CameraController.setStageShift(shift: Vector3, snap: boolean?)
	stageShift = shift
	local v = current
	if snap and v and v.stage then
		local tx, ty = target(v)
		if tx ~= panX or ty ~= panY then
			panX, panY = tx, ty
			pose(v)
		end
	end
end

function CameraController.stage(): Stage?
	return stage
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
	local ox, oz = Street.origin(v.plot)
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
		if cv.plot ~= plot or cv.tier ~= tier then
			plot, tier = cv.plot, cv.tier
			CameraController.refit()
			-- the next tier's cells, worked out at a quiet moment (not the frame the island grows)
			local t = cv.tier
			task.delay(3, function()
				Street.warm(t + 1)
			end)
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
