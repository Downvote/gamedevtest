# How work is done here (for Claude)

These rules came out of building Random Bakery and apply to any Roblox game built the same way. A new game copies this
file and `tools/` and keeps its own specifics (its languages, its baselines, its names) in its `CLAUDE.md`. Read this
file and `tools/README.md` at the start of a session.

## Every request

1. **Read before changing.** Find the code the request touches and what depends on it. When a request is ambiguous
   and the choice is the user's, ask once with concrete options; otherwise take the sensible default and say so.
2. **Make the change** in the source tree, minimal and in scope. Shared rules go where server and client both use
   them (see below), never copied into both.
3. **Verify before reporting:**
   - `bash scripts/check.sh` must pass: Rojo sourcemap, luau-lsp strict analysis, luau-compile limits (200 locals
     or upvalues per function), the spec tests, the Rojo build.
   - Run the simulations that cover the change (`tools/sim`): 0 findings, and known issue counts unchanged from
     their baselines (keep the baselines in `CLAUDE.md`). Add checks for the new behaviour to the sim that covers it.
   - Anything a player sees: render previews (`tools/preview`) at desktop and phone size and look at them. For a
     speed problem, measure before and after (a timing probe in the preview harness) rather than guess.
   - Anything that rebuilds world geometry: compare against the previous version (a pixel diff of the same scene, or
     the static picture against a full re-bake) so a refactor provably changes nothing visible.
4. **Update the docs in the same commit**: the design doc (what and why, quoting the user's request), the
   architecture contract (APIs, types, data), and any feature doc.
5. **Commit and deliver**: a clear commit message (what changed and why, the request quoted, the trailers the session
   asks for), push to the working branch, build the place file `<Game>-<short hash>.rbxlx` in the repository root
   (git-ignored; delete the previous one), send the previews and the place file, and report briefly: what changed,
   what was verified (with numbers), what was not, and any trade-off or limit the user should know.

## Rules

- Push only to the branch the session names. No pull request unless asked. Never force-push, rebase or amend commits
  already pushed. No model names or ids in commits or code.
- Leave alone anything the user marks off limits (other repositories, folders, files).
- Never rename a DataStore key: the players' saves are there. Change the save shape with a Schema version and a
  migration, and check a profile from before still loads.
- Never commit an asset whose licence is not confirmed (fonts the user uploaded stay out).
- A game shipped in several languages translates every player-visible string in the same commit (`CLAUDE.md` says how).
- Report honestly: never claim a check that was not run, show the output when something fails, say what was skipped.
- In long tasks, post a short note of what is being done every so often.
- Keep temporary work (scratch scripts, renders, logs) out of the repository; keep reusable tools in `tools/`.

## Conventions that worked (Rojo, strict Luau)

- `src/shared/Data/*`: pure data tables; `src/shared/Logic/*`: pure rules with specs in `tests/specs`; both
  required by the server and the client alike. `Types.luau` holds the shared types.
- The server decides everything. Every client action is one Router request (a name and a payload) checked by
  `Validate` and answered `{ok, data}` or `{ok = false, err = <ErrCode>}`; the client mirrors the profile through
  patches (Session changed / changedEntry) and never trusts itself.
- One `Config/Tuning.luau` for every number; one `Config/Monetization.luau` for every Roblox id (0 = not created yet:
  every call site checks it is enabled).
- Saves: `Schema.default / migrate / reconcile / sanitize`, a session lock, a size guard, autosave on a timer.
- World building rebuilds only what changed (keep models whose look did not change, compare by a signature), so every
  client re-draws as little as possible.
- Each feature's docs quote the request it came from, so later changes can tell intent from accident.

## Tools

`tools/README.md`: installing the tools, the check, the simulator (a fake Roblox engine that boots the real server and
client scripts), the preview renderer (PNG screenshots of the real UI and world, stitched panoramas, timing probes).
