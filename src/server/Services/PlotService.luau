--!strict
-- The islands on the sea (docs/ARCHITECTURE.md 7.5; GAME_DESIGN 8). At start the whole sea is built: every island
-- plot's water and the seabed the founders swim on (Workspace.Plots.Street) and an empty sandbar on every plot; no
-- docks (2026-11-13): each island stands alone and the founders swim between them. A player who joins takes the
-- lowest free plot: Workspace.Plots.Plot_<i>.Static gets their island (Static.Land: its grass and coast, the plaza
-- and campfire, the sign on its beach) and their buildings and decor
-- (Static.Decor, one model a piece, named by its uid, kind, place and level); the island is rebuilt only when its tier
-- changes, the pieces by difference, so a client's renderer re-casts as little as possible. A new part
-- goes up before an old one comes down. A player who leaves leaves an empty sandbar. Plot_<i>'s attributes tell every
-- client who is there and who lives there (WorldView draws every island's driftlings from them):
-- Owner, OwnerName, StudioName (the island's name), Tier, Day, Charm, Pals (the driftlings in its huts). The founder (the player's
-- character) appears on their own island's plaza.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local StreetModels = require(ReplicatedStorage.Shared.Models.StreetModels)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local Session = require(script.Parent.Session)

local PlotService = {}

type S = Session.S

local taken: { [number]: Player } = {}
-- Each occupied plot's island for the next tier, built ahead in the background (a few dozen parts a frame): only the
-- land's chunks that the next tier changes (StreetModels.landPlan), so an expansion puts those in at once and takes
-- the old ones out, and everything else stays (the request of 2026-11-19, "Expansion is very slow and laggy,
-- especially at higher levels": the whole island used to be swapped, 4,400 parts at tier 15, every client receiving
-- all of them and its pixel filter baking the whole picture again).
-- The Tree of Life too, when the next tier grows it a stage (`tree`: its model at the next stage, named as buildDecor
-- names it; a tree moved meanwhile is built again at the expansion instead).
local nextLand: { [number]: { tier: number, chunks: { [string]: Model }?, tree: Model?, hold: Folder?, gen: number } } = {}
local prebuildGen = 0
type TreeSpot = { uid: number, x: number, z: number, rot: number }
local prebuildQueue: { { plot: number, tier: number, gen: number, tree: TreeSpot? } } = {}
local prebuilding = false
local swaps = 0 -- expansions that swapped in an island built ahead (the sim checks it)
local plotsFolder: Folder? = nil
local homeAt: { [Player]: number } = {}

local function folder(): Folder
	local f = plotsFolder
	if f and f.Parent then
		return f
	end
	local existing = workspace:FindFirstChild("Plots")
	if existing and existing:IsA("Folder") then
		plotsFolder = existing
		return existing
	end
	local nf = Instance.new("Folder")
	nf.Name = "Plots"
	nf.Parent = workspace
	plotsFolder = nf
	return nf
end

local function originOf(i: number): Vector3
	local x, z = Street.origin(i)
	return Vector3.new(x, 0, z)
end

local function plotModel(i: number): Model
	local root = folder()
	local name = "Plot_" .. i
	local m = root:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	local nm = Instance.new("Model")
	nm.Name = name
	nm.Parent = root
	return nm
end

local function staticOf(i: number): Folder
	local m = plotModel(i)
	local s = m:FindFirstChild("Static")
	if s and s:IsA("Folder") then
		return s
	end
	local f = Instance.new("Folder")
	f.Name = "Static"
	f.Parent = m
	return f
end

-- Replace the child `name` of `parent` with what `make` builds into a fresh folder (the new one goes up first).
local function replace(parent: Instance, name: string, make: (f: Folder) -> ())
	local old = parent:FindFirstChild(name)
	local f = Instance.new("Folder")
	f.Name = name
	make(f)
	if old then
		old.Name = "Old"
	end
	f.Parent = parent
	if old then
		old:Destroy()
	end
end

-- Plot i's island model (Static.Land.Land: its land's chunks, the plaza and the sign); nil on an empty lot.
local function landModelOf(i: number): Model?
	local f = staticOf(i):FindFirstChild("Land")
	local m = if f then f:FindFirstChild("Land") else nil
	return if m and m:IsA("Model") then m else nil
end

