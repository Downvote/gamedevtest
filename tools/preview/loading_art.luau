-- The loading card's picture (src/first/LoadingCard, docs/ARCHITECTURE.md 8.0), drawn ahead of time for the preview
-- scenario "ploadingart" (tools/README.md). The request of 2026-11-20, with a screenshot of the island in the sky:
-- "make the island loading screen like this view, but render it as a still image, then polish it like a pixel art
-- illustration". The card goes up before the game has arrived, so its island is drawn here, through the game's own
-- picture path (the pixel filter: the world's palette, toon bands, dither, sun shadows and the 1 px outline), and
-- tools/preview/gen_loading_art.py polishes it and packs it into src/first/LoadingArt.luau.
--
-- What is drawn: a decorated island (VILLAGE's pieces on a tier `tier` island, its driftlings about, the Tree of Life
-- with its eggs), the whole of it floating as the game shows it, at midday in clear weather. Everything on the screen
-- but the pixel layer is off (the HUD, the painted sky); behind the layer a flat key colour (KEY) the packer takes out.
-- The founder stands on the last plot's islet, out of the frame. Two pictures: lart_big at View notch `big` (the
-- card's on a roomy screen) and lart_small at notch `small` (on a short one, a phone held flat); the log gives each
-- one's notch (`ploadingart: shot`).
return function(env)
	local E, H, log, capture = env.E, env.H, env.log, env.capture
	local Vector3, Color3, UDim2, Instance = E.types.Vector3, E.types.Color3, E.types.UDim2, E.Instance
	local tier = env.tier or 1
	-- (View notch 1, the farthest, as the request's screenshot; the small one at `smallPx` art px a stud, past the
	-- slider's end: the camera reads the notches from Tuning, so the scenario lends notch 1 that scale for the shot)
	local big, small, smallPx = env.big or 1, env.small or 1, env.smallPx or 3
	env.seedProfile(7301, tier, { pieces = env.pieces, pals = env.pals, shells = 65000 })
	local p = env.join(7301, "Lou")
	env.settle(p, 60, 1)
	local Street = H.sharedServer("Data.Street")
	local ox, oz = Street.origin(H.session(p).plot)
	if p.Character then
		local lx, lz = Street.origin(Street.MAX)
		p.Character:PivotTo(E.cf.new(lx, 3, lz + Street.CENTER.z))
	end
	local WV = env.modOr(p, "Controllers.WeatherView")
	if WV then
		H.inClient(p, WV.debugSet, "sunny")
	end
	local SB = env.modOr(p, "UI.SkyBackdrop")
	if SB then
		H.inClient(p, SB.debugHour, 0.45, 0)
	end
	local function guisOff()
		for _, g in p.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "LartKey" then
				g.Enabled = false
			end
		end
	end
	-- the key behind the layer
	local key = Instance.new("ScreenGui")
	key.Name = "LartKey"
	key.DisplayOrder = -101 -- (over the painted sky, which turns itself back on, and under the pixel layer)
	key.IgnoreGuiInset = true
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
	f.BorderSizePixel = 0
	f.Parent = key
	key.Parent = p.PlayerGui
	local SU = env.modOr(p, "UI.SettingsUI")
	local CC = env.modOr(p, "Controllers.CameraController")
	local function zoom(n)
		H.openPanel(p, "settings")
		E.run(0.4)
		if SU then
			H.inClient(p, SU.setZoom, n)
		end
		E.run(0.8)
		H.closePanel(p)
		E.run(0.5)
		guisOff()
	end
	local Tuning = env.cshared(p, "Config.Tuning")
	local farthest = Tuning.CamZoomNotches[1]
	local function shot(name, notch, px)
		Tuning.CamZoomNotches[1] = px or farthest
		zoom(if notch == 1 then 2 else 1) -- (a change of notch, so the camera takes the new scale)
		zoom(notch)
		if CC then
			H.inClient(p, CC.setFocus, Vector3.new(ox + Street.CENTER.x, Street.LAWN_Y - (env.drop or 4), oz + Street.CENTER.z), true)
		end
		E.run(1)
		env.settle(p, 60, 1)
		E.run(1.5)
		guisOff()
		E.run(0.2)
		capture(p, name)
		log("ploadingart: shot %s at notch %d (%d art px a stud), tier %d", name, notch, Tuning.CamZoomNotches[notch], tier)
	end
	guisOff()
	shot("lart_big", big)
	shot("lart_small", small, smallPx)
	Tuning.CamZoomNotches[1] = farthest
	return p
end
