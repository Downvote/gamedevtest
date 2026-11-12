#!/bin/sh
# The driftlings' portraits from their models: draws them through the game's own picture path (the preview scenario
# "pportraits", tools/preview/portraits.luau), tidies them to the pixel art rules into scripts/portraits.txt
# (gen_portraits.py) and remakes src/client/UI/ArtData.luau (scripts/gen_art.py).
#
# Usage: sh tools/preview/portraits.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the scenario's PNG and log and sheet.png (every portrait
#   raw and tidied, side by side, at 8x).
PREVIEW=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$PREVIEW/../.." && pwd)
out=${1:-}
keep=1
if [ -z "$out" ]; then
	out=$(mktemp -d) || exit 1
	keep=
fi
PREVIEW_KEEP=1 REPO="$REPO" sh "$PREVIEW/render.sh" pportraits "$out" desktop | tail -2 || exit 1
log="$out/_logs/dump_pportraits_desktop.txt"
[ -f "$log" ] || { echo "no log at $log" >&2; exit 1; }
grep -h "pportraits" "$log" | grep -v "^@@" | cut -c1-200
python3 "$PREVIEW/gen_portraits.py" "$log" --out "$REPO/scripts/portraits.txt" --sheet "$out/sheet.png" --raw || exit 1
python3 "$REPO/scripts/gen_art.py" || exit 1
if [ -z "$keep" ]; then
	rm -rf "$out"
else
	echo "sheet: $out/sheet.png"
fi