-- (each tier's plan, worked out once: it depends on the tier alone)
local plans: { [number]: StreetModels.LandPlan } = {}
local function planOf(tier: number): StreetModels.LandPlan
	local p = plans[tier]
	if p == nil then
		p = StreetModels.landPlan(tier)
		plans[tier] = p
	end
	return p
end

local function pieceKey(q: { uid: number, id: string, x: number, z: number, rot: number, lvl: number }): string
	return string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl or 1)
end

-- Where piece `id` at cell (x, z) turned `rot` stands on plot i (its model's pivot).
local function pieceAt(i: number, id: string, x: number, z: number, rot: number): CFrame
	local w, dd = Plot.footprint(id, rot)
	return CFrame.new(originOf(i) + Vector3.new(x + w / 2, Street.LAWN_Y, z + dd / 2)) * CFrame.Angles(0, math.rad(rot), 0)
end

-- The next island stands in the world before it is wanted (the request of 2026-11-20: "Is there a way to make island
-- expansion seamless, with no lag? Could you pre render max expansion floors so that expanding simply switches to that
-- expansion level?"): its parts go to every client ahead of time, in collision groups that nothing collides with and
-- no ray meets but the pixel filter's pre-cast ("Staged", and "StagedBounds" for the invisible walls and shelves that
-- are "Bounds" on the island), so the clients can draw it before the expansion. `unstage` gives them their groups back.
local function stageParts(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = if d.CollisionGroup == "Bounds" then "StagedBounds" else "Staged"
		end
	end
end
local function unstage(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local g = d.CollisionGroup
			if g == "StagedBounds" then
				d.CollisionGroup = "Bounds"
			elseif g == "Staged" then
				d.CollisionGroup = "Default"
			end
		end
	end
end

-- workspace.Staged: each plot's next island, Plot_<i> (attribute Tier when every part of it is there)
local function stagedRoot(): Folder
	local f = workspace:FindFirstChild("Staged")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "Staged"
		nf.Parent = workspace
		f = nf
	end
	return f :: Folder
end

-- Builds the queued next islands' new chunks one plot at a time, paced (Blocks.pace) so the server never stalls a
-- frame on them: the next tier's chunks that the island doesn't have now, each built out of the world, staged and then
-- put in workspace.Staged.Plot_<i>, so the clients receive them a chunk at a time long before the expansion.
local function prebuildLoop()
	if prebuilding then
		return
	end
	prebuilding = true
	while #prebuildQueue > 0 do
		local job = table.remove(prebuildQueue, 1) :: { plot: number, tier: number, gen: number, tree: TreeSpot? }
		local slot = nextLand[job.plot]
		if slot and slot.gen == job.gen then
			local plan = planOf(job.tier)
			local hold = Instance.new("Folder")
			hold.Name = "Plot_" .. job.plot
			local old = stagedRoot():FindFirstChild(hold.Name)
			if old then
				old:Destroy()
			end
			hold.Parent = stagedRoot()
			local work = Instance.new("Folder") -- (a chunk is built here, out of the world, then staged and moved over)
			local made: { [string]: Model } = {}
			local tree: Model? = nil
			Blocks.pace(function()
				task.wait()
			end, 60)
			local ok, err = pcall(function(): boolean
				for _, c in plan.chunks do
					local still = nextLand[job.plot]
					if still == nil or still.gen ~= job.gen then
						return false
					end
					local lm = landModelOf(job.plot)
					if lm == nil or lm:FindFirstChild(c.name) == nil then
						local m = StreetModels.landChunk(work, originOf(job.plot), job.tier, c)
						stageParts(m)
						m.Parent = hold
						made[c.name] = m
					end
				end
				-- the tree at its next stage, where the next tier grows it one
				local t = job.tree
				local stage = Tree.stage(job.tier)
				if t and stage ~= Tree.stage(job.tier - 1) then
					local m = DecorModels.build(Tree.ID, pieceAt(job.plot, Tree.ID, t.x, t.z, t.rot), stage)
					m.Name = pieceKey({ uid = t.uid, id = Tree.ID, x = t.x, z = t.z, rot = t.rot, lvl = stage })
					stageParts(m)
					m.Parent = hold
					tree = m
				end
				return true
			end)
			Blocks.pace(nil)
			work:Destroy()
			local still = nextLand[job.plot]
			if ok and still and still.gen == job.gen then
				still.chunks, still.tree, still.hold = made, tree, hold
				-- (every part is there: the clients may draw it now)
				hold:SetAttribute("Tier", job.tier)
			else
				if not ok then
					warn("next island build failed: " .. tostring(err))
				end
				hold:Destroy()
			end
		end
	end
	prebuilding = false
end

-- Forget plot i's next island (a new one is queued when `tier` is given and the island can still grow).
local function planNext(i: number, tier: number?, tree: TreeSpot?)
	local old = nextLand[i]
	if old and old.hold then
		old.hold:Destroy()
	end
	nextLand[i] = nil
	if tier == nil or Island.expandCost(tier) == nil then
		return
	end
	prebuildGen += 1
	nextLand[i] = { tier = tier + 1, chunks = nil, tree = nil, hold = nil, gen = prebuildGen }
	table.insert(prebuildQueue, { plot = i, tier = tier + 1, gen = prebuildGen, tree = tree })
	task.defer(prebuildLoop)
end

-- An empty lot on plot i, with no attributes left of its last owner.
local function emptyLot(i: number)
	local m = plotModel(i)
	for _, k in { "Owner", "OwnerName", "StudioName", "Tier", "Day", "Charm", "Pals", "Eggs" } do
		m:SetAttribute(k, nil)
	end
	m:SetAttribute("Owner", 0)
	local static = staticOf(i)
	replace(static, "Land", function(f)
		StreetModels.emptyLot(f, originOf(i))
	end)
	for _, n in { "Office", "Decor" } do
		local c = static:FindFirstChild(n)
		if c then
			c:Destroy()
		end
	end
	static:SetAttribute("Built", nil)
end

function PlotService.init()
	-- every tier's cells now, before anyone joins (the top tiers take tens of ms each: never at an expansion)
	local most = 1
	while Island.expandCost(most) ~= nil do
		most += 1
	end
	for t = 1, most do
		Street.warm(t)
	end
	-- the invisible seabed, shelves and world walls ("Bounds") hold the founders but are never in the pixel filter's
	-- rays ("PixelRays")
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Bounds")
		PhysicsService:RegisterCollisionGroup("PixelRays")
		PhysicsService:CollisionGroupSetCollidable("PixelRays", "Bounds", false)
		-- the next island, built ahead (stageParts): it collides with nothing and only the pixel filter's pre-cast
		-- ("PreCast") meets it, its walls and shelves not even that (the island's "Bounds" never meet a ray)
		for _, g in { "Staged", "StagedBounds", "PreCast" } do
			PhysicsService:RegisterCollisionGroup(g)
		end
		for _, g in { "Staged", "StagedBounds" } do
			for _, o in { "Default", "Bounds", "PixelRays", "Staged", "StagedBounds", "PreCast" } do
				PhysicsService:CollisionGroupSetCollidable(g, o, false)
			end
		end
		PhysicsService:CollisionGroupSetCollidable("PreCast", "Staged", true)
		PhysicsService:CollisionGroupSetCollidable("PreCast", "Bounds", false)
	end)
	stagedRoot()
	local root = folder()
	local street = Instance.new("Folder")
	street.Name = "Street"
	for i = 1, Street.MAX do
		StreetModels.road(street, originOf(i)).Name = "Road_" .. i
	end
	StreetModels.ends(street)
	street.Parent = root
	for i = 1, Street.MAX do
		emptyLot(i)
	end
end

-- The lowest free plot for a player (0 when the street is full: Main kicks then; the server's size is MaxPlots).
function PlotService.claim(player: Player): number
	for i = 1, Street.MAX do
		if not taken[i] then
			taken[i] = player
			return i
		end
	end
	return 0
end

function PlotService.release(i: number)
	if i < 1 then
		return
	end
	taken[i] = nil
	planNext(i, nil)
	emptyLot(i)
end

------------------------------------------------------------------ building a studio's plot
-- A water tile's neighbours (GAME_DESIGN 4.3): 1 + a bit for each side with water next to it (north 1, east 2, south
-- 4, west 8), so its model draws its banks only where the water ends; it takes the level's place in the model's name,
-- so a tile is built again when the water round it changes.
local function waterMasks(placed: { Types.Piece }): { [number]: number }
	local wet: { [number]: boolean } = {}
	for _, q in placed do
		if Plot.isWater(q.id) then
			wet[Street.cellKey(q.x, q.z)] = true
		end
	end
	local out: { [number]: number } = {}
	for _, q in placed do
		if Plot.isWater(q.id) then
			local m = 0
			if wet[Street.cellKey(q.x, q.z - 2)] then
				m += 1
			end
			if wet[Street.cellKey(q.x + 2, q.z)] then
				m += 2
			end
			if wet[Street.cellKey(q.x, q.z + 2)] then
				m += 4
			end
			if wet[Street.cellKey(q.x - 2, q.z)] then
				m += 8
			end
			out[Street.cellKey(q.x, q.z)] = 1 + m
		end
	end
	return out
end
PlotService.waterMasks = waterMasks

-- The decor by difference: keep the models whose piece is still there, build the new ones, remove the gone ones. The
-- Tree of Life's model goes by its stage (Tree.stage: it grows grander with the island) in place of a level, so a new
-- stage builds it again; a water tile's by its neighbours (waterMasks).
function PlotService.buildDecor(s: S, pre: { [string]: Model }?)
	local static = staticOf(s.plot)
	local decor = static:FindFirstChild("Decor")
	if decor == nil then
		local f = Instance.new("Folder")
		f.Name = "Decor"
		f.Parent = static
		decor = f
	end
	local d = decor :: Instance
	local want: { [string]: boolean } = {}
	-- (the models there now, by name, looked at once: a FindFirstChild a piece walked every child for each of them,
	-- 3,500 by 3,500 at tier 15, on every expansion and every piece placed)
	local have: { [string]: Instance } = {}
	for _, c in d:GetChildren() do
		have[c.Name] = c
	end
	local stage = Tree.stage(s.profile.tier)
	local masks = waterMasks(s.profile.plot.placed)
	for _, q in s.profile.plot.placed do
		local lvl = if q.id == Tree.ID then stage elseif Plot.isWater(q.id) then masks[Street.cellKey(q.x, q.z)] or 1 else q.lvl or 1
		local key = pieceKey({ uid = q.uid, id = q.id, x = q.x, z = q.z, rot = q.rot, lvl = lvl })
		want[key] = true
		if not have[key] then
			local ready = if pre then pre[key] else nil
			if pre and ready then
				-- (built ahead: the tree's next stage)
				ready.Parent = d
				pre[key] = nil
			else
				local m = DecorModels.build(q.id, pieceAt(s.plot, q.id, q.x, q.z, q.rot), lvl)
				m.Name = key
				m.Parent = d
			end
			have[key] = d -- (a second piece with the same key is built once, as before)
		end
	end
	if pre then
		for _, m in pre do
			m:Destroy()
		end
	end
	for _, c in d:GetChildren() do
		if not want[c.Name] then
			c:Destroy()
		end
	end
end

-- (Re)build the session's plot: the island when the tier changed, then the decor and the attributes.
function PlotService.build(s: S)
	local m = plotModel(s.plot)
	m:SetAttribute("Owner", s.player.UserId)
	m:SetAttribute("OwnerName", s.player.DisplayName)
	m:SetAttribute("StudioName", s.player.DisplayName .. "'s Isle")
	local static = staticOf(s.plot)
	local tier = s.profile.tier
	local tree: TreeSpot? = nil
	for _, q in s.profile.plot.placed do
		if q.id == Tree.ID then
			tree = { uid = q.uid, x = q.x, z = q.z, rot = q.rot }
			break
		end
	end
	local ahead: { [string]: Model } = {}
	if static:GetAttribute("Built") ~= tier then
		local o = originOf(s.plot)
		local lm = landModelOf(s.plot)
		if lm == nil then
			-- the first island on the lot (it was an empty sandbar): all of it
			replace(static, "Land", function(f)
				StreetModels.land(f, o, tier)
			end)
		else
			-- another tier: the chunks it changes, built ahead in the background where they could be, go up first,
			-- then the ones it no longer has come down; the rest of the island stays as it is
			local plan = planOf(tier)
			local ready = nextLand[s.plot]
			local made: { [string]: Model } = (if ready and ready.tier == tier then ready.chunks else nil) or {}
			if ready and ready.tier == tier and ready.chunks then
				swaps += 1
			end
			-- (the tree built ahead at its next stage, kept out of the hold that planNext lets go below)
			local t = if ready and ready.tier == tier then ready.tree else nil
			if t then
				unstage(t)
				t.Parent = nil
				ahead[t.Name] = t
				ready.tree = nil
			end
			local want: { [string]: boolean } = { Plaza = true, [plan.sign] = true }
			for _, c in plan.chunks do
				want[c.name] = true
				if lm:FindFirstChild(c.name) == nil then
					local pre = made[c.name]
					if pre then
						unstage(pre)
						pre.Parent = lm
						made[c.name] = nil
					else
						StreetModels.landChunk(lm, o, tier, c)
					end
				end
			end
			if lm:FindFirstChild(plan.sign) == nil then
				StreetModels.landSign(lm, o, tier)
			end
			if lm:FindFirstChild("Plaza") == nil then
				StreetModels.landPlaza(lm, o)
			end
			for _, ch in lm:GetChildren() do
				if not want[ch.Name] then
					ch:Destroy()
				end
			end
		end
		static:SetAttribute("Built", tier)
		planNext(s.plot, tier, tree)
	elseif nextLand[s.plot] == nil then
		planNext(s.plot, tier, tree)
	end
	PlotService.buildDecor(s, ahead)
	PlotService.sync(s)
end

-- Plot i's island built ahead: the tier it is for (nil: none planned), whether it is finished, and how many
-- expansions so far swapped one in (the sim's check).
function PlotService.debugNext(i: number): (number?, boolean, number)
	local n = nextLand[i]
	return if n then n.tier else nil, n ~= nil and n.chunks ~= nil, swaps
end

-- The plot's attributes from the session (cheap: only changed values replicate).
function PlotService.sync(s: S)
	local m = plotModel(s.plot)
	local p = s.profile
	-- who lives there: each driftling in a hut "id.species.work.home" (work: the uid of the building it works at, 0
	-- resting; home: its hut; one with no hut, its hut cleared away, shows once it moves in), then ".mut,mut" when it
	-- has mutations (a tap on a neighbour's driftling shows them: Menus' "pal" panel). The tree's eggs round its roots
	-- "id.rarity" (every client draws every island's, Controllers/EggView).
	local pals = {}
	for _, x in p.pals do
		if (x.home or 0) ~= 0 then
			local muts = if x.muts and #x.muts > 0 then "." .. table.concat(x.muts, ",") else ""
			table.insert(pals, string.format("%d.%s.%d.%d", x.id, x.sp, x.work, x.home) .. muts)
		end
	end
	local function set(k: string, v: any)
		if m:GetAttribute(k) ~= v then
			m:SetAttribute(k, v)
		end
	end
	set("Tier", p.tier)
	set("Day", p.day)
	set("Charm", Island.charm(p))
	set("Pals", table.concat(pals, ";"))
	local eggs = {}
	for _, e in Tree.shown(p) do
		-- ("id.r", or "id.r.wx" for an egg the weather touched: every client marks it, GAME_DESIGN 13; the rarest
		-- Tuning.EggShown of the lot: the ring's room)
		table.insert(eggs, string.format("%d.%d", e.id, e.r) .. (if e.wx then "." .. e.wx else ""))
	end
	set("Eggs", table.concat(eggs, ";"))
	-- the founder's look (Data/Looks.encode: the colours and style, then the pieces worn) and the title worn (a
	-- Data/Titles id, "" none): every client draws the founder and the name tag over them from these (GAME_DESIGN 14)
	local look = Looks.encode(p.founder :: any)
	if s.player:GetAttribute("Founder") ~= look then
		s.player:SetAttribute("Founder", look)
	end
	if s.player:GetAttribute("Title") ~= p.title then
		s.player:SetAttribute("Title", p.title)
	end
	s.player:SetAttribute("Plot", s.plot)
end

------------------------------------------------------------------ the founder
-- Where a session's founder appears (world CFrame): on their island's plaza, south of the campfire.
function PlotService.spawnCFrame(s: S): CFrame
	local x, z = Street.spawn()
	local o = originOf(s.plot)
	return CFrame.new(o + Vector3.new(x, 3, z))
end

function PlotService.placeCharacter(s: S)
	local char = s.player.Character
	if char and char.Parent then
		char:PivotTo(PlotService.spawnCFrame(s))
	end
end

-- "Go home" (char.home): the founder back on their own island's plaza (from a swim, a neighbour's island), at most
-- once every Tuning.HomeCooldown seconds.
function PlotService.home(s: S): (boolean, any)
	local now = os.clock()
	if now - (homeAt[s.player] or -math.huge) < Tuning.HomeCooldown then
		return false, "cooldown"
	end
	if s.player.Character == nil then
		return false, "not_ready"
	end
	homeAt[s.player] = now
	PlotService.placeCharacter(s)
	return true, nil
end

-- A new character goes home once it has a root (Roblox drops it at the world's origin first).
function PlotService.watchCharacters(player: Player)
	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			char:WaitForChild("HumanoidRootPart", 10)
			local s = Session.get(player)
			if s and s.ready and player.Character == char then
				PlotService.placeCharacter(s)
			end
		end)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	homeAt[player] = nil
end)

return PlotService
