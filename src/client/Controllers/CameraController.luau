--!strict
-- The camera (docs/ARCHITECTURE.md 9.2; Random Bakery's view and its walk): orthographic, yaw 45°, pitch 30°, the 2:1
-- pixel-art grid. Its zoom on the islands is the Settings panel's View slider: one of ten notches, art px a stud
-- (Tuning.CamZoomNotches; `setZoom`), the same on every screen and tier; a box round the island's heart (FRAME times
-- Tuning.CamFrame) only says where the view starts, clear of the HUD's blocks (the "home" view). The view's grid (Raster.Grid: `a` art px per
-- ground stud, its phase, the ray plane `l`) depends only on the plot, the screen and K; on it the view pans by whole
-- art px (`pan()`), so the pixel renderer scrolls its picture instead of baking it again:
--   follow (the default): the view keeps the founder (the player's character) in the middle of the screen between
--     the HUD's strips, wherever they walk, on a soft spring (Tuning.CamFollowSecs): it eases off when they set out,
--     trails them a little while they walk and eases in to stop on them once they stand (the request of 2026-11-18:
--     "make the camera a smooth lerp follow the player like most top down games instead of sharply cutting to the
--     player"); the pan is in whole art px (at most what the renderer can scroll in a frame);
--   free (Build mode): the view still follows the founder, lowered a little (Build mode's tray covers the bottom of
--     the screen), plus where Build mode drags it (`panBy`, kept over the own plot); a drag holds while the founder
--     stands, and once they walk the view eases back onto them (the request of 2026-11-14: "in build mode, make the
--     camera still follow the player as they walk around, even though it is displaced downwards abit");
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
local DisplayScale = require(script.Parent.Parent.Pixel.DisplayScale)
local ScreenSize = require(script.Parent.Parent.Pixel.ScreenSize)

export type Room = { x0: number, x1: number, z0: number, z1: number, y1: number }
-- A microgame's stage: its origin on the ground (the ray plane's anchor), the points its picture must show (x, y, z
-- triples), the overlay's strips (art px) and a name for the view's key.
-- (`tight`: a smaller frame for a short screen, a phone held sideways: the band the action is in, drawn bigger)
-- (`clear`: the sky left see-through, so a picture behind the pixel layer shows round the stage: the hatch scene's)
export type Stage = { name: string, origin: Vector3, pts: { number }, tight: { number }?, top: number, bottom: number, clear: boolean?, empty: boolean? }
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
	clear: boolean, -- the sky see-through: the islands' (a painted sky behind, UI/SkyBackdrop) or a stage's (Stage.clear)
	empty: boolean, -- a see-through stage with nothing static on it (Stage.empty): the renderer shows it at once, no bake
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
local camX, camY = 0, 0 -- the follow's own place (art px, not rounded): the pan is worked out from it every frame
local velX, velY = 0, 0 -- how fast it moves (art px a second)
local free = false -- Build mode: the view follows the founder lowered by `buildDown`, plus a drag
local buildDown = 0 -- art px the view is lowered by in Build mode
local dragX, dragY = 0, 0 -- art px Build mode's drag has moved the view from the founder
local lastBaseX: number?, lastBaseY: number? = nil, nil -- the founder's follow target last frame (Build mode: did they walk?)
local focus: Vector3? = nil -- a cutscene's point to follow instead of the founder (setFocus)
local zoom = Tuning.CamZoomDefault -- the View slider's notch (setZoom)
local savedZoom: number? = nil -- the notch the profile last said (a change there is applied; a tap waiting on it is not undone)
local stage: Stage? = nil
local stageShift = Vector3.zero -- an endless islet's camera: how far along the stage looks (setStageShift)
-- The founder on the screen (the report of 2026-11-21, "the camera now stutters the player as they walk"): where the
-- follow puts the founder's ground point this frame (`fGX, fGY`, global art px, nil when it follows something else),
-- where that lands on the screen (`lockX, lockY`, whole art px from its top-left), and where AvatarView last put the
-- founder's rig, snapped to the art grid (`drawnAt`, setDrawn). The pixel layer's window is placed from the rig as
-- drawn (drawnPan), so the founder stands exactly where the follow wants it whatever order the frame's steps run in.
local fGX: number?, fGY: number? = nil, nil
local lockX: number?, lockY: number? = nil, nil
local drawnAt: Vector3? = nil
local lockOff = false -- (previews: the window put from the pan alone, debugLock)
local DRAWN_SLACK = 8 -- art px the rig as drawn may be from the follow before the pan is shown as it is

-- (the whole screen, a notched phone's safe-area margins too: Camera.ViewportSize left them out there, and the
-- pixel layer drawn from the screen's left edge stopped short of the right one: Pixel/ScreenSize)
local function screenSize(): Vector2
	local v = ScreenSize.full()
	return Vector2.new(math.max(320, v.X), math.max(240, v.Y))
end

-- (nudged to a whole number of the screen's own pixels on a display scaled by a fraction: Pixel/DisplayScale)
function CameraController.pixelK(size: Vector2?): number
	local s = size or screenSize()
	return DisplayScale.fit(Raster.pixelScale(s.X, s.Y, Tuning.PixelScaleMin, Tuning.PixelScaleSides, pixelLimit, 1024))
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

-- The box's corners, shrunk about its middle by Tuning.CamFrame (the request of 2026-11-14: "zoom into the island more
-- such that there isnt too much sea in the screen": a smaller box is fitted bigger, so the view is closer).
local function framePts(ox: number, oz: number, phone: boolean?): { number }
	local f = Street.CENTER
	local k = if phone then Tuning.CamFramePhone else Tuning.CamFrame
	local mx, mz = (FRAME.x0 + FRAME.x1) / 2, (FRAME.z0 + FRAME.z1) / 2
	local pts = {}
	for _, x in { FRAME.x0, FRAME.x1 } do
		for _, y in { Street.LAWN_Y, Street.LAWN_Y + (FRAME.y1 - Street.LAWN_Y) * k } do
			for _, z in { FRAME.z0, FRAME.z1 } do
				table.insert(pts, ox + f.x + mx + (x - mx) * k)
				table.insert(pts, y)
				table.insert(pts, oz + f.z + mz + (z - mz) * k - 6)
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
	-- (a phone: the screen's short side 500 px or less, UIKit.phone's rule, gets its own box: Tuning.CamFramePhone)
	local pts = framePts(ox, oz, math.min(fx, fy) <= 500)
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
	local a: number
	local sx, sy = fx / 2, fy / 2
	if st == nil then
		-- The islands: the same detail on every screen, the View slider's notch in art px a stud however big it is
		-- (the request of 2026-11-18: "make it such that the pixel filter is, by default, on all devices, zoomed in to
		-- be at a good level of detail. make it such that smaller windows or smaller devices will still receive the
		-- same amount of detail as bigger ones"). The view was fitted to the frame box, so a phone's 195 art px drew
		-- the island at about 6 a stud where a desktop drew it at 11. A smaller screen now shows less of the island,
		-- the founder in the middle of it. Then the slider (the same day: "make a view slider for zooming the camera
		-- in and out, with 10 notches"): 5 a stud far out to 16 close in, 12 by default.
		a = Raster.gridScale(Tuning.CamZoomNotches[zoom] or Tuning.CamZoomNotches[Tuning.CamZoomDefault], 1, false)
		local x, y = Raster.place(ROT12, fx, fy, bl, pad, pts, a * K * SQRT2)
		if x ~= nil and y ~= nil then
			sx, sy = x, y
		end
	else
		-- a stage (the hatch scene) fits its own box, as big as the screen allows
		local _, _, _, viewH = Raster.fit(ROT12, fx, fy, bl, pad, pts)
		local aFit = (fy / viewH) / (K * SQRT2)
		a = Raster.gridScale(aFit, 1, false)
		local cand = a
		while cand >= 1 do
			local x, y = Raster.place(ROT12, fx, fy, bl, pad, pts, cand * K * SQRT2)
			if x ~= nil and y ~= nil then
				a, sx, sy = cand, x, y
				break
			end
			cand = Raster.gridScale(cand - 0.25, 1, false)
		end
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
		key = (if st then "stage:" .. st.name .. "|" else "") .. string.format("%d|%g|%.5f|%.5f|%.4f|%dx%d|%g", plot, a, phX, phY, l, fx, fy, K),
		fullX = fx,
		fullY = fy,
		K = K,
		tier = tier,
		plot = plot,
		room = room,
		box = { x0 = (bx0 - g.px) * K, y0 = (by0 - g.py) * K, x1 = (bx1 - g.px) * K, y1 = (by1 - g.py) * K },
		stage = st ~= nil,
		-- (the islands' sky is see-through too: UI/SkyBackdrop's painted sky shows round them, since 2026-11-20)
		clear = st == nil or st.clear == true,
		empty = st ~= nil and st.clear == true and st.empty == true,
	}
end

-- The grid at a pan (a copy of the view's).
function CameraController.gridAt(px: number, py: number): Raster.Grid
	local g = CameraController.view().grid
	return { a = g.a, q = g.q, phX = g.phX, phY = g.phY, l = g.l, px = px, py = py }
end

-- The view's centre on the ground at pan (px, py) (world studs).
local function centerAt(px: number, py: number): Vector3
	local v = CameraController.view()
	local cx, cy, cz = Raster.gridCenter(ROT12, CameraController.gridAt(px, py), v.fullX, v.fullY, v.K)
	if math.abs(LY) > 1e-6 then
		local t = (0 - cy) / LY
		cx, cy, cz = cx + LX * t, cy + LY * t, cz + LZ * t
	end
	return Vector3.new(cx, cy, cz)
end

-- The view's centre on the ground at the pan now (world studs).
function CameraController.centerWorld(): Vector3
	return centerAt(panX, panY)
end

-- Poses the Roblox camera on the view at the pan now. (In the classic style, with no pixel filter to keep to its grid,
-- it stands on the follow's own place, so the 3D view slides without the art pixel steps.)
local function pose(v: View)
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local fov = if classic then Tuning.CamOffFov else Tuning.CamFov
	local dist = v.viewH / (2 * math.tan(math.rad(fov) / 2))
	local c = if classic and not v.stage then centerAt(camX, camY) else centerAt(panX, panY)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(c - v.look * dist, c)
end

local targetOf: (v: View) -> (number, number) -- (where the view should be: below)

-- The view put on (tx, ty) at once, standing still there.
local function jumpTo(tx: number, ty: number)
	camX, camY, velX, velY = tx, ty, 0, 0
	panX, panY = math.floor(tx + 0.5), math.floor(ty + 0.5)
end

function CameraController.refit()
	local v = build()
	local old = current
	current = v
	if old == nil or old.key ~= v.key or old.plot ~= v.plot then
		-- a new view starts where it should look (a cutscene's focus, the founder), never on the island's middle first
		-- and gliding over: the stage closing on the way home must not swing the view across the land to the boat
		jumpTo(v.grid.px, v.grid.py)
		jumpTo(targetOf(v))
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

-- World point p moved across the ground (x and z) so that its ground point at the follow's height lands on a whole art
-- px of the view's grid: AvatarView puts the founder's rig there, so its picture steps a whole pixel exactly when the
-- follow's does (a rig between pixels drew a pixel off now and then and back the next frame). p as it is with no view.
function CameraController.snapGround(p: Vector3): Vector3
	local v = current
	if v == nil or v.stage then
		return p
	end
	local y = Street.LAWN_Y + 1.5
	local g = v.grid
	local x0, y0 = Raster.gridPoint(ROT12, g, p.X, y, p.Z)
	local x1, y1 = Raster.gridPoint(ROT12, g, p.X + 1, y, p.Z)
	local x2, y2 = Raster.gridPoint(ROT12, g, p.X, y, p.Z + 1)
	-- (the grid is linear in x and z: solve for the step that rounds both)
	local a, b, c, d = x1 - x0, x2 - x0, y1 - y0, y2 - y0
	local det = a * d - b * c
	if math.abs(det) < 1e-9 then
		return p
	end
	local rx, ry = math.floor(x0 + 0.5) - x0, math.floor(y0 + 0.5) - y0
	local dx, dz = (rx * d - b * ry) / det, (a * ry - c * rx) / det
	return Vector3.new(p.X + dx, p.Y, p.Z + dz)
end

-- Where AvatarView put the founder's rig (snapGround's point; nil: none).
function CameraController.setDrawn(p: Vector3?)
	drawnAt = p
end

-- The pan the pixel layer shows: the one that puts the founder's rig, as AvatarView last put it (what the renderer
-- draws this frame), where the follow wants the founder on the screen; `pan()` when the view follows something else.
function CameraController.drawnPan(): (number, number)
	local v, at = current, drawnAt
	local lx, ly = lockX, lockY
	if v == nil or v.stage or at == nil or lx == nil or ly == nil or lockOff then
		return panX, panY
	end
	local gx, gy = Raster.gridPoint(ROT12, v.grid, at.X, Street.LAWN_Y + 1.5, at.Z)
	local px, py = math.floor(gx + 0.5) - lx, math.floor(gy + 0.5) - ly
	if math.abs(px - panX) > DRAWN_SLACK or math.abs(py - panY) > DRAWN_SLACK then
		-- (the rig not where the follow is: a jump home, the view there a frame before the rig. The pan, so the picture
		-- is not sent back to where the rig was)
		return panX, panY
	end
	return px, py
end

-- Previews: false puts the layer's window from the pan alone (as before the founder was locked to it), true again.
function CameraController.debugLock(on: boolean)
	lockOff = not on
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

-- Build mode's view: a pan whose centre's ground point stays inside the own plot grown by Tuning.CamBuildPan.
local function clampBuild(v: View, nx: number, ny: number): (number, number)
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
	return math.clamp(nx, math.floor(gx0 - W / 2), math.ceil(gx1 - W / 2)), math.clamp(ny, math.floor(gy0 - H / 2), math.ceil(gy1 - H / 2))
end

-- Build mode: the founder's own follow target (no drag, not lowered), or nil when there is none to follow.
local function baseTarget(v: View): (number?, number?)
	if v.stage or focus ~= nil then
		return nil, nil
	end
	local root = founderRoot(v)
	if root == nil then
		return nil, nil
	end
	local p = root.Position
	local gx, gy = Raster.gridPoint(ROT12, v.grid, p.X, Street.LAWN_Y + 1.5, p.Z)
	local W, H = v.fullX / v.K, v.fullY / v.K
	local top, bottom = hudStrips(v)
	return math.floor(gx - W / 2 + 0.5), math.floor(gy - (top + (H - bottom + 20)) / 2 + 0.5)
end

-- Where the view should be this frame (art px; on the islands not rounded, so the follow moves as smoothly as the
-- founder does).
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
	local p: Vector3
	fGX, fGY = nil, nil
	if focus then
		p = focus :: Vector3
	else
		local root = founderRoot(v)
		if root == nil then
			if free then
				return camX, camY -- (Build mode with no founder to follow: the view stays)
			end
			return v.grid.px, v.grid.py
		end
		p = root.Position
	end
	-- the founder (or a cutscene's focus) in the middle of the screen between the HUD's strips (the ground under
	-- them: their feet)
	local gx, gy = Raster.gridPoint(ROT12, v.grid, p.X, Street.LAWN_Y + 1.5, p.Z)
	if focus == nil then
		fGX, fGY = gx, gy
	end
	local W, H = v.fullX / v.K, v.fullY / v.K
	local top, bottom = hudStrips(v)
	local tx = gx - W / 2
	local ty = gy - (top + (H - bottom + 20)) / 2
	if free then
		-- Build mode: lowered, plus the drag, the centre kept over the own plot
		return clampBuild(v, tx + dragX, ty + buildDown + dragY)
	end
	return tx, ty
end

targetOf = target

-- The most the view moves a frame: what the renderer can scroll in one (its strips within Tuning.PixelPanRays rays,
-- about 1.5 rays a pixel with the sun's), so its picture never falls behind into a re-bake.
local function panCaps(v: View): (number, number)
	local W, H = v.fullX / v.K, v.fullY / v.K
	return math.max(1, math.floor(Tuning.PixelPanRays / (H * 1.5))), math.max(1, math.floor(Tuning.PixelPanRays / (W * 1.5)))
end

-- One axis of the follow a frame: a critically damped spring (Unity's SmoothDamp), `Tuning.CamFollowSecs` its smooth
-- time. It sets off gently, trails a founder walking at a steady pace by their speed times that, and settles on them
-- once they stand without going past. Returns the new place and speed.
local function follow(cur: number, to: number, vel: number, dt: number): (number, number)
	local w = 2 / Tuning.CamFollowSecs
	local x = w * dt
	local e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local off = cur - to
	local t = (vel + w * off) * dt
	local nv = (vel - w * t) * e
	local out = to + (off + t) * e
	if (to - cur > 0) == (out > to) then
		out, nv = to, 0 -- (never past the target)
	end
	if math.abs(to - out) < 0.01 and math.abs(nv) < 0.5 then
		out, nv = to, 0
	end
	return out, nv
end

-- Where the founder lands on the screen this frame (the follow's own place less its ground point), or none.
local function lockOn()
	local gx, gy = fGX, fGY
	if gx and gy then
		lockX, lockY = math.floor(gx - camX + 0.5), math.floor(gy - camY + 0.5)
	else
		lockX, lockY = nil, nil
	end
end

local function step(dt: number?)
	local v = current
	if v == nil then
		return
	end
	if free then
		-- Build mode: a drag holds while the founder stands; once they walk it eases away, so the view comes back
		-- onto them (in whole art px, a share a frame)
		local bx, by = baseTarget(v)
		if bx and by then
			local lx, ly = lastBaseX, lastBaseY
			if lx and ly and (bx ~= lx or by ~= ly) then
				local function ease(d: number): number
					if d == 0 then
						return 0
					end
					local m = math.max(1, math.ceil(math.abs(d) * Tuning.CamBuildRecenter))
					return d - math.sign(d) * math.min(m, math.abs(d))
				end
				dragX, dragY = ease(dragX), ease(dragY)
			end
			lastBaseX, lastBaseY = bx, by
		end
	end
	local tx, ty = target(v)
	-- a far jump (home from the other end of the street) snaps: the renderer bakes once at the new pan (on a stage the
	-- view always glides: an endless islet's next area is a scroll away)
	local W, H = v.fullX / v.K, v.fullY / v.K
	if not v.stage and (math.abs(tx - camX) > W * 0.75 or math.abs(ty - camY) > H * 0.75) then
		jumpTo(tx, ty)
		lockOn()
		pose(v)
		return
	end
	-- (the frame's length counts, so the view keeps up as well at 30 frames a second as at 60)
	local secs = math.clamp(dt or 1 / 60, 1 / 240, 0.1)
	local cx0, cy0 = camX, camY
	camX, velX = follow(camX, tx, velX, secs)
	camY, velY = follow(camY, ty, velY, secs)
	-- The pan in whole art px. It is the target's pixel less the gap's: while the founder walks at a steady pace the gap
	-- stays the same, so the pan steps with them pixel for pixel and they keep still on the screen (rounding the
	-- follow's place on its own would shake them by a pixel); as the view closes in or falls back the gap changes a
	-- pixel at a time. A frame moves it at most what the renderer can scroll in one (`panCaps`), so its picture never
	-- falls behind into a re-bake (a quick Build mode drag catches up over a few frames).
	local nx = math.floor(tx + 0.5) - math.floor(tx - camX + 0.5)
	local ny = math.floor(ty + 0.5) - math.floor(ty - camY + 0.5)
	local capX, capY = panCaps(v)
	nx = panX + math.clamp(nx - panX, -capX, capX)
	ny = panY + math.clamp(ny - panY, -capY, capY)
	if nx ~= panX or ny ~= panY or (classic and (camX ~= cx0 or camY ~= cy0)) then
		panX, panY = nx, ny
		pose(v)
	end
	lockOn()
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
		jumpTo(target(v))
		pose(v)
	end
end

-- Whether the view is where it should be (a cutscene waits for it before opening its blinds).
function CameraController.settled(): boolean
	local v = current
	if v == nil then
		return true
	end
	local tx, ty = target(v)
	return math.floor(tx + 0.5) == panX and math.floor(ty + 0.5) == panY
end

-- Build mode (true): the view keeps following the founder, lowered by half of `down` art px (Build mode's tray
-- covers the bottom of the screen), and Build mode's drag (`panBy`) moves it from there; false: the plain follow.
function CameraController.setFree(on: boolean, down: number?)
	free = on
	buildDown = if on then math.floor((down or 0) / 2) else 0
	dragX, dragY = 0, 0
	lastBaseX, lastBaseY = nil, nil
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
		jumpTo(target(v))
		pose(v)
	end
end

function CameraController.stage(): Stage?
	return stage
end

function CameraController.isFree(): boolean
	return free
end

-- Build mode's drag: the world follows the pointer by (dx, dy) full-screen px (the drag kept as an offset from the
-- founder), the view's centre kept over the own plot (Tuning.CamBuildPan studs past its edges at most). The follow's
-- place moves with the drag at once (no spring between the pointer and the world).
function CameraController.panBy(dx: number, dy: number)
	local v = CameraController.view()
	local fx, fy = baseTarget(v)
	local bx: number = if fx then fx else panX - dragX
	local by: number = if fy then fy else panY - buildDown - dragY
	local nx = bx + dragX - math.floor(dx / v.K + 0.5)
	local ny = by + buildDown + dragY - math.floor(dy / v.K + 0.5)
	local cx, cy = clampBuild(v, nx, ny)
	local odx, ody = dragX, dragY
	dragX, dragY = cx - bx, cy - by - buildDown
	camX += dragX - odx
	camY += dragY - ody
end

-- The View slider's notch (1 far out .. #Tuning.CamZoomNotches close in): the islands are drawn at that many art px a
-- stud. A new notch is a new view (the pixel filter bakes the island again at the new scale; the old picture stays up
-- meanwhile), the founder in the middle of it; Build mode's drag keeps the same studs.
function CameraController.setZoom(n: number)
	local z = math.clamp(math.floor(n + 0.5), 1, #Tuning.CamZoomNotches)
	if z == zoom then
		return
	end
	local from = Tuning.CamZoomNotches[zoom]
	zoom = z
	local k = Tuning.CamZoomNotches[z] / from
	dragX, dragY = math.floor(dragX * k + 0.5), math.floor(dragY * k + 0.5)
	CameraController.refit()
end

function CameraController.zoom(): number
	return zoom
end

-- Build mode's drag now (art px from the founder, not counting the lowering): the sims check it.
function CameraController.buildDrag(): (number, number)
	return dragX, dragY
end

function CameraController.init() end

function CameraController.start()
	local function fromView(cv: Types.ClientView)
		-- the View slider's notch as the profile keeps it (at the join, or from another device); a tap still on its
		-- way to the server keeps what it set
		local z = cv.settings.zoom
		if type(z) == "number" and z ~= savedZoom then
			savedZoom = z
			CameraController.setZoom(z)
		end
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
	-- (the screen's own scale found or set: the pixel size follows)
	DisplayScale.start()
	DisplayScale.Changed:Connect(function()
		CameraController.refit()
	end)
	local cam = Workspace.CurrentCamera
	ScreenSize.start()
	ScreenSize.Changed:Connect(function()
		CameraController.refit()
	end)
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
