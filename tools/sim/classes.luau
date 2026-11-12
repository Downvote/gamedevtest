-- Class behaviours for the fake engine: parts, models, GUI geometry, camera, humanoid, run service, tweens, sounds.
local E = require("./engine")
local I = require("./inst")
local v3, v2, c3 = E.v3, E.v2, E.c3
local CF = E.cf
local typeOf = E.typeof
local Enum = E.Enum
local task = E.task
local getD = I.getD
local IMPL, GET, SET, DEFAULT, READONLY, INIT = I.IMPL, I.GET, I.SET, I.DEFAULT, I.READONLY, I.INIT
local UDim2 = E.types.UDim2

local function ctxKind()
	return E.curCtx().kind
end

------------------------------------------------------------------ BasePart
DEFAULT.BasePart = {
	Size = v3(4, 1, 2),
	Color = c3(163 / 255, 162 / 255, 165 / 255),
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	Transparency = 0,
	Reflectance = 0,
	Archivable = true,
	PivotOffset = CF.identity,
	CFrame = CF.identity,
}
DEFAULT.Part = { Shape = function()
	return Enum.PartType.Block
end }
DEFAULT.Instance = { Archivable = true }
local function checkFiniteCF(cf, what)
	local x, y, z = cf.X, cf.Y, cf.Z
	if x ~= x or y ~= y or z ~= z or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
		E.issue("nan-cframe", what .. " set to a non-finite CFrame")
		return false
	end
	return true
end
local function setPartCF(self, d, cf)
	checkFiniteCF(cf, I.fullName(self) .. ".CFrame")
	local old = d.props.CFrame
	d.props.CFrame = cf
	if old ~= cf then
		I.firePropChanged(self, d, "CFrame")
		I.firePropChanged(self, d, "Position")
		I.firePropChanged(self, d, "Orientation")
	end
end
I.setPartCF = setPartCF
local function partCF(self, d)
	return d.props.CFrame or CF.identity
end
GET.BasePart = {
	Position = function(self, d)
		return partCF(self, d).Position
	end,
	Orientation = function(self, d)
		local rx, ry, rz = partCF(self, d):ToOrientation()
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	end,
	Rotation = function(self, d)
		local rx, ry, rz = partCF(self, d):ToEulerAnglesXYZ()
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	end,
	ExtentsSize = function(self, d)
		return d.props.Size or v3(4, 1, 2)
	end,
	Mass = function(self, d)
		local s = d.props.Size or v3(4, 1, 2)
		return s.X * s.Y * s.Z * 0.7
	end,
}
SET.BasePart = {
	CFrame = setPartCF,
	Position = function(self, d, v)
		local cf = partCF(self, d)
		setPartCF(self, d, CF.new(v.X, v.Y, v.Z) * cf.Rotation)
	end,
	Orientation = function(self, d, v)
		local p = partCF(self, d).Position
		setPartCF(self, d, CF.new(p.X, p.Y, p.Z) * CF.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
	end,
	Rotation = function(self, d, v)
		local p = partCF(self, d).Position
		setPartCF(self, d, CF.new(p.X, p.Y, p.Z) * CF.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)))
	end,
	Size = function(self, d, v)
		if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
			E.issue("nan-size", I.fullName(self) .. ".Size set to NaN")
		end
		local nv = v3(math.max(0.001, v.X), math.max(0.001, v.Y), math.max(0.001, v.Z))
		local old = d.props.Size
		d.props.Size = nv
		if old ~= nv then
			I.firePropChanged(self, d, "Size")
		end
	end,
}
READONLY.BasePart = { Mass = true, ExtentsSize = true, AssemblyMass = true }
local function partPivot(self)
	local d = getD(self)
	return partCF(self, d) * (d.props.PivotOffset or CF.identity)
end
IMPL.BasePart = {
	GetPivot = partPivot,
	PivotTo = function(self, cf)
		if not E.isCF(cf) then
			error("PivotTo: CFrame expected", 2)
		end
		local d = getD(self)
		setPartCF(self, d, cf * (d.props.PivotOffset or CF.identity):Inverse())
	end,
	GetMass = function(self)
		return self.Mass
	end,
	GetTouchingParts = function()
		return {}
	end,
	GetConnectedParts = function()
		return {}
	end,
	ApplyImpulse = function() end,
	SetNetworkOwner = function() end,
	GetNetworkOwner = function()
		return nil
	end,
	CanSetNetworkOwnership = function()
		return true, nil
	end,
}

------------------------------------------------------------------ Model
local function partsOf(model)
	local out = {}
	for _, x in I.descendants(model, {}) do
		if I.isA(getD(x).cls, "BasePart") then
			table.insert(out, x)
		end
	end
	return out
