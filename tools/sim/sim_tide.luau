-- The tide (GAME_DESIGN 6; Logic/Tide): "use the drifting in idea. you can remove the tree of life, there should now
-- be a steady stream of driftlings, with rarities that players can pick up", then "make them float by just like a
-- conveyer belt instead of drifting towards the island and stopping, with one every second". End to end through the
-- real server and client: a new island's belt full at join (TideLife / TideSecs of them, TideSecs apart, every third a
-- cheap common good with wood or at a farm), the view, the plot's Tide attribute ("id.species.at.life"), the HUD's
-- card (the best few with the time they have left) and the world (each one at its place along the lane past the
-- island, under the water at the jetty and at the ends, price tags over the own island's only, names for the rarer
-- ones, tags hidden while under and never on top of each other); refusals (no hut, malformed payloads, not enough
-- shells, one that floated off); the belt running (one in every second and one gone when its life is up, the Fx
-- "tide" patching the client's view with no whole view sent for it, the attribute following); one taken in from the
-- HUD's card, one from its tag, one by tapping the driftling itself (hopping ashore) and one from the tide panel; every
-- hut full: the swap picker, one sold for its price and replaced, the picker going back when its one floats off; the
-- huts' tide shares bringing them faster and floating them past faster; selling from the Driftlings panel; a hut
-- cleared away; the island grown and every price going up by TideTier; a neighbour's belt drawn by both clients with
-- no price tags on the other's, and a neighbour's taken one hopping ashore in the other client.
local E = require("./loader")
local H = require("./harness")
local I = require("./inst")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.dt = 0.1
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Plot = H.sharedServer("Logic.Plot")
local Tide = H.sharedServer("Logic.Tide")
local Island = H.sharedServer("Logic.Island")
local Numbers = H.sharedServer("Logic.Numbers")
local Creatures = H.sharedServer("Data.Creatures")
local Buildings = H.sharedServer("Data.Buildings")
local Traits = H.sharedServer("Data.Traits")
local Street = H.sharedServer("Data.Street")

local LANE = Street.TIDE
local VIEW = 62 -- studs along the lane from the view's centre TideView draws one within
local BELT = math.floor(Tuning.TideLife / Tuning.TideSecs + 1e-9) -- how many float past at once

------------------------------------------------------------------ helpers
local p = H.addPlayer({ userId = 9601, name = "Beachcomber" })
E.run(2)
local s = H.session(p)
local prof = H.profile(p)
local SC = H.cmod(p, "Controllers.StateClient")

-- every Fx message the client gets with the server's time it came, the whole views it gets, and the tide's patches
local fx = {}
local states, tideChanges = 0, 0
H.inClient(p, function()
	SC.Fx:Connect(function(msg)
		table.insert(fx, { msg = msg, t = E.now() })
	end)
	SC.Changed:Connect(function()
		states += 1
	end)
	SC.TideChanged:Connect(function()
		tideChanges += 1
	end)
end)

-- a player's client modules
local function clientOf(pl)
	return {
		TV = H.cmod(pl, "Controllers.TideView"),
		WV = H.cmod(pl, "Controllers.WorldView"),
		CC = H.cmod(pl, "Controllers.CameraController"),
		PR = H.cmod(pl, "Pixel.PixelRenderer"),
		UIKit = H.cmod(pl, "UI.UIKit"),
	}
end
local C = clientOf(p)

-- (a quiet moment on the belt: the last change has reached the client, and the next one to come in and the next one
-- to leave are a good while off, so a check that compares the server with the client sees nothing change half way.
-- While the pace changes, the ones coming in and the ones leaving keep different beats.)
local function hold(sess)
	local ss = sess or s
	local sig, quiet = nil, 0
	E.runUntil(function()
		local list = ss.tide.list
		local key = #list .. ":" .. (list[1] and list[1].id or 0) .. ":" .. (list[#list] and list[#list].id or 0)
		quiet = if key == sig then quiet + 1 else 0
		sig = key
		local nextOut = math.huge
		for _, d in list do
			nextOut = math.min(nextOut, d.at + d.life - ss.tide.clock)
		end
		return quiet >= 1 and Tide.secs(ss.profile) - ss.tide.t >= 0.35 and nextOut >= 0.35
	end, 8, 0.1)
end
local function idsOf(list)
	local out = {}
	for _, d in list do
		table.insert(out, tostring(d.id))
	end
	return table.concat(out, ",")
end
-- what the plot's Tide attribute should say: "id.species.at.life" each (at and life in tenths of a second), the
-- oldest first
local function attrWant(sess)
	local out = {}
	for _, d in sess.tide.list do
		table.insert(out, string.format("%d.%s.%d.%d", d.id, d.sp, math.floor(d.at * 10 + 0.5), math.floor(d.life * 10 + 0.5)))
	end
	return table.concat(out, ";")
end
local function plotModel(i)
	return E.workspace.Plots:FindFirstChild("Plot_" .. i)
end
local function gui(pl, name)
	local pg = pl:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild(name, true)
end
local function labelText(pl, name)
	local l = gui(pl, name)
	return if l and l:IsA("TextLabel") then l.Text else nil
end
local function buttonText(b)
	return if b then table.concat(H.textsOf(b), "/") else ""
end
-- the GUI objects whose names start with `prefix` (visible ones only when `vis`), under `root` (the PlayerGui)
local function named(pl, prefix, vis, root)
	local out = {}
	for _, d in (root or pl:FindFirstChild("PlayerGui")):GetDescendants() do
		if string.sub(d.Name, 1, #prefix) == prefix and (not vis or H.guiVisible(d)) then
			table.insert(out, d)
		end
	end
	return out
end
-- a visible line of text saying `text` (a notice, or the open panel's status line)
local function says(pl, text)
	for _, d in pl:FindFirstChild("PlayerGui"):GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, text, 1, true) and H.guiVisible(d) then
			return true
		end
	end
	return false
end
local function fxSince(i0, kind)
	local out = {}
	for i = i0 + 1, #fx do
		if fx[i].msg.kind == kind then
			table.insert(out, fx[i])
		end
	end
	return out
end
local function inTide(id, sess)
	for _, d in (sess or s).tide.list do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function viewTide(id, pl)
	local v = H.view(pl or p)
	for _, d in (v and v.tide or {}) do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function palOf(id)
	for _, x in prof.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end
local function newPal(ids0)
	for _, x in prof.pals do
		if not ids0[x.id] then
			return x
		end
	end
	return nil
end
local function palIds()
	local out = {}
	for _, x in prof.pals do
		out[x.id] = true
	end
	return out
end
local function hutIndex(uid)
	for i, q in prof.plot.placed do
		if q.uid == uid then
			return i
		end
	end
	return 0
end
local function pieceOf(uid)
	local i = hutIndex(uid)
	return if i > 0 then prof.plot.placed[i] else nil
end
local function rarityOf(sp)
	local d = Creatures.byId[sp]
	return if d then d.rarity else 0
end
local function worthOf(d)
	return Tide.worth({ id = 0, sp = d.sp, home = 0, work = 0, muts = d.muts })
end
-- at work at a building of its knack, or no free place of its knack anywhere
local function workingOrNoPlace(x)
	local d = Creatures.byId[x.sp]
	if x.work ~= 0 then
		local q = pieceOf(x.work)
		return q ~= nil and Buildings.byId[q.id].knack == d.knack
	end
	return Island.freeJob(prof, d.knack) == 0
end
-- shells the island may earn in `secs` (its buildings sell while the checks run)
local function earnSlack(secs)
	return math.abs(Island.rates(prof).shells) / Tuning.TurnSeconds * (secs + 1) + 2
end
-- a raw request's refusal code (the malicious path: the remote directly)
local function rawErr(pl, action, payload)
	local okc, res = H.raw(pl, action, payload)
	E.run(0.1)
	if not okc then
		return "threw: " .. tostring(res)
	end
	if type(res) ~= "table" then
		return "no response"
	end
	return if res.ok then "ok" else tostring(res.err)
end
local function placeFor(pl, id)
	local pr = H.profile(pl)
	local x, z, rot = Plot.spot(pr.tier, pr.plot.placed, id, 6, 14, 0)
	if x == nil then
		return { ok = false, err = "no spot" }
	end
	local res = H.req(pl, "plot.place", { id = id, x = x, z = z, rot = rot })
	E.run(0.2)
	return res
end
local function place(id)
	return placeFor(p, id)
end
-- tap a button wherever it is: true when it was there, and whether it was visible
local function tap(pl, name)
	local b = gui(pl, name)
	if b == nil then
		return false, false
	end
	local vis = H.guiVisible(b)
	I.fire(I.getSig(b, "Activated"), nil, 1)
	I.fire(I.getSig(b, "MouseButton1Click"))
	E.flushDeferred()
	E.run(0.6)
	return true, vis
end
-- the ones a client follows on island `plot`, and of those the ones it draws
local function drawn(pl, plot)
	return H.inClient(pl, clientOf(pl).TV.count, plot)
end
-- where one is along the lane at server time `now`: plot-local x and how far along (0 .. 1)
local function laneAt(d, now)
	local k = math.clamp((now - d.at) / d.life, 0, 1)
	return LANE.x0 + (LANE.x1 - LANE.x0) * k, k
end
-- what the client draws for one of island `plot`'s: world x, y, z, where the server says it should be along the lane
-- (lx, k), how far under it is drawn (from the client's own place along the lane) and the screen px of its tag's anchor
local function seen(pl, plot, d)
	local c = clientOf(pl)
	return H.inClient(pl, function()
		local x, y, z = c.TV.where(plot, d.id)
		if x == nil then
			return nil
		end
		local ox = Street.origin(plot)
		local lx, k = laneAt(d, E.now())
		local kc = math.clamp((x - ox - LANE.x0) / (LANE.x1 - LANE.x0), 0, 1)
		local depth = c.TV.depth(x - ox, kc)
		local px, py, on = c.PR.projectPixel(E.v3(x, y + depth + 2.9, z))
		return { x = x, y = y, z = z, lx = lx, k = k, depth = depth, px = px, py = py, on = on }
	end)
end
-- the best `n` off the view's tide as the HUD's card and the tide panel show them: the best workers (Tide.worth; on a
-- tie the newest), and when the shells cover none of them, the best one they do cover in the last place
local function bestOf(v, n)
	local list = {}
	for _, d in v.tide do
		table.insert(list, { d = d, w = worthOf(d) })
	end
	table.sort(list, function(a, b)
		if math.abs(a.w - b.w) > 1e-9 then
			return a.w > b.w
		end
		return a.d.id > b.d.id
	end)
	local out, can = {}, false
	for i = 1, math.min(n, #list) do
		table.insert(out, list[i].d)
		can = can or v.shells >= list[i].d.cost
	end
	if not can and #out > 0 then
		for i = n + 1, #list do
			if v.shells >= list[i].d.cost then
				out[#out] = list[i].d
				break
			end
		end
	end
	return out
end
-- the view's tide is the session's drift by drift (its time, its life, its cost on this island), and the plot's Tide
-- attribute too
local function tideMirror(pl, sess, label)
	local v = H.view(pl)
	local pr = H.profile(pl)
	local same = v ~= nil and #v.tide == #sess.tide.list
	local bad = nil
	for i, d in sess.tide.list do
		local e = v and v.tide[i]
		if not (e and e.id == d.id and e.sp == d.sp and e.at == d.at and e.life == d.life and e.cost == Tide.cost(pr, d.sp, d.muts) and #e.muts == #d.muts) then
			same = false
			bad = bad or d.id
		end
	end
	H.expect(same, "mirror", label .. ": the view's tide is the session's (each one's id, kind, time, life and cost)", string.format("%d vs %d, first bad %s", v and #v.tide or -1, #sess.tide.list, tostring(bad)))
	local m = plotModel(sess.plot)
	H.expect(m ~= nil and m:GetAttribute("Tide") == attrWant(sess), "mirror", label .. ": the plot's Tide attribute is the session's", m and string.sub(tostring(m:GetAttribute("Tide")), 1, 200))
end
local function checks(label)
	hold()
	H.push(p, 0.3)
	H.checkProfile(p, label)
	H.checkMirror(p, label)
	tideMirror(p, s, label)
end
-- the belt as it should be between two arrivals: BELT-ish of them (floor(life / secs)), each `secs` after the one
-- before, the newest `t` ago, none past its life, each with this island's life
local function beltCheck(sess, label, secs, life)
	local list = sess.tide.list
	local pr = sess.profile
	secs = secs or Tide.secs(pr)
	life = life or Tide.life(pr)
	H.expect(#list == math.floor(life / secs + 1e-6), "belt", label .. ": the belt full, floor(life / secs) floating past", string.format("%d (life %.2f, secs %.2f)", #list, life, secs))
	local spaced, lives, past = true, true, 0
	for i, d in list do
		if i > 1 and math.abs((d.at - list[i - 1].at) - secs) > 1e-6 then
			spaced = false
		end
		if math.abs(d.life - life) > 1e-9 then
			lives = false
		end
		if sess.tide.clock - d.at >= d.life then
			past += 1
		end
	end
	H.expect(spaced, "belt", label .. ": each one came `secs` after the one before", idsOf(list))
	H.expect(lives, "belt", label .. ": each one floats past in Tide.life", string.format("%.2f", life))
	H.expect(past == 0, "belt", label .. ": none past its life", tostring(past))
	local newest = list[#list]
	H.expect(newest ~= nil and math.abs((sess.tide.clock - newest.at) - sess.tide.t) < 1e-6, "belt", label .. ": the newest came in on the tide's last beat", newest and string.format("%.3f vs %.3f", sess.tide.clock - newest.at, sess.tide.t))
end
-- what a client draws of island `sess.plot`'s belt: every one it has had time to see followed, each at its place along
-- the lane (k of the way: x0 + 80 k, z = TIDE.z, its depth under the water), the ones near the view drawn; on the own
-- island, a price tag over each drawn one (a name over a rarer one), hidden while it is under and never on top of
-- another tag, the best worker on screen and above the water always tagged, and no other tags
local function worldCheck(pl, sess, label)
	local c = clientOf(pl)
	local plot = sess.plot
	local own = H.session(pl).plot == plot
	local ox, oz = Street.origin(plot)
	local focusX = H.inClient(pl, c.CC.centerWorld).X
	local followed, nDrawn = drawn(pl, plot)
	local canvas = H.inClient(pl, c.UIKit.canvas, "World")
	local v = H.view(pl)
	local missing, badPlace, badY, mine = nil, nil, nil, 0
	local wantDrawn, wantTags, shownRects = 0, 0, {}
	local badTag, badName, underShown, bestOn, bestTagged = nil, nil, nil, nil, false
	for _, d in sess.tide.list do
		local w = seen(pl, plot, d)
		if w == nil then
			if sess.tide.clock - d.at >= 0.6 then
				missing = missing or d.id
			end
			continue
		end
		mine += 1
		-- (the attribute rounds its time and life to tenths of a second)
		local slack = (LANE.x1 - LANE.x0) * 0.05 * (1 + w.k) / d.life + 0.05
		if math.abs(w.x - (ox + w.lx)) > slack or math.abs(w.z - (oz + LANE.z)) > 1e-6 then
			badPlace = badPlace or string.format("%d at %.2f,%.2f (want %.2f,%.2f)", d.id, w.x - ox, w.z - oz, w.lx, LANE.z)
		end
		if math.abs(w.y - (Street.WATER_Y + 0.12 - w.depth)) > 0.1 then
			badY = badY or string.format("%d y %.2f depth %.2f", d.id, w.y, w.depth)
		end
		local isDrawn = math.abs(w.x - focusX) <= VIEW
		if isDrawn then
			wantDrawn += 1
		end
		if own then
			local e = viewTide(d.id, pl)
			local tag = canvas:FindFirstChild("TideTake_" .. d.id)
			local name = canvas:FindFirstChild("TideName_" .. d.id)
			local should = isDrawn and e ~= nil
			if should then
				wantTags += 1
			end
			if (tag ~= nil) ~= should or (tag and string.find(buttonText(tag), Numbers.coins(e.cost), 1, true) == nil) then
				badTag = badTag or string.format("%d: tag %s, drawn %s, text %s", d.id, tostring(tag ~= nil), tostring(isDrawn), buttonText(tag))
			end
			if (name ~= nil) ~= (should and rarityOf(d.sp) >= 2) or (name and name.Text ~= Creatures.byId[d.sp].name) then
				badName = badName or string.format("%d (%s, rarity %d): name %s", d.id, d.sp, rarityOf(d.sp), tostring(name ~= nil))
			end
			if tag then
				local tw = tag.Size.X.Offset
				local vis = tag.Visible
				if vis and (w.depth >= 0.6 or not w.on) then
					underShown = underShown or string.format("%d depth %.2f on %s", d.id, w.depth, tostring(w.on))
				end
				if name and name.Visible ~= vis then
					badName = badName or string.format("%d: its name shown %s, its tag %s", d.id, tostring(name.Visible), tostring(vis))
				end
				if math.abs(tag.Position.X.Offset + math.floor(tw / 2) - w.px) > 1 or math.abs(tag.Position.Y.Offset + 12 - w.py) > 1 then
					badTag = badTag or string.format("%d: tag at %d,%d, over %d,%d", d.id, tag.Position.X.Offset + math.floor(tw / 2), tag.Position.Y.Offset + 12, w.px, w.py)
				end
				if vis then
					local r = { tag.Position.X.Offset, tag.Position.Y.Offset, tag.Position.X.Offset + tw, tag.Position.Y.Offset + tag.Size.Y.Offset }
					if name then
						r[1] = math.min(r[1], name.Position.X.Offset)
						r[2] = math.min(r[2], name.Position.Y.Offset)
						r[3] = math.max(r[3], name.Position.X.Offset + name.Size.X.Offset)
					end
					table.insert(shownRects, { id = d.id, r = r })
				end
				if w.depth < 0.6 and w.on then
					local wo = worthOf(d)
					if bestOn == nil or wo > bestOn.w + 1e-9 or (math.abs(wo - bestOn.w) <= 1e-9 and d.id < bestOn.id) then
						bestOn = { id = d.id, w = wo }
						bestTagged = vis
					end
				end
			end
		end
	end
	H.expect(missing == nil, "world", label .. ": the client follows every one on the belt", tostring(missing))
	H.expect(followed == mine, "world", label .. ": and no others", string.format("%d followed, %d on the belt", followed, mine))
	H.expect(badPlace == nil, "world", label .. ": each at its place along the lane (x0 + 80 k, TIDE.z)", tostring(badPlace))
	H.expect(badY == nil, "world", label .. ": each at the water, as far under as TideView.depth says", tostring(badY))
	H.expect(nDrawn == wantDrawn, "world", label .. ": the ones near the view drawn", string.format("%d drawn, %d near", nDrawn, wantDrawn))
	if own then
		H.expect(badTag == nil, "world", label .. ": a price tag over each drawn one, at its place", tostring(badTag))
		H.expect(badName == nil, "world", label .. ": a name over the uncommon ones and better only", tostring(badName))
		H.expect(underShown == nil, "world", label .. ": no tag shown while it is under (the jetty, the ends) or off screen", tostring(underShown))
		local overlap = nil
		for i, a in shownRects do
			for j = i + 1, #shownRects do
				local b = shownRects[j]
				if a.r[1] < b.r[3] and b.r[1] < a.r[3] and a.r[2] < b.r[4] and b.r[2] < a.r[4] then
					overlap = overlap or string.format("%d and %d", a.id, b.id)
				end
			end
		end
		H.expect(overlap == nil, "world", label .. ": no two tags on top of each other", tostring(overlap))
		H.expect(bestOn == nil or bestTagged, "world", label .. ": the best worker above the water has its tag shown", bestOn and tostring(bestOn.id))
		local tags = 0
		for _, g in canvas:GetChildren() do
			if string.sub(g.Name, 1, 9) == "TideTake_" then
				tags += 1
			end
		end
		H.expect(tags == wantTags, "world", label .. ": no other price tags (none over a neighbour's)", string.format("%d tags, %d drawn own", tags, wantTags))
	end
	return { followed = followed, drawn = nDrawn, shown = #shownRects, tags = wantTags }
end
-- the HUD's card: Open, then a row for each of the best three (TideView.best): its name, its price on a button and a
-- bar of the time it has left
local function cardCheck(label)
	local v = H.view(p)
	local want = bestOf(v, 3)
	local card = gui(p, "TideCard")
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TideOpen") ~= nil, "card", label .. ": the tide's card on the HUD with Open")
	if card == nil then
		return
	end
	H.expect(idsOf(want) == idsOf(H.inClient(p, C.TV.best, v, 3)), "card", label .. ": TideView.best: the best workers, or one the shells cover last", idsOf(want))
	local badRow, badBar = nil, nil
	for _, d in want do
		local b = card:FindFirstChild("CardTake_" .. d.id, true)
		local nm = card:FindFirstChild("TideName_" .. d.id, true)
		local back = card:FindFirstChild("TideLeft_" .. d.id, true)
		local fill = back and back:FindFirstChild("Fill")
		if not (b and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) and nm and nm.Text == Creatures.byId[d.sp].name) then
			badRow = badRow or string.format("%d: %s", d.id, buttonText(b))
		end
		local left = 1 - math.clamp((E.now() - d.at) / d.life, 0, 1)
		if not (fill and math.abs(fill.Size.X.Offset - (back.Size.X.Offset - 2) * left) <= 1) then
			badBar = badBar or string.format("%d: %s of %s, %.2f left", d.id, fill and tostring(fill.Size.X.Offset) or "none", back and tostring(back.Size.X.Offset - 2) or "none", left)
		end
	end
	H.expect(badRow == nil, "card", label .. ": each row's name and price", tostring(badRow))
	H.expect(badBar == nil, "card", label .. ": each row's bar shows the time it has left", tostring(badBar))
	H.expect(#named(p, "CardTake_", false, card) == #want and #named(p, "TideLeft_", false, card) == #want, "card", label .. ": no other rows", string.format("%d rows, %d wanted", #named(p, "CardTake_", false, card), #want))
	H.expect(card:FindFirstChild("TideBar", true) == nil, "card", label .. ": no bar to the next one any more")
end
-- the youngest one on the belt the client has had time to see, with at least `left` seconds to go (and `ok` true)
local function aDrift(ok, left)
	hold()
	local best = nil
	for _, d in s.tide.list do
		local age = s.tide.clock - d.at
		if age >= 0.6 and d.life - age >= (left or 4) and (ok == nil or ok(d)) and (best == nil or d.at > best.at) then
			best = d
		end
	end
	return best or { id = 0, sp = "", muts = {}, cost = 0, at = 0, life = 1 }
end
-- the model a client draws one with (the driftling on its raft, not the raft): the one standing where it floats
local function modelAt(x, y, z)
	local dyn = E.workspace:FindFirstChild("PixelDynamic")
	local best, bestD = nil, 0.8
	for _, m in (dyn and dyn:GetChildren() or {}) do
		if m:IsA("Model") and string.sub(m.Name, 1, 12) == "Micro_drift_" then
			local cx, cz, n = 0, 0, 0
			for _, q in m:GetDescendants() do
				if q:IsA("BasePart") then
					cx += q.Position.X
					cz += q.Position.Z
					n += 1
				end
			end
			if n > 0 then
				local dd = math.sqrt((cx / n - x) ^ 2 + (cz / n - z) ^ 2)
				if dd < bestD then
					best, bestD = m, dd
				end
			end
		end
	end
	return best
end
local function centerOf(m)
	local sum, n = E.v3(0, 0, 0), 0
	for _, q in m:GetDescendants() do
		if q:IsA("BasePart") then
			sum += q.Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end
-- tap the screen on a driftling floating by (on its body, as a player's tap arrives: below the top bar), through
-- WorldView's taps; true when it is drawn there
local function tapDrift(pl, plot, d, wait)
	local c = clientOf(pl)
	local w = seen(pl, plot, d)
	if w == nil then
		return false
	end
	H.inClient(pl, function()
		local pos = c.PR.project(E.v3(w.x, w.y + w.depth + 1.2, w.z))
		c.WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
	end)
	if (wait or 0.6) > 0 then
		E.run(wait or 0.6)
	end
	return true
end
-- the first commons: while nothing is taken in, every third one (id 1, 4, 7 ...) a common good with wood or at a
-- farm, by turns
local function firstCommons(list, label)
	local bad, n = nil, 0
	local byId = {}
	for _, d in list do
		byId[d.id] = d
	end
	for id, d in byId do
		if id % 3 == 1 then
			local def = Creatures.byId[d.sp]
			local k = def and def.knack
			local before = byId[id - 3]
			local kb = before and Creatures.byId[before.sp] and Creatures.byId[before.sp].knack
			if not (def and def.rarity == 1 and (k == "wood" or k == "farm") and k ~= kb) then
				bad = bad or string.format("%d %s", id, d.sp)
			end
			n += 1
		end
	end
	H.expect(n > 0 and bad == nil, "first", label .. ": every third a common good with wood or at a farm, by turns", string.format("%d of them, bad %s", n, tostring(bad)))
end

------------------------------------------------------------------ 1. a new island's belt
E.phase = "join"
hold()
H.push(p, 0.6)
hold()
H.expect(s ~= nil and s.ready and prof.tut == 1 and #prof.pals == 0 and prof.stats.taken == 0, "join", "a new island: tips at step 1, no driftlings yet", string.format("tut %d, %d pals", prof.tut, #prof.pals))
H.expect(math.abs(prof.shells - Tuning.StartShells) < 1 and math.abs(prof.wood - Tuning.StartWood) < 1, "join", "the starting shells and wood", string.format("%s %s", tostring(prof.shells), tostring(prof.wood)))
H.expect(Tuning.TideMax == nil and Tuning.TideStart == nil and Tuning.TideSecs == 1, "join", "one every second floating past in TideLife (no TideMax, no TideStart)", string.format("secs %s life %s", tostring(Tuning.TideSecs), tostring(Tuning.TideLife)))
H.expect(Tide.secs(prof) == Tuning.TideSecs and Tide.life(prof) == Tuning.TideLife, "join", "no huts: TideSecs apart, TideLife to float past", string.format("%.2f %.2f", Tide.secs(prof), Tide.life(prof)))
H.expect(math.abs(s.tide.clock - E.now()) <= 0.11, "join", "the tide runs on the server's time", string.format("%.2f vs %.2f", s.tide.clock, E.now()))
beltCheck(s, "join")
local start = table.clone(s.tide.list)
firstCommons(start, "join")
-- the tips' first two: the cheapest one good with wood and the cheapest at a farm, the starting shells cover both
local cheapest = {}
for _, d in start do
	local def = Creatures.byId[d.sp]
	if d.id % 3 == 1 and def and (cheapest[def.knack] == nil or d.cost < cheapest[def.knack].cost) then
		cheapest[def.knack] = d
	end
end
H.expect(cheapest.wood ~= nil and cheapest.farm ~= nil and cheapest.wood.cost + cheapest.farm.cost <= Tuning.StartShells, "join", "the starting shells cover a wood one and a farm one", string.format("%s + %s of %d", cheapest.wood and tostring(cheapest.wood.cost) or "none", cheapest.farm and tostring(cheapest.farm.cost) or "none", Tuning.StartShells))
local costOk, seenOk = true, true
for _, d in start do
	costOk = costOk and d.cost == Tide.cost(prof, d.sp, d.muts)
	seenOk = seenOk and prof.seen[d.sp] == 1
end
H.expect(costOk, "join", "each one's cost is Tide.cost")
H.expect(seenOk, "join", "each one seen on the belt: in the Index (1)")
local v = H.view(p)
H.expect(v ~= nil and idsOf(v.tide) == idsOf(start), "join", "the view carries the belt", v and idsOf(v.tide))
H.expect(v ~= nil and v.tideSecs == Tide.secs(prof) and v.tideT == nil, "join", "the view: tideSecs, and no tideT any more", v and tostring(v.tideSecs))
tideMirror(p, s, "join")
-- the plot's attribute read back: each one's id, kind, time and life (tenths of a second)
local m1 = plotModel(s.plot)
local parsed, attrOk = 0, true
for entry in string.gmatch(tostring(m1 and m1:GetAttribute("Tide") or ""), "[^;]+") do
	local id, sp, at, life = string.match(entry, "^(%d+)%.([%w_]+)%.(%d+)%.(%d+)$")
	local d = id and inTide(tonumber(id))
	if not (d and d.sp == sp and math.abs(tonumber(at) / 10 - d.at) <= 0.05 and math.abs(tonumber(life) / 10 - d.life) <= 0.05) then
		attrOk = false
	end
	parsed += 1
end
H.expect(attrOk and parsed == #s.tide.list, "join", "the attribute reads back as id.species.at.life", string.format("%d of %d", parsed, #s.tide.list))
-- the HUD's card
cardCheck("join")
local anyCan = false
for _, d in bestOf(v, 3) do
	anyCan = anyCan or v.shells >= d.cost
end
H.expect(anyCan, "join", "the card offers one the starting shells cover")
-- the world: where they float, how far under at the jetty and the ends
local function depthAt(x, k)
	return H.inClient(p, C.TV.depth, x, k)
end
H.expect(depthAt(0, 0.5) >= 3 and depthAt(1.5, 0.5) >= 3 and depthAt(-2, 0.5) >= 3, "join", "under the water at the jetty", string.format("%.2f", depthAt(0, 0.5)))
H.expect(depthAt(4, 0.5) == 0 and depthAt(-4, 0.5) == 0 and depthAt(20, 0.25) == 0 and depthAt(-20, 0.75) == 0, "join", "on the water clear of it", string.format("%.2f %.2f", depthAt(4, 0.5), depthAt(20, 0.25)))
H.expect(depthAt(LANE.x0, 0) >= 3 and depthAt(LANE.x1, 1) >= 3 and depthAt(-30, 0.1) == 0 and depthAt(30, 0.9) == 0, "join", "coming up at the start, going down at the end", string.format("%.2f %.2f", depthAt(LANE.x0, 0), depthAt(LANE.x1, 1)))
H.expect(LANE.x0 == -Tuning.PlotSpacing / 2 and LANE.x1 == Tuning.PlotSpacing / 2, "join", "the lane runs the lot's length, west to east")
local w0 = worldCheck(p, s, "join")
H.expect(w0.drawn == w0.followed and w0.followed >= #s.tide.list - 1 and w0.shown > 0, "join", "the whole belt drawn past the own island, some tags shown", string.format("%d drawn of %d, %d tags shown", w0.drawn, #s.tide.list, w0.shown))
checks("join")

------------------------------------------------------------------ 2. refusals before a hut
E.phase = "refuse"
hold()
local first = aDrift()
local sh0 = prof.shells
H.expect(rawErr(p, "tide.take", { id = first.id, swap = 0 }) == "no_hut", "refuse", "no hut yet: no_hut")
H.expect(rawErr(p, "tide.take", { id = 99999, swap = 0 }) == "not_found", "refuse", "one that never came: not_found")
H.expect(rawErr(p, "tide.take", { id = 0, swap = 0 }) == "not_found", "refuse", "id 0: not_found")
local bad = {
	{ "a string id", { id = tostring(first.id), swap = 0 } },
	{ "no swap", { id = first.id } },
	{ "no id", { swap = 0 } },
	{ "an extra field", { id = first.id, swap = 0, uid = 1 } },
	{ "a negative id", { id = -1, swap = 0 } },
	{ "a fraction", { id = 1.5, swap = 0 } },
	{ "a huge id", { id = 2e6, swap = 0 } },
	{ "a string swap", { id = first.id, swap = "x" } },
	{ "a boolean id", { id = true, swap = 0 } },
	{ "a table id", { id = {}, swap = 0 } },
	{ "a list", { first.id, 0 } },
	{ "a string payload", "take" },
	{ "a number payload", 42 },
}
for _, b in bad do
	local err = rawErr(p, "tide.take", b[2])
	H.expect(err == "bad_payload", "refuse", "a malformed payload (" .. b[1] .. "): bad_payload", err)
end
H.expect(rawErr(p, "tide.take", nil) == "bad_payload", "refuse", "no payload: bad_payload")
hold()
H.expect(#s.tide.list == BELT and #prof.pals == 0 and prof.stats.taken == 0 and math.abs(prof.shells - sh0) < 1, "refuse", "nothing changed (the belt still full)", string.format("%d drifts, %d pals", #s.tide.list, #prof.pals))
checks("refuse")

------------------------------------------------------------------ 3. the tips' buildings, then not enough shells
E.phase = "build"
hold()
local res = place("lumber")
H.expect(res.ok and prof.tut == 2, "build", "a lumber camp: the tips move on to the farm", string.format("%s tut %d", tostring(res.err), prof.tut))
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: on to the hut", string.format("%s tut %d", tostring(res.err), prof.tut))
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: on to taking one in off the tide", string.format("%s tut %d", tostring(res.err), prof.tut))
local hutUid = res.data and res.data.uid
H.push(p, 0.3)
v = H.view(p)
H.expect(v.nests == Buildings.byId.nest.slots and Tide.room(prof) == Buildings.byId.nest.slots, "build", "the hut's room", tostring(v.nests))
-- not enough shells (a hut now, so the money check comes next)
local cheap = aDrift()
local keepShells = prof.shells
prof.shells = cheap.cost - 1
H.push(p, 0.3)
H.expect(rawErr(p, "tide.take", { id = cheap.id, swap = 0 }) == "money", "build", "a shell short: money")
H.expect(#prof.pals == 0 and inTide(cheap.id) ~= nil, "build", "nothing taken")
prof.shells = keepShells
checks("build")

------------------------------------------------------------------ 4. the belt running
E.phase = "flow"
hold()
local i0 = #fx
local states0, changes0 = states, tideChanges
local view0 = H.view(p)
local life = {} -- every id seen on the belt: when it came and its life
local function note()
	for _, d in s.tide.list do
		life[d.id] = life[d.id] or { at = d.at, life = d.life }
	end
end
note()
local most, past, mid, midBad, attrBad, viewBad = 0, 0, 0, 0, 0, 0
local watched = s.tide.list[#s.tide.list - 2]
local x0 = seen(p, s.plot, watched)
local T = 6
E.runUntil(function()
	note()
	most = math.max(most, #s.tide.list)
	for _, d in s.tide.list do
		if s.tide.clock - d.at >= d.life then
			past += 1
		end
	end
	-- (half way between two: the belt full, the attribute and the client's view following it)
	if s.tide.t >= 0.4 and s.tide.t < 0.5 then
		mid += 1
		if #s.tide.list ~= BELT then
			midBad += 1
		end
		if m1:GetAttribute("Tide") ~= attrWant(s) then
			attrBad += 1
		end
		if idsOf(H.view(p).tide) ~= idsOf(s.tide.list) then
			viewBad += 1
		end
	end
	return false
end, T, 0.1)
H.expect(most <= BELT + 1 and past == 0, "flow", "never one past its life on the belt", string.format("most %d, %d past", most, past))
H.expect(mid >= T - 1 and midBad == 0, "flow", "half way between two, the belt always full", string.format("%d of %d", midBad, mid))
H.expect(attrBad == 0, "flow", "the plot's attribute follows every second", tostring(attrBad))
H.expect(viewBad == 0, "flow", "and the client's view", tostring(viewBad))
-- the Fx: one came and one gone every second, as they happened
local tf = fxSince(i0, "tide")
local cameN, goneN, cameBad, goneBad, spaced = 0, 0, nil, nil, true
local prevAt = nil
for _, f in tf do
	for _, e in f.msg.came do
		cameN += 1
		local l = life[e.id]
		if not (l and e.at == l.at and e.life == l.life and e.cost == Tide.cost(prof, e.sp, e.muts) and f.t - e.at >= 0 and f.t - e.at <= 0.25) then
			cameBad = cameBad or string.format("%d at %.2f got %.2f", e.id, e.at or -1, f.t)
		end
		if prevAt and math.abs(e.at - prevAt - Tuning.TideSecs) > 1e-6 then
			spaced = false
		end
		prevAt = e.at
	end
	for _, id in f.msg.gone do
		goneN += 1
		local l = life[id]
		if not (l and f.t >= l.at + l.life and f.t - (l.at + l.life) <= 0.35) then
			goneBad = goneBad or string.format("%d (came %.2f, life %.2f) gone at %.2f", id, l and l.at or -1, l and l.life or -1, f.t)
		end
	end
end
H.expect(#tf >= T - 1 and #tf <= T + 1 and cameN == #tf and goneN == #tf, "flow", "Fx tide: one came in and one gone every second", string.format("%d Fx, %d came, %d gone in %d s", #tf, cameN, goneN, T))
H.expect(cameBad == nil, "flow", "each one came with its time, life and cost, at that time", tostring(cameBad))
H.expect(spaced, "flow", "each one TideSecs after the last")
H.expect(goneBad == nil, "flow", "each one gone when its life was up", tostring(goneBad))
H.expect(tideChanges - changes0 == #tf, "flow", "the client patched its view for each (TideChanged)", string.format("%d of %d", tideChanges - changes0, #tf))
-- no whole view sent for the tide (only a turn or a new day sends one now)
local turns = #fxSince(i0, "turn") + #fxSince(i0, "day")
H.expect(states - states0 <= turns, "flow", "no whole view sent for the tide", string.format("%d views, %d turns or days", states - states0, turns))
H.expect(turns > 0 or rawequal(H.view(p), view0), "flow", "the client's view patched in place")
local ticks = fxSince(i0, "tick")
local tickOk = #ticks >= T - 1
for _, f in ticks do
	tickOk = tickOk and f.msg.tideSecs == Tide.secs(prof) and f.msg.tideT == nil
end
H.expect(tickOk, "flow", "Fx tick: tideSecs every second, no tideT", tostring(#ticks))
-- the client: each one floats east along the lane at 80 / life studs a second
local x1 = seen(p, s.plot, watched)
H.expect(x0 ~= nil and x1 ~= nil and math.abs((x1.x - x0.x) - (x1.lx - x0.lx)) <= 0.5 and x1.x - x0.x > (LANE.x1 - LANE.x0) / Tuning.TideLife * (T - 0.5), "flow", "one floats east along the lane, 80 / life studs a second", x0 and x1 and string.format("%.2f -> %.2f", x0.x, x1.x) or "not followed")
hold()
cardCheck("flow")
worldCheck(p, s, "flow")
-- the first commons still come every third while nothing is taken
local flowList = {}
for _, f in tf do
	for _, e in f.msg.came do
		table.insert(flowList, e)
	end
end
-- (every one that came since the island opened, before any was taken in)
local both = table.clone(start)
for _, f in fx do
	if f.msg.kind == "tide" then
		for _, e in f.msg.came do
			table.insert(both, e)
		end
	end
end
firstCommons(both, "join and flow")
-- the Index: every kind that came is seen; one never taken in is seen (1), not had
local kinds = {}
for _, d in start do
	kinds[d.sp] = true
end
for _, d in flowList do
	kinds[d.sp] = true
end
local seenBad = nil
for sp in kinds do
	if prof.seen[sp] ~= 1 then
		seenBad = seenBad or sp
	end
end
H.expect(seenBad == nil, "flow", "every kind that came is in the Index, seen (1)", tostring(seenBad))
H.openPanel(p, "index")
for sp in kinds do
	local entry = gui(p, "Entry_" .. sp)
	local nm = entry and entry:FindFirstChild("Name")
	H.expect(nm ~= nil and nm.Text == Creatures.byId[sp].name, "flow", "the Index panel shows it by name", string.format("%s: %s", sp, nm and nm.Text or "none"))
end
H.closePanel(p)
-- one that floated off: not_found (the remote, and the client saying so)
local goneId = tf[1] and tf[1].msg.gone[1] or 1
H.expect(inTide(goneId) == nil and rawErr(p, "tide.take", { id = goneId, swap = 0 }) == "not_found", "flow", "taking one that floated off: not_found")
H.inClient(p, C.TV.take, goneId)
E.run(0.1)
H.expect(says(p, "That one has floated off."), "flow", "the client says it floated off")
checks("flow")

------------------------------------------------------------------ 5. taking one in: the HUD's card, a world tag, the driftling itself
E.phase = "take"
hold()
H.push(p, 0.3)
v = H.view(p)
-- (from the card: the one it offers that the shells cover)
local pick = nil
for _, d in bestOf(v, 3) do
	if v.shells >= d.cost then
		pick = d
	end
end
H.expect(pick ~= nil, "take", "the card offers one the shells cover")
pick = pick or aDrift()
local ids0 = palIds()
local t0 = E.now()
i0 = #fx
sh0 = prof.shells
H.expect(H.clickNamed(p, "CardTake_" .. pick.id, { wait = 0.6 }), "take", "the card's price button")
local x1p = newPal(ids0)
H.expect(x1p ~= nil and x1p.sp == pick.sp and x1p.home == hutUid, "take", "taken in, into the hut", x1p and string.format("%s home %d", x1p.sp, x1p.home) or "none")
H.expect(x1p ~= nil and workingOrNoPlace(x1p), "take", "at work at a building of its knack (or no free place)", x1p and tostring(x1p.work))
H.expect(math.abs((sh0 - prof.shells) - pick.cost) <= earnSlack(E.now() - t0), "take", "its cost paid in shells", string.format("%.1f -> %.1f, cost %d", sh0, prof.shells, pick.cost))
H.expect(prof.stats.taken == 1 and prof.tut == 5 and prof.seen[pick.sp] == 2, "take", "stats.taken, the tips on to the shop, the Index has it (2)", string.format("taken %d tut %d seen %s", prof.stats.taken, prof.tut, tostring(prof.seen[pick.sp])))
local tk = fxSince(i0, "taken")
H.expect(#tk == 1 and type(tk[1].msg.data) == "table" and tk[1].msg.data.id == (x1p and x1p.id) and tk[1].msg.data.cost == pick.cost and tk[1].msg.data.sold == 0, "take", "Fx taken: its id and cost, nothing sold", tostring(#tk))
H.expect(inTide(pick.id) == nil and viewTide(pick.id) == nil, "take", "gone from the belt (server and view)")
H.expect(says(p, "moved into a hut"), "take", "the HUD says it moved in")
E.run(1.2)
H.expect(H.buttonNamed(p, "CardTake_" .. pick.id) == nil and gui(p, "TideTake_" .. pick.id) == nil, "take", "its price buttons gone (card and world)")
H.expect(H.inClient(p, C.WV.ownCount) == 1, "take", "and it walks the island from its hut", tostring(H.inClient(p, C.WV.ownCount)))
-- (from its price tag over the water: one the shells cover with its tag shown)
hold()
local canvas = H.inClient(p, C.UIKit.canvas, "World")
local tagPick = nil
for _, d in s.tide.list do
	local tag = canvas:FindFirstChild("TideTake_" .. d.id)
	local lx, k = laneAt(d, E.now())
	-- (clear of the jetty and the ends, so it stays shown while it's tapped)
	if tag and tag.Visible and math.abs(lx) > 8 and k > 0.1 and k < 0.85 and (tagPick == nil or d.cost < tagPick.cost) then
		tagPick = d
	end
end
H.expect(tagPick ~= nil, "take", "a price tag shown over the water")
tagPick = tagPick or aDrift()
if prof.shells < tagPick.cost then
	H.log("topping up %d shells for the second", tagPick.cost - prof.shells)
	prof.shells = tagPick.cost + 1
	H.push(p, 0.3)
end
ids0 = palIds()
t0, sh0 = E.now(), prof.shells
local found, vis = tap(p, "TideTake_" .. tagPick.id)
H.expect(found and vis, "take", "the world tag is there, on screen")
local x2 = newPal(ids0)
H.expect(x2 ~= nil and x2.sp == tagPick.sp and x2.home == hutUid and workingOrNoPlace(x2), "take", "taken in from its tag: into the hut, at work", x2 and string.format("%s home %d work %d", x2.sp, x2.home, x2.work) or "none")
H.expect(math.abs((sh0 - prof.shells) - tagPick.cost) <= earnSlack(E.now() - t0), "take", "its cost paid", string.format("%.1f -> %.1f, cost %d", sh0, prof.shells, tagPick.cost))
H.expect(prof.stats.taken == 2 and Tide.room(prof) == 0, "take", "two taken, the hut full", string.format("taken %d room %d", prof.stats.taken, Tide.room(prof)))
-- (a second hut, then a tap on the driftling itself: taken in, hopping ashore to the jetty)
prof.wood = math.max(prof.wood, Buildings.byId.nest.wood + 10)
prof.shells = 50000
H.push(p, 0.3)
res = place("nest")
local hut2 = res.data and res.data.uid
H.expect(res.ok and Tide.room(prof) == Buildings.byId.nest.slots, "take", "a second hut", tostring(res.err))
hold()
-- (a tap on the island, where nothing floats, takes nothing)
local nothing = H.inClient(p, function()
	local ox, oz = Street.origin(s.plot)
	local pos = C.PR.project(E.v3(ox + Street.CENTER.x, Street.LAWN_Y, oz + Street.CENTER.z))
	return C.TV.tapAt(E.v2(pos.X, pos.Y - E.inset))
end)
E.run(0.3)
H.expect(nothing == false and prof.stats.taken == 2, "take", "a tap where nothing floats takes nothing")
local tapPick = aDrift(function(d)
	local w = seen(p, s.plot, d)
	return w ~= nil and w.depth == 0 and w.on and math.abs(w.lx) > 8 and math.abs(w.lx) < 30
end, 3)
local wt = seen(p, s.plot, tapPick)
local model = wt and modelAt(wt.x, wt.y, wt.z)
local from = model and centerOf(model)
H.expect(model ~= nil, "take", "the driftling drawn where it floats", tostring(tapPick.id))
ids0 = palIds()
H.expect(tapDrift(p, s.plot, tapPick, 0), "take", "a tap on the driftling")
-- (it's taken in, then hops up and onto the jetty and is gone)
local ax, az = H.inClient(p, C.TV.ashore, s.plot)
local rose, nearest, goneAt = 0, math.huge, nil
local tHop = E.now()
E.runUntil(function()
	if model == nil or model.Parent == nil then
		goneAt = goneAt or E.now()
		return true
	end
	local c = centerOf(model)
	if c and from then
		rose = math.max(rose, c.Y - from.Y)
		nearest = math.min(nearest, math.sqrt((c.X - ax) ^ 2 + (c.Z - az) ^ 2))
	end
	return false
end, 2.5, 0.1)
local x3 = newPal(ids0)
H.expect(x3 ~= nil and x3.sp == tapPick.sp and x3.home == hut2 and prof.stats.taken == 3, "take", "taken in by a tap on itself, into the new hut", x3 and string.format("%s home %d", x3.sp, x3.home) or "none")
H.expect(inTide(tapPick.id) == nil, "take", "gone from the belt")
local dist0 = from and math.sqrt((from.X - ax) ^ 2 + (from.Z - az) ^ 2) or 0
H.expect(rose > 1.5, "take", "it hops up off its raft", string.format("%.2f", rose))
H.expect(nearest < dist0 * 0.3, "take", "and onto the jetty", string.format("%.2f of %.2f", nearest, dist0))
H.expect(goneAt ~= nil and H.inClient(p, C.TV.where, s.plot, tapPick.id) == nil, "take", "then it's gone from the water", goneAt and string.format("after %.1f s", goneAt - tHop) or "still there")
H.expect(gui(p, "TideTake_" .. tapPick.id) == nil, "take", "its tag gone")
E.run(1)
H.expect(H.inClient(p, C.WV.ownCount) == 3, "take", "three walk the island", tostring(H.inClient(p, C.WV.ownCount)))
checks("take")

------------------------------------------------------------------ 6. the tide panel
E.phase = "panel"
hold()
H.expect(H.clickNamed(p, "TideOpen", { wait = 0.4 }) and H.currentPanel(p) == "tide", "panel", "the card's Open opens the tide panel")
local function panelCheck(label)
	local vv = H.view(p)
	local want = bestOf(vv, 4)
	local badRow = nil
	for _, d in want do
		local row = gui(p, "Drift_" .. d.id)
		local b = H.buttonNamed(p, "PanelTake_" .. d.id)
		local back = row and row:FindFirstChild("Left")
		local fill = back and back:FindFirstChildWhichIsA("Frame")
		local left = 1 - math.clamp((E.now() - d.at) / d.life, 0, 1)
		if not (row and H.guiVisible(row) and b and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) and fill and math.abs(fill.Size.X.Offset - 54 * left) <= 1) then
			badRow = badRow or string.format("%d: %s, bar %s, %.2f left", d.id, buttonText(b), fill and tostring(fill.Size.X.Offset) or "none", left)
		end
	end
	H.expect(badRow == nil, "panel", label .. ": a row for each of the best four, Take with its price, a bar of its time left", tostring(badRow))
	H.expect(#named(p, "Drift_", true) == #want, "panel", label .. ": no other rows", string.format("%d of %d", #named(p, "Drift_", true), #want))
	return want
end
panelCheck("open")
for r = 1, 5 do
	H.expect(gui(p, "Odds_" .. r) ~= nil, "panel", "the odds of rarity " .. r)
end
H.expect(labelText(p, "Pace") == "One floats by every second", "panel", "how often", tostring(labelText(p, "Pace")))
H.expect(labelText(p, "Jetty") == "Floating by", "panel", "what floats by", tostring(labelText(p, "Jetty")))
H.expect(labelText(p, "Room") == string.format("In huts %d/%d", #prof.pals, Island.nests(prof)), "panel", "the huts' room", tostring(labelText(p, "Room")))
H.expect(gui(p, "TideBar") == nil and gui(p, "Leaving") == nil, "panel", "no bar to the next one, no Leaving soon")
-- rebuilt only when what it shows changes (the belt moves every second)
local kept, rebuilt, stale, needless = 0, 0, 0, 0
local function rowsNow()
	local out = {}
	for _, r in named(p, "Drift_", true) do
		out[r.Name] = r
	end
	return out
end
local function wantKey()
	return idsOf(bestOf(H.view(p), 4))
end
local prevRows, prevKey, prevChanges, prevStates = rowsNow(), wantKey(), tideChanges, states
E.runUntil(function()
	local rows, key = rowsNow(), wantKey()
	local same = true
	for name, r in prevRows do
		same = same and rows[name] == r
	end
	local ids = {}
	for _, d in bestOf(H.view(p), 4) do
		ids["Drift_" .. d.id] = true
	end
	for name in rows do
		if not ids[name] then
			stale += 1
		end
	end
	if key == prevKey and tideChanges > prevChanges and states == prevStates then
		if same then
			kept += 1
		else
			needless += 1
		end
	elseif key ~= prevKey then
		rebuilt += 1
	end
	prevRows, prevKey, prevChanges, prevStates = rows, key, tideChanges, states
	return false
end, 8, 0.1)
H.expect(kept > 0 and needless == 0, "panel", "not rebuilt while the best four stay", string.format("kept %d, rebuilt for nothing %d", kept, needless))
H.expect(stale == 0, "panel", "always showing the best four now", string.format("%d stale, %d changes", stale, rebuilt))
hold()
local shownNow = panelCheck("later")
-- Take from the panel: into the last free place, the panel stays open without it
local d4 = shownNow[#shownNow]
ids0 = palIds()
local sold0 = prof.stats.sold
H.expect(d4 ~= nil and H.clickNamed(p, "PanelTake_" .. d4.id, { wait = 0.6 }), "panel", "Take on the tide panel")
local z1 = newPal(ids0)
H.expect(z1 ~= nil and d4 and z1.sp == d4.sp and z1.home == hut2 and prof.stats.sold == sold0 and Tide.room(prof) == 0, "panel", "into the free place, nothing sold, every hut full", z1 and string.format("%s home %d", z1.sp, z1.home) or "none")
H.expect(H.currentPanel(p) == "tide" and d4 and gui(p, "Drift_" .. d4.id) == nil, "panel", "the panel stays open without it")
H.closePanel(p)
H.expect(H.guiVisible(gui(p, "TideCard")), "panel", "the HUD's card back once it closes")
checks("panel")

------------------------------------------------------------------ 7. every hut full: the swap picker
E.phase = "full"
hold()
H.push(p, 0.4)
v = H.view(p)
local target = bestOf(v, 3)[1]
local n0, taken0 = #prof.pals, prof.stats.taken
sold0 = prof.stats.sold
H.expect(Tide.room(prof) == 0, "full", "every hut full", tostring(Tide.room(prof)))
H.expect(target ~= nil and H.clickNamed(p, "CardTake_" .. target.id, { wait = 0.6 }), "full", "the card's price button")
H.expect(prof.stats.taken == taken0 and #prof.pals == n0 and inTide(target.id) ~= nil, "full", "refused (full): nothing taken, still floating")
H.expect(H.currentPanel(p) == "tide", "full", "the tide panel opens", tostring(H.currentPanel(p)))
local hutPals = {}
for _, x in prof.pals do
	if x.home ~= 0 then
		table.insert(hutPals, x)
	end
end
table.sort(hutPals, function(a, b)
	return Tide.better(b, a)
end)
for _, x in hutPals do
	local row = gui(p, "SwapOut_" .. x.id)
	H.expect(row ~= nil and H.guiVisible(row) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil, "full", "the swap picker: a row and Swap for each in a hut", tostring(x.id))
end
H.expect(not H.guiVisible(gui(p, "TideCard")), "full", "the HUD's card steps aside for the panel")
local out = hutPals[1]
local price, outHome = Tide.price(out), out.home
ids0 = palIds()
i0, t0 = #fx, E.now()
sh0 = prof.shells
H.expect(H.clickNamed(p, "SwapTake_" .. out.id, { wait = 0.6 }), "full", "Swap on the weakest")
local y = newPal(ids0)
H.expect(palOf(out.id) == nil, "full", "the swapped one is gone")
H.expect(y ~= nil and y.sp == target.sp and y.home == outHome, "full", "the new one in its place", y and string.format("%s home %d", y.sp, y.home) or "none")
H.expect(y ~= nil and workingOrNoPlace(y), "full", "at work, or no free place of its knack", y and tostring(y.work))
H.expect(#prof.pals == n0 and prof.stats.taken == taken0 + 1 and prof.stats.sold == sold0 + 1, "full", "one in, one sold", string.format("%d pals, taken %d sold %d", #prof.pals, prof.stats.taken, prof.stats.sold))
tk = fxSince(i0, "taken")
H.expect(#tk == 1 and tk[1].msg.data.sold == price and tk[1].msg.data.cost == target.cost and tk[1].msg.data.swapped == out.id, "full", "Fx taken: sold for Tide.price, its cost", tk[1] and string.format("sold %s cost %s", tostring(tk[1].msg.data.sold), tostring(tk[1].msg.data.cost)) or "none")
H.expect(math.abs((prof.shells - sh0) - (price - target.cost)) <= earnSlack(E.now() - t0), "full", "shells: the price back, the cost paid", string.format("%.1f -> %.1f (price %d, cost %d)", sh0, prof.shells, price, target.cost))
H.expect(inTide(target.id) == nil, "full", "it left the belt")
H.expect(H.currentPanel(p) == "tide" and #named(p, "SwapOut_", true) == 0, "full", "the panel back on the tide")
H.closePanel(p)
-- swaps the server refuses
local d2 = aDrift()
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = 0 }) == "full", "full", "every hut full and no swap: full")
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = 99999 }) == "bad_payload", "full", "a swap that isn't a driftling: bad_payload")
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = hutUid }) == "bad_payload", "full", "a swap that is a hut: bad_payload")
H.expect(#prof.pals == n0 and inTide(d2.id) ~= nil, "full", "nothing changed")
-- the swap picker open on one about to float off: it floats off, the panel goes back to the belt and says so
hold()
local leaving = nil
for _, d in s.tide.list do
	local left = d.life - (s.tide.clock - d.at)
	if left >= 1.5 and left <= 2.6 then
		leaving = d
	end
end
H.expect(leaving ~= nil, "full", "one with two seconds left")
leaving = leaving or d2
H.inClient(p, C.TV.take, leaving.id)
E.run(0.3)
H.expect(H.currentPanel(p) == "tide" and #named(p, "SwapOut_", true) == #prof.pals, "full", "the swap picker for it", tostring(#named(p, "SwapOut_", true)))
E.runUntil(function()
	return inTide(leaving.id) == nil
end, 4, 0.1)
E.run(0.3)
H.expect(inTide(leaving.id) == nil and H.currentPanel(p) == "tide" and #named(p, "SwapOut_", true) == 0 and #named(p, "Drift_", true) > 0, "full", "it floats off: the panel back on the belt", string.format("%d swap rows, %d drift rows", #named(p, "SwapOut_", true), #named(p, "Drift_", true)))
H.expect(says(p, "That one has floated off."), "full", "and says it floated off")
H.expect(rawErr(p, "tide.take", { id = leaving.id, swap = hutPals[2] and hutPals[2].id or 0 }) == "not_found" and #prof.pals == n0, "full", "a swap for one that floated off: not_found, nothing sold")
H.closePanel(p)
checks("full")

------------------------------------------------------------------ 8. the huts' tide shares: faster in, faster past
E.phase = "fast"
hold()
local kept0 = {}
local share = 0
local lifeBefore = Tide.life(prof)
for _, x in prof.pals do
	kept0[x.id] = x.muts
	if x.home ~= 0 then
		x.muts = { "swift4" }
		local def = Creatures.byId[x.sp]
		share += Traits.sum(def and def.passive.fx, x.muts).tide or 0
	end
end
H.push(p, 0.3)
local secsF = Tuning.TideSecs / (1 + math.min(share, Tuning.HutTide))
local lifeF = Tuning.TideLife * secsF / Tuning.TideSecs
H.expect(secsF < Tuning.TideSecs and math.abs(Tide.secs(prof) - secsF) < 1e-9, "fast", "the huts' tide shares: one comes in sooner", string.format("%.3f s (shares %.2f)", Tide.secs(prof), share))
H.expect(math.abs(Tide.life(prof) - lifeF) < 1e-9, "fast", "and floats past as much sooner", string.format("%.2f s", Tide.life(prof)))
i0 = #fx
E.runUntil(function()
	local n = 0
	for _, f in fxSince(i0, "tide") do
		n += #f.msg.came
	end
	return n >= 4
end, 5, 0.1)
local fastCame = {}
for _, f in fxSince(i0, "tide") do
	for _, e in f.msg.came do
		table.insert(fastCame, e)
	end
end
local fastOk = #fastCame >= 4
for i, e in fastCame do
	fastOk = fastOk and math.abs(e.life - lifeF) < 1e-9 and (i == 1 or math.abs(e.at - fastCame[i - 1].at - secsF) < 1e-6)
end
H.expect(fastOk, "fast", "the new ones come Tide.secs apart, each with the shorter life", string.format("%d came", #fastCame))
E.run(1.2)
v = H.view(p)
H.expect(v ~= nil and math.abs(v.tideSecs - secsF) < 1e-9, "fast", "the client's tideSecs follows (Fx tick)", v and tostring(v.tideSecs))
-- (a new one floats past faster than an old one)
local newOne, oldOne = nil, nil
for _, d in s.tide.list do
	local _, k = laneAt(d, E.now())
	if k > 0.1 and k < 0.8 and math.abs(d.life - lifeF) < 1e-9 and newOne == nil then
		newOne = d
	elseif k > 0.1 and k < 0.8 and math.abs(d.life - lifeBefore) < 1e-9 then
		oldOne = d
	end
end
local a1, b1 = newOne and seen(p, s.plot, newOne), oldOne and seen(p, s.plot, oldOne)
E.run(1)
local a2, b2 = newOne and seen(p, s.plot, newOne), oldOne and seen(p, s.plot, oldOne)
local fastDx = a1 and a2 and (a2.x - a1.x) or 0
local slowDx = b1 and b2 and (b2.x - b1.x) or 0
H.expect(newOne ~= nil and oldOne ~= nil, "fast", "the ones already on the belt keep the life they had", string.format("%s %s", tostring(newOne and newOne.id), tostring(oldOne and oldOne.id)))
H.expect(math.abs(fastDx - (LANE.x1 - LANE.x0) / lifeF) <= 0.6 and math.abs(slowDx - (LANE.x1 - LANE.x0) / lifeBefore) <= 0.6 and fastDx > slowDx, "fast", "a new one floats past faster", string.format("%.2f vs %.2f studs a second", fastDx, slowDx))
H.openPanel(p, "tide")
H.expect(labelText(p, "Pace") == string.format("One floats by every %.1fs", secsF), "fast", "the panel's pace", tostring(labelText(p, "Pace")))
H.closePanel(p)
-- (once the old ones are gone: the belt full of fast ones, as many as before)
local pastF, mostF = 0, 0
E.runUntil(function()
	mostF = math.max(mostF, #s.tide.list)
	for _, d in s.tide.list do
		if s.tide.clock - d.at >= d.life then
			pastF += 1
		end
	end
	return false
end, Tuning.TideLife + 1, 0.1)
hold()
beltCheck(s, "fast", secsF, lifeF)
H.expect(pastF == 0, "fast", "never one past its life", tostring(pastF))
worldCheck(p, s, "fast")
tideMirror(p, s, "fast")
-- (back to the tide as it was)
for _, x in prof.pals do
	if kept0[x.id] ~= nil then
		x.muts = kept0[x.id]
	end
end
H.push(p, 0.3)
E.run(Tuning.TideLife + 1)
hold()
beltCheck(s, "slow again")
checks("fast")

------------------------------------------------------------------ 9. selling from the Driftlings panel; a hut cleared away
E.phase = "sell"
hold()
H.push(p, 0.3)
H.openPanel(p, "pals")
local sellOne = nil
for _, x in prof.pals do
	if x.home ~= 0 and (sellOne == nil or Tide.better(sellOne, x)) then
		sellOne = x
	end
end
price = Tide.price(sellOne)
sold0 = prof.stats.sold
H.expect(H.clickNamed(p, "Sell_" .. sellOne.id, { wait = 0.3 }), "sell", "Sell on the weakest")
H.expect(palOf(sellOne.id) ~= nil and string.find(buttonText(H.buttonNamed(p, "Sell_" .. sellOne.id)), "Sure?", 1, true) ~= nil, "sell", "one tap asks: Sure?", buttonText(H.buttonNamed(p, "Sell_" .. sellOne.id)))
sh0, t0 = prof.shells, E.now()
H.expect(H.clickNamed(p, "Sell_" .. sellOne.id, { wait = 0.6 }), "sell", "the second tap")
H.expect(palOf(sellOne.id) == nil and prof.stats.sold == sold0 + 1, "sell", "sold", string.format("sold %d", prof.stats.sold))
H.expect(math.abs((prof.shells - sh0) - price) <= earnSlack(E.now() - t0), "sell", "for Tide.price", string.format("%.1f -> %.1f (price %d)", sh0, prof.shells, price))
H.expect(Tide.room(prof) == 1, "sell", "a place in a hut free", tostring(Tide.room(prof)))
H.closePanel(p)
-- the free place filled from the tide panel (no swap)
H.openPanel(p, "tide")
hold()
local d5 = bestOf(H.view(p), 4)[1]
ids0 = palIds()
sold0 = prof.stats.sold
H.expect(d5 ~= nil and H.clickNamed(p, "PanelTake_" .. d5.id, { wait = 0.6 }), "sell", "Take on the tide panel")
local z2 = newPal(ids0)
H.expect(z2 ~= nil and d5 and z2.sp == d5.sp and prof.stats.sold == sold0 and Tide.room(prof) == 0, "sell", "into the free place, nothing sold", z2 and string.format("%s home %d", z2.sp, z2.home) or "none")
H.closePanel(p)
checks("sell")

E.phase = "clear"
hold()
local homed = #prof.pals
local huts = {}
for _, h in Tide.huts(prof) do
	table.insert(huts, h.uid)
end
for _, uid in huts do
	res = H.req(p, "plot.store", { i = hutIndex(uid) })
	E.run(0.2)
end
local noHut = 0
for _, x in prof.pals do
	if x.home == 0 and x.work == 0 then
		noHut += 1
	end
end
H.expect(res.ok and #Tide.huts(prof) == 0 and noHut == #prof.pals and #prof.pals == homed, "clear", "the huts cleared away: their driftlings kept, with no hut and not working", string.format("%s, %d of %d", tostring(res.err), noHut, #prof.pals))
E.run(1)
H.expect(m1:GetAttribute("Pals") == "" and H.inClient(p, C.WV.ownCount) == 0, "clear", "none drawn on the island while they have no hut", string.format("%s, %d drawn", tostring(m1:GetAttribute("Pals")), H.inClient(p, C.WV.ownCount)))
H.openPanel(p, "pals")
for _, x in prof.pals do
	local row = gui(p, "Pal_" .. x.id)
	local where = row and row:FindFirstChild("Where")
	H.expect(where ~= nil and string.sub(where.Text, 1, 6) == "No hut", "clear", "the Driftlings panel says it has no hut", where and where.Text or "none")
end
H.closePanel(p)
H.expect(rawErr(p, "tide.take", { id = aDrift().id, swap = 0 }) == "no_hut", "clear", "no hut to take one into: no_hut")
checks("clear")
hold()
prof.wood = math.max(prof.wood, Buildings.byId.nest.wood * 2 + 10)
H.push(p, 0.3)
res = place("nest")
local res2 = place("nest")
hutUid = res.data and res.data.uid
local housedN = 0
for _, x in prof.pals do
	if x.home ~= 0 then
		housedN += 1
		H.expect(workingOrNoPlace(x), "clear", "back at work", string.format("%s work %d", x.sp, x.work))
	end
end
H.expect(res.ok and res2.ok and housedN == #prof.pals, "clear", "new huts: they move back in (Tide.settle)", string.format("%d of %d", housedN, #prof.pals))
E.run(1)
H.expect(H.inClient(p, C.WV.ownCount) == #prof.pals, "clear", "drawn on the island again", tostring(H.inClient(p, C.WV.ownCount)))
checks("rehoused")

------------------------------------------------------------------ 10. the island grows: every price up by TideTier
E.phase = "expand"
hold()
prof.wood = Tuning.TierCost[2] + 300
H.push(p, 0.4)
local before = {}
hold()
v = H.view(p)
for _, d in v.tide do
	before[d.id] = d.cost
end
res = H.req(p, "island.expand", {})
E.run(1.5)
H.expect(res.ok and prof.tier == 2, "expand", "the island grows", tostring(res.err))
local ratio = Tuning.TideTier[2] / Tuning.TideTier[1]
hold()
v = H.view(p)
local priced, oldPriced = true, 0
for _, d in v.tide do
	local was = before[d.id]
	priced = priced and d.cost == Tide.cost(prof, d.sp, d.muts)
	if was then
		oldPriced += 1
		priced = priced and math.abs(d.cost - was * ratio) <= ratio / 2 + 0.5
	end
end
H.expect(priced and oldPriced > 0, "expand", "every one's cost times TideTier (the ones already floating too)", tostring(oldPriced))
for _, d in bestOf(v, 3) do
	local b = H.buttonNamed(p, "CardTake_" .. d.id)
	H.expect(b ~= nil and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) ~= nil, "expand", "the card shows the new price", buttonText(b))
end
H.expect(m1:GetAttribute("Tier") == 2, "expand", "the bigger island's attribute")
worldCheck(p, s, "expand")
checks("expand")

------------------------------------------------------------------ 11. a second player: both belts drawn by both clients
E.phase = "neighbour"
local q = H.addPlayer({ userId = 9602, name = "Neighbour" })
E.run(2.5)
local sq = H.session(q)
local qprof = H.profile(q)
local CQ = clientOf(q)
H.expect(sq ~= nil and sq.ready and sq.plot ~= s.plot, "neighbour", "a second island", sq and tostring(sq.plot))
H.expect(math.abs(Street.origin(sq.plot) - Street.origin(s.plot)) <= 100, "neighbour", "next door (each client follows the other's belt)")
local mq = plotModel(sq.plot)
-- (two islands opened at about the same time number their tides alike: the neighbour's next ones get the first
-- island's ids, so a tag or a tap that took the wrong island's for its own would show)
sq.tide.next = s.tide.next
E.run(5)
-- (each island's checks half way between two of its own)
hold(sq)
H.expect(mq ~= nil and mq:GetAttribute("Tide") == attrWant(sq), "neighbour", "the second island's belt in its own plot attribute", mq and string.sub(tostring(mq:GetAttribute("Tide")), 1, 200))
beltCheck(sq, "neighbour")
firstCommons(sq.tide.list, "neighbour")
local wqq = worldCheck(q, sq, "neighbour, its own")
local wpq = worldCheck(p, sq, "first, the neighbour's")
tideMirror(q, sq, "neighbour")
hold()
H.expect(m1:GetAttribute("Tide") == attrWant(s), "neighbour", "the first island's still in its own")
local wqp = worldCheck(q, s, "neighbour, the first island's")
local wpp = worldCheck(p, s, "first, its own")
H.expect(wqp.drawn > 0 and wqp.drawn < wqp.followed, "neighbour", "the second client draws the first island's ones near its view", string.format("%d of %d", wqp.drawn, wqp.followed))
H.expect(wpq.drawn > 0 and wpq.drawn < wpq.followed, "neighbour", "the first client draws the second's near its view", string.format("%d of %d", wpq.drawn, wpq.followed))
-- (the fake engine's two clients share one camera, so only the counts are compared here, not what is on screen)
H.expect(wqq.tags > 0 and wpp.tags > 0, "neighbour", "each has price tags over its own", string.format("%d / %d", wqq.tags, wpp.tags))
-- the neighbour's ones the first client draws, the furthest from its own belt first
local function theirsDrawn(ok)
	hold(sq)
	local fx0 = H.inClient(p, C.CC.centerWorld).X
	local best, bestX = nil, -math.huge
	for _, d in sq.tide.list do
		local w = seen(p, sq.plot, d)
		if w and math.abs(w.x - fx0) <= VIEW and sq.tide.clock - d.at >= 0.6 and ok(w) and w.lx > bestX then
			best, bestX = d, w.lx
		end
	end
	return best
end
-- a tap on the neighbour's driftling takes nothing
local theirs = theirsDrawn(function(w)
	return w.depth == 0 and w.on
end)
local takenP = prof.stats.taken
H.expect(theirs ~= nil, "neighbour", "one of the neighbour's drawn on the first screen")
if theirs then
	local hit = H.inClient(p, function()
		local x, yy, z = C.TV.where(sq.plot, theirs.id)
		local pos = C.PR.project(E.v3(x, yy + 1.2, z))
		return C.TV.tapAt(E.v2(pos.X, pos.Y - E.inset))
	end)
	E.run(0.6)
	H.expect(hit == false and prof.stats.taken == takenP and qprof.stats.taken == 0 and inTide(theirs.id, sq) ~= nil, "neighbour", "a tap on the neighbour's driftling takes nothing")
end
-- the neighbour takes one the first client draws: there it hops ashore at once, not floating on to the end
qprof.wood = math.max(qprof.wood, Buildings.byId.nest.wood + 10)
qprof.shells = 50000
H.push(q, 0.3)
res = placeFor(q, "nest")
H.expect(res.ok, "neighbour", "the neighbour builds a hut", tostring(res.err))
local theirPick = theirsDrawn(function(w)
	return w.k < 0.5
end)
H.expect(theirPick ~= nil, "neighbour", "one of theirs drawn on the first screen")
if theirPick then
	H.inClient(q, CQ.TV.take, theirPick.id)
	local kAt = (E.now() - theirPick.at) / theirPick.life
	H.expect(inTide(theirPick.id, sq) == nil and #qprof.pals == 1, "neighbour", "the neighbour took it in")
	local goneIn = nil
	local t1 = E.now()
	E.runUntil(function()
		if H.inClient(p, C.TV.where, sq.plot, theirPick.id) == nil then
			goneIn = E.now() - t1
			return true
		end
		return false
	end, 3, 0.1)
	H.expect(goneIn ~= nil and goneIn <= 1.5, "neighbour", "the first client: it hops ashore and is gone", goneIn and string.format("%.1f s, %.2f of the way", goneIn, kAt) or "still floating")
end
-- one more comes in on the first island: the neighbour follows it
local was = s.tide.list[#s.tide.list].id
E.runUntil(function()
	return s.tide.list[#s.tide.list].id ~= was
end, Tide.secs(prof) + 1, 0.1)
local newest = s.tide.list[#s.tide.list]
E.run(0.8)
local wn = seen(q, s.plot, newest)
H.expect(wn ~= nil and math.abs(wn.x - (Street.origin(s.plot) + wn.lx)) <= 0.4, "neighbour", "the neighbour's client follows a new one on the first island's belt", tostring(newest.id))
-- the first commons stopped once one was taken in: later every third one is whatever the tide brings
local later, notFirst = 0, 0
for _, f in fx do
	if f.msg.kind == "tide" then
		for _, e in f.msg.came do
			if e.id % 3 == 1 and e.id > pick.id + BELT then
				later += 1
				local def = Creatures.byId[e.sp]
				if not (def and def.rarity == 1 and (def.knack == "wood" or def.knack == "farm")) then
					notFirst += 1
				end
			end
		end
	end
end
H.expect(later > 10 and notFirst > 0, "first", "once one is taken in, every third is no longer always a first common", string.format("%d of %d", notFirst, later))
hold(sq)
H.checkProfile(q, "neighbour")
H.checkMirror(q, "neighbour")
tideMirror(q, sq, "neighbour")
checks("end")

report(E, H)
