#!/usr/bin/env bash
# scripts/check.sh - the Definition-of-Done gate (docs/WORKFLOW.md). Run from anywhere; exits non-zero on failure.
set -euo pipefail
# the tools (rojo, luau, luau-lsp; luau-compile optional) in $TOOLS/bin: tools/setup.sh installs them there
TOOLS="${TOOLS:-$HOME/.local/rbx-tools}"
cd "$(dirname "$0")/.."
# Roblox's API types for luau-lsp: the copy in $TOOLS/defs if there is one, else the repository's
DEFS="$TOOLS/defs/globalTypes.d.luau"
[ -f "$DEFS" ] || DEFS="tools/defs/globalTypes.d.luau"
for t in rojo luau-lsp luau; do
	[ -x "$TOOLS/bin/$t" ] || { echo "missing $TOOLS/bin/$t: run sh tools/setup.sh (or set TOOLS)" >&2; exit 1; }
done
echo "== rojo sourcemap"
"$TOOLS/bin/rojo" sourcemap default.project.json -o sourcemap.json
echo "== luau-lsp analyze"
"$TOOLS/bin/luau-lsp" analyze --definitions="$DEFS" --sourcemap=sourcemap.json src
echo "== luau compile"
# luau-lsp does not see compiler limits (e.g. 200 upvalues per function); luau-compile does. Optional binary.
if [ -x "$TOOLS/bin/luau-compile" ]; then
	find src -name '*.luau' -print0 | xargs -0 "$TOOLS/bin/luau-compile" --null
else
	echo "skipped: no $TOOLS/bin/luau-compile"
fi
echo "== luau tests"
rm -rf build/luautest
mkdir -p build/luautest
cp -R src/shared build/luautest/shared
find build/luautest -name '*.luau' -exec sed -i -E \
	-e 's/require\(script\.Parent\.Parent\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\)/require("..\/\1\/\2")/g' \
	-e 's/require\(script\.Parent\.Parent\.([A-Za-z0-9_]+)\)/require("..\/\1")/g' \
	-e 's/require\(script\.Parent\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' {} +
"$TOOLS/bin/luau" tests/run.luau
echo "== rojo build"
"$TOOLS/bin/rojo" build default.project.json -o build/ByteSizeStudio.rbxlx
echo "ALL CHECKS PASSED"
