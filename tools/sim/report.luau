-- Final report of a simulation run: findings, runtime errors, engine-detected issues, warnings (deduplicated).
-- An engine issue raised by the payloads a scenario's malicious client sends on purpose (phase "malicious", kind net-*)
-- is not a game issue: it is listed apart and not counted.
local function deliberate(e)
	return e.phase == "malicious" and string.sub(e.kind, 1, 4) == "net-"
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
	E.out("\n================ SIM REPORT ================")
	E.out(string.format("checks=%d findings=%d errors=%d issues=%d warnings=%d sim-time=%.0fs (deliberate net issues: %d)", H.checks, #H.findings, #E.errors, issues, #E.warnings, E.SIM.now - E.t0, mine))
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
		if not seen[w.text] then
			seen[w.text] = true
			E.out(string.format("WARN (%s, %s @%.1f) %s", w.ctx, tostring(w.phase), w.t, w.text))
		end
	end
end
