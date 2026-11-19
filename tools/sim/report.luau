-- Final report of a simulation run: findings, runtime errors, engine-detected issues, warnings (deduplicated).
-- An engine issue raised by the payloads a scenario's malicious client sends on purpose (phase "malicious", kind net-*)
-- is not a game issue: it is listed apart and not counted.
local function deliberate(e)
	return e.phase == "malicious" and string.sub(e.kind, 1, 4) == "net-"
end
-- A warning about a DataStore call a scenario made fail on purpose (E.ds.failNext / failRate: the fake engine's error
-- ends "(sim <op>)") is not a game warning either: listed apart, not counted.
local function injected(w)
	return string.find(w.text, "API Services rejected", 1, true) ~= nil and string.find(w.text, "(sim ", 1, true) ~= nil
end

return function(E, H)
	local issues, mine = 0, 0
	for _, e in E.issues do
		if deliberate(e) then
			mine += 1
		else
			issues += 1
		end
	end
	local warns, failed = 0, 0
	for _, w in E.warnings do
		if injected(w) then
			failed += 1
		else
			warns += 1
		end
	end
	E.out("\n================ SIM REPORT ================")
	E.out(string.format("checks=%d findings=%d errors=%d issues=%d warnings=%d sim-time=%.0fs (deliberate net issues: %d, deliberate store failures: %d)", H.checks, #H.findings, #E.errors, issues, warns, E.SIM.now - E.t0, mine, failed))
	for _, f in H.findings do
		E.out(string.format("FINDING [%s] (%s @%.1f) %s | %s", f.kind, tostring(f.phase), f.t, f.msg, f.evidence))
	end
	local seen = {}
	for _, e in E.errors do
		local key = e.kind .. e.msg
		if not seen[key] then
			seen[key] = true
			E.out(string.format("ERROR [%s] (%s, %s @%.1f) %s\n%s", e.kind, e.ctx, tostring(e.phase), e.t, e.msg, e.trace))
		end
	end
	seen = {}
	for _, e in E.issues do
		-- payload problems the malicious client sent on purpose are not game issues
		local key = e.kind .. e.msg
		if not seen[key] and not deliberate(e) then
			seen[key] = true
			E.out(string.format("ISSUE [%s] (%s, %s @%.1f) %s", e.kind, e.ctx, tostring(e.phase), e.t, e.msg))
		end
	end
	seen = {}
	for _, w in E.warnings do
		if not seen[w.text] and not injected(w) then
			seen[w.text] = true
			E.out(string.format("WARN (%s, %s @%.1f) %s", w.ctx, tostring(w.phase), w.t, w.text))
		end
	end
end
