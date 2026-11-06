--!strict
-- The HUD's menus (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 5-8): Staff (the crew: skills, energy, training, letting
-- go, the pizza party; and the job seekers), Research (genres, topics, the notebook of matches), Office (moving up,
-- the ad campaign, the pixel filter) and Games (every release with its reviews and sales, the awards). The New game
-- wizard is NewGameUI. Every action is a request; the panel rebuilds from the next view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Genres = require(ReplicatedStorage.Shared.Data.Genres)
local Topics = require(ReplicatedStorage.Shared.Data.Topics)
local Platforms = require(ReplicatedStorage.Shared.Data.Platforms)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Calendar = require(ReplicatedStorage.Shared.Logic.Calendar)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Crew = require(ReplicatedStorage.Shared.Logic.Crew)
local Dev = require(ReplicatedStorage.Shared.Logic.Dev)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local UIKit = require(script.Parent.UIKit)
local NewGameUI = require(script.Parent.NewGameUI)

local Menus = {}

local SKILL_SHORT: { [string]: string } = { code = "Cod", design = "Des", art = "Art", sound = "Snd" }
local SKILL_COLOR: { [string]: string } = { code = "fun", design = "ideas", art = "graphics", sound = "sound" }

-- Ask the server; tell the player when it says no.
local function ask(action: string, payload: { [string]: any }?, ok: string?)
	local res = StateClient.request(action, payload)
	if res.ok then
		if ok then
			UIKit.notice(ok, UIKit.color("good"))
		end
	else
		UIKit.notice(NewGameUI.errText(res.err), UIKit.color("bad"))
	end
	return res
end

-- Tabs along the body's top: returns the y below them.
local function tabs(body: Frame, list: { { text: string, key: string } }, current: string, panel: string): number
	local x = 0
	for _, t in list do
		local w = UIKit.buttonWidth(t.text, 5)
		UIKit.button(body, t.text, UDim2.fromOffset(w, 12), UDim2.fromOffset(x, 0), function()
			UIKit.openPanel(panel, t.key)
		end, { color = if t.key == current then UIKit.color("accent") else UIKit.color("plate_light"), name = "Tab_" .. t.key })
		x += w + 3
	end
	return 15
end

local function row(list: Instance, order: number, h: number): Frame
	local f = UIKit.plate(list, UDim2.new(1, -6, 0, h), nil, UIKit.color("plate_light"), 0, 2)
	f.Name = "Row"
	f.LayoutOrder = order
	return f
end

local function skillLine(parent: Instance, s: Types.Skills, x: number, y: number)
	local cx = x
	for _, k in Crew.SKILLS do
		local text = SKILL_SHORT[k] .. " " .. tostring((s :: any)[k])
		local w = UIKit.textWidth(text) + 6
		UIKit.text(parent, text, UDim2.fromOffset(w, 10), UDim2.fromOffset(cx, y), { color = UIKit.color(SKILL_COLOR[k]) })
		cx += w
	end
end

------------------------------------------------------------------ staff
local trainFor: number? = nil

