#!/bin/sh
# The loading card's scene art: draws it through the game's own picture path (the preview scenario "ploadingart",
# tools/preview/loading_art.luau) and packs it into src/first/LoadingArt.luau (gen_loading_art.py).
#
# Usage: sh tools/preview/loading_art.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the scenario's PNG and log, sheet.png (every sequence
#   at 4x on the card's dusk sky, with each anchor and point marked) and atlas.png (the packed atlas at 3x).
PREVIEW=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$PREVIEW/../.." && pwd)
out=${1:-}
keep=1
if [ -z "$out" ]; then
	out=$(mktemp -d) || exit 1
	keep=
fi
PREVIEW_KEEP=1 REPO="$REPO" sh "$PREVIEW/render.sh" ploadingart "$out" desktop | tail -2 || exit 1
log="$out/_logs/dump_ploadingart_desktop.txt"
[ -f "$log" ] || { echo "no log at $log" >&2; exit 1; }
grep -h "ploadingart" "$log" | grep -v "^@@" | cut -c1-200
python3 "$PREVIEW/gen_loading_art.py" "$log" "$REPO/src/first/LoadingArt.luau" --sheet "$out/sheet.png" --atlas "$out/atlas.png" || exit 1
if [ -z "$keep" ]; then
	rm -rf "$out"
else
	echo "sheet: $out/sheet.png, atlas: $out/atlas.png"
fi
