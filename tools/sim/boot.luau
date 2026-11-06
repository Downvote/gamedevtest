-- Smoke test: boot the server, one full client, print what is there (no checks).
local E = require("./loader")
local I = require("./inst")
local H = require("./harness")
local tree = require("./sources")
E.verbose = false
H.patchMonetizationIds(tree)
E.boot(tree)
E.startServer()
E.run(1)
local p = H.addPlayer({ userId = 1001, name = "Alice" })
E.run(6)
print("errors", #E.errors, "issues", #E.issues, "warnings", #E.warnings)
for _, e in E.errors do print("ERR", e.kind, e.ctx, e.msg, e.trace) end
for _, w in E.warnings do print("WARN", w.ctx, w.text) end
for _, w in E.issues do print("ISSUE", w.kind, w.ctx, w.msg) end
local s = H.session(p)
print("session", s ~= nil, s and s.ready, s and s.plot)
print("ws children"); for _, c in E.workspace:GetChildren() do print("  ", c.Name, c.ClassName, #c:GetDescendants()) end
local pg = p:FindFirstChild("PlayerGui")
for _, c in pg:GetChildren() do print("  gui", c.Name, c.ClassName, #c:GetDescendants()) end
local v = H.view(p)
print("view", v and v.money, v and v.week, v and #v.staff)
