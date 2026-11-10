--!strict
-- The islands on the sea (docs/ARCHITECTURE.md 7.5; GAME_DESIGN 8). At start the whole sea is built: every island
-- plot's stretch of boardwalk and water (Workspace.Plots.Street) and an empty sandbar on every plot. A player who
-- joins takes the lowest free plot: Workspace.Plots.Plot_<i>.Static gets their island (Static.Land: its grass and
-- coast, the plaza and campfire, the path and jetty, the sign, the mailbox) and their buildings and decor
-- (Static.Decor, one model a piece, named by its uid, kind, place and level); the island is rebuilt only when its tier
-- changes, the pieces by difference, so a client's renderer re-casts as little as possible. A new part
-- goes up before an old one comes down. A player who leaves leaves an empty sandbar. Plot_<i>'s attributes tell every
-- client who is there and who lives there (WorldView draws every island's villagers and driftlings from them):
-- Owner, OwnerName, StudioName (the island's name), Tier, Day, Charm, Islets, Folk, Pals. The founder (the player's
-- character) appears on their own path.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local StreetModels = require(ReplicatedStorage.Shared.Models.StreetModels)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local Session = require(script.Parent.Session)

local PlotService = {}

type S = Session.S

local taken: { [number]: Player } = {}
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

-- An empty lot on plot i, with no attributes left of its last owner.
local function emptyLot(i: number)
	local m = plotModel(i)
	for _, k in { "Owner", "OwnerName", "StudioName", "Tier", "Day", "Charm", "Islets", "Folk", "Pals", "Sailing" } do
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
	emptyLot(i)
end

------------------------------------------------------------------ building a studio's plot
local function pieceKey(q: { uid: number, id: string, x: number, z: number, rot: number, lvl: number }): string
	return string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl or 1)
end

-- The decor by difference: keep the models whose piece is still there, build the new ones, remove the gone ones.
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
	for _, q in s.profile.plot.placed do
		local key = pieceKey(q)
		want[key] = true
		if d:FindFirstChild(key) == nil then
			local w, dd = Plot.footprint(q.id, q.rot)
			local at = CFrame.new(o + Vector3.new(q.x + w / 2, Street.LAWN_Y, q.z + dd / 2)) * CFrame.Angles(0, math.rad(q.rot), 0)
			local m = DecorModels.build(q.id, at, q.lvl or 1)
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
		replace(static, "Land", function(f)
			StreetModels.land(f, o, tier)
		end)
		static:SetAttribute("Built", tier)
	end
	PlotService.buildDecor(s)
	PlotService.sync(s)
end

-- The plot's attributes from the session (cheap: only changed values replicate).
function PlotService.sync(s: S)
	local m = plotModel(s.plot)
	local p = s.profile
	-- who lives there: a villager "id.skin.hair.style.shirt.work.away", a driftling "id.species.work.away" (work: the
	-- uid of the building they work or help at, 0 idle; away: 1 while on an expedition)
	local away = s.away or {}
	local folk = {}
	for _, v in p.folk do
		local l = v.look
		table.insert(folk, string.format("%d.%d.%d.%d.%d.%d.%d", v.id, l.skin, l.hair, l.style, l.shirt, v.work, if away["v" .. v.id] then 1 else 0))
	end
	local pals = {}
	for _, x in p.pals do
		table.insert(pals, string.format("%d.%s.%d.%d", x.id, x.sp, x.work, if away["p" .. x.id] then 1 else 0))
	end
	local function set(k: string, v: any)
		if m:GetAttribute(k) ~= v then
			m:SetAttribute(k, v)
		end
	end
	set("Tier", p.tier)
	set("Day", p.day)
	set("Charm", Island.charm(p))
	set("Islets", p.islets)
	set("Folk", table.concat(folk, ";"))
	set("Pals", table.concat(pals, ";"))
	set("Sailing", s.exp ~= nil)
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
