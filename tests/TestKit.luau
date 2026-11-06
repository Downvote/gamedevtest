-- tests/TestKit.luau (WP0). Minimal test harness for the plain luau CLI (no io library available).
local TestKit = {}
local results = { passed = 0, failed = 0, failures = {} :: { string } }
local prefix = ""

local function fmt(v: any): string
	if type(v) == "table" then
		local parts = {}
		for k, x in v do
			table.insert(parts, tostring(k) .. "=" .. fmt(x))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TestKit.describe(name: string, fn: () -> ())
	local old = prefix
	prefix = old .. name .. " > "
	fn()
	prefix = old
end

function TestKit.it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, prefix .. name .. ": " .. tostring(err))
	end
end

function TestKit.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
	end
end
function TestKit.deepEq(actual: any, expected: any, msg: string?)
	if not deepEqual(actual, expected) then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
	end
end
function TestKit.near(actual: number, expected: number, tol: number, msg: string?)
	if type(actual) ~= "number" or math.abs(actual - expected) > tol then
		error(string.format("%sexpected %s +/- %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(tol), tostring(actual)), 2)
	end
end
function TestKit.truthy(v: any, msg: string?)
	if not v then
		error((msg or "expected truthy") .. ", got " .. fmt(v), 2)
	end
end
function TestKit.throws(fn: () -> (), msg: string?)
	if pcall(fn) then
		error(msg or "expected an error", 2)
	end
end

function TestKit.report(): boolean
	for _, f in results.failures do
		print("FAIL " .. f)
	end
	print(string.format("%d passed, %d failed", results.passed, results.failed))
	return results.failed == 0
end

return TestKit
