#!/bin/sh
# The game's thumbnails (1920 x 1080) and icon (512 x 512) to upload on the Creator Dashboard (the request of
# 2026-11-20: "could you make thumbnails that are engaging and show the gameplay well, along with an icon? use
# creature models, dont need to show the player"). Draws the scenes and the driftlings with the game's own picture
# path (the preview scenario "gthumbs": tools/preview/game_thumbs.luau, three runs at once: the driftlings and the egg
# drawn alone, the meadow with one eternal among the commons, the tier 20 town centred on its tree under the night sky
# (it logs its coins a minute); then the before-and-after pair (a first island and a full one) and the icon's island,
# each captured again with the world hidden for its sky alone, and the rarity ladder's three islets), then lays them
# out as pixel illustrations (tools/preview/game_thumbs.py, tools/preview/genre_thumbs.py,
# tools/preview/illustrate.py) into art/thumbnails/: thumb_0_days.png (the before and
# after, the lead; the request of 2026-11-21: "research other island building games, and make a thumbnail referencing
# their framing as close as possible"), the genre's other frames (the request of 2026-11-21: "do more thumbnail
# research, and replicate popular game thumbnails with the same genre type"): thumb_1_rarity.png (the rarity ladder),
# thumb_2_hero.png (the close-up), thumb_3_hatch.png (the egg and what hatched), thumb_4_lucky.png (one eternal among
# many) and thumb_5_rich.png (the big number), and icon.png. Run it again after changing a model or a scene they show
# (the Tree of Life, the eggs, the town, the driftlings in CAST).
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
rm -rf "$out/cast" "$out/field" "$out/rich" "$out/pedestal" "$out/day1" "$out/day100" "$out/icon" "$out/scenes"
run() {
	PREVIEW_FLAGS="--no-core" PREVIEW_KEEP=1 PREVIEW_JOBS=1 REPO="$REPO" sh "$PREVIEW/render.sh" "$1" "$out/$2" desktop > "$out/$2.txt" 2>&1
}
run gthumbs=cast cast &
run gthumbs=field field &
run gthumbs=day100:20:tree rich &
wait
run gthumbs=day1 day1 &
run gthumbs=day100 day100 &
run gthumbs=icon icon &
run gthumbs=pedestal pedestal &
wait
mkdir -p "$out/scenes"
cp "$out"/field/gth_*_desktop.png "$out"/pedestal/gth_*_desktop.png "$out"/day1/gth_*_desktop.png "$out"/day100/gth_*_desktop.png "$out"/icon/gth_*_desktop.png "$out/scenes/" 2>/dev/null
# (the tier 20 town is a day100 run of its own: its frames under their own names)
cp "$out/rich/gth_day100_desktop.png" "$out/scenes/gth_rich_desktop.png" 2>/dev/null
cp "$out/rich/gth_day100_sky_desktop.png" "$out/scenes/gth_rich_sky_desktop.png" 2>/dev/null
cp "$out/rich/gth_day100_tree_desktop.png" "$out/scenes/gth_rich_tree_desktop.png" 2>/dev/null
rate=$(grep -h "gthumbs: day100:20:tree coins a minute" "$out"/rich/_logs/*.txt 2>/dev/null | head -1 | sed 's/.*coins a minute //')
[ -n "$rate" ] || { echo "no coins a minute in the tier 20 run:" >&2; cat "$out/rich.txt" >&2; exit 1; }
log=$(ls "$out"/cast/_logs/dump_*.txt 2>/dev/null | head -1)
[ -n "$log" ] || { echo "no cast log:" >&2; cat "$out/cast.txt" >&2; exit 1; }
grep -h "gthumbs\|ERROR\|failed" "$out"/*/_logs/*.txt | grep -v "^@@" | cut -c1-200
python3 "$PREVIEW/game_thumbs.py" "$out/scenes" "$log" "$REPO/art/thumbnails" --rate "$rate" --sheet "$out/sheet.png" || exit 1
[ -z "$keep" ] && rm -rf "$out"
exit 0
