--!strict
--!native
-- PixelText: text drawn in the game's pixel font (Render/PixelFont) into EditableImages, one font pixel per art pixel
-- (ARCHITECTURE 10.6 / 11.10; README "Fonts and licences"). OWNER: WP9.
--
-- A bound TextLabel keeps its Text and every text property (sims, Roblox's localisation capture and screen readers
-- read them) but its own glyphs are hidden (TextTransparency 1). Two child ImageLabels draw it instead:
--   "Glyphs"      the letters, a white mask tinted with ImageColor3 (the face colour);
--   "GlyphUnder"  the layer under them, tinted with the under colour: the 1 px drop shadow (style "shadow"), the
--                 bold outline (style "outline": 1 px all round plus the shadow), the paper weight (style "weight":
--                 1 px under), the title's outline and 2 px of depth (style "title") - none for style "plain". On the
--                 big face a title's layer holds its own colours instead: the under colour, and pixel-art
--                 anti-aliasing in the elbows of the steps (PixelFont.smooth) in Ramp's shadow tone of the face (its
--                 hue turned toward blue-violet), so a new face or under colour draws it again.
-- They sit on whole art pixels inside the label's box (TextXAlignment / TextYAlignment, word wrap by the font's real
-- advances when TextWrapped, TextTruncate AtEnd clipping with "...", LineHeight as the line pitch,
-- MaxVisibleGraphemes as a typing prefix, RichText <font color> runs baked into the image), sized art px * unit (unit
-- = the label's Offset units per art pixel: 1 on a UIKit pixel canvas, K on a screen-px canvas), ResampleMode
-- Pixelated, so on screen every font pixel is exactly K x K screen px of the world's grid.
--
-- Atlas: every drawn text is a rect in a shared page (an EditableImage of PAGE_W x PAGE_H; a text too big for a page
-- gets a page of its own), shown through ImageRectOffset / ImageRectSize. Roblox refreshes only one changed
-- EditableImage per frame on the display side, so a few big pages beat one image per label. Entries are cached by
-- what they look like (face, text lines, alignment, pitch, rich colours), shared by every label that shows the same
-- thing and recoloured for free (ImageColor3); a label holds its entries until it shows something else or is
-- destroyed. When the pages are full, the rows nobody shows are reused, least recently used first: neighbouring free
-- shelves of any height are cut again into the one the new words need (PixelText.stats() reports pages, entries,
-- bytes and hits). Images come from Pixel/ImageMemory: when the device is out of image memory the other parts give up
-- pictures nobody shows, and the atlas gives up its pages nobody shows when they are short.
-- Never for good in Press Start 2P: when no image can be had at all, a label shows its own text for now (the native
-- font, so it is never blank) and is drawn again RETRY_MIN seconds later (doubling up to RETRY_MAX while it keeps
-- failing), and goes back to the pixel font the moment its words fit. Drawing runs once per frame for every label that
-- changed (TEXT_MS budget, then the next frame), so a burst of writes to one label draws once.
-- No flicker: a label lets go of its entries a frame late (a page rebuilt in one go finds its words still in the atlas,
-- not reused for other text in between), and words whose pixels were just written go up READY_FRAMES frames later
-- (the page's new pixels reach the screen a frame or two after the write): until then the label keeps what it shows,
-- so it never shows a blank or another text's pixels.
--
-- API
--   PixelText.available(): boolean   EditableImages work here (false: "Allow Mesh / Image APIs" off, or the device
--       was out of image memory at the start); callers then keep native TextLabels in Press Start 2P (UIKit does).
--   PixelText.bind(label, style?) -> boolean   style: { kind = "plain" | "shadow" | "outline" | "weight" | "title",
--       under = Color3?, underShade = number?, unit = number?, face = "small" | "big", autoY = boolean?,
--       tracking = number?, raw = boolean? }. raw: the words are drawn as written (never translated: chat, names). underShade: the under layer is the face colour times this (bold on paper). autoY: the
--       label's height follows its lines (lines * pitch; the label's own AutomaticSize is turned off).
--   PixelText.isBound(label): boolean
--   PixelText.unbind(label)   the label shows its own text again (its glyph layers go)
--   PixelText.setColor(label, Color3) / PixelText.color(label): Color3     the face colour (also label.TextColor3)
--   PixelText.setUnder(label, Color3)                                       the under layer's colour
--   PixelText.setTransparency(label, a) / PixelText.transparency(label)    the text's transparency (a write of
--       TextTransparency < 1 to a bound label means the same; the label itself stays at 1)
--   PixelText.refresh(label)   draw again now (after changing several properties at once)
--   PixelText.flush()          draw every changed label now
--   PixelText.reclaim(): number   frees the pages nobody shows (Pixel/ImageMemory asks when another part is out of
--       image memory); the bytes freed
--   PixelText.stats()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PixelFont = require(ReplicatedStorage.Shared.Render.PixelFont)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Ramp = require(ReplicatedStorage.Shared.Render.Ramp)
local PixelRenderer = require(script.Parent.PixelRenderer)
local ImageMemory = require(script.Parent.ImageMemory)