end
I.partsOf = partsOf
local function bboxIn(parts, frame)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local inv = frame:Inverse()
	for _, p in parts do
		local pd = getD(p)
		local cf = pd.props.CFrame or CF.identity
		local s = pd.props.Size or v3(4, 1, 2)
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		local rel = inv * cf
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = rel * v3(sx * hx, sy * hy, sz * hz)
					minX, minY, minZ = math.min(minX, c.X), math.min(minY, c.Y), math.min(minZ, c.Z)
					maxX, maxY, maxZ = math.max(maxX, c.X), math.max(maxY, c.Y), math.max(maxZ, c.Z)
				end
			end
		end
	end
	local center = frame * v3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	return CF.new(center.X, center.Y, center.Z) * frame.Rotation, v3(maxX - minX, maxY - minY, maxZ - minZ)
end
local function modelPivot(self)
	local d = getD(self)
	local pp = d.props.PrimaryPart
	if pp and pp:IsDescendantOf(self) then
		return partPivot(pp)
	end
	if d.props.WorldPivot then
		return d.props.WorldPivot
	end
	local parts = partsOf(self)
	if #parts == 0 then
		return CF.identity
	end
	local cf = bboxIn(parts, CF.identity)
	return cf
end
GET.Model = {
	WorldPivot = function(self, d)
		if d.props.WorldPivot then
			return d.props.WorldPivot
		end
		return modelPivot(self)
	end,
}
SET.Model = {
	PrimaryPart = function(self, d, v)
		if v ~= nil and not v:IsDescendantOf(self) then
			error("PrimaryPart must be a descendant of the model", 3)
		end
		d.props.PrimaryPart = v
		if v == nil then
			d.propsNil = d.propsNil or {}
			d.propsNil.PrimaryPart = true
		end
	end,
}
IMPL.Model = {
	GetPivot = modelPivot,
	PivotTo = function(self, cf)
		if not E.isCF(cf) then
			error("PivotTo: CFrame expected, got " .. typeOf(cf), 2)
		end
		checkFiniteCF(cf, I.fullName(self) .. ":PivotTo")
		local d = getD(self)
		local cur = modelPivot(self)
		local delta = cf * cur:Inverse()
		for _, p in partsOf(self) do
			local pd = getD(p)
			setPartCF(p, pd, delta * (pd.props.CFrame or CF.identity))
		end
		local pp = d.props.PrimaryPart
		if not (pp and pp:IsDescendantOf(self)) then
			d.props.WorldPivot = cf
		elseif d.props.WorldPivot then
			d.props.WorldPivot = delta * d.props.WorldPivot
		end
	end,
	GetBoundingBox = function(self)
		local parts = partsOf(self)
		local pivot = modelPivot(self)
		if #parts == 0 then
			return pivot, v3(0, 0, 0)
		end
		return bboxIn(parts, pivot.Rotation)
	end,
	GetExtentsSize = function(self)
		local parts = partsOf(self)
		if #parts == 0 then
			return v3(0, 0, 0)
		end
		local _, s = bboxIn(parts, modelPivot(self).Rotation)
		return s
	end,
	GetScale = function(self)
		return getD(self).scale or 1
	end,
	ScaleTo = function(self, s)
		if type(s) ~= "number" or s ~= s or s <= 0 or s == math.huge then
			error("Model:ScaleTo() scale factor must be a positive number", 2)
		end
		local d = getD(self)
		local cur = d.scale or 1
		local ratio = s / cur
		local pivot = modelPivot(self)
		local inv = pivot:Inverse()
		for _, p in partsOf(self) do
			local pd = getD(p)
			local rel = inv * (pd.props.CFrame or CF.identity)
			local pos = rel.Position * ratio
			setPartCF(p, pd, pivot * (CF.new(pos.X, pos.Y, pos.Z) * rel.Rotation))
			local sz = pd.props.Size or v3(4, 1, 2)
			pd.props.Size = sz * ratio
		end
		d.scale = s
	end,
	MoveTo = function(self, pos)
		local piv = modelPivot(self)
		IMPL.Model.PivotTo(self, CF.new(pos.X, pos.Y, pos.Z) * piv.Rotation)
	end,
	TranslateBy = function(self, delta)
		IMPL.Model.PivotTo(self, modelPivot(self) + delta)
	end,
	SetPrimaryPartCFrame = function(self, cf)
		IMPL.Model.PivotTo(self, cf)
	end,
	GetPrimaryPartCFrame = function(self)
		return modelPivot(self)
	end,
	BreakJoints = function() end,
	MakeJoints = function() end,
}

------------------------------------------------------------------ Workspace
IMPL.Workspace = {
	GetServerTimeNow = function(_self)
		return E.now()
	end,
	GetRealPhysicsFPS = function()
		return 60
	end,
}
local function rayOBB(origin, dir, cf, size)
	local inv = cf:Inverse()
	local o = inv * origin
	local dd = inv:VectorToWorldSpace(dir)
	local half = { size.X / 2, size.Y / 2, size.Z / 2 }
	local oo = { o.X, o.Y, o.Z }
	local d3 = { dd.X, dd.Y, dd.Z }
	local tmin, tmax = 0, 1
	local nAxis, nSign = 0, 0
	for a = 1, 3 do
		if math.abs(d3[a]) < 1e-12 then
			if oo[a] < -half[a] or oo[a] > half[a] then
				return nil
			end
		else
			local t1 = (-half[a] - oo[a]) / d3[a]
			local t2 = (half[a] - oo[a]) / d3[a]
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin = t1
				nAxis, nSign = a, s
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	local nl = v3(if nAxis == 1 then nSign else 0, if nAxis == 2 then nSign else 0, if nAxis == 3 then nSign else 0)
	return tmin, cf:VectorToWorldSpace(nl)
