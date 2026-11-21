--!strict
-- The whole screen's size in UI units, for everything drawn edge to edge (the pixel layer and the camera's fit, the
-- painted skies). The bug of 2026-11-21, on a phone held sideways: "There is a bug causing a bar to appear at the
-- right": a strip at the right edge showed Roblox's own 3D view, about as wide as the safe-area margins a notched
-- phone keeps either side in landscape. Camera.ViewportSize there left those margins out, so the pixel layer (a
-- full-screen ScreenGui, drawn from the screen's left edge) was made that much too narrow. A ScreenGui that ignores
-- every inset (ScreenInsets None and IgnoreGuiInset) spans the whole screen, the margins too: `full` is the larger
-- of the two on each axis, and `Changed` fires when it changes.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ScreenSize = {}

local changedEvent = Instance.new("BindableEvent")
ScreenSize.Changed = changedEvent.Event

local probe: ScreenGui? = nil
local last = Vector2.zero
local ensureProbe: () -> ScreenGui?

local function viewport(): Vector2
	local cam = Workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	if v.X < 2 or v.Y < 2 then
		return Vector2.new(1280, 720)
	end
	return v
end

-- The whole screen: the camera's viewport or, where that leaves the safe-area margins out, the full-screen probe.
function ScreenSize.full(): Vector2
	local v = viewport()
	local g = ensureProbe()
	if g then
		local a = g.AbsoluteSize
		if a.X >= 2 and a.Y >= 2 then
			v = Vector2.new(math.max(v.X, a.X), math.max(v.Y, a.Y))
		end
	end
	return v
end

local function check()
	local v = ScreenSize.full()
	if v ~= last then
		last = v
		changedEvent:Fire(v)
	end
end

ensureProbe = function(): ScreenGui?
	local g = probe
	if g and g.Parent then
		return g
	end
	local pl = Players.LocalPlayer
	local pg = if pl then pl:FindFirstChildOfClass("PlayerGui") else nil
	if pg == nil then
		return nil
	end
	local ng = Instance.new("ScreenGui")
	ng.Name = "ScreenProbe"
	ng.IgnoreGuiInset = true
	ng.ScreenInsets = Enum.ScreenInsets.None
	ng.ResetOnSpawn = false
	ng.DisplayOrder = -1000
	ng.Parent = pg
	probe = ng
	ng:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(check)
	end)
	return ng
end

-- (the camera's viewport changing fires it too: callers listen to one signal)
function ScreenSize.start()
	ensureProbe()
	last = ScreenSize.full()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(check)
		end)
	end
end

return ScreenSize
