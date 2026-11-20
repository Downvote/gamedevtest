#!/bin/sh
# The game's thumbnails (1920 x 1080) and icon (512 x 512) to upload on the Creator Dashboard (the request of
# 2026-11-20: "could you make thumbnails that are engaging and show the gameplay well, along with an icon? use
# creature models, dont need to show the player"). Draws the scenes and the driftlings with the game's own picture
# path (the preview scenario "gthumbs": tools/preview/game_thumbs.luau, four runs at once: the town, the hatch, the
# islet with its crowd and the driftlings drawn alone), then lays them out with the title and the captions
# (tools/preview/game_thumbs.py) into art/thumbnails/: thumb_1_title.png .. thumb_5_eggs.png and icon.png. Run it again
# after changing a model or a scene they show (the Tree of Life, the eggs, the town, the driftlings in CAST).
#
# Usage: sh tools/preview/game_thumbs.sh [outdir]
#   outdir (default: a temporary folder, removed after) keeps the runs' logs, their frames and sheet.png.
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
rm -rf "$out/scene" "$out/hatch" "$out/lawn" "$out/cast" "$out/sky" "$out/scenes"
run() {
	PREVIEW_FLAGS="--no-core" PREVIEW_KEEP=1 PREVIEW_JOBS=1 REPO="$REPO" sh "$PREVIEW/render.sh" "$1" "$out/$2" desktop > "$out/$2.txt" 2>&1
}
run gthumbs scene &
run gthumbs=hatch hatch &
run gthumbs=lawn lawn &
run gthumbs=cast cast &
wait
run gthumbs=sky sky
mkdir -p "$out/scenes"
cp "$out"/scene/gth_*_desktop.png "$out"/hatch/gth_*_desktop.png "$out"/lawn/gth_*_desktop.png "$out"/sky/gth_*_desktop.png "$out/scenes/" 2>/dev/null
log=$(ls "$out"/cast/_logs/dump_*.txt 2>/dev/null | head -1)
[ -n "$log" ] || { echo "no cast log:" >&2; cat "$out/cast.txt" >&2; exit 1; }
grep -h "gthumbs\|ERROR\|failed" "$out"/*/_logs/*.txt | grep -v "^@@" | cut -c1-200
python3 "$PREVIEW/game_thumbs.py" "$out/scenes" "$log" "$REPO/art/thumbnails" --sheet "$out/sheet.png" || exit 1
[ -z "$keep" ] && rm -rf "$out"
exit 0
