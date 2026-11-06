--!strict
-- Plots (docs/ARCHITECTURE.md 7.5): each player gets the lowest free plot in the row along X and their office is
-- built there from code (Models/OfficeModels) under Workspace.Plots.Plot_<i>.Static, which every client's pixel
-- renderer raycasts. A move builds the new office before the old one comes down, so nobody sees an empty lot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Office = require(ReplicatedStorage.Shared.Data.Office)
local OfficeModels = require(ReplicatedStorage.Shared.Models.OfficeModels)
local Session = require(script.Parent.Session)

local PlotService = {}

type S = Session.S

local taken: { [number]: Player } = {}
local plotsFolder: Folder? = nil

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

function PlotService.init()
	folder()
end

-- The lowest free plot index for a player.
function PlotService.claim(player: Player): number
	local i = 1
	while taken[i] do
		i += 1
	end
	taken[i] = player
	return i
end

function PlotService.release(i: number)
	taken[i] = nil
	local plot = folder():FindFirstChild("Plot_" .. i)
	if plot then
		plot:Destroy()
	end
end

-- (Re)build the session's office for its tier. The new Static goes up first, then the old one comes down.
function PlotService.build(s: S)
	local root = folder()
	local name = "Plot_" .. s.plot
	local plot = root:FindFirstChild(name)
	if plot == nil then
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = root
		plot = m
	end
	local p = plot :: Instance
	p:SetAttribute("Owner", s.player.UserId)
	p:SetAttribute("Tier", s.profile.office)
	local old = p:FindFirstChild("Static")
	local static = Instance.new("Folder")
	static.Name = "Static"
	local ox, oz = Office.origin(s.plot)
	OfficeModels.build(static, s.profile.office, Vector3.new(ox, 0, oz))
	static.Parent = p
	if old then
		old.Name = "Old"
		old:Destroy()
	end
end

return PlotService
