--!strict
-- My founder (the "looks" panel; GAME_DESIGN 14.4, docs/ARCHITECTURE.md 10.14): dress the founder every player walks
-- around as, on a live picture of them. Random Bakery's "My baker" screen brought over (the request of 2026-11-20:
-- "Port the entire character customization menu from the bakery game to this game, such accessory colors and other
-- features, along with the accessories it has") in this game's sheets, buttons and words. The bakery's pets and staff
-- dressing stay behind: there are none here.
--
-- The panel keeps its name, "looks": the menu bar's Looks button opens it, and UIKit.openPanel("looks", tab) opens it
-- on a tab ("skin", "style", "bangs", "hair", "eyes", "shirt", "top", "apron", "hat", "face", "neck", "back", "hand",
-- "outfits", "titles"; "pieces", the old panel's argument, means the hats).
-- * The stage (left): the look being tried, drawn by Pixel/Snapshot from CharacterModels.preview in a driftwood
--   window onto the beach (sky, two clouds, the sea, the sand), under the name tag the world shows over the founder
--   (the name, the title worn), at 8 angles 45 degrees apart: the arrows either side or
--   a drag across the stage turn it a step at a time. Each angle is its own picture at one scale with the feet in one
--   place (Snapshot's anchor), so the founder stands still while a hat makes them taller; the angle on show is drawn
--   first, then the thumbnails, then the next angles. A change shows at once: the old picture stays up until the new
--   one is drawn, then the founder hops 2 px.
-- * The tabs (right; two rows on a wide sheet, a strip that scrolls sideways where they would not fit): Skin, Hair
--   style, Bangs, Hair colour (a second colour under it), Eyes (the other eye under it), Shirt, Top, Apron, Hat, Face,
--   Neck, Back, Hand, Outfits and Titles. Under them the option chosen ("Wizard Hat, Blue"), "Not saved yet" at the
--   right while the look differs from the one worn, then a grid of options, each on its own veil, the chosen one gold:
--   pictures of the player's own founder wearing each hair style, bangs, top, apron and piece (a back piece from
--   behind), colour chips for the colours ("None" and "Same" in the main colour with an = on it). Every piece of a slot
--   is there: owned ones first, the rarest first, then the rest dimmed with a padlock, the commonest first; each piece
--   has a bar in its rarity's colour. A tap on a locked one tries it on and says where it comes from; Save keeps the
--   piece worn there before. A piece tab ends with a cell that opens the Store's shop.
-- * The colour row (Top, Apron, Hat, Face, Neck, Back, Hand), over the grid: "Colour", Original (the piece's own colour
--   with an = on it) and the 20 colours of Data/Looks.tints, set in the slot's tint field (Types.Look's hatTint ...). A
--   rainbow piece keeps its colours and the row says so; with nothing worn it says to pick one. The Hand tab's row ends
--   in Turn: each tap turns what is in the hand on to the next of Looks.turns.
-- * Outfits: a + cell saves the look on show (outfit.set; not twice, Tuning.MaxOutfits at most), a tap on one puts it
--   on, and the one worn has an X in its corner (a tap arms it, a second tap deletes it).
-- * Titles: No title, then the titles earned (Wear: title.set, at once), then the ones still to earn, greyed, with
--   what earns them.
-- * The actions: Randomise (only pieces owned), Reset (a plain founder: skin, hair, eyes and shirt kept, everything
--   worn taken off), Cancel (closes, the changes dropped) and Save (look.set with Looks.encode of the look, a piece not
--   owned swapped back for the one worn before: the founder hops in a puff of confetti and the sheet closes). Closed with the X, an unsaved look
--   waits for the next opening and a notice says so.
-- * Pictures follow the world's look: with the pixel filter off (Settings, or a device that cannot run it) or no
--   EditableImages, the stage and the thumbnails are ViewportFrames of the same models at the same angles, as the
--   bakery's screen does. The filter switched while the sheet is open builds it again in the other kind.
-- * A phone: the sheet fills the screen (UIKit); the stage keeps the left, the tabs scroll, "Not saved yet" and the
--   option's name ride on the stage. A narrow portrait screen stacks the stage over the options.
-- The sheet is built once an opening (its root frame survives UIKit.refreshPanel: "Keep") and again only when what it
-- shows changes (the look worn, the pieces owned, the outfits, the titles), so a view arriving every few seconds does
-- not redraw it.
-- API: FounderUI.init(), FounderUI.TABS, FounderUI.working() (the look being tried; nil while shut: for the sims).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local Titles = require(ReplicatedStorage.Shared.Data.Titles)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Snapshot = require(script.Parent.Parent.Pixel.Snapshot)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local StoreUI = require(script.Parent.StoreUI)
local Words = require(script.Parent.Words)

