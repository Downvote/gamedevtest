--!strict
-- Snapshot: pixel-art pictures of models for the UI, drawn exactly like the world (ARCHITECTURE 11.10). OWNER: WP8.
--
-- A picture is a small EditableImage (w x h art pixels, transparent background) of a Model, a BasePart or a Folder
-- of parts, seen from the world's 2:1 camera (yaw 45, pitch Tuning.CamPitch = 30; optionally turned), with the world's look: palette, 3 toon
-- bands, Bayer dither at band edges, sun shadows inside the model, a 1 px ink outline round the silhouette (Neon
-- parts glow, see-through parts blend, parts smaller than an art pixel keep one pixel). It is drawn analytically by
-- Render/Picture (no raycasts, nothing is parented or moved), time-sliced at Tuning.PixelSnapshotMsPerFrame per
-- frame, in the fixed day palette (icons do not change at night or with the season).
--
-- Show it on the art grid, exactly art px * K screen px (K = PixelRenderer.pixelScale(), the game's one pixel size):
--   on a UIKit pixel canvas (UIScale K):   Size = UDim2.fromOffset(snap.w, snap.h), whole-number Position
--   on a plain screen-px canvas:           Size = UDim2.fromOffset(snap.w * K, snap.h * K), Position a multiple of K
-- (Snapshot.label does the sizing.) ResampleMode must stay Pixelated (Snapshot.show sets it).
--
-- API
--   Snapshot.available(): boolean
--       false when EditableImages cannot be created here (the "Allow Mesh / Image APIs" game setting is off, or the
--       device is out of image memory). get and turntable then return nil: show a ViewportFrame instead.
--   Snapshot.get(key: string, source: Source, opts: Options?): Snap?
--       The picture for `key`, cached: the same key returns the same Snap (opts and source only count the first
--       time, so put whatever changes the picture into the key, e.g. "cake:" .. lookId .. ":32"). It is drawn in the
--       background (higher `priority` first); snap.ready turns true and snap.Ready fires once it is uploaded. Asked
--       again at a higher priority before it is drawn, it moves up the queue (a picture drawn ahead for a hover,
--       then picked).
--       Source = a Model / BasePart / Folder (read only; it need not be parented) or a function that builds one
--       (called once, when the picture is drawn; what it returns is destroyed afterwards unless it has a Parent).
--   Snapshot.turntable(key: string, source: Source, opts: Options?, n: number): { Snap }?
--       n pictures (2..64) of the model turned in steps of 360 / n degrees (keys key .. "@1" .. key .. "@" .. n), all
--       at one scale around one centre so the model spins in place. Step a label through them with Snapshot.show.
--   Snapshot.show(label: ImageLabel, snap: Snap?)
--       Bind a picture to an ImageLabel: its ImageContent follows the picture (blank until ready), ResampleMode
--       Pixelated. One picture per label; nil unbinds. Pictures bound to a label in the game are never evicted.
--   Snapshot.label(snap: Snap, parent: Instance?, pixelCanvas: boolean?): ImageLabel
--       A transparent ImageLabel sized for the picture (art px on a pixel canvas, art px * K otherwise), shown. On a
--       pixel canvas the canvas's UIScale follows K; elsewhere re-size it on PixelRenderer.ScaleChanged.
--   Snapshot.release(key: string) / Snapshot.clear()
--       Forget pictures (their images are destroyed and bound labels go blank). A forgotten Snap stays failed (a new
--       one takes its key): whoever holds on to one asks for its key again.
--   Snapshot.pending(): number      pictures still to draw
--   Snapshot.setBudget(ms: number?)  drawing time per frame while a screen needs pictures fast and the world is not
--       drawn (the Recipe Desk); nil: Tuning.PixelSnapshotMsPerFrame again. While only pictures of a negative
--       priority wait (background ones), a frame draws for at most BACKGROUND_MS (3 ms).
-- Options:
--   size (square side, art px, default 32; e.g. 16 / 24 / 32 icons, 96 for the Recipe Desk stage) or w and h;
--   yaw (degrees the model is turned about world up, CFrame.Angles(0, rad(yaw), 0); default 0);
--   pitch (default Tuning.CamPitch, the world's); pad (art px kept free round the model, default 1, at least 1 with
--   the outer outline); scale (art px per stud: a fixed size instead of fitting the model's box, so a family of
--   icons shares one scale); anchor (with scale: the art px, from the picture's top-left corner, where the world
--   origin lands, so pictures of different models line up, e.g. a character's feet whatever it wears); outline
--   ("outer" default: ink outside the silhouette; "inner": on the rim, as in the world; "none"); shadows (default
--   true); priority (default 0); flat (a Color3: every drawn pixel in that one colour, fully opaque, and the ones on
--   the picture's rim, next to the background, in flatEdge (default flat): a pixel-clean silhouette, e.g. the Recipe
--   Book's recipes not made yet); keep (true: the cache never evicts the picture, only Snapshot.release forgets it:
--   for pictures a screen holds on to and shows later, e.g. the Recipe Desk's cake looks, its turned views and layers).
-- The cache keeps MAX_CACHE pictures: past that the least recently used ones that no label shows (and nobody keeps) go.
-- When the device runs out of image memory (a long session), every such picture goes, then, one at a time and least
-- recently used first, kept ones no label shows (they fail: their holders ask for their keys again), until the new
-- picture fits; when nothing fits it waits with its pixels and goes up once there is memory (tried again 1 s later,
-- doubling to 16 s), never failed for good.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Picture = require(ReplicatedStorage.Shared.Render.Picture)
local PixelRenderer = require(script.Parent.PixelRenderer)
local ImageMemory = require(script.Parent.ImageMemory)

export type Source = Instance | () -> Instance?

export type Options = {
	size: number?,
	w: number?,
	h: number?,
	yaw: number?,
	pitch: number?,
	pad: number?,
	scale: number?,
	anchor: Vector2?,
	outline: string?,
	shadows: boolean?,
	priority: number?,
	flat: Color3?,
	flatEdge: Color3?,
	keep: boolean?,
}

export type Snap = {
	key: string,
	w: number,
	h: number,
	yaw: number,
	ready: boolean,
	failed: boolean,
	keep: boolean, -- Options.keep: never evicted
	image: EditableImage?,
	Ready: Types.Signal<Snap>,
}

-- One queued drawing: a picture, or the n pictures of a turntable (one model read, one shared framing).
type Group = {
	snaps: { Snap },
	source: Source,
	opts: Options,
	priority: number,
	order: number,
	jobs: { Picture.Job }?,
	next: number, -- snap being drawn
}

local Snapshot = {}

local MAX_SIZE = 1024 -- EditableImage limit
local MAX_CACHE = 400 -- pictures kept before the least recently used unbound ones go
local INVISIBLE = 0.95
local MIN_WORK = 1 -- Picture.step calls per frame even when the budget is spent
-- drawing time per frame (at most) while only background pictures wait (a negative priority: the Recipe Desk's
-- turntable), whatever Snapshot.setBudget says: they trickle in without taking a big share of every frame where
-- scripts run interpreted (live clients)
local BACKGROUND_MS = 3

local supported: boolean? = nil -- nil until the first try
local cache: { [string]: Snap } = {}
local usedAt: { [string]: number } = {}
local queue: { Group } = {}
local order = 0
local boundSnap: { [ImageLabel]: Snap } = {}
local labelsOf: { [Snap]: { [ImageLabel]: boolean } } = {}
local labelConns: { [ImageLabel]: RBXScriptConnection } = {}
local stepConn: RBXScriptConnection? = nil
local budgetMs: number? = nil -- Snapshot.setBudget
-- drawn pictures waiting for image memory to upload (their pixels kept), tried again PARK_MIN seconds later, doubling
-- to PARK_MAX while there is none
local PARK_MIN, PARK_MAX = 1, 16
local parked: { [Snap]: { job: Picture.Job, opts: Options } } = {}
local parkedOnce: { [Snap]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local parkDelay = PARK_MIN
local parkScheduled = false

------------------------------------------------------------------ helpers
local function rgbOf(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

-- (Pixel/ImageMemory: when the device is out of image memory, the text atlas first gives up its pages nobody shows)
local function tryImage(w: number, h: number): EditableImage?
	return ImageMemory.create(w, h, "snapshot")
end

-- The parts of a source as Picture solids (invisible parts and the HumanoidRootPart left out).
local function readSolids(root: Instance): { Picture.Solid }
	local list: { Picture.Solid } = {}
	local function add(p: BasePart)
		if p.Transparency >= INVISIBLE or p.Name == "HumanoidRootPart" then
			return
		end
		local attr = p:GetAttribute("PixelColor")
		local rgb = rgbOf(if typeof(attr) == "Color3" then attr else p.Color)
		local shape = Picture.shape(p.ClassName, if p:IsA("Part") then p.Shape.Name else nil)
		local size = p.Size
		table.insert(
			list,
			Picture.solid(shape, { p.CFrame:GetComponents() }, size.X, size.Y, size.Z, rgb, p.Material == Enum.Material.Neon, 1 - p.Transparency)
		)
	end
	if root:IsA("BasePart") then
		add(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			add(d)
		end
	end
	return list
end

local function setLabel(label: ImageLabel, snap: Snap?)
	local img = if snap ~= nil and snap.ready then snap.image else nil
	label.ImageContent = if img ~= nil then Content.fromObject(img) else Content.none
end

local function unbind(label: ImageLabel)
	local old = boundSnap[label]
	if old ~= nil then
		local set = labelsOf[old]
		if set then
			set[label] = nil
			if next(set) == nil then
				labelsOf[old] = nil -- (no label shows it: the set would keep a dropped picture alive)
			end
		end
	end
	boundSnap[label] = nil
	local c = labelConns[label]
	if c then
		c:Disconnect()
		labelConns[label] = nil
	end
end

local function isBound(snap: Snap): boolean
	local set = labelsOf[snap]
	if set == nil then
		return false
	end
	for label in set do
		if label.Parent ~= nil then
			return true
		end
		unbind(label) -- a label that left the game
	end
	return false
end

local function drop(key: string)
	local snap = cache[key]
	if snap == nil then
		return
	end
	cache[key] = nil
	usedAt[key] = nil
	snap.failed = true
	snap.ready = false
	local img = snap.image
	snap.image = nil
	-- its labels go blank and let go of it (a dropped picture never comes back: a new one takes its key)
	local set = labelsOf[snap]
	if set then
		local labels: { ImageLabel } = {}
		for label in set do
			table.insert(labels, label)
		end
		for _, label in labels do
			unbind(label)
			setLabel(label, nil)
		end
		labelsOf[snap] = nil
	end
	if img then
		img:Destroy()
	end
end

-- The drawn pictures nobody needs now (no label shows them, nobody keeps them; `kept`: kept ones too), least recently
-- used first.
local function spare(kept: boolean?): { string }
	local keys: { string } = {}
	for key, snap in cache do
		if snap.ready and (kept or not snap.keep) and not isBound(snap) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a: string, b: string): boolean
		return (usedAt[a] or 0) < (usedAt[b] or 0)
	end)
	return keys
end

-- Keep the cache under MAX_CACHE: drop the least recently used spare pictures.
local function evict()
	local count = 0
	for _ in cache do
		count += 1
	end
	if count <= MAX_CACHE then
		return
	end
	local keys = spare()
	for i = 1, math.min(#keys, count - MAX_CACHE) do
		drop(keys[i])
	end
end

local function newSnap(key: string, w: number, h: number, yaw: number, keep: boolean?): Snap
	return { key = key, w = w, h = h, yaw = yaw, ready = false, failed = false, keep = keep == true, image = nil, Ready = Util.Signal() }
end

------------------------------------------------------------------ drawing
local function failGroup(g: Group, why: string)
	warn("[Snapshot] " .. why)
	for _, snap in g.snaps do
		snap.failed = true
	end
end

-- Read the model and frame every view of the group.
local function prepare(g: Group): boolean
	local src = g.source
	local root: Instance? = nil
	local built = false
	if typeof(src) == "Instance" then
		root = src
	else
		local ok, res = pcall(src :: () -> Instance?)
		if not ok then
			failGroup(g, "building " .. g.snaps[1].key .. " failed: " .. tostring(res))
			return false
		end
		if typeof(res) == "Instance" then
			root = res
			built = true
		end
	end
	if root == nil then
		failGroup(g, "no model for " .. g.snaps[1].key)
		return false
	end
	local solids = readSolids(root)
	if built and root.Parent == nil then
		root:Destroy()
	end
	local o = g.opts
	local first = g.snaps[1]
	local pitch = o.pitch or Tuning.CamPitch
	local rots: { { number } } = {}
	for _, snap in g.snaps do
		table.insert(rots, Raster.rotation(Tuning.CamYaw - snap.yaw, pitch))
	end
	local pad = math.max(if o.outline == "inner" or o.outline == "none" then 0 else 1, o.pad or 1)
	local at = o.anchor
	local cams = Picture.fit(rots, solids, first.w, first.h, pad, o.scale, if at then { at.X, at.Y } else nil)
	local jobs: { Picture.Job } = {}
	for k in g.snaps do
		table.insert(jobs, Picture.new(solids, cams[k], { outline = o.outline, shadows = o.shadows }))
	end
	g.jobs = jobs
	return true
end

local function packRGBA(c: Color3): number
	local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	return r + g * 256 + b * 65536 + 255 * 16777216
end

-- Options.flat: every drawn pixel (alpha > 0) of the packed RGBA buffer becomes `fill`, fully opaque, and the ones
-- next to the background (or the picture's border) `edge`. In place.
local function flatten(px: buffer, w: number, h: number, fill: Color3, edge: Color3)
	local fillV, edgeV = packRGBA(fill), packRGBA(edge)
	local solid = buffer.create(w * h)
	for i = 0, w * h - 1 do
		if buffer.readu8(px, i * 4 + 3) > 0 then
			buffer.writeu8(solid, i, 1)
		end
	end
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			if buffer.readu8(solid, i) == 1 then
				local rim = x == 0 or y == 0 or x == w - 1 or y == h - 1
					or buffer.readu8(solid, i - 1) == 0 or buffer.readu8(solid, i + 1) == 0
					or buffer.readu8(solid, i - w) == 0 or buffer.readu8(solid, i + w) == 0
				buffer.writeu32(px, i * 4, if rim then edgeV else fillV)
			end
		end
	end
end

local finish: (snap: Snap, job: Picture.Job, opts: Options) -> ()

-- No image memory for a drawn picture: it waits with its pixels (not failed: its labels stay blank meanwhile, as they
-- were while it was drawn) and is uploaded once memory is back.
local function park(snap: Snap, job: Picture.Job, opts: Options)
	if not parkedOnce[snap] then
		parkedOnce[snap] = true
		warn("[Snapshot] no image memory for " .. snap.key .. " (it goes up once there is)")
	end
	parked[snap] = { job = job, opts = opts }
	if parkScheduled then
		return
	end
	parkScheduled = true
	local wait = parkDelay
	parkDelay = math.min(PARK_MAX, parkDelay * 2)
	task.delay(wait, function()
		parkScheduled = false
		local list = parked
		parked = {}
		for p, w in list do
			if cache[p.key] == p and not p.ready then
				finish(p, w.job, w.opts)
			end
		end
	end)
end

-- Upload a finished picture.
finish = function(snap: Snap, job: Picture.Job, opts: Options)
	if cache[snap.key] ~= snap then
		return -- released while it was drawn
	end
	local img = tryImage(snap.w, snap.h)
	if img == nil then
		-- out of image memory (a long session): the spare pictures go (they are drawn again when shown); then kept ones
		-- no label shows, one at a time, the least recently used first
		for _, key in spare() do
			drop(key)
		end
		img = tryImage(snap.w, snap.h)
		if img == nil then
			for _, key in spare(true) do
				drop(key)
				img = tryImage(snap.w, snap.h)
				if img ~= nil then
					break
				end
			end
		end
	end
	if img == nil then
		park(snap, job, opts)
		return
	end
	parkDelay = PARK_MIN
	local ok, err = pcall(function()
		local flat = opts.flat
		if flat then
			flatten(job.pixels, snap.w, snap.h, flat, opts.flatEdge or flat)
		end
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(snap.w, snap.h), job.pixels)
	end)
	if not ok then
		img:Destroy()
		snap.failed = true
		warn("[Snapshot] upload of " .. snap.key .. " failed: " .. tostring(err))
		return
	end
	snap.image = img
	snap.ready = true
	local set = labelsOf[snap]
	if set then
		for label in set do
			setLabel(label, snap)
		end
	end
	snap.Ready:Fire(snap)
end

local function nextGroup(): (Group?, number)
	local best, bestIdx = nil, 0
	for i, g in queue do
		if best == nil or g.priority > best.priority or (g.priority == best.priority and g.order < best.order) then
			best, bestIdx = g, i
		end
	end
	return best, bestIdx
end

local function step()
	local ms = budgetMs or Tuning.PixelSnapshotMsPerFrame
	local first = nextGroup()
	if first and first.priority < 0 then
		ms = math.min(ms, BACKGROUND_MS)
	end
	local deadline = os.clock() + ms / 1000
	local calls = 0
	while #queue > 0 do
		local g, idx = nextGroup()
		if g == nil then
			break
		end
		local ok = true
		if g.jobs == nil then
			ok = prepare(g)
		end
		local jobs = g.jobs
		if not ok or jobs == nil then
			table.remove(queue, idx)
		else
			local snap = g.snaps[g.next]
			local job = jobs[g.next]
			calls += 1
			if cache[snap.key] ~= snap then
				g.next += 1 -- released: skip it
			elseif Picture.step(job, deadline) then
				finish(snap, job, g.opts)
				g.next += 1
			end
			if g.next > #g.snaps then
				table.remove(queue, idx)
				evict()
			end
		end
		if calls >= MIN_WORK and os.clock() >= deadline then
			break
		end
	end
	if #queue == 0 then
		local c = stepConn
		if c then
			c:Disconnect()
			stepConn = nil
		end
	end
end

local function enqueue(g: Group)
	order += 1
	g.order = order
	table.insert(queue, g)
	if stepConn == nil then
		stepConn = RunService.Heartbeat:Connect(step)
	end
end

local function sizeOf(o: Options): (number, number)
	local side = o.size or 32
	local w = math.clamp(math.floor(o.w or side), 1, MAX_SIZE)
	local h = math.clamp(math.floor(o.h or side), 1, MAX_SIZE)
	return w, h
end

-- Another part is out of image memory (Pixel/ImageMemory): the pictures nobody shows or keeps go (they are drawn again
-- when shown). How many went.
ImageMemory.onLow("snapshot", function(): number
	local keys = spare()
	for _, key in keys do
		drop(key)
	end
	return #keys
end)

------------------------------------------------------------------ API
function Snapshot.available(): boolean
	local known = supported
	if known ~= nil then
		return known
	end
	local img = tryImage(1, 1)
	if img then
		img:Destroy()
	end
	supported = img ~= nil
	return img ~= nil
end

function Snapshot.get(key: string, source: Source, opts: Options?): Snap?
	local known = cache[key]
	if known ~= nil and not known.failed then
		usedAt[key] = os.clock()
		if opts and opts.keep then
			known.keep = true
		end
		local prio = if opts then opts.priority else nil
		if prio and not known.ready then
			-- wanted sooner now: its drawing moves up
			for _, g in queue do
				if g.priority < prio and table.find(g.snaps, known) ~= nil then
					g.priority = prio
				end
			end
		end
		return known
	end
	if not Snapshot.available() then
		return nil
	end
	local o: Options = opts or {}
	local w, h = sizeOf(o)
	local snap = newSnap(key, w, h, o.yaw or 0, o.keep)
	cache[key] = snap
	usedAt[key] = os.clock()
	enqueue({ snaps = { snap }, source = source, opts = o, priority = o.priority or 0, order = 0, jobs = nil, next = 1 })
	return snap
end

function Snapshot.turntable(key: string, source: Source, opts: Options?, n: number): { Snap }?
	if not Snapshot.available() then
		return nil
	end
	local count = math.clamp(math.floor(n), 2, 64)
	local o: Options = opts or {}
	local w, h = sizeOf(o)
	local base = o.yaw or 0
	local snaps: { Snap } = {}
	local fresh = false
	for k = 1, count do
		local sk = key .. "@" .. k
		local known = cache[sk]
		if known == nil or known.failed then
			fresh = true
		end
	end
	if not fresh then
		for k = 1, count do
			local sk = key .. "@" .. k
			usedAt[sk] = os.clock()
			table.insert(snaps, cache[sk])
		end
		return snaps
	end
	for k = 1, count do
		local sk = key .. "@" .. k
		drop(sk)
		local snap = newSnap(sk, w, h, base + 360 * (k - 1) / count, o.keep)
		cache[sk] = snap
		usedAt[sk] = os.clock()
		table.insert(snaps, snap)
	end
	enqueue({ snaps = snaps, source = source, opts = o, priority = o.priority or 0, order = 0, jobs = nil, next = 1 })
	return snaps
end

function Snapshot.show(label: ImageLabel, snap: Snap?)
	if boundSnap[label] == snap and snap ~= nil then
		setLabel(label, snap)
		return
	end
	unbind(label)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	if snap == nil then
		setLabel(label, nil)
		return
	end
	boundSnap[label] = snap
	local set = labelsOf[snap]
	if set == nil then
		set = {}
		labelsOf[snap] = set
	end
	set[label] = true
	usedAt[snap.key] = os.clock()
	labelConns[label] = label.Destroying:Connect(function()
		unbind(label)
	end)
	setLabel(label, snap)
end

function Snapshot.label(snap: Snap, parent: Instance?, pixelCanvas: boolean?): ImageLabel
	local k = if pixelCanvas then 1 else PixelRenderer.pixelScale()
	local im = Instance.new("ImageLabel")
	im.Name = "Snapshot"
	im.BackgroundTransparency = 1
	im.BorderSizePixel = 0
	im.Size = UDim2.fromOffset(snap.w * k, snap.h * k)
	Snapshot.show(im, snap)
	if parent then
		im.Parent = parent
	end
	return im
end

function Snapshot.release(key: string)
	drop(key)
end

function Snapshot.clear()
	local keys: { string } = {}
	for key in cache do
		table.insert(keys, key)
	end
	for _, key in keys do
		drop(key)
	end
	table.clear(queue)
end

function Snapshot.setBudget(ms: number?)
	budgetMs = ms
end

function Snapshot.pending(): number
	local n = 0
	for _, g in queue do
		n += #g.snaps - g.next + 1
	end
	return n
end

return Snapshot
