local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Studio = require("../../build/luautest/shared/Logic/Studio")
local Util = require("../../build/luautest/shared/Logic/Util")

-- a JSON-like round trip (what a DataStore keeps): numbers, strings, booleans and tables only
local function roundTrip(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = roundTrip(x)
	end
	return out
end

return function()
	T.it("a new studio", function()
		local p = Schema.default(1000, 42)
		T.eq(p.v, Schema.VERSION)
		T.eq(p.money, Tuning.StartMoney)
		T.eq(#p.staff, Tuning.StartStaff)
		T.eq(p.office, 1)
		T.eq(p.week, 0)
		T.truthy(p.genres.action and p.genres.puzzle and p.genres.adventure and not p.genres.rpg)
		T.truthy(p.topics.space and not p.topics.robots)
		T.eq(p.tut, 1)
		T.eq(p.project, nil)
		T.eq(p.staff[1].desk, 1)
		T.eq(p.staff[2].desk, 2)
	end)
	T.it("the same seed makes the same crew", function()
		T.deepEq(Schema.default(1, 5).staff, Schema.default(1, 5).staff)
	end)
	T.it("reconcile keeps a played profile as it is", function()
		local p = Schema.default(1000, 7)
		local rng = Util.newRng(1)
		Studio.start(p, { genre = "puzzle", topic = "space", platform = "pc", size = "small", focus = "fun", seed = 0 })
		for _ = 1, 9 do
			Studio.week(p, rng)
		end
		Studio.release(p, rng)
		Studio.start(p, { genre = "action", topic = "pirates", platform = "pocket", size = "small", focus = "ideas", seed = 4 })
		for _ = 1, 3 do
			Studio.week(p, rng)
		end
		local back = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(back, p)
	end)
	T.it("reconcile turns garbage into a valid profile", function()
		for _, raw in { nil, 5, "x", {}, { money = 0 / 0, staff = "no", office = 99, week = -4, releases = { 1, { reviews = { 99, -1 } } } } } :: { any } do
			local p = Schema.reconcile(raw, 1000, 3)
			T.truthy(p.money == p.money, "money is a number")
			T.truthy(#p.staff >= 1)
			T.truthy(p.office >= 1 and p.office <= #Tuning.Offices)
			T.truthy(p.week >= 0)
			for _, r in p.releases do
				for _, v in r.reviews do
					T.truthy(v >= 1 and v <= 10)
				end
			end
		end
	end)
	T.it("sanitize: desks stay unique and inside the office, too many developers are cut", function()
		local p = Schema.default(1, 1) :: any
		p.staff[2].desk = 1
		local extra = {}
		for i = 3, 9 do
			local s = table.clone(p.staff[1])
			s.id = i
			s.desk = 1
			table.insert(extra, s)
		end
		for _, s in extra do
			table.insert(p.staff, s)
		end
		local back = Schema.reconcile(roundTrip(p), 1, 1)
		T.eq(#back.staff, Tuning.Offices[1].desks)
		local seen = {}
		for _, s in back.staff do
			T.truthy(s.desk >= 1 and s.desk <= Tuning.Offices[1].desks and not seen[s.desk])
			seen[s.desk] = true
		end
		T.truthy(back.nextStaff > 9 or back.nextStaff > 3)
	end)
	T.it("unknown genres and topics are dropped, the starting ones always open", function()
		local p = Schema.default(1, 1) :: any
		p.genres = { hacking = true, rpg = true }
		p.topics = {}
		p.matches = { ["puzzle|space"] = "great", ["x|y"] = "great", ["action|space"] = "awesome" }
		local back = Schema.reconcile(roundTrip(p), 1, 1)
		T.truthy(back.genres.rpg and back.genres.action and back.genres.hacking == nil)
		T.truthy(back.topics.space)
		T.eq(back.matches["puzzle|space"], "great")
		T.eq(back.matches["x|y"], nil)
		T.eq(back.matches["action|space"], nil)
	end)
end