export type Style = {
	kind: string?,
	under: Color3?,
	unit: number?,
	face: string?,
	autoY: boolean?,
	tracking: number?,
	underShade: number?,
	raw: boolean?,
}

type Page = {
	image: EditableImage,
	content: Content,
	w: number,
	h: number,
	shelves: { Shelf },
	nextY: number,
	dedicated: boolean,
	used: number,
}
type Shelf = { y: number, h: number, x: number, entries: { Entry }, page: Page }
type Entry = {
	key: string,
	page: Page,
	shelf: Shelf?,
	x: number,
	y: number,
	w: number,
	h: number,
	ox: number,
	oy: number,
	blockW: number,
	blockH: number,
	refs: number,
	used: number,
	live: boolean,
	ready: number, -- the frame (frameNo) from which its pixels are on screen
}
-- What a label shows: its entries and where they sit in its box.
type Look = { e: Entry, ue: Entry?, x0: number, y0: number, rich: boolean }
type Rec = {
	label: TextLabel,
	kind: string,
	unit: number,
	face: PixelFont.Face,
	autoY: boolean,
	tracking: number,
	glyphs: ImageLabel,
	under: ImageLabel?,
	color: Color3,
	underColor: Color3,
	underShade: number?,
	alpha: number,
	entry: Entry?,
	underEntry: Entry?,
	wait: Look?, -- new words waiting for their pixels to be on screen (held)
	rich: boolean,
	underBaked: boolean, -- the under layer holds its own colours (the big words' outline and anti-aliasing)
	conns: { RBXScriptConnection },
	fallback: boolean, -- no image could be had: the label shows its own text for now (drawn again later)
	typing: boolean,
	settingAlpha: boolean,
	settingSize: boolean,
	raw: boolean, -- drawn as written (never translated)
}

local PixelText = {}

-- Shared atlas pages shown through ImageRectOffset / ImageRectSize. false gives every text an image of its own
-- (only for a client where image rects would not apply to EditableImages; one changed image refreshes per frame,
-- so a menu's words would then appear over several frames).
local ATLAS = true
local PAGE_W, PAGE_H = 512, 256
local MAX_IMAGE = 1024
local SOFT_PAGES = 12 -- shared pages before least-recently-used shelves are reused (12 x 512 KB)
local HARD_PAGES = 24 -- never more shared pages than this
local DEDICATED_BYTES = 4 * 1024 * 1024 -- big texts with an image of their own, kept while unused up to this much
local GUTTER = 1 -- clear px right of and under every entry
local SHELF_STEP = 4 -- shelf heights round up to this
local TEXT_MS = 6 -- drawing budget per frame (ms); at least MIN_DRAWS labels a frame anyway
local MIN_DRAWS = 8
local SWEEP_SEC = 10
local READY_FRAMES = 2 -- frames between writing an entry's pixels and showing them
local RETRY_MIN, RETRY_MAX = 1, 16 -- seconds before a label that got no image tries again (doubling while it fails)

local supported: boolean? = nil
local pages: { Page } = {}
local dedicatedBytes = 0
local cache: { [string]: Entry } = {}
local recs: { [Instance]: Rec } = {}
local dirty: { [Rec]: boolean } = {}
local dirtyList: { Rec } = {}
local flushScheduled = false
local stepConn: RBXScriptConnection? = nil
local lastSweep = 0
local clock = 0 -- use counter (LRU)
local frameNo = 0 -- frames seen (RenderStepped)
local releasing: { Entry } = {} -- let go of this frame (applied after the next frame's start)
local released: { Entry } = {} -- let go of last frame (applied at this frame's start)
local waiting: { [Rec]: boolean } = {} -- labels with words waiting for their pixels (Rec.wait)
local retry: { [Rec]: boolean } = {} -- labels showing their own text until an image can be had (Rec.fallback)
local retryDelay = RETRY_MIN
local retryScheduled = false
local noImageFrame = -1 -- the last frame an image could not be made in (no more tries that frame: rows are reused)
local stats = { draws = 0, hits = 0, misses = 0, uploads = 0, reclaimed = 0, failures = 0, fallbacks = 0 }

------------------------------------------------------------------ availability

local function newImage(w: number, h: number): EditableImage?
	return ImageMemory.create(w, h, "text")
end

function PixelText.available(): boolean
	local known = supported
	if known ~= nil then
		return known
	end
	local ok = false
	local img = newImage(4, 4)
	if img then
		ok = pcall(function()
			local _c: Content = Content.fromObject(img)
		end)
		img:Destroy()
	end
	supported = ok
	return ok
end

------------------------------------------------------------------ atlas

local function bytesOf(p: Page): number
	return p.w * p.h * 4
end

local function newPage(w: number, h: number, dedicated: boolean): Page?
	if noImageFrame == frameNo then
		return nil
	end
	local img = newImage(w, h)
	if img == nil then
		noImageFrame = frameNo
		return nil
	end
	local okC, content = pcall(Content.fromObject, img)
	if not okC then
		img:Destroy()
		return nil
	end
	local p: Page = {
		image = img,
		content = content,
		w = w,
		h = h,
		shelves = {},
		nextY = 0,
		dedicated = dedicated,
		used = clock,
	}
	if dedicated then
		dedicatedBytes += bytesOf(p)
	else
		table.insert(pages, p)
	end
	return p
end

local function dropEntry(e: Entry)
	e.live = false
	if cache[e.key] == e then
		cache[e.key] = nil
	end
end

-- Frees the unused dedicated pages, oldest first, until their memory fits the budget.
local function trimDedicated(need: number)
	if dedicatedBytes + need <= DEDICATED_BYTES then
		return
	end
	local list: { Entry } = {}
	for _, e in cache do
		if e.page.dedicated and e.refs <= 0 then
			table.insert(list, e)
		end
	end
	table.sort(list, function(a: Entry, b: Entry): boolean
		return a.used < b.used
	end)
	for _, e in list do
		if dedicatedBytes + need <= DEDICATED_BYTES then
			break
		end
		dropEntry(e)
		dedicatedBytes -= bytesOf(e.page)
		e.page.image:Destroy()
	end
end

local function shelfFree(s: Shelf): boolean
	for _, e in s.entries do
		if e.live and e.refs > 0 then
			return false
		end
	end
	return true
end

local function shelfUsed(s: Shelf): number
	local u = 0
	for _, e in s.entries do
		u = math.max(u, e.used)
	end
	return u
end

local function resetShelf(s: Shelf)
	for _, e in s.entries do
		dropEntry(e)
	end
	table.clear(s.entries)
	s.x = 0
	stats.reclaimed += 1
end

local function freshShelf(p: Page, y: number, h: number): Shelf
	return { y = y, h = h, x = 0, entries = {}, page = p }
end

-- Rows nobody shows cut again into a shelf of height sh: the least recently used run of neighbouring free shelves (of
-- any heights) in a page that is tall enough, counting the free rows under the page's last shelf. A page's shelves
-- stay in order of y and tile its rows from 0 to nextY, so the run's rows are the new shelf's and a free shelf of what
-- is left (or, at the bottom, free rows again).
local function carve(sh: number): (Page?, Shelf?)
	local bestP: Page? = nil
	local bestI, bestJ, bestUsed, bestWaste = 0, 0, math.huge, math.huge
	local free: { boolean } = {}
	local usedAt: { number } = {}
	for _, p in pages do
		local list = p.shelves
		local n = #list
		for i, s in list do
			free[i] = shelfFree(s)
			usedAt[i] = if free[i] then shelfUsed(s) else 0
		end
		for i = 1, n do
			if free[i] then
				local sum, used, j = 0, 0, i
				while j <= n and free[j] do
					sum += list[j].h
					used = math.max(used, usedAt[j])
					if sum >= sh then
						break
					end
					j += 1
				end
				local fits = sum >= sh
				if not fits and j > n and sum + (p.h - p.nextY) >= sh then
					fits, j = true, n
				end
				local waste = sum - sh
				if fits and (used < bestUsed or (used == bestUsed and waste < bestWaste)) then
					bestP, bestI, bestJ, bestUsed, bestWaste = p, i, j, used, waste
				end
			end
		end
	end
	if bestP == nil then
		return nil, nil
	end
	local p: Page = bestP
	local list = p.shelves
	local atBottom = bestJ == #list
	local y = list[bestI].y
	local sum = 0
	for k = bestJ, bestI, -1 do
		local s = list[k]
		resetShelf(s)
		sum += s.h
		table.remove(list, k)
	end
	local s = freshShelf(p, y, sh)
	table.insert(list, bestI, s)
	if atBottom then
		p.nextY = y + sh
	elseif sum > sh then
		table.insert(list, bestI + 1, freshShelf(p, y + sh, sum - sh))
	end
	return p, s
end

-- A place for a w x h rect (gutter included by the caller) in the shared pages.
local function place(w: number, h: number): (Page?, Shelf?, number, number)
	local sh = math.ceil(h / SHELF_STEP) * SHELF_STEP
	-- an open shelf of this height with room
	for _, p in pages do
		for _, s in p.shelves do
			if s.h == sh and s.x + w <= p.w then
				return p, s, s.x, s.y
			end
		end
	end
	-- a new shelf in a page with room below its last shelf
	for _, p in pages do
		if p.nextY + sh <= p.h then
			local s = freshShelf(p, p.nextY, sh)
			table.insert(p.shelves, s)
			p.nextY += sh
			return p, s, 0, s.y
		end
	end
	-- a new page while under the soft cap
	if #pages < SOFT_PAGES then
		local p = newPage(PAGE_W, PAGE_H, false)
		if p then
			local s = freshShelf(p, 0, sh)
			table.insert(p.shelves, s)
			p.nextY = sh
			return p, s, 0, 0
		end
	end
	-- the rows nobody shows, least recently used first
	local cp, cs = carve(sh)
	if cp and cs then
		return cp, cs, 0, cs.y
	end
	-- everything is on screen: grow up to the hard cap
	if #pages < HARD_PAGES then
		local p = newPage(PAGE_W, PAGE_H, false)
		if p then
			local s = freshShelf(p, 0, sh)
			table.insert(p.shelves, s)
			p.nextY = sh
			return p, s, 0, 0
		end
	end
	return nil, nil, 0, 0
end

-- Frees the shared pages nobody shows and the unused texts with an image of their own (Pixel/ImageMemory: another part
-- is out of image memory). Their words are drawn again when shown. The bytes freed.
function PixelText.reclaim(): number
	local before = dedicatedBytes
	trimDedicated(math.huge)
	local freed = before - dedicatedBytes
	for i = #pages, 1, -1 do
		local p = pages[i]
		local free = true
		for _, s in p.shelves do
			if not shelfFree(s) then
				free = false
				break
			end
		end
		if free then
			for _, s in p.shelves do
				resetShelf(s)
			end
			table.clear(p.shelves)
			table.remove(pages, i)
			freed += bytesOf(p)
			p.image:Destroy()
		end
	end
	return freed
end
ImageMemory.onLow("text", PixelText.reclaim)

-- RGBA for a mask: white where the mask has ink (tinted by ImageColor3), or the palette's colours (rich text, the big
-- words' outline and anti-aliasing).
local function rgbaOf(m: PixelFont.Mask, palette: { number }?): buffer
	local n = m.w * m.h
	local out = buffer.create(n * 4)
	local src = m.px
	if palette then
		for i = 0, n - 1 do
			local v = buffer.readu8(src, i)
			if v ~= 0 then
				local rgb = palette[v] or 0xFFFFFF
				local r = bit32.rshift(rgb, 16) % 256
				local g = bit32.rshift(rgb, 8) % 256
				local b = rgb % 256
				buffer.writeu32(out, i * 4, r + g * 256 + b * 65536 + 0xFF000000)
			end
		end
	else
		for i = 0, n - 1 do
			if buffer.readu8(src, i) ~= 0 then
				buffer.writeu32(out, i * 4, 0xFFFFFFFF)
			end
		end
	end
	return out
end

-- The atlas entry for a mask (cached under key): uploads it on a miss. nil when no image could be made, and whether it
-- was the text's size (bigger than an image can be: trying again will not help).
local function entryFor(key: string, build: () -> PixelFont.Mask, palette: { number }?): (Entry?, boolean)
	clock += 1
	local hit = cache[key]
	if hit and hit.live then
		hit.used = clock
		hit.page.used = clock
		stats.hits += 1
		return hit, false
	end
	stats.misses += 1
	local m = build()
	local w, h = m.w, m.h
	local page: Page?, shelf: Shelf?, x, y = nil, nil, 0, 0
	if not ATLAS or w + GUTTER > PAGE_W or h + GUTTER > PAGE_H then
		if w > MAX_IMAGE or h > MAX_IMAGE then
			stats.failures += 1
			return nil, true
		end
		trimDedicated(w * h * 4)
		page = newPage(w, h, true)
	else
		page, shelf, x, y = place(w + GUTTER, h + GUTTER)
	end
	if page == nil then
		stats.failures += 1
		return nil, false
	end
	local ok = pcall(function()
		(page :: Page).image:WritePixelsBuffer(Vector2.new(x, y), Vector2.new(w, h), rgbaOf(m, palette))
	end)
	if not ok then
		stats.failures += 1
		return nil, false
	end
	stats.uploads += 1
	retryDelay = RETRY_MIN
	local e: Entry = {
		key = key,
		page = page,
		shelf = shelf,
		x = x,
		y = y,
		w = w,
		h = h,
		ox = m.ox,
		oy = m.oy,
		blockW = m.blockW,
		blockH = m.blockH,
		refs = 0,
		used = clock,
		live = true,
		ready = frameNo + READY_FRAMES,
	}
	if shelf then
		table.insert(shelf.entries, e)
		shelf.x += w + GUTTER
	end
	cache[key] = e
	return e, false
end

local function hold(e: Entry?)
	if e then
		e.refs += 1
	end
end

-- Lets go of an entry a frame late (see the header: a rebuilt page finds its words still held).
local function release(e: Entry?)
	if e then
		table.insert(releasing, e)
	end
end

local function lookReady(look: Look): boolean
	local ue = look.ue
	return look.e.ready <= frameNo and (ue == nil or ue.ready <= frameNo)
end

------------------------------------------------------------------ labels

local function boxOf(rec: Rec): (number, number)
	local l = rec.label
	local s = l.Size
	local u = rec.unit
	local w, h
	if s.X.Scale == 0 and (l.AutomaticSize == Enum.AutomaticSize.None or l.AutomaticSize == Enum.AutomaticSize.Y) then
		w = s.X.Offset / u
	else
		w = l.AbsoluteSize.X / math.max(1, PixelRenderer.pixelScale())
	end
	if s.Y.Scale == 0 and l.AutomaticSize == Enum.AutomaticSize.None then
		h = s.Y.Offset / u
	else
		h = l.AbsoluteSize.Y / math.max(1, PixelRenderer.pixelScale())
	end
	return math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5))
end

local function alignName(e: EnumItem): string
	return e.Name
end

local function shown(rec: Rec): string
	local l = rec.label
	-- in the player's language (Locale/Lang; the label normally holds it already: UIKit.localize), but never what a
	-- player wrote (style raw: chat, names)
	local text = if rec.raw then l.Text else Lang.t(l.Text)
	-- MaxVisibleGraphemes counts only once someone has set it (a typing effect); until then the whole text shows
	local n = if rec.typing then l.MaxVisibleGraphemes else -1
	if n >= 0 then
		local cs = PixelFont.graphemes(text)
		if n < #cs then
			text = table.concat(cs, "", 1, n)
		end
	end
	return text
end

local function setLayer(img: ImageLabel, e: Entry, dx: number, dy: number, unit: number)
	img.ImageContent = e.page.content
	img.ImageRectOffset = Vector2.new(e.x, e.y)
	img.ImageRectSize = Vector2.new(e.w, e.h)
	img.Size = UDim2.fromOffset(e.w * unit, e.h * unit)
	img.Position = UDim2.fromOffset(dx * unit, dy * unit)
	img.Visible = true
end

local function applyAlpha(rec: Rec)
	rec.glyphs.ImageTransparency = rec.alpha
	local u = rec.under
	if u then
		u.ImageTransparency = rec.alpha
	end
end

local function applyColors(rec: Rec)
	local k = rec.underShade
	if k then
		local c = rec.color
		rec.underColor = Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
	end
	rec.glyphs.ImageColor3 = if rec.rich then Color3.new(1, 1, 1) else rec.color
	local u = rec.under
	if u then
		u.ImageColor3 = if rec.underBaked then Color3.new(1, 1, 1) else rec.underColor
	end
end

local function rgbOf(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

-- Puts a look on the label (nil: nothing), holding its entries. A label that was showing its own text (no image could
-- be had) hides it again.
local function present(rec: Rec, look: Look?)
	if rec.fallback then
		rec.fallback = false
		retry[rec] = nil
		rec.settingAlpha = true
		rec.label.TextTransparency = 1
		rec.settingAlpha = false
	end
	local e = if look then look.e else nil
	local ue = if look then look.ue else nil
	hold(e)
	release(rec.entry)
	rec.entry = e
	hold(ue)
	release(rec.underEntry)
	rec.underEntry = ue
	local u = rec.under
	if look == nil or e == nil then
		rec.glyphs.Visible = false
		if u then
			u.Visible = false
		end
		return
	end
	rec.rich = look.rich
	setLayer(rec.glyphs, e, look.x0 + e.ox, look.y0 + e.oy, rec.unit)
	if u then
		if rec.kind == "outline" or rec.kind == "title" then
			if ue then
				setLayer(u, ue, look.x0 + ue.ox, look.y0 + ue.oy, rec.unit)
				u.Visible = not rec.rich
			else
				u.Visible = false
			end
		else
			local dx = if rec.kind == "weight" then 0 else 1
			setLayer(u, e, look.x0 + e.ox + dx, look.y0 + e.oy + 1, rec.unit)
			u.Visible = not rec.rich
		end
	end
	applyColors(rec)
	applyAlpha(rec)
end

-- Drops the words a label was waiting to show (and their holds).
local function dropWait(rec: Rec)
	local w = rec.wait
	if w then
		rec.wait = nil
		release(w.e)
		release(w.ue)
	end
	waiting[rec] = nil
end

local markDirty: (rec: Rec) -> ()

-- Draws every label showing its own text again (RETRY_MIN seconds after a failure, doubling while they keep failing).
local function scheduleRetry()
	if retryScheduled then
		return
	end
	retryScheduled = true
	local wait = retryDelay
	retryDelay = math.min(RETRY_MAX, retryDelay * 2)
	task.delay(wait, function()
		retryScheduled = false
		for rec in retry do
			if recs[rec.label] == rec and rec.fallback then
				markDirty(rec)
			else
				retry[rec] = nil
			end
		end
	end)
end

-- No image could be had for a label's words: it shows its own text for now (in the transparency and colour it was
-- drawn in), never nothing, and is drawn again later unless its words are too big for any image (a change of text or
-- size draws it again anyway).
local function toFallback(rec: Rec, tooBig: boolean)
	dropWait(rec)
	release(rec.entry)
	release(rec.underEntry)
	rec.entry, rec.underEntry = nil, nil
	rec.glyphs.Visible = false
	local u = rec.under
	if u then
		u.Visible = false
	end
	if not rec.fallback then
		rec.fallback = true
		stats.fallbacks += 1
		local l = rec.label
		rec.settingAlpha = true
		l.TextColor3 = rec.color
		l.TextTransparency = rec.alpha
		rec.settingAlpha = false
	end
	if tooBig then
		retry[rec] = nil
	else
		retry[rec] = true
		scheduleRetry()
	end
end

-- Draws a label now.
local function draw(rec: Rec)
	stats.draws += 1
	local l = rec.label
	local f = rec.face
	local pitch = PixelFont.pitch(l.LineHeight, f)
	local text = shown(rec)
	local rich = l.RichText and string.find(text, "<", 1, true) ~= nil
	local plain, colors, rgbs = text, nil :: { number }?, nil :: { number }?
	if rich then
		local p, c, r = PixelFont.rich(text)
		plain, colors, rgbs = p, c, r
	end
	local bw, bh = boxOf(rec)
	local lines: { string }
	if l.TextWrapped and bw > 0 then
		lines = PixelFont.wrap(plain, bw, f)
	else
		lines = string.split(plain, "\n")
	end
	if l.TextTruncate ~= Enum.TextTruncate.None and bw > 0 then
		if l.TextWrapped and not rec.autoY then
			local maxLines = math.max(1, (bh - f.em) // pitch + 1)
			if #lines > maxLines then
				local last = lines[maxLines]
				for i = #lines, maxLines + 1, -1 do
					table.remove(lines, i)
				end
				lines[maxLines] = PixelFont.ellipsize(last, bw, f)
			end
		else
			for i, line in lines do
				lines[i] = PixelFont.clip(line, bw, f)
			end
		end
	end
	if rec.autoY then
		local want = #lines * pitch
		local s = l.Size
		if s.Y.Scale ~= 0 or s.Y.Offset ~= want * rec.unit then
			rec.settingSize = true
			l.Size = UDim2.new(s.X.Scale, s.X.Offset, 0, want * rec.unit)
			rec.settingSize = false
		end
		bh = want
	end
	local xa = alignName(l.TextXAlignment)
	local ya = alignName(l.TextYAlignment)
	local lineColors = if colors then PixelFont.lineColors(lines, plain, colors) else nil
	local joined = table.concat(lines, "\n")
	local key = f.name .. "|" .. xa .. "|" .. pitch .. "|" .. rec.tracking .. "|" .. joined
	local palette: { number }? = nil
	if lineColors and rgbs then
		local pal: { number } = { rgbOf(rec.color) }
		for _, rgb in rgbs do
			table.insert(pal, rgb)
		end
		palette = pal
		local parts: { string } = {}
		for _, lc in lineColors do
			table.insert(parts, table.concat(lc, ","))
		end
		key ..= "|rich|" .. table.concat(pal, ",") .. "|" .. table.concat(parts, ";")
	end
	local mask: PixelFont.Mask? = nil
	local function build(): PixelFont.Mask
		local m = PixelFont.mask(lines, { face = f, align = xa, pitch = pitch, tracking = rec.tracking, colors = lineColors })
		mask = m
		return m
	end
	local e: Entry? = nil
	if joined ~= "" then
		local got, tooBig = entryFor(key, build, palette)
		if got == nil then
			-- no image: the label's own text for now, the pixel font again once its words fit
			toFallback(rec, tooBig)
			return
		end
		e = got
	end
	-- the text block's em box (the same for every label that shares the entry)
	local blockW = if e then e.blockW else 0
	local blockH = if e then e.blockH else f.em
	local x0 = 0
	if xa == "Center" then
		x0 = (bw - blockW) // 2
	elseif xa == "Right" then
		x0 = bw - blockW
	end
	local y0 = 0
	if ya == "Center" then
		y0 = (bh - blockH) // 2
	elseif ya == "Bottom" then
		y0 = bh - blockH
	end
	if e == nil then
		dropWait(rec)
		rec.rich = rich
		present(rec, nil)
		return
	end
	local entry: Entry = e
	local ue: Entry? = nil
	local baked = false
	if rec.under and rec.kind == "title" and f == PixelFont.BIG and palette == nil then
		-- the big words: the outline and depth with pixel-art anti-aliasing in the elbows of the steps, in a tone
		-- between the face and the outline turned toward blue-violet (Ramp's shadow tone of the face), baked in
		local c = rec.color
		local tones = Ramp.rgb(c.R, c.G, c.B)
		local aa = tones[2]
		local aaRGB = math.floor(aa[1] * 255 + 0.5) * 65536 + math.floor(aa[2] * 255 + 0.5) * 256 + math.floor(aa[3] * 255 + 0.5)
		local pal = { rgbOf(rec.underColor), aaRGB }
		baked = true
		ue = (entryFor(key .. "|title|" .. pal[1] .. "," .. pal[2], function(): PixelFont.Mask
			local m = mask or build()
			return PixelFont.smooth(m, PixelFont.under(m, "title"))
		end, pal))
	elseif rec.under and (rec.kind == "outline" or rec.kind == "title") then
		local kind = rec.kind
		ue = (entryFor(key .. "|" .. kind, function(): PixelFont.Mask
			return PixelFont.under(mask or build(), kind)
		end, nil))
	end
	rec.underBaked = baked
	local look: Look = { e = entry, ue = ue, x0 = x0, y0 = y0, rich = rich }
	if lookReady(look) then
		dropWait(rec)
		present(rec, look)
		return
	end
	-- its pixels were written just now: the label keeps what it shows until they are on screen (words that were
	-- waiting and are ready by now go up on the way, so a count-up still counts)
	local before = rec.wait
	if before and lookReady(before) then
		present(rec, before)
	end
	dropWait(rec)
	hold(entry)
	hold(ue)
	rec.wait = look
	waiting[rec] = true
end

-- Every frame: what was let go of a frame ago is released, and words waiting for their pixels go up once they are on
-- screen.
local function frameTick()
	frameNo += 1
	for _, e in released do
		e.refs = math.max(0, e.refs - 1)
	end
	table.clear(released)
	releasing, released = released, releasing
	if next(waiting) == nil then
		return
	end
	for rec in waiting do
		local look = rec.wait
		if look == nil or recs[rec.label] ~= rec then
			waiting[rec] = nil
		elseif lookReady(look) then
			waiting[rec] = nil
			rec.wait = nil
			present(rec, look)
			release(look.e)
			release(look.ue)
		end
	end
end
local frameConn: RBXScriptConnection? = nil

local flush: () -> ()

local function step()
	if #dirtyList == 0 then
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		return
	end
	flush()
end

markDirty = function(rec: Rec)
	if dirty[rec] then
		return
	end
	dirty[rec] = true
	table.insert(dirtyList, rec)
	if not flushScheduled then
		flushScheduled = true
		task.defer(function()
			flushScheduled = false
			flush()
		end)
	end
end

flush = function()
	local t0 = os.clock()
	local n = 0
	while #dirtyList > 0 do
		local rec = table.remove(dirtyList, 1) :: Rec
		dirty[rec] = nil
		if recs[rec.label] == rec then
			local ok, err = pcall(function()
				draw(rec)
			end)
			if not ok then
				warn("[PixelText] drawing '" .. string.sub(rec.label.Text, 1, 40) .. "' failed: " .. tostring(err))
			end
		end
		n += 1
		if n >= MIN_DRAWS and (os.clock() - t0) * 1000 > TEXT_MS then
			break
		end
	end
	if #dirtyList > 0 and stepConn == nil then
		stepConn = RunService.Heartbeat:Connect(step)
	end
	if os.clock() - lastSweep > SWEEP_SEC then
		lastSweep = os.clock()
		PixelText.sweep()
	end
end

local function unbind(rec: Rec)
	if recs[rec.label] ~= rec then
		return
	end
	recs[rec.label] = nil
	retry[rec] = nil
	dropWait(rec)
	release(rec.entry)
	release(rec.underEntry)
	rec.entry, rec.underEntry = nil, nil
	for _, c in rec.conns do
		c:Disconnect()
	end
	table.clear(rec.conns)
end

-- Whether a label that has no parent was destroyed (its Parent is locked: setting it, even to nil, fails).
local function destroyed(label: Instance): boolean
	return not pcall(function()
		label.Parent = nil
	end)
end

-- Recounts who holds which entry (keeps the counts honest whatever order labels were redrawn and destroyed in). A
-- label destroyed without its Destroying handler running (deferred events can drop it) lets go here, so its words do
-- not hold atlas rows for the rest of the session.
function PixelText.sweep()
	for label, rec in recs do
		if label.Parent == nil and destroyed(label) then
			unbind(rec)
		end
	end
	for _, e in cache do
		e.refs = 0
	end
	for _, rec in recs do
		if rec.entry then
			rec.entry.refs += 1
		end
		if rec.underEntry then
			(rec.underEntry :: Entry).refs += 1
		end
		local w = rec.wait
		if w then
			w.e.refs += 1
			if w.ue then
				(w.ue :: Entry).refs += 1
			end
		end
	end
	-- the counts are the truth now: what was let go of is already out of them
	table.clear(releasing)
	table.clear(released)
	trimDedicated(0)
end


local function layer(name: string, parent: Instance, z: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.Size = UDim2.fromOffset(0, 0)
	img.Visible = false
	img.ZIndex = z
	img.Parent = parent
	return img
end

local REDRAW = { "Text", "TextXAlignment", "TextYAlignment", "TextWrapped", "TextTruncate", "LineHeight", "RichText", "AbsoluteSize" }

function PixelText.bind(label: TextLabel, style: Style?): boolean
	if not PixelText.available() then
		return false
	end
	local old = recs[label]
	if old then
		unbind(old)
	end
	local s: Style = style or {}
	local kind = s.kind or "plain"
	local rec: Rec = {
		label = label,
		kind = kind,
		unit = s.unit or 1,
		face = if s.face == "big" then PixelFont.BIG else PixelFont.SMALL,
		autoY = s.autoY == true,
		tracking = s.tracking or 0,
		glyphs = nil :: any,
		under = nil,
		color = label.TextColor3,
		underColor = s.under or Color3.new(0, 0, 0),
		underShade = s.underShade,
		alpha = if label.TextTransparency < 1 then label.TextTransparency else 0,
		entry = nil,
		underEntry = nil,
		rich = false,
		underBaked = false,
		conns = {},
		fallback = false,
		typing = false,
		settingAlpha = false,
		settingSize = false,
		raw = s.raw == true,
	}
	if frameConn == nil then
		frameConn = RunService.RenderStepped:Connect(frameTick)
	end
	if rec.autoY then
		label.AutomaticSize = Enum.AutomaticSize.None
	end
	if kind ~= "plain" then
		rec.under = layer("GlyphUnder", label, label.ZIndex)
	end
	rec.glyphs = layer("Glyphs", label, label.ZIndex + 1)
	label.TextTransparency = 1
	recs[label] = rec
	local function redraw()
		if not rec.settingSize then
			markDirty(rec)
		end
	end
	for _, prop in REDRAW do
		table.insert(rec.conns, label:GetPropertyChangedSignal(prop :: any):Connect(redraw))
	end
	table.insert(rec.conns, label:GetPropertyChangedSignal("Size"):Connect(redraw))
	table.insert(rec.conns, label:GetPropertyChangedSignal("MaxVisibleGraphemes"):Connect(function()
		rec.typing = true
		markDirty(rec)
	end))
	table.insert(rec.conns, label:GetPropertyChangedSignal("TextColor3"):Connect(function()
		if rec.settingAlpha then
			return
		end
		local c = label.TextColor3
		if c ~= rec.color then
			rec.color = c
			if rec.rich then
				markDirty(rec)
			else
				applyColors(rec)
			end
		end
	end))
	table.insert(rec.conns, label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		if rec.settingAlpha then
			return
		end
		local a = label.TextTransparency
		if rec.fallback then
			-- the label shows its own text for now: the write is the text's transparency as it is
			rec.alpha = a
			return
		end
		if a < 1 then
			-- a write meant for the text: it fades the glyphs; the label's own text stays hidden
			rec.alpha = a
			applyAlpha(rec)
			rec.settingAlpha = true
			label.TextTransparency = 1
			rec.settingAlpha = false
		end
	end))
	table.insert(rec.conns, label:GetPropertyChangedSignal("ZIndex"):Connect(function()
		rec.glyphs.ZIndex = label.ZIndex + 1
		local u = rec.under
		if u then
			u.ZIndex = label.ZIndex
		end
	end))
	table.insert(rec.conns, label.Destroying:Connect(function()
		unbind(rec)
	end))
	markDirty(rec)
	return true
end

-- Lets a label go: its glyph layers go and it shows its own text again (a language the pixel font has no letters for,
-- UIKit.applyLanguage), in the transparency it was drawn at.
function PixelText.unbind(label: TextLabel)
	local rec = recs[label]
	if rec == nil then
		return
	end
	unbind(rec)
	rec.glyphs:Destroy()
	local u = rec.under
	if u then
		u:Destroy()
	end
	label.TextTransparency = rec.alpha
end

function PixelText.isBound(label: Instance): boolean
	return recs[label] ~= nil
end

function PixelText.setColor(label: TextLabel, c: Color3)
	local rec = recs[label]
	if rec == nil then
		label.TextColor3 = c
		return
	end
	rec.color = c
	rec.settingAlpha = true
	label.TextColor3 = c
	rec.settingAlpha = false
	if rec.rich or rec.underBaked then
		markDirty(rec)
	else
		applyColors(rec)
	end
end

function PixelText.color(label: TextLabel): Color3
	local rec = recs[label]
	return if rec then rec.color else label.TextColor3
end

function PixelText.setUnder(label: TextLabel, c: Color3)
	local rec = recs[label]
	if rec then
		rec.underColor = c
		if rec.underBaked then
			markDirty(rec)
		else
			applyColors(rec)
		end
	end
end

function PixelText.underColor(label: TextLabel): Color3?
	local rec = recs[label]
	return if rec then rec.underColor else nil
end

function PixelText.setTransparency(label: TextLabel, a: number)
	local rec = recs[label]
	if rec == nil then
		label.TextTransparency = a
		return
	end
	rec.alpha = a
	if rec.fallback then
		rec.settingAlpha = true
		label.TextTransparency = a
		rec.settingAlpha = false
	else
		applyAlpha(rec)
	end
end

function PixelText.transparency(label: TextLabel): number
	local rec = recs[label]
	if rec then
		return rec.alpha
	end
	return label.TextTransparency
end

function PixelText.refresh(label: TextLabel)
	local rec = recs[label]
	if rec then
		dirty[rec] = nil
		local i = table.find(dirtyList, rec)
		if i then
			table.remove(dirtyList, i)
		end
		local ok, err = pcall(function()
			draw(rec)
		end)
		if not ok then
			warn("[PixelText] drawing failed: " .. tostring(err))
		end
	end
end

function PixelText.flush()
	while #dirtyList > 0 do
		local rec = table.remove(dirtyList, 1) :: Rec
		dirty[rec] = nil
		if recs[rec.label] == rec then
			pcall(function()
				draw(rec)
			end)
		end
	end
end

function PixelText.stats(): { [string]: number }
	local bytes = 0
	for _, p in pages do
		bytes += bytesOf(p)
	end
	local entries, held = 0, 0
	for _, e in cache do
		entries += 1
		if e.refs > 0 then
			held += 1
		end
	end
	local labels, showingOwn = 0, 0
	for _, rec in recs do
		labels += 1
		if rec.fallback then
			showingOwn += 1
		end
	end
	return {
		pages = #pages,
		pageBytes = bytes,
		dedicatedBytes = dedicatedBytes,
		entries = entries,
		held = held,
		labels = labels,
		draws = stats.draws,
		hits = stats.hits,
		misses = stats.misses,
		uploads = stats.uploads,
		reclaimed = stats.reclaimed,
		failures = stats.failures,
		fallbacks = stats.fallbacks,
		showingOwnText = showingOwn,
	}
end

return PixelText
