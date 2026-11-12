--!strict
-- The islands on the sea (docs/ARCHITECTURE.md 7.5; GAME_DESIGN 8). At start the whole sea is built: every island
-- plot's stretch of boardwalk and water (Workspace.Plots.Street) and an empty sandbar on every plot. A player who
-- joins takes the lowest free plot: Workspace.Plots.Plot_<i>.Static gets their island (Static.Land: its grass and
-- coast, the plaza and campfire, the path and jetty, the sign, the mailbox) and their buildings and decor
-- (Static.Decor, one model a piece, named by its uid, kind, place and level); the island is rebuilt only when its tier
-- changes, the pieces by difference, so a client's renderer re-casts as little as possible. A new part
-- goes up before an old one comes down. A player who leaves leaves an empty sandbar. Plot_<i>'s attributes tell every
-- client who is there and who lives there (WorldView draws every island's driftlings from them):
-- Owner, OwnerName, StudioName (the island's name), Tier, Day, Charm, Pals (the driftlings in its huts). The founder (the player's
-- character) appears on their own path.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local StreetModels = require(ReplicatedStorage.Shared.Models.StreetModels)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local Session = require(script.Parent.Session)

local PlotService = {}

type S = Session.S

local taken: { [number]: Player } = {}
-- Each occupied plot's island for the next tier, built ahead in the background (a few dozen parts a frame) so an
-- expansion swaps it in at once instead of making ~1,200 parts in one frame.
local nextLand: { [number]: { tier: number, model: Model?, gen: number } } = {}
local prebuildGen = 0
local prebuildQueue: { { plot: number, tier: number, gen: number } } = {}
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

-- Builds the queued next islands one at a time, paced (Blocks.pace) so the server never stalls a frame on them.
local function prebuildLoop()
	if prebuilding then
		return
	end
	prebuilding = true
	while #prebuildQueue > 0 do
		local job = table.remove(prebuildQueue, 1) :: { plot: number, tier: number, gen: number }
		local slot = nextLand[job.plot]
		if slot and slot.gen == job.gen then
			local holder = Instance.new("Folder")
			Blocks.pace(function()
				task.wait()
			end, 60)
			local ok, m = pcall(StreetModels.land, holder, originOf(job.plot), job.tier)
			Blocks.pace(nil)
			local still = nextLand[job.plot]
			if ok and still and still.gen == job.gen then
				m.Parent = nil
				still.model = m
			else
				if not ok then
					warn("next island build failed: " .. tostring(m))
				end
			end
			holder:Destroy()
		end
	end
	prebuilding = false
end

-- Forget plot i's next island (a new one is queued when `tier` is given and the island can still grow).
local function planNext(i: number, tier: number?)
	local old = nextLand[i]
	if old and old.model then
		old.model:Destroy()
	end
	nextLand[i] = nil
	if tier == nil or Island.expandCost(tier) == nil then
		return
	end
	prebuildGen += 1
	nextLand[i] = { tier = tier + 1, model = nil, gen = prebuildGen }
	table.insert(prebuildQueue, { plot = i, tier = tier + 1, gen = prebuildGen })
	task.defer(prebuildLoop)
end

-- An empty lot on plot i, with no attributes left of its last owner.
local function emptyLot(i: number)
	local m = plotModel(i)
	for _, k in { "Owner", "OwnerName", "StudioName", "Tier", "Day", "Charm", "Pals" } do
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
	-- the invisible walls ("Bounds") keep founders in but are never in the pixel filter's rays ("PixelRays")
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Bounds")
		PhysicsService:RegisterCollisionGroup("PixelRays")
		PhysicsService:CollisionGroupSetCollidable("PixelRays", "Bounds", false)
	end)
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
local function pieceKey(q: { uid: number, id: string, x: number, z: number, rot: number, lvl: number }): string
	return string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl or 1)
end

-- The decor by difference: keep the models whose piece is still there, build the new ones, remove the gone ones. The
-- Tree of Life's model goes by its stage (Tree.stage: it grows bigger at Luck milestones) in place of a level, so a
-- new stage builds it again.
function PlotService.buildDecor(s: S)
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
	local o = originOf(s.plot)
	local stage = Tree.stage(s.profile)
	for _, q in s.profile.plot.placed do
		local lvl = if q.id == Tree.ID then stage else q.lvl or 1
		local key = pieceKey({ uid = q.uid, id = q.id, x = q.x, z = q.z, rot = q.rot, lvl = lvl })
		want[key] = true
		if d:FindFirstChild(key) == nil then
			local w, dd = Plot.footprint(q.id, q.rot)
			local at = CFrame.new(o + Vector3.new(q.x + w / 2, Street.LAWN_Y, q.z + dd / 2)) * CFrame.Angles(0, math.rad(q.rot), 0)
			local m = DecorModels.build(q.id, at, lvl)
			m.Name = key
			m.Parent = d
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
	if static:GetAttribute("Built") ~= tier then
		local o = originOf(s.plot)
		-- built ahead in the background: swap it in (the slot forgets it, so planNext doesn't destroy it)
		local ready = nextLand[s.plot]
		local made: Model? = nil
		if ready and ready.tier == tier then
			made = ready.model
			ready.model = nil
		end
		if made then
			swaps += 1
			replace(static, "Land", function(f)
				made.Parent = f
			end)
		else
			replace(static, "Land", function(f)
				StreetModels.land(f, o, tier)
			end)
		end
		static:SetAttribute("Built", tier)
		planNext(s.plot, tier)
	elseif nextLand[s.plot] == nil then
		planNext(s.plot, tier)
	end
	PlotService.buildDecor(s)
	PlotService.sync(s)
end

-- Plot i's island built ahead: the tier it is for (nil: none planned), whether it is finished, and how many
-- expansions so far swapped one in (the sim's check).
function PlotService.debugNext(i: number): (number?, boolean, number)
	local n = nextLand[i]
	return if n then n.tier else nil, n ~= nil and n.model ~= nil, swaps
end

-- The plot's attributes from the session (cheap: only changed values replicate).
function PlotService.sync(s: S)
	local m = plotModel(s.plot)
	local p = s.profile
	-- who lives there: each driftling in a hut "id.species.work.home" (work: the uid of the building it works at, 0
	-- resting; home: its hut). The Tree of Life's pen is no place on the island ("no need to render the pen, just a
	-- ui should be enough"): its driftlings are left out.
	local pals = {}
	for _, x in p.pals do
		if (x.home or 0) ~= 0 then
			table.insert(pals, string.format("%d.%s.%d.%d", x.id, x.sp, x.work, x.home))
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
	local f = p.founder
	local look = string.format("%d.%d.%d.%d", f.skin, f.hair, f.style, f.shirt)
	if s.player:GetAttribute("Founder") ~= look then
		s.player:SetAttribute("Founder", look)
	end
	s.player:SetAttribute("Plot", s.plot)
end

------------------------------------------------------------------ the founder
-- Where a session's founder appears (world CFrame): on the path just south of the plaza.
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

-- "Go home" (char.home): the founder back on their own footpath, at most once every Tuning.HomeCooldown seconds.
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