local function staffCrew(body: Frame, v: Types.ClientView, y: number)
	local desks = Tuning.Offices[v.office].desks
	local party = Crew.partyCost(#v.staff)
	UIKit.text(body, string.format("Crew %d/%d desks   Payroll %s/month", #v.staff, desks, Numbers.money(Crew.payroll(v.staff))), UDim2.new(1, -90, 0, 12), UDim2.fromOffset(0, y), { color = UIKit.color("text_dim") })
	UIKit.button(body, "Pizza party " .. Numbers.money(party), UDim2.fromOffset(88, 12), UDim2.new(1, -88, 0, y), function()
		ask("staff.party", {}, "Pizza! Everyone's full of energy.")
	end, { enabled = v.canParty and v.money >= party, color = UIKit.color("button_warn"), name = "Party" })
	local list = UIKit.scroll(body, UDim2.new(1, 0, 1, -(y + 15)), UDim2.fromOffset(0, y + 15))
	UIKit.vlist(list, 2)
	for i, s in v.staff do
		local training = trainFor == s.id
		local r = row(list, i, if training then 40 else 26)
		UIKit.portrait(r, s.look, 22, UDim2.fromOffset(2, 2))
		UIKit.text(r, s.name, UDim2.fromOffset(80, 10), UDim2.fromOffset(26, 2), { color = UIKit.color("text") })
		UIKit.text(r, Crew.role(s.skills), UDim2.fromOffset(70, 10), UDim2.fromOffset(26, 13), { color = UIKit.color("text_dim") })
		skillLine(r, s.skills, 94, 2)
		UIKit.text(r, "Energy", UDim2.fromOffset(34, 10), UDim2.fromOffset(94, 13), { color = UIKit.color("text_dim") })
		local _, set = UIKit.bar(r, UDim2.fromOffset(46, 3), UDim2.fromOffset(130, 17), if s.energy < Tuning.EnergyTired then UIKit.color("bad") else UIKit.color("good"), UIKit.color("ink"))
		set(s.energy / Tuning.EnergyMax)
		UIKit.button(r, "Train", UDim2.fromOffset(34, 11), UDim2.new(1, -74, 0, 2), function()
			trainFor = if trainFor == s.id then nil else s.id
			UIKit.refreshPanel()
		end, { name = "Train_" .. s.id })
		UIKit.button(r, "Let go", UDim2.fromOffset(36, 11), UDim2.new(1, -38, 0, 2), function()
			ask("staff.fire", { id = s.id }, s.name .. " has left the studio.")
		end, { enabled = #v.staff > 1, color = UIKit.color("plate"), name = "Fire_" .. s.id })
		if training then
			local can = v.rp >= Tuning.TrainRp and v.money >= Tuning.TrainMoney
			UIKit.text(r, string.format("Train (%d RP, %s):", Tuning.TrainRp, Numbers.money(Tuning.TrainMoney)), UDim2.fromOffset(110, 10), UDim2.fromOffset(4, 27), { color = UIKit.color("text_dim") })
			local x = 116
			for _, k in Crew.SKILLS do
				UIKit.button(r, "+" .. Crew.SKILL_NAMES[k], UDim2.fromOffset(40, 11), UDim2.fromOffset(x, 27), function()
					local res = ask("staff.train", { id = s.id, skill = k })
					if res.ok then
						UIKit.notice(string.format("%s: %s +%d", s.name, Crew.SKILL_NAMES[k], (res.data and res.data.gain) or 0), UIKit.color("good"))
					end
				end, { enabled = can and (s.skills :: any)[k] < Tuning.SkillMax, color = UIKit.color(SKILL_COLOR[k]), name = "TrainSkill_" .. k })
				x += 43
			end
		end
	end
end

local function staffHire(body: Frame, v: Types.ClientView, y: number)
	local desks = Tuning.Offices[v.office].desks
	local full = #v.staff >= desks
	UIKit.text(body, if full then "Every desk is taken: a bigger office has more." else "Hiring costs one month's salary.", UDim2.new(1, 0, 0, 12), UDim2.fromOffset(0, y), { color = UIKit.color("text_dim") })
	local list = UIKit.scroll(body, UDim2.new(1, 0, 1, -(y + 15)), UDim2.fromOffset(0, y + 15))
	UIKit.vlist(list, 2)
	if #v.candidates == 0 then
		UIKit.text(list, "Nobody new this month. More come next month.", UDim2.new(1, -6, 0, 12), nil, { color = UIKit.color("text_dim") })
	end
	for i, c in v.candidates do
		local r = row(list, i, 26)
		UIKit.portrait(r, c.look, 22, UDim2.fromOffset(2, 2))
		UIKit.text(r, c.name, UDim2.fromOffset(80, 10), UDim2.fromOffset(26, 2), { color = UIKit.color("text") })
		UIKit.text(r, Crew.role(c.skills) .. ", " .. Numbers.money(c.salary) .. "/mo", UDim2.fromOffset(140, 10), UDim2.fromOffset(26, 13), { color = UIKit.color("text_dim") })
		skillLine(r, c.skills, 110, 2)
		UIKit.button(r, "Hire " .. Numbers.money(c.salary), UDim2.fromOffset(62, 11), UDim2.new(1, -64, 0, 13), function()
			ask("staff.hire", { i = i }, c.name .. " joins the studio!")
		end, { enabled = not full and v.money >= c.salary, color = UIKit.color("button_ok"), name = "Hire_" .. i })
	end
end

local function buildStaff(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local tab = if arg == "hire" then "hire" else "crew"
	local y = tabs(body, { { text = "Crew", key = "crew" }, { text = "Hire (" .. #v.candidates .. ")", key = "hire" } }, tab, "staff")
	if tab == "hire" then
		staffHire(body, v, y)
	else
		staffCrew(body, v, y)
	end
end

------------------------------------------------------------------ research
local function buildResearch(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local tab = if arg == "topics" or arg == "notebook" then arg else "genres"
	local y = tabs(body, { { text = "Genres", key = "genres" }, { text = "Topics", key = "topics" }, { text = "Notebook", key = "notebook" } }, tab, "research")
	UIKit.text(body, string.format("%d RP to spend", v.rp), UDim2.fromOffset(90, 12), UDim2.new(1, -90, 0, 0), { x = "right", color = UIKit.color("ideas") })
	local list = UIKit.scroll(body, UDim2.new(1, 0, 1, -y), UDim2.fromOffset(0, y))
	UIKit.vlist(list, 2)
	if tab == "notebook" then
		local known = {}
		for key, m in v.matches do
			local g, t = string.match(key, "^(%w+)|(%w+)$")
			local gd, td = Genres.byId[g or ""], Topics.byId[t or ""]
			if gd and td then
				table.insert(known, { text = td.name .. " " .. gd.name, m = m })
			end
		end
		table.sort(known, function(a, b)
			return a.text < b.text
		end)
		if #known == 0 then
			UIKit.text(list, "Release a game to learn how well its genre and topic go together.", UDim2.new(1, -6, 0, 22), nil, { wrap = true, color = UIKit.color("text_dim") })
		end
		for i, k in known do
			local r = row(list, i, 13)
			UIKit.text(r, k.text, UDim2.new(1, -70, 1, 0), UDim2.fromOffset(4, 0), { color = UIKit.color("text") })
			UIKit.text(r, Dev.MATCH_NAMES[k.m], UDim2.fromOffset(60, 13), UDim2.new(1, -64, 0, 0), { x = "right", color = UIKit.color(k.m) })
		end
		return
	end
	local defs: { any } = if tab == "topics" then Topics.list else Genres.list
	for i, d in defs do
		local open = if tab == "topics" then v.topics[d.id] else v.genres[d.id]
		local cost = if tab == "topics" then Dev.topicCost(d.id) else Dev.genreCost(d.id)
		local r = row(list, i, 14)
		UIKit.text(r, d.name, UDim2.fromOffset(120, 14), UDim2.fromOffset(4, 0), { color = if open then UIKit.color("text") else UIKit.color("text_dim") })
		if open then
			UIKit.text(r, "Open", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 0), { x = "right", color = UIKit.color("good") })
		else
			UIKit.button(r, string.format("Unlock %d RP", cost), UDim2.fromOffset(70, 11), UDim2.new(1, -72, 0, 1), function()
				ask(if tab == "topics" then "research.topic" else "research.genre", { id = d.id }, d.name .. " is open!")
			end, { enabled = v.rp >= cost, color = UIKit.color("ideas"), name = "Unlock_" .. d.id })
		end
	end
end

------------------------------------------------------------------ office
local PIXEL_CHOICES = { { "high", "High" }, { "medium", "Medium" }, { "low", "Low" }, { "off", "Classic" } }

local function buildOffice(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local plan = Office.plan(v.office)
	local spec = Tuning.Offices[v.office]
	local y = 0
	local function line(text: string, color: Color3?)
		UIKit.text(body, text, UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, y), { color = color or UIKit.color("text") })
		y += 11
	end
	line(string.format("%s: %d desks, rent %s a month", plan.name, spec.desks, Numbers.money(spec.rent)), UIKit.color("accent"))
	local nextSpec = Tuning.Offices[v.office + 1]
	if nextSpec then
		local nextPlan = Office.plan(v.office + 1)
		line(string.format("Next: %s, %d desks, rent %s", nextPlan.name, nextSpec.desks, Numbers.money(nextSpec.rent)))
		line(string.format("Needs %s fans (you have %s) and %s", Numbers.int(nextSpec.fans), Numbers.int(v.fans), Numbers.money(nextSpec.cost, true)), if v.fans >= nextSpec.fans and v.money >= nextSpec.cost then UIKit.color("good") else UIKit.color("text_dim"))
		UIKit.button(body, "Move to the " .. nextPlan.name, UDim2.fromOffset(UIKit.buttonWidth("Move to the " .. nextPlan.name, 6), 12), UDim2.fromOffset(0, y), function()
			ask("office.move", {}, "Welcome to the " .. nextPlan.name .. "!")
		end, { enabled = v.fans >= nextSpec.fans and v.money >= nextSpec.cost, color = UIKit.color("button_ok"), name = "Move" })
		y += 15
	else
		line("This is the biggest office there is.", UIKit.color("text_dim"))
	end
	local adCost = Dev.adCost(v.office)
	line(string.format("Ad campaign: %s for about %s new fans (once a month)", Numbers.money(adCost), Numbers.int(Dev.adFans(v.office))))
	UIKit.button(body, "Run an ad", UDim2.fromOffset(56, 12), UDim2.fromOffset(0, y), function()
		ask("office.ad", {}, "The ads are out: new fans are on their way!")
	end, { enabled = v.canAd and v.money >= adCost, color = UIKit.color("button_warn"), name = "Ad" })
	y += 16
	local s = v.stats
	line(string.format("Games %d   Hall of Fame %d   Best %d/40   Copies %s", s.games, s.hof, s.best, Numbers.short(s.copies)), UIKit.color("text_dim"))
	y += 2
	line("Picture:", UIKit.color("text_dim"))
	local x = 44
	y -= 11
	for _, c in PIXEL_CHOICES do
		local w = UIKit.buttonWidth(c[2], 4)
		UIKit.button(body, c[2], UDim2.fromOffset(w, 11), UDim2.fromOffset(x, y), function()
			ask("settings.set", { k = "pixel", v = c[1] })
		end, { color = if v.settings.pixel == c[1] then UIKit.color("accent") else UIKit.color("plate_light"), name = "Pixel_" .. c[1] })
		x += w + 3
	end
end

------------------------------------------------------------------ games
local function totalColor(total: number): Color3
	if total >= Tuning.HallOfFame then
		return UIKit.color("accent")
	elseif total >= 24 then
		return UIKit.color("good")
	elseif total >= 16 then
		return UIKit.color("text")
	end
	return UIKit.color("bad")
end

local function buildGames(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local list = UIKit.scroll(body, UDim2.fromScale(1, 1), nil)
	UIKit.vlist(list, 2)
	local order = 0
	for i = #v.awards, 1, -1 do
		local a = v.awards[i]
		order += 1
		local r = row(list, order, 13)
		UIKit.setPlate(r, UIKit.color("plate"))
		UIKit.text(r, string.format("Y%d %s: %s (%d)", a.year, if a.kind == "goty" then "Game of the Year" else "Critics' Choice", a.title, a.total), UDim2.new(1, -8, 1, 0), UDim2.fromOffset(4, 0), { color = UIKit.color("accent") })
	end
	if #v.releases == 0 then
		order += 1
		UIKit.text(list, "No games yet. Make your first one with New game!", UDim2.new(1, -6, 0, 12), nil, { color = UIKit.color("text_dim") }).LayoutOrder = order
	end
	for i = #v.releases, 1, -1 do
		local r = v.releases[i]
		order += 1
		local f = row(list, order, 24)
		local pl = Platforms.byId[r.platform]
		local gd, td = Genres.byId[r.genre], Topics.byId[r.topic]
		UIKit.text(f, r.title .. (if r.hof then "  Hall of Fame" else ""), UDim2.new(1, -60, 0, 10), UDim2.fromOffset(4, 2), { color = if r.hof then UIKit.color("accent") else UIKit.color("text") })
		UIKit.text(f, string.format("%d/40", r.total), UDim2.fromOffset(40, 10), UDim2.new(1, -44, 0, 2), { x = "right", color = totalColor(r.total) })
		local sub = string.format("%s %s, %s, %s   %s copies, %s%s", if td then td.name else r.topic, if gd then gd.name else r.genre, if pl then pl.short else r.platform, Calendar.label(r.week), Numbers.short(r.copies), Numbers.money(r.revenue), if r.onSale then "  selling" else "")
		UIKit.text(f, sub, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 12), { color = UIKit.color("text_dim") })
	end
end

function Menus.init()
	NewGameUI.init()
	UIKit.registerPanel("staff", { title = "Staff", w = 340, h = 180, build = buildStaff })
	UIKit.registerPanel("research", { title = "Research", w = 300, h = 172, build = buildResearch })
	UIKit.registerPanel("office", { title = "Office", w = 320, h = 140, build = buildOffice })
	UIKit.registerPanel("games", { title = "Games", w = 340, h = 180, build = buildGames })
end

return Menus
