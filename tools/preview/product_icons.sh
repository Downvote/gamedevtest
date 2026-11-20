#!/bin/sh
# The game passes' and developer products' icons (Config/Monetization: six passes, ten products): draws their subjects
# from the game's own models (the preview scenario "picons", tools/preview/product_icons.luau), lays them on their
# badges with the words and symbols (tools/preview/product_icons.py) and writes the 512 x 512 PNGs to upload on the
# Creator Dashboard into art/products/<key>.png. Run it again after changing a model an icon shows (an egg, the Tree of
# Life, the Hatchery, the Snack Stall, the fountain, a pile of coins, the founder, the Golden Crown).
#
# Usage: sh tools/preview/product_icons.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the run's log and sheet.png (every icon at half size).
PREVIEW=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$PREVIEW/../.." && pwd)
out=${1:-}
keep=1
if [ -z "$out" ]; then
	out=$(mktemp -d) || exit 1
	keep=
fi
mkdir -p "$out" || exit 1
out=$(cd "$out" && pwd) || exit 1
rm -rf "$out/run"
PREVIEW_KEEP=1 PREVIEW_JOBS=1 REPO="$REPO" sh "$PREVIEW/render.sh" picons "$out/run" desktop off > "$out/run.txt" 2>&1
log="$out/run/_logs/dump_picons_desktop.txt"
[ -f "$log" ] || { echo "no log at $log:" >&2; cat "$out/run.txt" >&2; exit 1; }
grep -h "picons\|ERROR\|failed" "$log" | grep -v "^@@" | cut -c1-200
python3 "$PREVIEW/product_icons.py" "$log" "$REPO/art/products" --sheet "$out/sheet.png" || exit 1
[ -z "$keep" ] && rm -rf "$out"
exit 0
