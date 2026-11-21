--!strict
-- The whole screen's size in UI units, for everything drawn edge to edge (the pixel layer and the camera's fit, the
-- painted skies). The bug of 2026-11-21, on a phone held sideways: "There is a bug causing a bar to appear at the
-- right": a strip at the right edge showed Roblox's own 3D view, about as wide as the safe-area margins a notched
-- phone keeps either side in landscape. Camera.ViewportSize there left those margins out, so the pixel layer (a
-- full-screen ScreenGui, drawn from the screen's left edge) was made that much too narrow. A ScreenGui that ignores
-- every inset (ScreenInsets None and IgnoreGuiInset) spans the whole screen, the margins too: `full` is the larger
-- of the two on each axis, and `Changed` fires when it changes.
-- A size under MIN_SIDE on either axis is not a screen: a window minimised or tabbed away from can say 0 x 0, 1 x 1
-- or a title bar's strip. The last real size stands meanwhile, so nothing is laid out or drawn again for it (the
-- report of 2026-11-21, "the island sometimes disappeared when the player tabs out": the pixel layer was made again
-- for the strip and again on the way back, its picture baked afresh each time with the island hidden meanwhile).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ScreenSize = {}

local changedEvent = Instance.new("BindableEvent")
ScreenSize.Changed = changedEvent.Event

local MIN_SIDE = 100
local probe: ScreenGui? = nil
local last = Vector2.zero
local good: Vector2? = nil -- the last real size
local ensureProbe: () -> ScreenGui?

-- The whole screen: the camera's viewport or, where that leaves the safe-area margins out, the full-screen probe; the
-- last real size while neither is one.
function ScreenSize.full(): Vector2
	local cam = Workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.zero
	local g = ensureProbe()
	if g then
		local a = g.AbsoluteSize
		v = Vector2.new(math.max(v.X, a.X), math.max(v.Y, a.Y))
	end
	if v.X < MIN_SIDE or v.Y < MIN_SIDE then
		return good or Vector2.new(1280, 720)
	end
	good = v
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
