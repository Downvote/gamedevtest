#!/bin/sh
# The cosmetics' pictures from the pieces' models (GAME_DESIGN 14.1): draws every piece in Data/Cosmetics through the
# game's own picture path (the preview scenario "cthumbs", tools/preview/cosmetic_thumbs.luau, split over a few runs
# that go at once), tidies them to the pixel art rules into scripts/cosmetic_thumbs.txt (gen_thumbs.py) and remakes
# src/client/UI/CosmeticThumbData.luau (and ArtData.luau and ThumbData.luau, unchanged) with scripts/gen_art.py. Run it
# again after a piece's model changes (Models/CosmeticModels).
#
# Usage: sh tools/preview/cosmetic_thumbs.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the runs' logs, sheet.png (every picture at 6x, as it
#   goes in the game) and raw.png (each picture as drawn beside its tidied one).
# Environment: THUMB_RUNS=<n> runs at once (default 4).
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
runs=${THUMB_RUNS:-4}
start=$(date +%s)
k=1
while [ "$k" -le "$runs" ]; do
	rm -rf "$out/run$k"
	PREVIEW_KEEP=1 PREVIEW_JOBS=1 REPO="$REPO" sh "$PREVIEW/render.sh" "cthumbs=${k}of$runs" "$out/run$k" desktop off > "$out/run$k.txt" 2>&1 &
	k=$((k + 1))
done
wait
logs=
k=1
while [ "$k" -le "$runs" ]; do
	log="$out/run$k/_logs/dump_cthumbs-${k}of${runs}_desktop.txt"
	[ -f "$log" ] || { echo "no log at $log:" >&2; cat "$out/run$k.txt" >&2; exit 1; }
	grep -h "cthumbs\|ERROR\|failed" "$log" | grep -v "^@@" | cut -c1-200
	logs="$logs $log"
	k=$((k + 1))
done
echo "drawn in $(( $(date +%s) - start ))s"
# shellcheck disable=SC2086
python3 "$PREVIEW/gen_thumbs.py" $logs --cosmetics --out "$REPO/scripts/cosmetic_thumbs.txt" --sheet "$out/sheet.png" --raw-sheet "$out/raw.png" || exit 1
python3 "$REPO/scripts/gen_art.py" || exit 1
echo "done in $(( $(date +%s) - start ))s"
if [ -z "$keep" ]; then
	rm -rf "$out"
else
	echo "sheet: $out/sheet.png (raw beside tidied: $out/raw.png)"
fi