type Look = Types.Look
type Snap = Snapshot.Snap
-- a thumbnail family: the part of the founder kept (parts whose centre is `lo` studs above the feet or higher, `hi` or
-- lower; nil: all of them) and how it is seen (one scale and focus for every option of a tab; scale in art px a stud
-- for a 40 px picture, focusY the height in the picture's middle, focusX how far along the screen's right of the feet)
type Spec = { lo: number?, hi: number?, yaw: number, pitch: number, scale: number, focusY: number, focusX: number? }
-- an option of a look field: its value (a list index, or a piece's id with "" for none), its name, a chip's colour
-- (a palette key), `same` for the "None" / "Same" chips (drawn in the main colour), the piece
type Opt = { value: any, name: string, color: string?, same: boolean?, piece: Cosmetics.Piece? }
-- a tab: the look fields it shows (a second one under its own heading), and whether its options are colour chips,
-- pieces (a shop cell at the end), and the slot its colour row tints
type TabDef = { id: string, text: string, keys: { string }, head: string?, chips: boolean?, pieces: boolean?, tint: string? }
-- a grid cell: option `value` of field `key` ("outfit": a saved outfit, value its number; "" the save and shop cells)
type Cell = {
	key: string,
	value: any,
	button: TextButton,
	veil: Frame,
	image: ImageLabel?,
	view: ViewportFrame?,
	shown: string?,
	extra: TextButton?,
	locked: boolean,
}
type Ui = {
	root: Frame,
	sig: string,
	pixel: boolean, -- pixel pictures (Snapshot), else ViewportFrames
	stage: GuiObject,
	picture: ImageLabel?,
	viewport: ViewportFrame?,
	viewCode: string?,
	pw: number,
	ph: number,
	scale: number,
	anchor: Vector2,
	px: number,
	py: number,
	right: Frame,
	rw: number,
	tabs: { [string]: TextButton }, -- the tab buttons by id
	gridTop: number, -- the grid area (the colour row's top to the actions' gap)
	gridBottom: number,
	gridY: number,
	gridH: number,
	grid: ScrollingFrame?,
	cells: { Cell },
	tintRow: Frame?,
	tintCells: { Cell },
	tintFor: string?,
	cell: number,
	thumb: number,
	cols: number,
	gap: number,
	gridX: number,
	caption: TextLabel?,
	status: TextLabel?,
	save: TextButton?,
	actions: { TextButton },
}

local FounderUI = {}

------------------------------------------------------------------ constants
local PANEL = "looks"
local TITLE = "My founder"
local SHEET_W, SHEET_H = 560, 272
local ANGLES = 8 -- stage views, 45 degrees apart; view 1 is the world's own (Snapshot yaw 0)
local STEP_DEG = 360 / ANGLES
local DRAG_STEP = 14 -- UI px of drag a step
-- How far a founder reaches from the feet on the stage (studs as drawn: up the screen at the world's pitch, down, and
-- out either side), over every piece and angle (CharacterModels.preview: the tall toque and the wizard hat at the top,
-- the long wands and balloons held out at the sides)
local REACH_UP, REACH_DOWN, REACH_SIDE = 5.6, 0.5, 2.4
local STAGE_SCALE_MIN, STAGE_SCALE_MAX = 8, 26
local KEEP_LOOKS = 4 -- stage pictures kept for this many recent looks (going back is instant)
local MAX_CELL, GAP = 48, 3
local LINE = 10
local PRIORITY_VIEW, PRIORITY_THUMB, PRIORITY_NEAR, PRIORITY_FAR = 3, 2, 1, 0
local PITCH = Tuning.CamPitch

local TABS: { TabDef } = {
	{ id = "skin", text = "Skin", keys = { "skin" }, chips = true },
	{ id = "style", text = "Hair style", keys = { "style" } },
	{ id = "bangs", text = "Bangs", keys = { "bangs" } },
	{ id = "hair", text = "Hair colour", keys = { "hair", "hair2" }, head = "Second colour", chips = true },
	{ id = "eyes", text = "Eyes", keys = { "eye", "eye2" }, head = "Other eye", chips = true },
	{ id = "shirt", text = "Shirt", keys = { "shirt" }, chips = true },
	{ id = "top", text = "Top", keys = { "top" }, pieces = true, tint = "top" },
	{ id = "apron", text = "Apron", keys = { "apron" }, tint = "apron" },
	{ id = "hat", text = "Hat", keys = { "hat" }, pieces = true, tint = "hat" },
	{ id = "face", text = "Face", keys = { "face" }, pieces = true, tint = "face" },
	{ id = "neck", text = "Neck", keys = { "neck" }, pieces = true, tint = "neck" },
	-- ("Back@@slot": the back of the body, apart from the Back button, so a language has its own word: Locale/Lang)
	{ id = "back", text = "Back@@slot", keys = { "back" }, pieces = true, tint = "back" },
	{ id = "hand", text = "Hand", keys = { "hand" }, pieces = true, tint = "hand" },
	{ id = "outfits", text = "Outfits", keys = {} },
	{ id = "titles", text = "Titles", keys = {} },
}
local TAB_BY: { [string]: TabDef } = {}
for _, t in TABS do
	TAB_BY[t.id] = t
end
local PIECE_SLOT: { [string]: boolean } = {}
for _, s in Looks.worn do
	PIECE_SLOT[s] = true
end

-- the thumbnail families (a tab's first field; the colours are chips)
local THUMBS: { [string]: Spec } = {
	style = { lo = 2.45, yaw = -10, pitch = PITCH, scale = 13, focusY = 3.45 },
	bangs = { lo = 2.45, yaw = 45, pitch = 8, scale = 18, focusY = 3.4 },
	hat = { lo = 2.45, yaw = 0, pitch = PITCH, scale = 12, focusY = 4.05 },
	face = { lo = 2.3, yaw = 45, pitch = 10, scale = 18, focusY = 3.1 },
	neck = { lo = 1.5, yaw = 35, pitch = 12, scale = 15, focusY = 2.55 },
	top = { hi = 2.6, yaw = 30, pitch = 14, scale = 14, focusY = 1.45 },
	apron = { hi = 2.6, yaw = 45, pitch = 14, scale = 14, focusY = 1.4 },
	back = { lo = 1.0, yaw = 225, pitch = 14, scale = 10.5, focusY = 2.45 },
	hand = { lo = 0.4, yaw = 45, pitch = 14, scale = 10, focusY = 2.0, focusX = 1.0 },
}
local OUTFIT_THUMB: Spec = { yaw = 20, pitch = 14, scale = 9, focusY = 2.35 }

------------------------------------------------------------------ state
local working: Look? = nil -- the look being tried (nil: the sheet is shut)
local kept: Look? = nil -- an unsaved look the X left behind (back on the next opening)
local tab = "skin"
local angle = 1
local seq = -1 -- the opening the state belongs to (UIKit.openCount)
local busy = false -- a request is on its way
local settled = false -- the coming close needs no "not saved" notice (saved or cancelled)
local quiet = false -- (the shop cell: closed for the Store, the look kept without a notice)
local armed: number? = nil -- the saved outfit whose X was tapped once
local outfitsNow: { list: { string }, at: number }? = nil -- the last outfit.set's answer, till the view catches up
local scrollOf: { [string]: number } = {} -- each tab's grid scroll this opening (UI px)
local ui: Ui? = nil
local drag: { x: number, from: number, input: InputObject }? = nil
local conns: { RBXScriptConnection } = {}

local mine: { [string]: Snap } = {} -- every picture this sheet asked for, by key (released on close)
local stageKeys: { [string]: { string } } = {} -- look code -> its stage pictures' keys
local stageOrder: { string } = {} -- look codes, most recent last
local want: { [ImageLabel]: string } = setmetatable({}, { __mode = "k" }) :: any
local bound: { [ImageLabel]: string } = setmetatable({}, { __mode = "k" }) :: any
local waits: { [ImageLabel]: Types.Connection } = setmetatable({}, { __mode = "k" }) :: any

------------------------------------------------------------------ helpers
local function color(key: string): Color3
	return UIKit.color(key)
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end

-- a one-px-grid rectangle
local function rect(parent: Instance, x: number, y: number, w: number, h: number, c: Color3, z: number, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Px"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = c
	f.BackgroundTransparency = alpha or 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function notice(text: string, c: Color3?)
	UIKit.notice(text, c or color("text"), 3.5)
end

local function view(): Types.ClientView?
	return StateClient.view()
end

local function ownedSet(): { [string]: boolean }
	local v = view()
	return if v and v.owned then v.owned else {}
end

local function owns(id: string): boolean
	return Cosmetics.owns(ownedSet(), id)
end

local function wrapAngle(k: number): number
	return (k - 1) % ANGLES + 1
end

-- The look worn now (the view's).
local function savedLook(): Look
	local v = view()
	return if v then table.clone(v.founder) else { skin = 1, hair = 1, style = 1, shirt = 1 }
end

-- `look` with field `key` set to `value` (a piece's "" takes it off).
local function with(look: Look, key: string, value: any): Look
	local l = table.clone(look) :: any
	l[key] = if value == "" then nil else value
	return l :: Look
end

local function num(look: Look, key: string): number
	local v = (look :: any)[key]
	return if type(v) == "number" then v else Looks.extraDefault[key] or 1
end

local function pieceOf(look: Look, slot: string): Cosmetics.Piece?
	local id = (look :: any)[slot]
	return if type(id) == "string" and id ~= "" then Cosmetics.byId[id] else nil
end

-- The look as the server keeps it: defaults dropped, and no tint on an empty slot or a rainbow piece, no apron colour
-- without an apron, no turn without something in the hand (so two looks that draw the same compare the same).
local function tidy(look: Look): Look
	local l = table.clone(look) :: any
	for _, slot in Looks.worn do
		if l[slot] == "" then
			l[slot] = nil
		end
		local p = pieceOf(l, slot)
		if p == nil or p.rainbow then
			l[Looks.tintField[slot]] = nil
		end
	end
	if num(l, "apron") == 1 then
		l.apronTint = nil
	end
	if l.hand == nil then
		l.turn = nil
	end
	for _, k in Looks.extra do
		if l[k] == Looks.extraDefault[k] then
			l[k] = nil
		end
	end
	for _, f in Looks.tintFields do
		if l[f] == 1 then
			l[f] = nil
		end
	end
	return l :: Look
end

local function codeOf(look: Look): string
	return Looks.encode(tidy(look) :: any)
end

-- The look Save sends: tidied, a piece not owned swapped back for the one worn there now with its colour (their ids
-- returned).
local function cleaned(look: Look): (Look, { string })
	local l = table.clone(look) :: any
	local now = savedLook() :: any
	local left: { string } = {}
	for _, slot in Looks.worn do
		local id = l[slot]
		if type(id) == "string" and id ~= "" and not owns(id) then
			table.insert(left, id)
			local back = now[slot]
			local f = Looks.tintField[slot]
			l[slot] = if type(back) == "string" and back ~= "" and owns(back) then back else nil
			l[f] = now[f]
			if slot == "hand" then
				l.turn = now.turn
			end
		end
	end
	return tidy(l :: Look), left
end

local function changed(): boolean
	local w = working
	return w ~= nil and codeOf(w) ~= codeOf(savedLook())
end

-- A look from a code (Looks.decode), its indices kept inside the lists; nil for words that are no look.
local function lookFrom(code: string): Look?
	local d = Looks.decode(code)
	if d == nil then
		return nil
	end
	local function clampTo(key: string, lo: number, n: number)
		local v = d[key]
		d[key] = math.clamp(math.floor(if type(v) == "number" then v else lo), lo, n)
	end
	clampTo("skin", 1, #Looks.skin)
	clampTo("hair", 1, #Looks.hair)
	clampTo("style", 1, #Looks.styles)
	clampTo("shirt", 1, #Looks.shirt)
	clampTo("bangs", 1, #Looks.bangs)
	clampTo("hair2", 0, #Looks.hair)
	clampTo("eye", 1, #Looks.eyes)
	clampTo("eye2", 0, #Looks.eyes)
	clampTo("apron", 1, #Looks.aprons)
	clampTo("turn", 1, #Looks.turns)
	for _, slot in Looks.worn do
		local p = pieceOf(d :: any, slot)
		if p == nil or p.slot ~= slot then
			d[slot] = nil
		end
	end
	return d :: any
end

------------------------------------------------------------------ options
local function chipList(list: { string }, names: { string }): { Opt }
	local out: { Opt } = {}
	for i, c in list do
		table.insert(out, { value = i, name = names[i] or c, color = c })
	end
	return out
end

local RARITY_ORDER = function(a: Cosmetics.Piece, b: Cosmetics.Piece, rarestFirst: boolean): boolean
	if a.rarity ~= b.rarity then
		return if rarestFirst then a.rarity > b.rarity else a.rarity < b.rarity
	end
	return a.name < b.name
end

-- A field's options, in the order the grid shows them.
local function optionsOf(key: string): { Opt }
	if key == "skin" then
		return chipList(Looks.skin, Looks.names.skin)
	elseif key == "hair" then
		return chipList(Looks.hair, Looks.names.hair)
	elseif key == "hair2" then
		local out = chipList(Looks.hair, Looks.names.hair)
		table.insert(out, 1, { value = 0, name = "None", same = true })
		return out
	elseif key == "eye" then
		return chipList(Looks.eyes, Looks.names.eyes)
	elseif key == "eye2" then
		local out = chipList(Looks.eyes, Looks.names.eyes)
		table.insert(out, 1, { value = 0, name = "Same", same = true })
		return out
	elseif key == "shirt" then
		return chipList(Looks.shirt, Looks.names.shirt)
	elseif key == "style" then
		local out: { Opt } = {}
		for i in Looks.styles do
			table.insert(out, { value = i, name = Looks.names.styles[i] })
		end
		return out
	elseif key == "bangs" then
		local out: { Opt } = {}
		for i, o in Looks.bangs do
			table.insert(out, { value = i, name = o.name })
		end
		return out
	elseif key == "apron" then
		local out: { Opt } = {}
		for i, o in Looks.aprons do
			table.insert(out, { value = i, name = o.name, color = o.color })
		end
		return out
	end
	-- a slot's pieces: none, the ones owned (the rarest first), then the rest (the commonest first)
	local have: { Cosmetics.Piece } = {}
	local rest: { Cosmetics.Piece } = {}
	local owned = ownedSet()
	local pool: { Cosmetics.Piece } = Cosmetics.bySlot[key] or {}
	for _, p in pool do
		if Cosmetics.owns(owned, p.id) then
			table.insert(have, p)
		else
			table.insert(rest, p)
		end
	end
	table.sort(have, function(a, b): boolean
		return RARITY_ORDER(a, b, true)
	end)
	table.sort(rest, function(a, b): boolean
		return RARITY_ORDER(a, b, false)
	end)
	local out: { Opt } = { { value = "", name = "None" } }
	for _, list in { have, rest } do
		for _, p in list do
			table.insert(out, { value = p.id, name = p.name, piece = p })
		end
	end
	return out
end

-- The value a field holds in `look` ("" for an empty slot).
local function valueOf(look: Look, key: string): any
	if PIECE_SLOT[key] then
		local id = (look :: any)[key]
		return if type(id) == "string" then id else ""
	end
	return num(look, key)
end

local function optName(key: string, value: any): string
	for _, o in optionsOf(key) do
		if o.value == value then
			return o.name
		end
	end
	return ""
end

-- Where a piece not owned comes from, for the notice when it is tried on.
local function whereFrom(p: Cosmetics.Piece): string
	local src = p.src
	if src == "shop" then
		return "Sold in the shop now and then."
	elseif src == "track" then
		return "A pass track reward."
	elseif src == "trackp" then
		return "A premium track reward."
	elseif src == "vip" then
		return "Comes with VIP."
	elseif src == "starter" then
		return "Comes with the Starter Pack."
	end
	return "Not yours yet."
end

------------------------------------------------------------------ outfits
local function outfitList(): { string }
	local o = outfitsNow
	if o and os.clock() - o.at < 5 then
		return o.list
	end
	local v = view()
	local list = if v then v.outfits else nil
	return if type(list) == "table" then list else {}
end

-- The saved outfit the look on show is, nil when it is none of them.
local function wornOutfit(): number?
	local w = working
	if w == nil then
		return nil
	end
	local code = codeOf(w)
	for i, c in outfitList() do
		local l = lookFrom(c)
		if l and codeOf(l) == code then
			return i
		end
	end
	return nil
end

------------------------------------------------------------------ captions
-- What the tab has chosen: "Brown and Snow", "Wizard Hat, Blue", "Magic Wand, Tipped forward", "Outfit 2".
local function captionText(): string
	local w = working
	if w == nil then
		return ""
	end
	if tab == "titles" then
		local v = view()
		local t = if v then Titles.byId[v.title or ""] else nil
		return if t then Lang.fmt("Wearing: {name}", { name = t.name }) else Lang.t("No title")
	elseif tab == "outfits" then
		local i = wornOutfit()
		return if i
			then Lang.fmt("Outfit {n}", { n = i })
			else Lang.fmt("Your outfits: {n}/{max}", { n = #outfitList(), max = Tuning.MaxOutfits })
	end
	local t = TAB_BY[tab]
	local k1 = t.keys[1]
	local v1 = valueOf(w, k1)
	local text = Lang.t(optName(k1, v1))
	local k2 = t.keys[2]
	if k2 then
		local v2 = valueOf(w, k2)
		if v2 ~= 0 then
			text = Lang.fmt("{a} and {b}", { a = text, b = Lang.t(optName(k2, v2)) })
		end
	end
	local slot = t.tint
	if slot then
		local p = if PIECE_SLOT[slot] then pieceOf(w, slot) else nil
		local worn = if slot == "apron" then num(w, "apron") > 1 else p ~= nil
		if p and not owns(p.id) then
			text = Lang.fmt("{name} (locked)", { name = text })
		end
		local ti = num(w, Looks.tintField[slot])
		if worn and not (p and p.rainbow) and ti > 1 and Looks.tints[ti] then
			text ..= ", " .. Lang.t(Looks.tints[ti].name)
		end
		if slot == "hand" and p and num(w, "turn") > 1 and Looks.turns[num(w, "turn")] then
			text ..= ", " .. Lang.t(Looks.turns[num(w, "turn")].name)
		end
	end
	return text
end

local function paintCaption()
	local u = ui
	if u == nil then
		return
	end
	local cap = u.caption
	if cap then
		UIKit.setText(cap, captionText())
	end
	local st = u.status
	if st then
		UIKit.setText(st, if changed() then "Not saved yet" else "")
	end
end

------------------------------------------------------------------ pictures
-- Whether the sheet draws pixel pictures: while the world wears the pixel filter and EditableImages work.
local function pixelPictures(): boolean
	local ok, tier = pcall(PixelRenderer.tier)
	return Snapshot.available() and not (ok and tier == "off")
end

local function hop(g: GuiObject, base: UDim2, dy: number, t: number)
	g.Position = base - UDim2.fromOffset(0, dy)
	UIKit.tween(g, t, { Position = base })
end

local function hopStage(dy: number, t: number)
	local u = ui
	if u == nil then
		return
	end
	local g: GuiObject? = u.picture or u.viewport
	if g then
		hop(g, UDim2.fromOffset(u.px, u.py), dy, t)
	end
end

-- Shows `snap` on `label` once it is drawn; till then the label keeps what it shows (a blank label shows it at once).
-- `hopIt`: the stage's founder hops when the new picture swaps in.
local function bindWhenReady(label: ImageLabel, snap: Snap, hopIt: boolean)
	local w = waits[label]
	if w then
		w:Disconnect()
		waits[label] = nil
	end
	want[label] = snap.key
	if bound[label] == snap.key then
		return
	end
	if snap.ready or bound[label] == nil then
		Snapshot.show(label, snap)
		bound[label] = snap.key
		if snap.ready and hopIt then
			hopStage(2, 0.16)
		end
		return
	end
	waits[label] = snap.Ready:Once(function()
		waits[label] = nil
		if want[label] == snap.key and label.Parent ~= nil then
			Snapshot.show(label, snap)
			bound[label] = snap.key
			if hopIt then
				hopStage(2, 0.16)
			end
		end
	end)
end

local function forgetLabels()
	for label, c in waits do
		c:Disconnect()
		waits[label] = nil
	end
	table.clear(want)
	table.clear(bound)
end

local function releaseAll()
	forgetLabels()
	for key in mine do
		Snapshot.release(key)
	end
	table.clear(mine)
	table.clear(stageKeys)
	table.clear(stageOrder)
end

-- The founder with only the parts a family keeps.
local function cropped(look: Look, spec: Spec): Model
	local m = CharacterModels.preview(look)
	local lo, hi = spec.lo, spec.hi
	if lo or hi then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local y = d.Position.Y
				if (lo and y < lo) or (hi and y > hi) then
					d:Destroy()
				end
			end
		end
	end
	return m
end

-- The look a thumbnail shows: the look being tried wearing `value`, with what the picture does not show taken off
-- (so its key changes only when something it shows changes). Every piece in its own colours, held as it is made: the
-- colour row and Turn change the stage, never the thumbnails.
local function thumbLook(key: string, value: any): Look
	local w = working or savedLook()
	local l = with(w, key, value) :: any
	for _, f in Looks.tintFields do
		l[f] = nil
	end
	l.turn = nil
	if key ~= "back" then
		l.back = nil
	end
	if key ~= "hand" then
		l.hand = nil
	end
	if key ~= "neck" and key ~= "hand" then
		l.neck = nil
	end
	if key == "style" or key == "bangs" or key == "face" then
		l.hat, l.top, l.apron = nil, nil, nil
	elseif key == "hat" then
		l.apron, l.top = nil, nil
	elseif key == "apron" then
		l.hat, l.face, l.top = nil, nil, nil
	elseif key == "top" then
		l.hat, l.face, l.apron = nil, nil, nil
	elseif key == "back" or key == "neck" then
		l.hat, l.face, l.apron = nil, nil, nil
	elseif key == "hand" then
		l.hat = nil
	end
	return tidy(l :: Look)
end

local function specSnap(prefix: string, look: Look, spec: Spec, size: number, priority: number): Snap?
	local snapKey = prefix .. size .. ":" .. Looks.encode(look :: any)
	local s = spec.scale * size / 40
	local anchor = Vector2.new(math.floor(size / 2 - (spec.focusX or 0) * s + 0.5), math.floor(size / 2 + spec.focusY * math.cos(math.rad(spec.pitch)) * s + 0.5))
	local snap = Snapshot.get(snapKey, function(): Instance?
		return cropped(look, spec)
	end, { size = size, scale = s, anchor = anchor, yaw = spec.yaw, pitch = spec.pitch, priority = priority })
	if snap then
		mine[snapKey] = snap
	end
	return snap
end

-- A ViewportFrame's camera: looking at `focus` from the world's side turned `yaw` degrees, `pitch` down, far enough
-- that `viewH` studs fill its height (a narrow field of view: nearly the pixel pictures' flat projection).
local VIEW_FOV = 20
local function viewCam(yaw: number, pitch: number, focus: Vector3, viewH: number): CFrame
	local a, p = math.rad(Tuning.CamYaw - yaw), math.rad(pitch)
	local back = Vector3.new(math.sin(a) * math.cos(p), math.sin(p), math.cos(a) * math.cos(p))
	local dist = (viewH / 2) / math.tan(math.rad(VIEW_FOV / 2))
	return CFrame.lookAt(focus + back * dist, focus)
end

local function viewportOf(parent: Instance, w: number, h: number, model: Model, yaw: number, pitch: number, focus: Vector3, viewH: number, z: number): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.Name = "View"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.fromOffset(w, h)
	vf.Ambient = Color3.fromRGB(170, 160, 175)
	vf.LightColor = Color3.fromRGB(255, 248, 235)
	vf.LightDirection = Vector3.new(-1, -1.5, -0.6)
	vf.ZIndex = z
	local cam = Instance.new("Camera")
	cam.FieldOfView = VIEW_FOV
	cam.CFrame = viewCam(yaw, pitch, focus, viewH)
	cam.Parent = vf
	vf.CurrentCamera = cam
	model.Parent = vf
	vf.Parent = parent
	return vf
end

-- A thumbnail as a ViewportFrame in its cell (the classic look), `code` naming the look it shows; a cell's old one
-- goes.
local function thumbView(c: Cell, model: Model, spec: Spec, code: string, dim: boolean)
	local u = ui
	if u == nil then
		model:Destroy()
		return
	end
	local old = c.view
	if old then
		old:Destroy()
	end
	local s = spec.scale * u.thumb / 40
	-- (the focus moved along the camera's right: the pixel picture's focusX)
	local a, fx = math.rad(Tuning.CamYaw - spec.yaw), spec.focusX or 0
	local focus = Vector3.new(math.cos(a) * fx, spec.focusY, -math.sin(a) * fx)
	local vf = viewportOf(c.button, u.thumb, u.thumb, model, spec.yaw, spec.pitch, focus, u.thumb / s, 4)
	vf.Position = UDim2.fromOffset((u.cell - u.thumb) // 2, (u.cell - u.thumb) // 2)
	vf.ImageTransparency = if dim then 0.45 else 0
	c.view, c.shown = vf, code
end

------------------------------------------------------------------ the stage
local function stageSnap(k: number, priority: number): Snap?
	local u = ui
	local w = working
	if u == nil or w == nil then
		return nil
	end
	local look = tidy(w)
	local code = Looks.encode(look :: any)
	local key = string.format("founder:stage:%d:%dx%d:%s@%d", u.scale, u.pw, u.ph, code, k)
	local list = stageKeys[code]
	if list == nil then
		list = {}
		stageKeys[code] = list
	end
	if not table.find(list, key) then
		table.insert(list, key)
	end
	local snap = Snapshot.get(key, function(): Instance?
		return CharacterModels.preview(look)
	end, { w = u.pw, h = u.ph, scale = u.scale, anchor = u.anchor, yaw = (k - 1) * STEP_DEG, priority = priority })
	if snap then
		mine[key] = snap
	end
	return snap
end

-- Stage pictures no longer wanted: pending ones of every other look stop (they would only hold up the one on show),
-- and looks older than the last KEEP_LOOKS go.
local function trimStage(code: string)
	local i = table.find(stageOrder, code)
	if i then
		table.remove(stageOrder, i)
	end
	table.insert(stageOrder, code)
	local u = ui
	local showing = if u and u.picture then bound[u.picture :: ImageLabel] else nil
	for n, c in stageOrder do
		if c ~= code then
			local old = n <= #stageOrder - KEEP_LOOKS
			local keys: { string } = stageKeys[c] or {}
			for _, key in keys do
				local snap = if key ~= showing then mine[key] else nil
				if snap and (old or not snap.ready) then
					Snapshot.release(key)
					mine[key] = nil
				end
			end
		end
	end
	while #stageOrder > KEEP_LOOKS do
		local c = table.remove(stageOrder, 1) :: string
		stageKeys[c] = nil
	end
end

-- The look on the stage at the angle on show. `hopIt`: a new look (the founder hops as it swaps in), not a turn.
local function showStage(hopIt: boolean)
	local u = ui
	local w = working
	if u == nil or w == nil then
		return
	end
	local look = tidy(w)
	local code = Looks.encode(look :: any)
	local label = u.picture
	if label then
		local snap = stageSnap(angle, PRIORITY_VIEW)
		if snap then
			bindWhenReady(label, snap, hopIt)
		end
		-- the neighbouring views next (a turn is instant), the rest after the thumbnails
		for _, d in { 1, -1, 2, -2, 3, -3, 4 } do
			stageSnap(wrapAngle(angle + d), if math.abs(d) == 1 then PRIORITY_NEAR else PRIORITY_FAR)
		end
		trimStage(code)
		return
	end
	-- the classic look: the feet where the pixel picture puts them, the same scale
	local focus = Vector3.new(0, (u.anchor.Y - u.ph / 2) / u.scale / math.cos(math.rad(PITCH)), 0)
	local old = u.viewport
	local cam = if old then old.CurrentCamera else nil
	if old and cam and u.viewCode == code then
		cam.CFrame = viewCam((angle - 1) * STEP_DEG, PITCH, focus, u.ph / u.scale)
		return
	end
	if old then
		old:Destroy()
	end
	local vf = viewportOf(u.stage, u.pw, u.ph, CharacterModels.preview(look), (angle - 1) * STEP_DEG, PITCH, focus, u.ph / u.scale, 5)
	vf.Name = "Founder"
	vf.Position = UDim2.fromOffset(u.px, u.py)
	u.viewport, u.viewCode = vf, code
	if hopIt then
		hopStage(2, 0.16)
	end
end

local function setAngle(k: number)
	local a = wrapAngle(k)
	if a ~= angle then
		angle = a
		showStage(false)
	end
end

local function disconnectAll()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	drag = nil
end

local function isPress(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

local function connectDrag(stage: GuiButton)
	table.insert(
		conns,
		stage.InputBegan:Connect(function(input: InputObject)
			if isPress(input) then
				drag = { x = input.Position.X, from = angle, input = input }
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local d = drag
			if d == nil then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == d.input) then
				local dx = (input.Position.X - d.x) / math.max(1, UIKit.P())
				setAngle(d.from + math.floor(dx / DRAG_STEP + 0.5))
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if isPress(input) then
				drag = nil
			end
		end)
	)
end

-- A little cloud of stepped rows (white, its underside a step bluer), `w` px wide at (x, y).
local function cloud(parent: Instance, x: number, y: number, w: number, z: number)
	local white, under = color("white"), lighter(color("sky_day"), 0.55)
	local a = math.max(4, w // 3)
	rect(parent, x + a, y, a, 1, white, z)
	rect(parent, x + a - 2, y + 1, a + 5, 1, white, z)
	rect(parent, x + 1, y + 2, w - 2, 1, white, z)
	rect(parent, x, y + 3, w, 1, white, z)
	rect(parent, x + 1, y + 4, w - 2, 1, under, z)
end

-- The stage: a driftwood window onto the beach, the founder standing on the sand, the turning arrows either side.
-- `statusTop`: "Not saved yet" rides on the glass's top; `captionFoot`: the option's name on the sand.
local function buildStage(parent: Instance, x: number, y: number, w: number, h: number, statusTop: boolean, captionFoot: boolean)
	local u = ui :: Ui
	local stage = Instance.new("TextButton")
	stage.Name = "Stage"
	stage.Text = ""
	stage.AutoButtonColor = false
	stage.BackgroundTransparency = 1
	stage.BorderSizePixel = 0
	stage.Position = UDim2.fromOffset(x, y)
	stage.Size = UDim2.fromOffset(w, h)
	stage.ZIndex = 2
	stage.Parent = parent
	-- the frame: an outline a darker step of the driftwood (UIKit.plate), the wood lit along its top and left and
	-- shaded along its right and bottom, a dark line round the glass
	local F = 4
	local frame = UIKit.plate(stage, UDim2.fromScale(1, 1), nil, color("frame"), 0, 2)
	frame.Name = "WindowFrame"
	frame.ZIndex = 1
	rect(stage, 2, 1, w - 4, 1, color("frame_hi"), 2)
	rect(stage, 1, 2, 1, h - 4, color("frame_hi"), 2)
	rect(stage, 2, h - 2, w - 4, 1, color("frame_lo"), 2)
	rect(stage, w - 2, 2, 1, h - 4, color("frame_lo"), 2)
	local gw, gh = w - 2 * F, h - 2 * F
	rect(stage, F - 1, F - 1, gw + 2, 1, color("frame_dark"), 2)
	rect(stage, F - 1, F + gh, gw + 2, 1, color("frame_dark"), 2)
	rect(stage, F - 1, F, 1, gh, color("frame_dark"), 2)
	rect(stage, F + gw, F, 1, gh, color("frame_dark"), 2)
	-- the glass: sky (paler toward the sea), two clouds, the sea with a light line where it meets the sky and foam at
	-- the shore, then the sand with a few darker grains
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.BackgroundTransparency = 1
	glass.ClipsDescendants = true
	glass.Position = UDim2.fromOffset(F, F)
	glass.Size = UDim2.fromOffset(gw, gh)
	glass.ZIndex = 2
	glass.Parent = stage
	local horizon = math.floor(gh * 0.47)
	local sandY = math.floor(gh * 0.64)
	local sky = color("sky_day")
	rect(glass, 0, 0, gw, horizon, sky, 2)
	rect(glass, 0, horizon - math.max(4, horizon // 3), gw, math.max(4, horizon // 3), lighter(sky, 0.18), 2)
	rect(glass, 0, horizon - math.max(2, horizon // 7), gw, math.max(2, horizon // 7), lighter(sky, 0.34), 2)
	cloud(glass, math.floor(gw * 0.12), math.floor(horizon * 0.22) + (if statusTop then 8 else 18), math.max(12, gw // 6), 3)
	cloud(glass, math.floor(gw * 0.62), math.floor(horizon * 0.48), math.max(10, gw // 8), 3)
	rect(glass, 0, horizon, gw, sandY - horizon, color("water"), 2)
	rect(glass, 0, horizon, gw, 1, color("shallow"), 3)
	rect(glass, 0, sandY - 3, gw, 2, color("shallow"), 3)
	rect(glass, 0, sandY - 1, gw, 1, color("foam"), 3)
	rect(glass, 0, sandY, gw, gh - sandY, color("sand"), 2)
	local grains = { { 0.09, 0.3 }, { 0.27, 0.72 }, { 0.48, 0.18 }, { 0.71, 0.55 }, { 0.88, 0.25 }, { 0.17, 0.88 }, { 0.62, 0.9 }, { 0.93, 0.8 } }
	for _, g in grains do
		local gx, gy = math.floor(gw * g[1]), sandY + 2 + math.floor((gh - sandY - 4) * g[2])
		rect(glass, gx, gy, 2, 1, color("sand_dark"), 3)
	end
	-- the founder's picture: the largest scale whose tallest look fits over the feet and whose widest fits between the
	-- arrows
	-- (higher up the sand when the option's name, two lines at most, sits under the feet)
	local feetY = F + sandY + math.floor((gh - sandY) * (if captionFoot then 0.3 else 0.55))
	local aw = 15
	local headroom = if statusTop then 12 else 3
	local s = STAGE_SCALE_MAX
	while s > STAGE_SCALE_MIN do
		local up = math.ceil(REACH_UP * s) + 2
		local across = 2 * (math.ceil(REACH_SIDE * s) + 2)
		if up <= feetY - F - headroom and across <= w - 2 * aw - 2 * F then
			break
		end
		s -= 1
	end
	local foot = math.ceil(REACH_DOWN * s) + 2
	local half = math.ceil(REACH_SIDE * s) + 2
	local pw, ph = 2 * half, math.ceil(REACH_UP * s) + 2 + foot
	local cx = w // 2
	-- a soft shadow under the feet
	local sw = math.max(8, math.floor(1.8 * s))
	local sh = math.max(3, math.floor(0.4 * s))
	sw -= sw % 2
	rect(stage, cx - sw // 2 + sw // 6, feetY - sh // 2, sw - 2 * (sw // 6), sh, color("ink"), 3, 0.82)
	rect(stage, cx - sw // 2, feetY - sh // 2 + 1, sw, math.max(1, sh - 2), color("ink"), 3, 0.82)
	u.stage = stage
	u.scale = s
	u.pw, u.ph = pw, ph
	u.anchor = Vector2.new(half, ph - foot)
	u.px, u.py = cx - half, feetY - (ph - foot)
	if u.pixel then
		local im = Instance.new("ImageLabel")
		im.Name = "Founder"
		im.BackgroundTransparency = 1
		im.BorderSizePixel = 0
		im.Size = UDim2.fromOffset(pw, ph)
		im.Position = UDim2.fromOffset(u.px, u.py)
		im.ResampleMode = Enum.ResamplerMode.Pixelated
		im.ZIndex = 5
		im.Parent = stage
		u.picture = im
	end
	-- the turning arrows, either side of the founder's middle
	local ay = math.clamp(feetY - math.floor(3.4 * s * 0.5) - aw // 2, F + headroom, h - aw - F)
	for _, side in { -1, 1 } do
		local b = UIKit.button(stage, "", UDim2.fromOffset(aw, aw), UDim2.fromOffset(if side < 0 then F + 1 else w - aw - F - 1, ay), function()
			setAngle(angle + side)
		end, { name = if side < 0 then "TurnLeft" else "TurnRight", ghost = true })
		b.ZIndex = 6
		PixelSprites.image(b, if side < 0 then "arrow_left" else "arrow_right", UDim2.fromOffset(1, 1), 7)
	end
	if statusTop then
		local st = UIKit.text(stage, "", UDim2.fromOffset(gw - 4, LINE), UDim2.fromOffset(F + 2, F + 1), { x = "center", color = color("pink"), kind = "outline", z = 7, name = "Status" })
		u.status = st
	else
		-- the name tag every player sees over the founder: the name in white, the title worn under it in its colour
		local v = view()
		local t = if v then Titles.byId[v.title or ""] else nil
		UIKit.text(stage, Players.LocalPlayer.DisplayName, UDim2.fromOffset(gw - 4, LINE), UDim2.fromOffset(F + 2, F + 4), { x = "center", kind = "outline", color = color("white"), z = 7, name = "TagName" })
		if t then
			UIKit.text(stage, t.name, UDim2.fromOffset(gw - 4, LINE), UDim2.fromOffset(F + 2, F + 4 + LINE), { x = "center", kind = "outline", color = color(t.color), z = 7, name = "TagTitle" })
		end
	end
	if captionFoot then
		local cap = UIKit.text(stage, "", UDim2.fromOffset(gw - 4, 2 * LINE), UDim2.fromOffset(F + 2, h - F - 2 * LINE - 1), { x = "center", y = "bottom", wrap = true, kind = "outline", z = 7, name = "Choice" })
		u.caption = cap
	end
	connectDrag(stage)
end

------------------------------------------------------------------ the grid
-- A colour chip in a box `cell` px square: a rounded swatch with a 1 px outline a darker step of its colour, its top
-- rows lit and its bottom rows shaded (lit from the top left), a glint. `same`: an = on it (the "None" / "Same" chips).
local function chip(parent: Instance, cell: number, c: Color3, same: boolean?)
	local side = math.max(10, math.floor(cell * 0.62 + 0.5))
	side -= side % 2
	local x0 = (cell - side) // 2
	local y0 = math.max(0, x0 - 1)
	local base = UIKit.plate(parent, UDim2.fromOffset(side, side), UDim2.fromOffset(x0, y0), c, 0, 2)
	base.Name = "Chip"
	base.ZIndex = 3
	local light, dark = lighter(c, 0.22), darker(c, 0.16)
	local lightRows, darkRows = math.max(1, side // 5), math.max(2, side // 5)
	for r = 1, lightRows do
		local k = if r == 1 then 2 else 1
		rect(base, k, r, side - 2 * k, 1, light, 4)
	end
	for r = 1, darkRows do
		local k = if r == 1 then 2 else 1
		rect(base, k, side - 1 - r, side - 2 * k, 1, dark, 4)
	end
	rect(base, 3, 2, math.max(2, side // 6), 1, lighter(c, 0.5), 5)
	if same then
		local mw = math.max(4, side // 3)
		mw -= mw % 2
		local mx, my = (side - mw) // 2, side // 2 - 2
		local ink = if (c.R + c.G + c.B) > 1.6 then color("ink") else color("white")
		rect(base, mx, my, mw, 1, ink, 6)
		rect(base, mx, my + 2, mw, 1, ink, 6)
	end
end

local function cellPaint(c: Cell, on: boolean, hot: boolean)
	if c.key == "shop" then
		-- (the shop's cell: an orange veil)
		UIKit.setPlate(c.veil, color("button_warn"), if hot then 0.55 else 0.7)
		return
	end
	local tint: Color3? = if on then color("accent") else nil
	local alpha = if on then 0.45 elseif hot then 0.8 else UIKit.ROW_ALPHA
	UIKit.setPlate(c.veil, tint or color("veil"), alpha)
	c.button:SetAttribute("Selected", on)
end

local function isChosen(c: Cell): boolean
	local w = working
	if w == nil then
		return false
	end
	if c.key == "outfit" then
		return c.value == wornOutfit()
	elseif c.key == "" or c.key == "shop" then
		return false
	elseif c.key == "tint" then
		local slot = TAB_BY[tab].tint
		return slot ~= nil and num(w, Looks.tintField[slot]) == c.value
	end
	return valueOf(w, c.key) == c.value
end

local paintTints: () -> ()

local function paintCells()
	local u = ui
	if u == nil then
		return
	end
	for _, c in u.cells do
		local on = isChosen(c)
		cellPaint(c, on, false)
		local extra = c.extra
		if extra then
			extra.Visible = on
		end
	end
	paintTints()
end

-- A cell button at (x, y), `size` px square, on its own veil (a mouse over it lightens it and names it in the
-- caption); its words for the sims and screen readers (the pixels draw it).
local function cellButton(holder: Instance, name: string, text: string, x: number, y: number, size: number): (TextButton, Frame)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = Lang.t(text)
	b.TextTransparency = 1
	b.Font = Enum.Font.Arcade
	b.TextSize = 8
	b.AutoButtonColor = true
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.fromOffset(x, y)
	b.ZIndex = 3
	b.Parent = holder
	local veil = UIKit.row(b, UDim2.fromScale(1, 1), nil)
	veil.Name = "Veil"
	veil.ZIndex = 1
	return b, veil
end

local function hoverable(c: Cell, text: string)
	local b = c.button
	b.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			cellPaint(c, isChosen(c), true)
			local u = ui
			if u and u.caption then
				UIKit.setText(u.caption :: TextLabel, text)
			end
		end
	end)
	b.MouseLeave:Connect(function()
		cellPaint(c, isChosen(c), false)
		paintCaption()
	end)
end

local onDraft: (refresh: boolean) -> ()
local rebuild: () -> ()
local regrid: () -> ()

-- Thumbnails of the cells on show for the look being tried: pixel pictures, or the views.
local function refreshThumbs()
	local u = ui
	if u == nil then
		return
	end
	for _, c in u.cells do
		if c.key == "outfit" then
			local code = outfitList()[c.value]
			local look = if code then lookFrom(code) else nil
			if look then
				local t = tidy(look)
				local im = c.image
				if im then
					local snap = specSnap("founder:outfit:", t, OUTFIT_THUMB, u.thumb, PRIORITY_THUMB)
					if snap then
						bindWhenReady(im, snap, false)
					end
				else
					local enc = Looks.encode(t :: any)
					if c.view == nil or c.shown ~= enc then
						thumbView(c, CharacterModels.preview(t), OUTFIT_THUMB, enc, false)
					end
				end
			end
		elseif c.key ~= "" and THUMBS[c.key] then
			local spec = THUMBS[c.key]
			local look = thumbLook(c.key, c.value)
			local im = c.image
			if im then
				local snap = specSnap("founder:thumb:" .. c.key .. ":", look, spec, u.thumb, PRIORITY_THUMB)
				if snap then
					bindWhenReady(im, snap, false)
				end
			else
				local enc = Looks.encode(look :: any)
				if c.view == nil or c.shown ~= enc then
					thumbView(c, cropped(look, spec), spec, enc, c.locked)
				end
			end
		end
	end
end

local function thumbLabel(u: Ui, b: TextButton, dim: boolean): ImageLabel
	local im = Instance.new("ImageLabel")
	im.Name = "Thumb"
	im.BackgroundTransparency = 1
	im.BorderSizePixel = 0
	im.Size = UDim2.fromOffset(u.thumb, u.thumb)
	im.Position = UDim2.fromOffset((u.cell - u.thumb) // 2, (u.cell - u.thumb) // 2)
	im.ResampleMode = Enum.ResamplerMode.Pixelated
	im.ImageTransparency = if dim then 0.45 else 0
	im.ZIndex = 4
	im.Parent = b
	return im
end

-- A tap on an option: the look takes it, the stage follows at once.
local function pick(key: string, o: Opt)
	if busy then
		return
	end
	local w = working
	if w == nil then
		return
	end
	Audio.play("click")
	working = with(w, key, o.value)
	local p = o.piece
	if p and not owns(p.id) then
		notice(Lang.t(whereFrom(p)) .. " " .. Lang.t("It won't save till it's yours."), color("text_dim"))
	end
	local t = TAB_BY[tab]
	if t.keys[2] and key == t.keys[1] then
		-- (the second section's None / Same chip wears the new main colour)
		regrid()
		showStage(true)
		return
	end
	onDraft(false)
end

------------------------------------------------------------------ outfits
local function saveOutfit()
	local w = working
	if busy or w == nil then
		return
	end
	local clean, left = cleaned(w)
	local code = Looks.encode(clean :: any)
	local list = outfitList()
	for _, c in list do
		local l = lookFrom(c)
		if l and codeOf(l) == code then
			Audio.play("deny")
			notice("This look is saved already.", color("text_dim"))
			return
		end
	end
	if #list >= Tuning.MaxOutfits then
		Audio.play("deny")
		notice("Your outfits are full. Delete one first.", color("bad"))
		return
	end
	busy = true
	local res = StateClient.request("outfit.set", { i = #list + 1, look = code })
	busy = false
	if res.ok and type(res.data) == "table" and type(res.data.outfits) == "table" then
		outfitsNow = { list = res.data.outfits, at = os.clock() }
		Audio.play("reward")
		notice(if #left > 0 then "Outfit saved, without the pieces you don't have." else "Outfit saved.", color("good"))
		if UIKit.currentPanel() == PANEL then
			regrid()
		end
	else
		Audio.play("deny")
		notice(Words.errText(res.err), color("bad"))
	end
end

local function deleteOutfit(i: number)
	if busy then
		return
	end
	if armed ~= i then
		armed = i
		Audio.play("click")
		notice("Tap the X again to delete this outfit.", color("text_dim"))
		local u = ui
		if u then
			for _, c in u.cells do
				local extra = c.extra
				if extra and c.value == i then
					UIKit.setButtonColor(extra, color("bad"))
				end
			end
		end
		return
	end
	armed = nil
	busy = true
	local res = StateClient.request("outfit.set", { i = i, look = "" })
	busy = false
	if res.ok and type(res.data) == "table" and type(res.data.outfits) == "table" then
		outfitsNow = { list = res.data.outfits, at = os.clock() }
		Audio.play("flip")
		notice("Outfit deleted.", color("text_dim"))
		if UIKit.currentPanel() == PANEL then
			regrid()
		end
	else
		Audio.play("deny")
		notice(Words.errText(res.err), color("bad"))
	end
end

local function wearOutfit(i: number)
	if busy then
		return
	end
	local code = outfitList()[i]
	local look = if code then lookFrom(code) else nil
	if look then
		Audio.play("click")
		working = look
		armed = nil
		onDraft(true)
	end
end

------------------------------------------------------------------ the colour row
-- The colour row of a tab that tints (Top, Apron, Hat, Face, Neck, Back, Hand), over the grid and outside its scroll:
-- "Colour", Original and a swatch a colour, the chosen one gold; a mouse over a swatch names it in the caption. The
-- swatches share the row's width (16 px at most; a touch screen's are 18 and the row scrolls sideways, the chosen one
-- scrolled into view). With nothing worn the row says to pick one first, and on a rainbow piece that it keeps its
-- colours. The Hand tab's row ends in Turn once something is held. Returns the height it takes with the gap under it
-- (0 on the other tabs), the same whatever is worn.
local function buildTints(right: Frame, y: number): number
	local u = ui
	local w = working
	if u == nil or w == nil then
		return 0
	end
	local old = u.tintRow
	if old then
		old:Destroy()
	end
	u.tintRow, u.tintFor = nil, nil
	table.clear(u.tintCells)
	local slot = TAB_BY[tab].tint
	if slot == nil then
		return 0
	end
	local field = Looks.tintField[slot]
	local rw = u.rw
	local list = Looks.tints
	local n, g = #list, 2
	local label = "Colour"
	local lw = UIKit.textWidth(label) + 6
	local piece = if PIECE_SLOT[slot] then pieceOf(w, slot) else nil
	local worn = if slot == "apron" then num(w, "apron") > 1 else piece ~= nil
	local tw = if slot == "hand" then UIKit.buttonWidth("Turn", 4) + 13 else 0
	local tg = if tw > 0 then 4 else 0
	local sw = rw - lw - tw - tg
	local s = math.min(16, (sw + g) // n - g)
	if UIKit.touch() then
		s = 18
	end
	s = math.max(10, s)
	local rowW = n * (s + g) - g
	local scrolls = rowW > sw
	local h = s + (if scrolls then 3 else 0)
	local row = Instance.new("Frame")
	row.Name = "Colours"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.fromOffset(rw, h)
	row.ZIndex = 2
	row.Parent = right
	u.tintRow = row
	u.tintFor = if slot == "apron" then tostring(num(w, "apron")) else (if piece then piece.id else "")
	UIKit.text(row, label, UDim2.fromOffset(lw - 4, LINE), UDim2.fromOffset(1, (s - LINE) // 2), { color = color("sheet_head"), z = 4, name = "ColourLabel" })
	if tw > 0 and piece then
		local turn = UIKit.button(row, "Turn", UDim2.fromOffset(tw, math.min(s, 16)), UDim2.fromOffset(rw - tw, (s - math.min(s, 16)) // 2), function()
			local cur = working
			if busy or cur == nil then
				return
			end
			working = with(cur, "turn", num(cur, "turn") % #Looks.turns + 1)
			onDraft(false)
		end, { name = "TurnHeld", color = color("plate_light") })
		turn.ZIndex = 4
		PixelSprites.image(turn, "mini_refresh", UDim2.fromOffset(2, (math.min(s, 16) - 11) // 2), 6)
		local words = turn:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(13, 0)
			words.Size = UDim2.new(1, -15, 1, 0)
		end
	end
	if not worn or (piece and piece.rainbow) then
		local text = if not worn then "Pick one to colour it." else "This one keeps its own colours."
		UIKit.text(row, text, UDim2.fromOffset(sw, LINE), UDim2.fromOffset(lw, (s - LINE) // 2), { color = color("text_dim"), z = 4, name = "ColourNote" })
		return h + 3
	end
	local strip: GuiObject
	if scrolls then
		local sf = Instance.new("ScrollingFrame")
		sf.ScrollingDirection = Enum.ScrollingDirection.X
		sf.ScrollBarThickness = 2
		sf.ScrollBarImageColor3 = color("text_dim")
		sf.ElasticBehavior = Enum.ElasticBehavior.Never
		sf.CanvasSize = UDim2.fromOffset(rowW, 0)
		strip = sf
	else
		strip = Instance.new("Frame")
	end
	strip.Name = "Swatches"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Position = UDim2.fromOffset(lw, 0)
	strip.Size = UDim2.fromOffset(sw, h)
	strip.ZIndex = 2
	strip.Parent = row
	-- Original: the piece's own main colour (an apron's body; a piece of ours with no colour on record: cream)
	local own = if slot == "apron" then Looks.aprons[num(w, "apron")].color else (if piece then piece.color else nil)
	local ownC = color(own or "cream")
	local chosenX = 0
	for i, o in list do
		local x = (i - 1) * (s + g)
		local b, veil = cellButton(strip, "Tint_" .. o.id, o.name, x, 0, s)
		local c: Cell = { key = "tint", value = i, button = b, veil = veil, image = nil, view = nil, shown = nil, extra = nil, locked = false }
		chip(b, s, if i == 1 then ownC else color(o.color or "white"), i == 1)
		if num(w, field) == i then
			chosenX = x
		end
		hoverable(c, o.name)
		b.Activated:Connect(function()
			local cur = working
			if busy or cur == nil then
				return
			end
			Audio.play("click")
			working = with(cur, field, i)
			onDraft(false)
		end)
		table.insert(u.tintCells, c)
	end
	if scrolls and strip:IsA("ScrollingFrame") then
		local at = math.clamp(chosenX - sw // 2, 0, math.max(0, rowW - sw))
		strip.CanvasPosition = Vector2.new(at * UIKit.P(), 0)
	end
	return h + 3
end

paintTints = function()
	local u = ui
	local w = working
	if u == nil or w == nil then
		return
	end
	local slot = TAB_BY[tab].tint
	if slot == nil then
		return
	end
	local now = if slot == "apron" then tostring(num(w, "apron")) else (if pieceOf(w, slot) then (pieceOf(w, slot) :: Cosmetics.Piece).id else "")
	local row = u.tintRow
	if row and u.tintFor ~= now then
		-- another piece: its Original chip (or the note) follows
		buildTints(u.right, row.Position.Y.Offset)
	end
	for _, c in u.tintCells do
		cellPaint(c, isChosen(c), false)
	end
end

------------------------------------------------------------------ titles
local function buildTitles(parent: Frame, y: number, w: number, h: number)
	local v = view()
	if v == nil then
		return
	end
	local list = UIKit.scroll(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(0, y))
	list.Name = "TitleList"
	UIKit.vlist(list, 2)
	local rw = w - 6
	local earned: { Titles.Title } = {}
	local locked: { Titles.Title } = {}
	for _, t in Titles.list do
		if v.titles and v.titles[t.id] then
			table.insert(earned, t)
		else
			table.insert(locked, t)
		end
	end
	local function wearTitle(id: string, name: string?)
		if busy then
			return
		end
		busy = true
		local res = StateClient.request("title.set", { id = id })
		busy = false
		if res.ok then
			Audio.play("flip")
			if name then
				notice(Lang.fmt("Title set: {name}.", { name = Lang.t(name) }), color("good"))
			end
		else
			Audio.play("deny")
			notice(Words.errText(res.err), color("bad"))
		end
	end
	local order = 1
	local nf = UIKit.row(list, UDim2.new(1, -6, 0, 16), nil)
	nf.Name = "Title_none"
	nf.LayoutOrder = order
	UIKit.text(nf, "No title", UDim2.fromOffset(rw - 60, 10), UDim2.fromOffset(5, 3), { color = color("text_dim"), z = 4 })
	local noneOn = (v.title or "") == ""
	UIKit.button(nf, if noneOn then "Worn" else "Wear", UDim2.fromOffset(46, 12), UDim2.new(1, -49, 0, 2), function()
		wearTitle("", nil)
	end, { name = "WearTitle_none", color = if noneOn then color("plate_light") else color("button_ok"), enabled = not noneOn }).ZIndex = 4
	for _, t in earned do
		order += 1
		local f = UIKit.row(list, UDim2.new(1, -6, 0, 24), nil)
		f.Name = "Title_" .. t.id
		f.LayoutOrder = order
		UIKit.text(f, t.name, UDim2.fromOffset(rw - 60, 10), UDim2.fromOffset(5, 2), { color = color(t.color), z = 4, name = "Name" })
		UIKit.text(f, StoreUI.howWords(t), UDim2.fromOffset(rw - 60, 10), UDim2.fromOffset(5, 12), { color = color("text_dim"), z = 4 })
		local on = v.title == t.id
		UIKit.button(f, if on then "Worn" else "Wear", UDim2.fromOffset(46, 12), UDim2.new(1, -49, 0, 6), function()
			wearTitle(t.id, t.name)
		end, { name = "WearTitle_" .. t.id, color = if on then color("plate_light") else color("button_ok"), enabled = not on }).ZIndex = 4
	end
	for _, t in locked do
		order += 1
		local f = UIKit.row(list, UDim2.new(1, -6, 0, 24), nil, nil, 0.93)
		f.Name = "Locked_" .. t.id
		f.LayoutOrder = order
		UIKit.text(f, t.name, UDim2.fromOffset(rw - 10, 10), UDim2.fromOffset(5, 2), { color = color("text_dim"), z = 4, name = "Name" })
		UIKit.text(f, StoreUI.howWords(t), UDim2.fromOffset(rw - 10, 10), UDim2.fromOffset(5, 12), { color = color("text_dim"), z = 4 })
	end
end

------------------------------------------------------------------ the grid of a tab
-- The tab's grid from y down to the actions: its colour row first (a tab that tints), then the options of each of
-- its fields (a second one under its heading), a piece tab's shop cell last; Outfits its + cell and the outfits;
-- Titles a list. `entrance`: the cells arrive one after another (the sheet just opened).
local function buildGrid(right: Frame, y: number, bottom: number, entrance: boolean)
	local u = ui
	local w = working
	if u == nil or w == nil then
		return
	end
	table.clear(u.cells)
	local rw = u.rw
	if tab == "titles" then
		u.tintRow = nil
		buildTitles(right, y, rw, bottom - y)
		return
	end
	local rowH = buildTints(right, y)
	local gy = y + rowH
	local gridH = bottom - gy
	u.gridY, u.gridH = gy, gridH
	local cell, gap, cols = u.cell, u.gap, u.cols
	local g = Instance.new("ScrollingFrame")
	g.Name = "Options"
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.Position = UDim2.fromOffset(0, gy)
	g.Size = UDim2.fromOffset(rw, gridH)
	g.ScrollingDirection = Enum.ScrollingDirection.Y
	g.ScrollBarThickness = 3
	g.ScrollBarImageColor3 = color("text_dim")
	g.ElasticBehavior = Enum.ElasticBehavior.Never
	g.ZIndex = 2
	g.Parent = right
	u.grid = g
	local function at(i: number, y0: number): (number, number)
		local col, row = (i - 1) % cols, (i - 1) // cols
		return u.gridX + col * (cell + gap), y0 + row * (cell + gap)
	end
	local yEnd = 0
	local chosenY: number? = nil
	if tab == "outfits" then
		local list = outfitList()
		local sx, sy = at(1, 0)
		local sb, sveil = cellButton(g, "SaveOutfit", "Save this look", sx, sy, cell)
		local sc: Cell = { key = "", value = "", button = sb, veil = sveil, image = nil, view = nil, shown = nil, extra = nil, locked = false }
		-- a plus, drawn 1:1
		local arm, thick = math.max(8, cell // 3), if cell >= 40 then 3 else 2
		arm -= (arm - thick) % 2
		local mid = (cell - thick) // 2
		rect(sb, mid, (cell - arm) // 2, thick, arm, color("text"), 4)
		rect(sb, (cell - arm) // 2, mid, arm, thick, color("text"), 4)
		hoverable(sc, "Save this look")
		sb.Activated:Connect(saveOutfit)
		table.insert(u.cells, sc)
		for i in list do
			local x, yy = at(i + 1, 0)
			local b, veil = cellButton(g, "Outfit_" .. i, Lang.fmt("Outfit {n}", { n = i }), x, yy, cell)
			local c: Cell = { key = "outfit", value = i, button = b, veil = veil, image = nil, view = nil, shown = nil, extra = nil, locked = false }
			if u.pixel then
				c.image = thumbLabel(u, b, false)
			end
			-- the X, top right, while it is the one worn
			local del = UIKit.button(b, "", UDim2.fromOffset(13, 13), UDim2.fromOffset(cell - 14, 1), function()
				deleteOutfit(i)
			end, { name = "DeleteOutfit_" .. i, color = if armed == i then color("bad") else color("plate_light") })
			del.ZIndex = 6
			PixelSprites.image(del, "mini_close", UDim2.fromOffset(1, 0), 7)
			del.Visible = false
			c.extra = del
			hoverable(c, Lang.fmt("Outfit {n}", { n = i }))
			b.Activated:Connect(function()
				wearOutfit(i)
			end)
			table.insert(u.cells, c)
		end
		local _, ly = at(#list + 1, 0)
		yEnd = ly + cell
	else
		local t = TAB_BY[tab]
		local y0 = 0
		for n, key in t.keys do
			if n > 1 then
				UIKit.text(g, t.head or "", UDim2.fromOffset(rw - 2 * u.gridX - 4, LINE), UDim2.fromOffset(u.gridX + 1, y0 + 1), { color = color("sheet_head"), z = 4, name = "Section" })
				y0 += LINE + 4
			end
			local opts = optionsOf(key)
			local count = #opts + (if t.pieces and n == #t.keys then 1 else 0)
			for i, o in opts do
				local x, yy = at(i, y0)
				local name = if n > 1 then "Option_" .. key .. "_" .. tostring(o.value) else "Option_" .. tostring(o.value)
				if o.value == "" then
					name = "Option_none"
				end
				local b, veil = cellButton(g, name, o.name, x, yy, cell)
				local p = o.piece
				local locked = p ~= nil and not owns(p.id)
				local c: Cell = { key = key, value = o.value, button = b, veil = veil, image = nil, view = nil, shown = nil, extra = nil, locked = locked }
				if t.chips then
					local main = t.keys[1]
					local ck = o.color
					if o.same then
						local pal: { string } = if main == "hair" then Looks.hair else Looks.eyes
						ck = pal[num(w, main)]
					end
					chip(b, cell, color(ck or "white"), o.same)
				elseif u.pixel then
					c.image = thumbLabel(u, b, locked)
				end
				if p then
					-- its rarity: a bar along the cell's foot; not owned: a padlock in the corner
					local rar = Traits.RARITY[p.rarity] or Traits.RARITY[1]
					rect(b, 3, cell - 3, cell - 6, 1, color(rar.color), 5)
					if locked then
						PixelSprites.image(b, "mini_lock", UDim2.fromOffset(cell - 11, 1), 6).Name = "Lock"
					end
					b:SetAttribute("Owned", not locked)
				end
				hoverable(c, if locked then Lang.fmt("{name} (locked)", { name = o.name }) else o.name)
				b.Activated:Connect(function()
					pick(key, o)
				end)
				table.insert(u.cells, c)
				if n == 1 and valueOf(w, key) == o.value then
					chosenY = yy
				end
			end
			if t.pieces and n == #t.keys then
				-- the shop: the Store's rotating shop
				local x, yy = at(#opts + 1, y0)
				local b, veil = cellButton(g, "ShopCell", "More in the shop", x, yy, cell)
				local c: Cell = { key = "shop", value = "", button = b, veil = veil, image = nil, view = nil, shown = nil, extra = nil, locked = false }
				local word = cell >= 30
				PixelSprites.image(b, "mini_store", UDim2.fromOffset((cell - 11) // 2, if word then (cell - 22) // 2 else (cell - 11) // 2), 5)
				if word then
					local tw = UIKit.textWidth("Shop") + 2
					UIKit.text(b, "Shop", UDim2.fromOffset(tw, LINE), UDim2.fromOffset((cell - tw) // 2, (cell - 22) // 2 + 12), { z = 5 })
				end
				hoverable(c, "More in the shop")
				b.Activated:Connect(function()
					if busy then
						return
					end
					Audio.play("click")
					quiet = true
					UIKit.openPanel("store", "shop")
				end)
				table.insert(u.cells, c)
			end
			local rows = math.ceil(count / cols)
			y0 += rows * (cell + gap)
		end
		yEnd = y0 - gap
	end
	g.CanvasSize = UDim2.fromOffset(0, math.max(0, yEnd))
	paintCells()
	refreshThumbs()
	-- where it opens: where this tab was left this opening, else the chosen option in view
	local P = UIKit.P()
	local keep = scrollOf[tab]
	local maxY = math.max(0, yEnd - gridH)
	local top = if keep then keep elseif chosenY then math.clamp(chosenY - (gridH - cell) // 2, 0, maxY) else 0
	g.CanvasPosition = Vector2.new(0, math.clamp(top, 0, maxY) * P)
	local myTab = tab
	g:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		scrollOf[myTab] = math.floor(g.CanvasPosition.Y / P + 0.5)
	end)
	if entrance then
		-- the cells arrive one after another, a few px up into place
		for i, c in u.cells do
			local b = c.button
			local base = b.Position
			b.Position = base + UDim2.fromOffset(0, 3)
			task.delay(math.min(i, 30) * 0.012, function()
				if b.Parent ~= nil then
					UIKit.tween(b, 0.12, { Position = base })
				end
			end)
		end
	end
end

onDraft = function(refresh: boolean)
	paintCells()
	paintCaption()
	showStage(true)
	if refresh then
		refreshThumbs()
	end
end

------------------------------------------------------------------ the actions
local function randomLook(): Look
	local rng = Random.new()
	local function roll(n: number): number
		return rng:NextInteger(1, n)
	end
	local l: { [string]: any } = {
		skin = roll(#Looks.skin),
		hair = roll(#Looks.hair),
		style = roll(#Looks.styles),
		shirt = roll(#Looks.shirt),
		bangs = if rng:NextNumber() < 0.5 then 1 else roll(#Looks.bangs),
		hair2 = if rng:NextNumber() < 0.6 then 0 else roll(#Looks.hair),
		eye = roll(#Looks.eyes),
		eye2 = if rng:NextNumber() < 0.85 then 0 else roll(#Looks.eyes),
		apron = if rng:NextNumber() < 0.5 then 1 else roll(#Looks.aprons),
	}
	-- the pieces owned, now and then none (more often round the neck and in the hand), most in their own colours
	local owned = ownedSet()
	for _, slot in Looks.worn do
		local have: { string } = {}
		local pool: { Cosmetics.Piece } = Cosmetics.bySlot[slot] or {}
		for _, p in pool do
			if Cosmetics.owns(owned, p.id) then
				table.insert(have, p.id)
			end
		end
		local none = if slot == "neck" or slot == "hand" then 0.5 else 0.3
		if #have > 0 and rng:NextNumber() >= none then
			l[slot] = have[roll(#have)]
		end
	end
	for _, f in Looks.tintFields do
		if rng:NextNumber() >= 0.7 then
			l[f] = rng:NextInteger(2, #Looks.tints)
		end
	end
	local out = tidy(l :: any)
	local w = working
	if w and codeOf(out) == codeOf(w) then
		out = with(out, "skin", num(out, "skin") % #Looks.skin + 1)
	end
	return out
end

-- A plain founder: the skin, hair, eyes and shirt kept, everything worn taken off.
local function plainLook(look: Look): Look
	local l: { [string]: any } = { skin = look.skin, hair = look.hair, style = look.style, shirt = look.shirt }
	l.hair2 = (look :: any).hair2
	l.eye = (look :: any).eye
	l.eye2 = (look :: any).eye2
	return tidy(l :: any)
end

local function setBusy(on: boolean)
	busy = on
	local u = ui
	if u then
		for _, b in u.actions do
			UIKit.setEnabled(b, not on)
		end
	end
end

local function closeSoon(after: number, text: string?)
	task.delay(after, function()
		if UIKit.currentPanel() == PANEL and settled then
			UIKit.closePanel()
			if text then
				UIKit.notice(text, color("good"), 3.5)
			end
		end
	end)
end

-- Save: look.set with the look being tried (a piece not owned swapped back). A refused save stays open and says why.
local function save()
	local w = working
	if busy or w == nil then
		return
	end
	local clean, left = cleaned(w)
	local code = Looks.encode(clean :: any)
	if code == codeOf(savedLook()) then
		if #left > 0 then
			Audio.play("deny")
			notice("You don't own that piece yet.", color("bad"))
			return
		end
		settled = true
		kept = nil
		UIKit.closePanel()
		return
	end
	setBusy(true)
	local u = ui
	if u and u.save then
		UIKit.setButtonText(u.save :: TextButton, "Saving")
	end
	local res = StateClient.request("look.set", { look = code })
	if not res.ok then
		setBusy(false)
		if u and ui == u and u.save then
			UIKit.setButtonText(u.save :: TextButton, "Save")
		end
		Audio.play("deny")
		notice(Words.errText(res.err), color("bad"))
		return
	end
	working = clean
	kept = nil
	settled = true
	Audio.play("reward")
	local text = if #left > 0 then "Saved, without the pieces you don't have yet." else "Saved. Everyone sees your new look."
	if u and ui == u then
		if u.save then
			UIKit.setButtonText(u.save :: TextButton, "Saved")
		end
		paintCaption()
		hopStage(4, 0.26)
		UIKit.confetti(u.stage, 16)
	end
	closeSoon(0.6, text)
end

local function cancel()
	if busy then
		return
	end
	kept = nil
	settled = true
	UIKit.closePanel()
end

-- The action row: Randomise and Reset at the left, Cancel and Save at the right; the words get shorter to fit
-- (Randomise, Random, the die alone).
local function buildActions(parent: Frame, w: number, y: number, h: number): { TextButton }
	local u = ui :: Ui
	local saveW = UIKit.buttonWidth("Save", 8)
	local cancelW = UIKit.buttonWidth("Cancel", 5)
	local resetW = UIKit.buttonWidth("Reset", 5)
	local rText = "Randomise"
	local function rw(text: string): number
		return if text == "" then 17 else UIKit.textWidth(text) + 21
	end
	if rw(rText) + resetW + cancelW + saveW + 12 > w then
		rText = "Random"
		if rw(rText) + resetW + cancelW + saveW + 12 > w then
			rText = ""
		end
	end
	local out: { TextButton } = {}
	local rnd = UIKit.button(parent, rText, UDim2.fromOffset(rw(rText), h), UDim2.fromOffset(0, y), function()
		if busy or working == nil then
			return
		end
		working = randomLook()
		onDraft(true)
	end, { name = "Randomise", color = color("plate_light") })
	rnd.ZIndex = 4
	PixelSprites.image(rnd, "mini_dice", UDim2.fromOffset(3, (h - 11) // 2), 6)
	local words = rnd:FindFirstChild("Words")
	if words and words:IsA("GuiObject") then
		words.Position = UDim2.fromOffset(15, 0)
		words.Size = UDim2.new(1, -17, 1, 0)
	end
	if rText == "" then
		rnd.Text = Lang.t("Randomise")
		rnd.TextTransparency = 1
	end
	table.insert(out, rnd)
	local reset = UIKit.button(parent, "Reset", UDim2.fromOffset(resetW, h), UDim2.fromOffset(rw(rText) + 4, y), function()
		local cur = working
		if busy or cur == nil then
			return
		end
		working = plainLook(cur)
		onDraft(true)
	end, { name = "ResetLook", color = color("plate_light") })
	reset.ZIndex = 4
	table.insert(out, reset)
	local cn = UIKit.button(parent, "Cancel", UDim2.fromOffset(cancelW, h), UDim2.fromOffset(w - saveW - 4 - cancelW, y), cancel, { name = "CancelLook", color = color("plate_light") })
	cn.ZIndex = 4
	table.insert(out, cn)
	local sv = UIKit.button(parent, "Save", UDim2.fromOffset(saveW, h), UDim2.fromOffset(w - saveW, y), save, { name = "SaveLook", color = color("button_ok") })
	sv.ZIndex = 4
	table.insert(out, sv)
	u.save = sv
	if busy then
		for _, b in out do
			UIKit.setEnabled(b, false)
		end
	end
	return out
end

------------------------------------------------------------------ the tabs
-- The tab buttons (named LooksTab_<id>, the open one teal), in rows across `w` px when two rows hold them, else in a
-- strip that scrolls sideways (the open one scrolled into view). Returns the height they take.
local function buildTabs(parent: Frame, w: number, wrapOk: boolean, onPick: (id: string) -> ()): number
	local TH = UIKit.TAB_H
	local widths: { number } = {}
	local total = 0
	for i, t in TABS do
		widths[i] = UIKit.textWidth(t.text) + 10
		total += widths[i] + (if i > 1 then 2 else 0)
	end
	local rows = 1
	do
		local x = 0
		for i in TABS do
			if x > 0 and x + widths[i] > w then
				x = 0
				rows += 1
			end
			x += widths[i] + 2
		end
	end
	local wrap = wrapOk and rows <= 2
	local holder: GuiObject
	if wrap then
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(w, rows * (TH + 2))
		holder = f
	else
		local sf = Instance.new("ScrollingFrame")
		sf.ScrollingDirection = Enum.ScrollingDirection.X
		sf.ScrollBarThickness = 2
		sf.ScrollBarImageColor3 = color("text_dim")
		sf.ElasticBehavior = Enum.ElasticBehavior.Never
		sf.CanvasSize = UDim2.fromOffset(total, 0)
		sf.Size = UDim2.fromOffset(w, TH + 4)
		holder = sf
	end
	holder.Name = "Tabs"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 3
	holder.Parent = parent
	local x, row = 0, 0
	local pickedX0, pickedX1 = 0, 0
	for i, t in TABS do
		if wrap and x > 0 and x + widths[i] > w then
			x = 0
			row += 1
		end
		local on = t.id == tab
		local b = UIKit.button(holder, t.text, UDim2.fromOffset(widths[i], TH), UDim2.fromOffset(x, row * (TH + 2)), function()
			onPick(t.id)
		end, { name = "LooksTab_" .. t.id, color = if on then color("button") else color("plate_light") })
		b.ZIndex = 4
		local u = ui
		if u then
			u.tabs[t.id] = b
		end
		if on then
			pickedX0, pickedX1 = x, x + widths[i]
		end
		x += widths[i] + 2
	end
	if not wrap and holder:IsA("ScrollingFrame") and total > w then
		local at = math.clamp(pickedX0 - 24, 0, total - w)
		if pickedX1 + 24 > at + w then
			at = math.clamp(pickedX1 + 24 - w, 0, total - w)
		end
		holder.CanvasPosition = Vector2.new(at * UIKit.P(), 0)
	end
	return if wrap then rows * (TH + 2) else TH + 5
end

------------------------------------------------------------------ the sheet
-- What the sheet shows of the view: when it changes the sheet is built again.
local function signature(v: Types.ClientView): string
	local n, t = 0, 0
	local owned: { [string]: boolean } = v.owned or {}
	local titles: { [string]: boolean } = v.titles or {}
	for _ in owned do
		n += 1
	end
	for _ in titles do
		t += 1
	end
	return string.format("%s|%d|%d|%s|%s", Looks.encode(v.founder :: any), n, t, v.title or "", table.concat(v.outfits or {}, ";"))
end

local currentBody: Frame? = nil

local function layout(body: Frame, sig: string, entrance: boolean)
	local old = ui
	if old then
		old.root:Destroy()
	end
	forgetLabels()
	disconnectAll()
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local root = Instance.new("Frame")
	root.Name = "Founder"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(W, H)
	root.ZIndex = 2
	root:SetAttribute("Keep", true)
	root.Parent = body
	-- side by side (the stage left of the options), or stacked on a narrow portrait screen
	local stacked = W < 300
	local gap = if H < 190 or stacked then 5 else 8
	local stageW, stageH, rx, ry
	if stacked then
		stageW, stageH = W, math.clamp(math.floor(H * 0.4), 96, 220)
		rx, ry = 0, stageH + gap
	else
		stageW, stageH = math.clamp(math.floor(W * 0.31), 96, 190), H
		rx, ry = stageW + gap, 0
	end
	local rw, rh = W - rx, H - ry
	-- short: no caption line (the option's name and the status ride on the stage); narrow: the status on the stage
	local compact = rh < 190
	local statusOnStage = compact or rw < 280
	local u: Ui = {
		root = root,
		sig = sig,
		pixel = pixelPictures(),
		stage = root,
		picture = nil,
		viewport = nil,
		viewCode = nil,
		pw = 0,
		ph = 0,
		scale = 1,
		anchor = Vector2.zero,
		px = 0,
		py = 0,
		right = root,
		rw = rw,
		tabs = {},
		gridTop = 0,
		gridBottom = 0,
		gridY = 0,
		gridH = 0,
		grid = nil,
		cells = {},
		tintRow = nil,
		tintCells = {},
		tintFor = nil,
		cell = 40,
		thumb = 36,
		cols = 1,
		gap = GAP,
		gridX = 0,
		caption = nil,
		status = nil,
		save = nil,
		actions = {},
	}
	ui = u
	buildStage(root, 0, 0, stageW, stageH, statusOnStage, compact)
	local right = Instance.new("Frame")
	right.Name = "Controls"
	right.BackgroundTransparency = 1
	right.BorderSizePixel = 0
	right.Position = UDim2.fromOffset(rx, ry)
	right.Size = UDim2.fromOffset(rw, rh)
	right.ZIndex = 2
	right:SetAttribute("W", rw)
	right:SetAttribute("H", rh)
	right.Parent = root
	u.right = right
	local tabsH = buildTabs(right, rw, not compact, function(id: string)
		if id ~= tab and not busy then
			tab = id
			armed = nil
			Audio.play("flip")
			for tid, b in u.tabs do
				UIKit.setButtonColor(b, if tid == tab then color("button") else color("plate_light"))
			end
			regrid()
		end
	end)
	local y = tabsH + (if compact then 1 else 3)
	if not compact then
		local statusW = if statusOnStage then 0 else UIKit.textWidth("Not saved yet") + 4
		local cap = UIKit.text(right, "", UDim2.fromOffset(rw - statusW - 4, LINE), UDim2.fromOffset(1, y), { name = "Choice", z = 4 })
		u.caption = cap
		if not statusOnStage then
			u.status = UIKit.text(right, "", UDim2.fromOffset(statusW, LINE), UDim2.fromOffset(rw - statusW, y), { x = "right", color = color("pink"), name = "Status", z = 4 })
		end
		y += LINE + 3
	end
	local btnH = 14
	local actionsY = rh - btnH
	-- cells: as many across as fit at the smallest size a tab of pictures reads at (a phone's smaller), the spare px
	-- in the gaps; the grid scrolls
	local gw = rw - 4
	local minCell = if compact then 30 else 40
	local cols = math.max(1, (gw + GAP) // (minCell + GAP))
	local cell = math.min(MAX_CELL, (gw - (cols - 1) * GAP) // cols)
	cell -= cell % 2
	local cgap = if cols > 1 then math.min(3 * GAP, (gw - cols * cell) // (cols - 1)) else 0
	u.cell, u.cols, u.gap = cell, cols, cgap
	u.gridX = (gw - (cols * (cell + cgap) - cgap)) // 2
	u.thumb = cell - (if cell >= 40 then 6 else 4)
	u.actions = buildActions(right, rw, actionsY, btnH)
	u.gridTop, u.gridBottom = y, actionsY - (if compact then 2 else 4)
	buildGrid(right, u.gridTop, u.gridBottom, entrance)
	paintCaption()
	showStage(false)
end

-- The grid area built again (another tab, an outfit saved or deleted, a main colour picked): the stage and the
-- tabs stay as they are.
regrid = function()
	local u = ui
	if u == nil then
		return
	end
	for _, name in { "Options", "Colours", "TitleList", "MoreBelow" } do
		local old = u.right:FindFirstChild(name)
		while old do
			old:Destroy()
			old = u.right:FindFirstChild(name)
		end
	end
	u.grid, u.tintRow = nil, nil
	table.clear(u.tintCells)
	buildGrid(u.right, u.gridTop, u.gridBottom, false)
	paintCaption()
end

-- The open sheet built again (the pixel filter switched), keeping the look and the angle.
rebuild = function()
	local b = currentBody
	local u = ui
	if b == nil or b.Parent == nil or u == nil then
		return
	end
	layout(b, u.sig, false)
end

local function onOpen(arg: any?)
	local now = savedLook()
	local k = kept
	kept = nil
	working = if k and codeOf(k) ~= codeOf(now) then k else now
	if type(arg) == "string" then
		local t = if arg == "pieces" then "hat" else arg
		if TAB_BY[t] then
			tab = t
		end
	end
	angle = 1
	busy, settled, quiet = false, false, false
	armed = nil
	outfitsNow = nil
	table.clear(scrollOf)
end

local function build(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local fresh = seq ~= UIKit.openCount()
	if fresh then
		seq = UIKit.openCount()
		onOpen(arg)
	end
	currentBody = body
	local sig = signature(v)
	local u = ui
	if not fresh and u and u.root.Parent == body and (sig == u.sig or settled) then
		-- nothing it shows changed (or it is closing after a save): the sheet stays as it is
		return
	end
	layout(body, sig, fresh)
end

-- The sheet shut (the X, Cancel, Save, another panel): an unsaved look is kept for the next opening, with a notice
-- unless it went to the shop; the pictures it held are let go.
local function onClose()
	local w = working
	working = nil
	disconnectAll()
	if w and not settled and codeOf(w) ~= codeOf(savedLook()) then
		kept = w
		if not quiet then
			UIKit.notice("Your new look isn't saved yet. Open Looks to finish it.", color("accent"), 4)
		end
	elseif settled then
		kept = nil
	end
	busy, settled, quiet = false, false, false
	armed = nil
	releaseAll()
	ui = nil
	currentBody = nil
end

------------------------------------------------------------------ public
function FounderUI.init()
	UIKit.registerPanel(PANEL, { title = TITLE, icon = "visitor", w = SHEET_W, h = SHEET_H, props = { "crown", "petal" }, build = build })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= PANEL and working ~= nil then
			onClose()
		end
	end)
	-- the pixel filter switched while the sheet is open: built again in the other kind of picture
	PixelRenderer.Changed:Connect(function()
		local u = ui
		if u and u.pixel ~= pixelPictures() then
			task.defer(function()
				local u2 = ui
				if u2 and u2.pixel ~= pixelPictures() then
					releaseAll()
					rebuild()
				end
			end)
		end
	end)
end

FounderUI.TABS = TABS

-- (for the sims: the look being tried, nil while the sheet is shut)
function FounderUI.working(): Look?
	return working
end

return FounderUI