end
IMPL.WorldRoot = {
	Raycast = function(self, origin, dir, params)
		if not E.isV3(origin) or not E.isV3(dir) then
			error("Raycast: Vector3 expected", 2)
		end
		if params ~= nil and typeOf(params) ~= "RaycastParams" then
			error("Raycast: RaycastParams expected, got " .. typeOf(params), 2)
		end
		E.stats.raycasts = (E.stats.raycasts or 0) + 1
		if E.raycastParts then
			local filter = params and params.FilterDescendantsInstances or {}
			local include = params and params.FilterType == Enum.RaycastFilterType.Include
			-- (as Roblox: a part whose collision group doesn't collide with the ray's is passed through)
			local rayGroup = params and params.CollisionGroup or "Default"
			local best, bestPart, bestN = math.huge, nil, nil
			for _, p in partsOf(self) do
				local pd = getD(p)
				-- (as Roblox: CanQuery = false only counts on a part that doesn't collide)
				local queried = pd.props.CanQuery ~= false or pd.props.CanCollide ~= false
				if queried and E.collisionGroupsCollide(rayGroup, pd.props.CollisionGroup or "Default") then
					local inFilter = false
					for _, f in filter do
						if p == f or p:IsDescendantOf(f) then
							inFilter = true
							break
						end
					end
					if (include and inFilter) or (not include and not inFilter) then
						local t, n = rayOBB(origin, dir, pd.props.CFrame or CF.identity, pd.props.Size or v3(4, 1, 2))
						if t and t < best then
							best, bestPart, bestN = t, p, n
						end
					end
				end
			end
			if bestPart then
				local pos = origin + dir * best
				return E.mkRaycastResult({ Instance = bestPart, Position = pos, Normal = bestN, Distance = (dir * best).Magnitude, Material = Enum.Material.SmoothPlastic })
			end
			return nil
		end
		-- default: ground plane y = 0 only (no instance hit)
		if dir.Y < 0 and origin.Y > 0 then
			local t = -origin.Y / dir.Y
			if t <= 1 then
				local pos = origin + dir * t
				local ground = E.groundPart
				return E.mkRaycastResult({ Instance = ground, Position = pos, Normal = v3(0, 1, 0), Distance = (dir * t).Magnitude, Material = Enum.Material.Grass })
			end
		end
		return nil
	end,
	BulkMoveTo = function(self, parts, cfs, mode)
		if type(parts) ~= "table" or type(cfs) ~= "table" then
			error("BulkMoveTo: tables expected", 2)
		end
		if #parts ~= #cfs then
			error("BulkMoveTo: partList and cframeList must be the same length", 2)
		end
		for i, p in parts do
			if not I.isInst(p) or not I.isA(getD(p).cls, "BasePart") then
				error("BulkMoveTo: BasePart expected at " .. i, 2)
			end
			if not E.isCF(cfs[i]) then
				error("BulkMoveTo: CFrame expected at " .. i, 2)
			end
			setPartCF(p, getD(p), cfs[i])
		end
	end,
	GetPartBoundsInBox = function()
		return {}
	end,
	GetPartBoundsInRadius = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
	Spherecast = function()
		return nil
	end,
	Blockcast = function()
		return nil
	end,
}

------------------------------------------------------------------ RaycastParams / OverlapParams
local RPMT = {}
E.TYPEOF_REGISTER(RPMT, "RaycastParams")
RPMT.__index = function(t, k)
	if k == "AddToFilter" then
		return function(self, x)
			local list = rawget(self, "_f")
			if type(x) == "table" and not I.isInst(x) then
				for _, y in x do
					table.insert(list, y)
				end
			else
				table.insert(list, x)
			end
		end
	end
	local f = rawget(t, "_f")
	if k == "FilterDescendantsInstances" then
		return table.clone(f)
	end
	local v = rawget(t, "_p")[k]
	if v ~= nil then
		return v
	end
	if k == "FilterType" then
		return Enum.RaycastFilterType.Exclude
	elseif k == "IgnoreWater" or k == "RespectCanCollide" or k == "BruteForceAllSlow" then
		return false
	elseif k == "CollisionGroup" then
		return "Default"
	end
	error(tostring(k) .. " is not a valid member of RaycastParams", 2)
end
RPMT.__newindex = function(t, k, v)
	if k == "FilterDescendantsInstances" then
		if type(v) ~= "table" then
			error("FilterDescendantsInstances must be an array", 2)
		end
		for _, x in v do
			if not I.isInst(x) then
				error("FilterDescendantsInstances: Instance expected, got " .. typeOf(x), 2)
			end
		end
		rawset(t, "_f", table.clone(v))
		return
	end
	if k == "FilterType" or k == "IgnoreWater" or k == "CollisionGroup" or k == "RespectCanCollide" or k == "BruteForceAllSlow" then
		rawget(t, "_p")[k] = v
		return
	end
	error(tostring(k) .. " is not a valid member of RaycastParams", 2)
end
E.types.RaycastParams = {
	new = function()
		return setmetatable({ _f = {}, _p = {} }, RPMT)
	end,
}
E.types.OverlapParams = {
	new = function()
		return setmetatable({ _f = {}, _p = {} }, RPMT)
	end,
}

------------------------------------------------------------------ Camera
E.viewport = v2(1280, 720)
E.inset = 36
DEFAULT.Camera = { FieldOfView = 70, CFrame = CF.identity, NearPlaneZ = -0.1, Focus = CF.identity }
GET.Camera = {
	ViewportSize = function()
		return E.viewport
	end,
}
READONLY.Camera = { ViewportSize = true }
local Ray = {}
local RayMT = { __index = function(_, k)
	error(tostring(k) .. " is not a valid member of Ray", 2)
end }
E.TYPEOF_REGISTER(RayMT, "Ray")
local function mkRay(o, d)
	return setmetatable({ Origin = o, Direction = d, Unit = nil }, RayMT)
end
E.types.Ray = { new = mkRay }
local function camRay(self, x, y, depth)
	local d = getD(self)
	local cf = d.props.CFrame or CF.identity
	local fov = math.rad(d.props.FieldOfView or 70)
	local vp = E.viewport
	local th = math.tan(fov / 2)
	local nx = (x / vp.X) * 2 - 1
	local ny = 1 - (y / vp.Y) * 2
	local dirL = v3(nx * th * vp.X / vp.Y, ny * th, -1).Unit
	local dir = cf:VectorToWorldSpace(dirL)
	return mkRay(cf.Position, dir * (depth or 1))
end
local function camProject(self, p)
	local d = getD(self)
	local cf = d.props.CFrame or CF.identity
	local fov = math.rad(d.props.FieldOfView or 70)
	local vp = E.viewport
	local l = cf:PointToObjectSpace(p)
	local depth = -l.Z
	local th = math.tan(fov / 2)
	if depth <= 1e-6 then
		return v3(0, 0, depth), false
	end
	local nx = l.X / (depth * th * vp.X / vp.Y)
	local ny = l.Y / (depth * th)
	local sx = (nx + 1) / 2 * vp.X
	local sy = (1 - ny) / 2 * vp.Y
	return v3(sx, sy, depth), sx >= 0 and sx <= vp.X and sy >= 0 and sy <= vp.Y
end
IMPL.Camera = {
	ViewportPointToRay = function(self, x, y, depth)
		return camRay(self, x, y, depth)
	end,
	ScreenPointToRay = function(self, x, y, depth)
		return camRay(self, x, y + E.inset, depth)
	end,
	WorldToViewportPoint = function(self, p)
		return camProject(self, p)
	end,
	WorldToScreenPoint = function(self, p)
		local v, on = camProject(self, p)
		return v3(v.X, v.Y - E.inset, v.Z), on
	end,
	GetPivot = function(self)
		return getD(self).props.CFrame or CF.identity
	end,
	PivotTo = function(self, cf)
		self.CFrame = cf
	end,
}

------------------------------------------------------------------ GUI geometry
DEFAULT.GuiObject = {
	Visible = true,
	BackgroundTransparency = 0,
	BackgroundColor3 = c3(1, 1, 1),
	ZIndex = 1,
	Size = UDim2.new(0, 100, 0, 100),
	Position = UDim2.new(0, 0, 0, 0),
	AnchorPoint = v2(0, 0),
	BorderSizePixel = 1,
	Active = false,
	Selectable = false,
	Interactable = true,
}
DEFAULT.GuiButton = { AutoButtonColor = true, Active = true, Selectable = true }
DEFAULT.TextLabel = { TextSize = 14, Text = "Label", TextColor3 = c3(0, 0, 0), TextTransparency = 0, TextStrokeTransparency = 1 }
DEFAULT.TextButton = { TextSize = 14, Text = "Button", TextColor3 = c3(0, 0, 0), TextTransparency = 0, TextStrokeTransparency = 1 }
DEFAULT.TextBox = { TextSize = 14, Text = "TextBox", TextColor3 = c3(0, 0, 0), TextEditable = true, ClearTextOnFocus = true }
DEFAULT.ImageLabel = { ImageTransparency = 0, ImageColor3 = c3(1, 1, 1) }
DEFAULT.ImageButton = { ImageTransparency = 0, ImageColor3 = c3(1, 1, 1) }
DEFAULT.ScrollingFrame = { ScrollingEnabled = true, ScrollBarThickness = 12, CanvasSize = UDim2.new(0, 0, 2, 0), CanvasPosition = v2(0, 0) }
DEFAULT.LayerCollector = { Enabled = true, ResetOnSpawn = true }
DEFAULT.ScreenGui = { DisplayOrder = 0 }
DEFAULT.UIStroke = { Thickness = 1, Enabled = true, Transparency = 0 }
DEFAULT.UIScale = { Scale = 1 }
DEFAULT.UIGridLayout = { CellSize = UDim2.new(0, 100, 0, 100), CellPadding = UDim2.new(0, 5, 0, 5) }
DEFAULT.UIListLayout = { Padding = E.types.UDim.new(0, 0) }
DEFAULT.UIGridStyleLayout = { FillDirection = function()
	return Enum.FillDirection.Vertical
end }
DEFAULT.ViewportFrame = { ImageTransparency = 0 }
DEFAULT.UICorner = { CornerRadius = E.types.UDim.new(0, 8) }
DEFAULT.Highlight = { Enabled = true, FillTransparency = 0.5, OutlineTransparency = 0 }

local function guiAbs(self)
	local d = getD(self)
	if I.isA(d.cls, "LayerCollector") then
		local full = d.props.IgnoreGuiInset == true or d.props.ScreenInsets == Enum.ScreenInsets.None
		if full then
			return v2(0, -E.inset), E.viewport
		end
		return v2(0, 0), v2(E.viewport.X, E.viewport.Y - E.inset)
	end
	local parent = d.props.Parent
	local pPos, pSize = v2(0, 0), v2(0, 0)
	if parent and I.isA(getD(parent).cls, "GuiBase2d") then
		pPos, pSize = guiAbs(parent)
		local pd = getD(parent)
		if pd.cls == "ScrollingFrame" then
			local cs = pd.props.CanvasSize or UDim2.new(0, 0, 2, 0)
			pSize = v2(pSize.X * cs.X.Scale + cs.X.Offset, pSize.Y * cs.Y.Scale + cs.Y.Offset)
		end
	end
	local size = d.props.Size or UDim2.new(0, 100, 0, 100)
	local pos = d.props.Position or UDim2.new(0, 0, 0, 0)
	local ap = d.props.AnchorPoint or v2(0, 0)
	local absSize = v2(pSize.X * size.X.Scale + size.X.Offset, pSize.Y * size.Y.Scale + size.Y.Offset)
	local absPos = v2(pPos.X + pSize.X * pos.X.Scale + pos.X.Offset - ap.X * absSize.X, pPos.Y + pSize.Y * pos.Y.Scale + pos.Y.Offset - ap.Y * absSize.Y)
	return absPos, absSize
end
I.guiAbs = guiAbs
GET.GuiBase2d = {
	AbsoluteSize = function(self)
		local _, s = guiAbs(self)
		return s
	end,
	AbsolutePosition = function(self)
		local p = guiAbs(self)
		return p
	end,
	AbsoluteRotation = function()
		return 0
	end,
}
READONLY.GuiBase2d = { AbsoluteSize = true, AbsolutePosition = true, AbsoluteRotation = true }
local function textBounds(self, d)
	local text = d.props.Text or ""
	local size = d.props.TextSize or 14
	text = string.gsub(text, "<[^>]*>", "")
	local lines = 1
	for _ in string.gmatch(text, "\n") do
		lines += 1
	end
	return v2(math.min(#text, 60) * size * 0.5, size * lines)
end
GET.TextLabel = { TextBounds = textBounds, TextFits = function()
	return true
end, ContentText = function(self, d)
	return d.props.Text or ""
end }
GET.TextButton = GET.TextLabel
GET.TextBox = GET.TextLabel
READONLY.TextLabel = { TextBounds = true, TextFits = true, ContentText = true }
READONLY.TextButton = READONLY.TextLabel
READONLY.TextBox = READONLY.TextLabel
GET.ScrollingFrame = {
	AbsoluteCanvasSize = function(self, d)
		local _, s = guiAbs(self)
		local cs = d.props.CanvasSize or UDim2.new(0, 0, 2, 0)
		return v2(s.X * cs.X.Scale + cs.X.Offset, s.Y * cs.Y.Scale + cs.Y.Offset)
	end,
	AbsoluteWindowSize = function(self)
		local _, s = guiAbs(self)
		return s
	end,
}
READONLY.ScrollingFrame = { AbsoluteCanvasSize = true, AbsoluteWindowSize = true }
GET.UIGridStyleLayout = {
	AbsoluteContentSize = function(self, d)
		local parent = d.props.Parent
		if not parent then
			return v2(0, 0)
		end
		local horizontal = d.props.FillDirection == Enum.FillDirection.Horizontal
		local pad = 0
		if d.cls == "UIListLayout" then
			local p = d.props.Padding
			pad = if p then p.Offset else 0
		end
		local sumMain, maxCross, n = 0, 0, 0
		for _, c in getD(parent).children do
			local cd = getD(c)
			if I.isA(cd.cls, "GuiObject") and cd.props.Visible ~= false then
				local _, s = guiAbs(c)
				n += 1
				if horizontal then
					sumMain += s.X
					maxCross = math.max(maxCross, s.Y)
				else
					sumMain += s.Y
					maxCross = math.max(maxCross, s.X)
				end
			end
		end
		if d.cls == "UIGridLayout" then
			local cell = d.props.CellSize or UDim2.new(0, 100, 0, 100)
			local _, ps = guiAbs(parent)
			local perRow = math.max(1, math.floor(ps.X / math.max(1, cell.X.Offset + 5)))
			local rows = math.ceil(n / perRow)
			return v2(ps.X, rows * (cell.Y.Offset + 5))
		end
		sumMain += math.max(0, n - 1) * pad
		if horizontal then
			return v2(sumMain, maxCross)
		end
		return v2(maxCross, sumMain)
	end,
}
READONLY.UIGridStyleLayout = { AbsoluteContentSize = true }
IMPL.UIGridStyleLayout = {
	ApplyLayout = function() end,
}
local function visibleChain(g)
	local cur = g
	while cur do
		local cd = getD(cur)
		if I.isA(cd.cls, "GuiObject") and cd.props.Visible == false then
			return false
		end
		if I.isA(cd.cls, "LayerCollector") then
			return cd.props.Enabled ~= false
		end
		cur = cd.props.Parent
	end
	return false
end
local function guiObjectsAt(root, x, y)
	local hits = {}
	for _, g in I.descendants(root, {}) do
		local gd = getD(g)
		if I.isA(gd.cls, "GuiObject") and visibleChain(g) then
			local p, s = guiAbs(g)
			if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
				table.insert(hits, g)
			end
		end
	end
	return hits
end
IMPL.BasePlayerGui = {
	GetGuiObjectsAtPosition = function(self, x, y)
		return guiObjectsAt(self, x, y)
	end,
	GetGuiObjectsInCircle = function()
		return {}
	end,
}
IMPL.LayerCollector = {
	GetGuiObjectsAtPosition = function(self, x, y)
		return guiObjectsAt(self, x, y)
	end,
}
IMPL.PlayerGui = {
	SetTopbarTransparency = function() end,
	GetTopbarTransparency = function()
		return 0
	end,
}
IMPL.TextBox = {
	CaptureFocus = function(self)
		getD(self).focused = true
		I.fire(I.getSig(self, "Focused"))
	end,
	ReleaseFocus = function(self, submitted)
		getD(self).focused = false
		I.fire(I.getSig(self, "FocusLost"), submitted == true, nil)
	end,
	IsFocused = function(self)
		return getD(self).focused == true
	end,
}
IMPL.GuiObject = {
	TweenPosition = function(self, pos)
		self.Position = pos
		return true
	end,
	TweenSize = function(self, size)
		self.Size = size
		return true
	end,
	TweenSizeAndPosition = function(self, size, pos)
		self.Size = size
		self.Position = pos
		return true
	end,
}
IMPL.ViewportFrame = {}
IMPL.ImageLabel = { SetEnableContentImageSizeChangedEvents = function() end }

------------------------------------------------------------------ Humanoid
-- (FloorMaterial: a humanoid standing on a part, as Roblox reports it; Air only in the air)
DEFAULT.Humanoid = { WalkSpeed = 16, Health = 100, MaxHealth = 100, HipHeight = 2, JumpPower = 50, JumpHeight = 7.2, AutoRotate = true, FloorMaterial = Enum.Material.Plastic }
GET.Humanoid = {
	RootPart = function(self, d)
		local m = d.props.Parent
		if m then
			return m:FindFirstChild("HumanoidRootPart")
		end
		return nil
	end,
}
IMPL.Humanoid = {
	MoveTo = function(self, pos, part)
		if not E.isV3(pos) then
			error("MoveTo: Vector3 expected", 2)
		end
		local d = getD(self)
		local model = d.props.Parent
		d.moveSeq = (d.moveSeq or 0) + 1
		local mySeq = d.moveSeq
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local from = root.Position
		local dist = (v3(pos.X, from.Y, pos.Z) - from).Magnitude
		local speed = d.props.WalkSpeed or 16
		task.delay(math.max(0.05, dist / math.max(1, speed)), function()
			if d.moveSeq ~= mySeq or not model.Parent then
				return
			end
			local r = model:FindFirstChild("HumanoidRootPart")
			if r then
				model:PivotTo(CF.new(pos.X, r.Position.Y, pos.Z) * r.CFrame.Rotation)
			end
			I.fire(I.getSig(self, "MoveToFinished"), true)
		end)
	end,
	ChangeState = function() end,
	GetState = function()
		return Enum.HumanoidStateType.Running
	end,
	SetStateEnabled = function() end,
	TakeDamage = function() end,
	GetAppliedDescription = function()
		E.gap("Humanoid:GetAppliedDescription")
	end,
	LoadAnimation = function()
		E.gap("Humanoid:LoadAnimation")
	end,
}

------------------------------------------------------------------ RunService
local renderBinds = {} -- ctx -> { {name, prio, fn} }
E.renderBinds = renderBinds
IMPL.RunService = {
	IsServer = function()
		return ctxKind() == "server"
	end,
	IsClient = function()
		return ctxKind() == "client"
	end,
	IsStudio = function()
		return E.isStudio
	end,
	IsRunning = function()
		return true
	end,
	IsRunMode = function()
		return false
	end,
	IsEdit = function()
		return false
	end,
	BindToRenderStep = function(self, name, prio, fn)
		local ctx = E.curCtx()
		if ctx.kind ~= "client" then
			error("BindToRenderStep can only be called from the client", 2)
		end
		if type(name) ~= "string" or type(prio) ~= "number" or type(fn) ~= "function" then
			error("BindToRenderStep: bad arguments", 2)
		end
		local list = renderBinds[ctx] or {}
		renderBinds[ctx] = list
		for i, b in list do
			if b.name == name then
				table.remove(list, i)
				break
			end
		end
		table.insert(list, { name = name, prio = prio, fn = fn })
		table.sort(list, function(a, b)
			return a.prio < b.prio
		end)
	end,
	UnbindFromRenderStep = function(self, name)
		local list = renderBinds[E.curCtx()]
		if list then
			for i, b in list do
				if b.name == name then
					table.remove(list, i)
					return
				end
			end
		end
	end,
}
local function clientOnly(what)
	return function(ctx)
		if ctx.kind == "server" then
			error(what .. " event can only be used from local scripts", 3)
		end
	end
end
I.SIGGUARD.RunService = { RenderStepped = clientOnly("RenderStepped"), PreRender = clientOnly("PreRender") }

------------------------------------------------------------------ Tweens
local TWEENABLE = { number = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim2 = true, UDim = true, Rect = true, NumberRange = true, boolean = true }
IMPL.TweenService = {
	Create = function(self, inst, info, props)
		if not I.isInst(inst) then
			error("TweenService:Create: Instance expected, got " .. typeOf(inst), 2)
		end
		if typeOf(info) ~= "TweenInfo" then
			error("TweenService:Create: TweenInfo expected, got " .. typeOf(info), 2)
		end
		if type(props) ~= "table" then
			error("TweenService:Create: property table expected", 2)
		end
		local d = getD(inst)
		for k, v in props do
			local m = I.memberOf(d.cls, k)
			if not m or m.kind ~= "prop" then
				error(string.format("TweenService:Create no property named '%s' for object '%s'", tostring(k), d.props.Name), 2)
			end
			local cur = inst[k]
			if not TWEENABLE[typeOf(v)] then
				error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", k, typeOf(cur), typeOf(v)), 2)
			end
			if cur ~= nil and typeOf(cur) ~= typeOf(v) and not (typeOf(cur) == "EnumItem") then
				error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", k, typeOf(cur), typeOf(v)), 2)
			end
		end
		local tw = I.new("Tween")
		local td = getD(tw)
		td.target = inst
		td.info = info
		td.goals = table.clone(props)
		td.props.Instance = inst
		td.props.TweenInfo = info
		td.props.PlaybackState = Enum.PlaybackState.Begin
		return tw
	end,
	GetValue = function(self, alpha)
		return alpha
	end,
}
IMPL.TweenBase = {
	Play = function(self)
		local td = getD(self)
		td.playSeq = (td.playSeq or 0) + 1
		local my = td.playSeq
		td.props.PlaybackState = Enum.PlaybackState.Playing
		local info = td.info
		local dur = (info.DelayTime or 0) + (info.Time or 0)
		if (info.RepeatCount or 0) < 0 then
			for k, v in td.goals do
				pcall(function()
					td.target[k] = v
				end)
			end
			return
		end
		dur *= (1 + math.max(0, info.RepeatCount or 0)) * (if info.Reverses then 2 else 1)
		task.delay(dur, function()
			if td.playSeq ~= my or td.props.PlaybackState ~= Enum.PlaybackState.Playing then
				return
			end
			for k, v in td.goals do
				local ok, err = pcall(function()
					td.target[k] = v
				end)
				if not ok then
					E.recordError("tween", err, "")
				end
			end
			td.props.PlaybackState = Enum.PlaybackState.Completed
			I.fire(I.getSig(self, "Completed"), Enum.PlaybackState.Completed)
		end)
	end,
	Pause = function(self)
		getD(self).props.PlaybackState = Enum.PlaybackState.Paused
	end,
	Cancel = function(self)
		local td = getD(self)
		if td.props.PlaybackState == Enum.PlaybackState.Playing then
			td.props.PlaybackState = Enum.PlaybackState.Cancelled
			I.fire(I.getSig(self, "Completed"), Enum.PlaybackState.Cancelled)
		end
	end,
}
I.CREATABLE_EXTRA.Tween = true

------------------------------------------------------------------ Sound
DEFAULT.Sound = { Volume = 0.5, PlaybackSpeed = 1 }
IMPL.Sound = {
	Play = function(self)
		local d = getD(self)
		local id = d.props.SoundId or ""
		if id == "" or string.match(id, "^rbxassetid://0*$") then
			E.issue("sound-id", "Sound:Play() with empty/zero SoundId '" .. id .. "' (" .. I.fullName(self) .. ")")
		end
		d.props.IsPlaying = true
		d.props.Playing = true
		E.stats.soundsPlayed = (E.stats.soundsPlayed or 0) + 1
	end,
	Stop = function(self)
		local d = getD(self)
		d.props.IsPlaying = false
		d.props.Playing = false
	end,
	Pause = function(self)
		getD(self).props.IsPlaying = false
	end,
	Resume = function(self)
		getD(self).props.IsPlaying = true
	end,
}

------------------------------------------------------------------ misc classes
IMPL.Lighting = {
	GetSunDirection = function()
		return v3(-0.45, 0.8, 0.35).Unit
	end,
	GetMoonDirection = function()
		return v3(0.45, -0.8, -0.35).Unit
	end,
	GetMinutesAfterMidnight = function(self)
		return (self.ClockTime or 14) * 60
	end,
}
IMPL.GuiService = {
	GetGuiInset = function()
		return v2(0, E.inset), v2(0, 0)
	end,
	IsTenFootInterface = function()
		return false
	end,
	CloseInspectMenu = function() end,
}
DEFAULT.GuiService = { TopbarInset = function()
	return E.types.Rect.new(0, 0, E.viewport.X, E.inset)
end }
DEFAULT.UserInputService = { KeyboardEnabled = true, MouseEnabled = true, TouchEnabled = false, GamepadEnabled = false, MouseIconEnabled = true }
IMPL.UserInputService = {
	GetMouseLocation = function()
		return E.mouse or v2(640, 400)
	end,
	GetFocusedTextBox = function()
		return nil
	end,
	IsKeyDown = function()
		return false
	end,
	IsMouseButtonPressed = function()
		return false
	end,
	GetLastInputType = function()
		return Enum.UserInputType.MouseMovement
	end,
	GetConnectedGamepads = function()
		return {}
	end,
	GetKeysPressed = function()
		return {}
	end,
	GetMouseButtonsPressed = function()
		return {}
	end,
	GetStringForKeyCode = function(_, kc)
		return kc.Name
	end,
	GetMouseDelta = function()
		return v2(0, 0)
	end,
}
IMPL.SoundService = {
	PlayLocalSound = function(self, s)
		if not I.isInst(s) or getD(s).cls ~= "Sound" then
			error("PlayLocalSound: Sound expected", 2)
		end
		IMPL.Sound.Play(s)
	end,
}
-- Collision groups (what a game registers on the server): pairs set not collidable; every other pair collides.
-- E.collisionGroupsCollide answers for the fake raycaster (tools/preview/raycast.luau).
local groupRules: { [string]: boolean } = {}
local function groupKey(a, b)
	if a > b then
		a, b = b, a
	end
	return a .. "|" .. b
end
E.collisionGroupsCollide = function(a, b)
	local r = groupRules[groupKey(a or "Default", b or "Default")]
	return r ~= false
end
IMPL.PhysicsService = {
	RegisterCollisionGroup = function(_self, _name) end,
	IsCollisionGroupRegistered = function(_self, _name)
		return true
	end,
	CollisionGroupSetCollidable = function(_self, a, b, on)
		groupRules[groupKey(a, b)] = on == true
	end,
	CollisionGroupsAreCollidable = function(_self, a, b)
		return E.collisionGroupsCollide(a, b)
	end,
}
IMPL.ServiceProvider = {
	GetService = function(self, name)
		local s = E.services[name]
		if not s then
			error(string.format("'%s' is not a valid Service name", tostring(name)), 2)
		end
		return s
	end,
	FindService = function(self, name)
		return E.services[name]
	end,
}
IMPL.DataModel = {
	BindToClose = function(self, fn)
		if E.curCtx().kind ~= "server" then
			error("BindToClose can only be called on the server", 2)
		end
		table.insert(E.closeHandlers, fn)
	end,
	IsLoaded = function()
		return true
	end,
}
-- ReplicatedFirst (the loading card's Boot): there is no default loading screen here; a client's call is noted
IMPL.ReplicatedFirst = {
	RemoveDefaultLoadingScreen = function(self)
		local ctx = E.curCtx()
		if ctx.kind ~= "client" then
			error("RemoveDefaultLoadingScreen can only be called from the client", 2)
		end
		ctx.defaultLoadingRemoved = true
	end,
	IsDefaultLoadingGuiRemoved = function(self)
		return E.curCtx().defaultLoadingRemoved == true
	end,
}
E.closeHandlers = {}
DEFAULT.DataModel = { PlaceId = 1234567, GameId = 7654321, JobId = "sim-job-0001", CreatorId = 1 }
E.stats = {}

return true
