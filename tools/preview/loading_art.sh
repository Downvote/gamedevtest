#!/bin/sh
# The loading card's picture: the island drawn by the game's own picture path (the preview scenario "ploadingart",
# tools/preview/loading_art.luau: a big picture and a small one on a flat key colour), polished and packed into
# src/first/LoadingArt.luau by gen_loading_art.py. Run it again after changing a model or the island it shows.
#
# Usage: sh tools/preview/loading_art.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the scenario's PNGs and sheet.png (the raw and the
#   polished pictures side by side at 3x on the card's night sky).
PREVIEW=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$PREVIEW/../.." && pwd)
out=${1:-}
keep=1
if [ -z "$out" ]; then
	out=$(mktemp -d) || exit 1
	keep=
fi
PREVIEW_FLAGS="--no-core" PREVIEW_KEEP=1 REPO="$REPO" sh "$PREVIEW/render.sh" ploadingart "$out" desktop | tail -2 || exit 1
grep -h "ploadingart" "$out"/_logs/*.txt 2>/dev/null | grep -v "^@@" | cut -c1-200
[ -f "$out/lart_big_desktop.png" ] && [ -f "$out/lart_small_desktop.png" ] || { echo "no pictures in $out" >&2; exit 1; }
python3 "$PREVIEW/gen_loading_art.py" "$out/lart_big_desktop.png" "$out/lart_small_desktop.png" "$REPO/src/first/LoadingArt.luau" --sheet "$out/sheet.png" || exit 1
if [ -z "$keep" ]; then
	rm -rf "$out"
else
	echo "sheet: $out/sheet.png"
fi
