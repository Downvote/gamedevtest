#!/bin/sh
# Driftling Isle preview: boots the real server + client scripts of a Rojo tree in the fake engine, runs a scenario
# and writes PNGs at the device resolution (pixel layer + GUI).
#
# Usage: sh render.sh <scenario> <outdir> [devices] [tier]
#   scenario: island | village | island2 | island3 | city | gallery | day | dusk | night | dawn | panel=<folk|pals|hatch|site|index|looks> |
#             exp=<kind 1-9>[_battle|_boss|_clear|_win|_lose|_loot|_fight|_snack|_skills|_aim|_throw|_tut] | sea | visit | build | water | voyage | late | all
#             (preview.luau's SCEN; all = island village island3 sea build day)
#   devices:  space-separated list, default "desktop phone" (also: laptop tablet portrait android iphone8 desktop1440)
#   tier:     auto (default, what the game picks: high) | low | medium | high | off
# Environment:
#   REPO=<dir>          Rojo tree to boot (default: this repository; read only)
#   PREVIEW_JOBS=<n>    parallel runs (default 4)
#   PREVIEW_KEEP=1      keep the dumps and logs in <outdir>/_logs
#   PREVIEW_FLAGS=...   extra topng.py flags (--ui --boxes --no-core)
#   PREVIEW_LUAU=...    luau flags (default --codegen: native, like Studio; -O2: interpreted, like a live client)
PREVIEW=$(cd "$(dirname "$0")" && pwd)
T=${TOOLS:-$HOME/.local/rbx-tools}
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
scen=${1:?usage: render.sh <island|village|island2|island3|city|day|dusk|night|dawn|panel=name|exp=kind|sea|visit|build|water|work|voyage|late|all> <outdir> [devices] [tier]}
out=${2:?usage: render.sh <scenario> <outdir> [devices] [tier]}
devices=${3:-desktop phone}
tier=${4:-auto}
jobs=${PREVIEW_JOBS:-4}

case $scen in
	all) scens="island village island3 sea build day" ;;
	island|village|island2|island3|city|gallery|day|dusk|night|dawn|panel=*|exp=*|sea|visit|build|expand|zoo|paths|water|work|voyage|late|loading|ploadingart) scens=$scen ;;
	*) echo "unknown scenario: $scen" >&2; exit 2 ;;
esac
mkdir -p "$out" || exit 1
out=$(cd "$out" && pwd) || exit 1
run="r$(date +%s)_$$"
work="$PREVIEW/work/$run"
mkdir -p "$work" || exit 1

# sources of the tree as it is right now
(cd "$REPO" || exit 1; "$T/bin/rojo" sourcemap default.project.json -o "$work/sourcemap.json" >/dev/null) || { echo "rojo sourcemap failed in $REPO" >&2; exit 1; }
python3 "$PREVIEW/gen_sources.py" "$REPO" "$work/sourcemap.json" "$work/sources.luau" >/dev/null || exit 1

cd "$PREVIEW" || exit 1
for s in $scens; do
	for d in $devices; do
		echo "$s $d"
	done
done > "$work/jobs.txt"
start=$(date +%s)
export PREVIEW_LUAU="${PREVIEW_LUAU:---codegen}"
xargs -P "$jobs" -L 1 sh -c 'cd "$0" || exit 1; "$1/bin/luau" $PREVIEW_LUAU preview.luau -a "work/$2" "$5" "$6" "$3" "$4" > "work/$2/dump_$(echo "$5" | tr "=" "-")_$6.txt" 2>&1' "$PREVIEW" "$T" "$run" "$tier" "${PREVIEW_INSET:-}" < "$work/jobs.txt"
echo "simulated in $(( $(date +%s) - start ))s; drawing PNGs"

status=0
for f in "$work"/dump_*.txt; do
	[ -f "$f" ] || continue
	python3 "$PREVIEW/topng.py" "$f" "$out" ${PREVIEW_FLAGS:-} || status=1
	tag=$(basename "$f" .txt | sed 's/^dump_//')
	# what went wrong while booting or playing (script errors, failed inits, kicks, driver misses)
	grep -h -E "^\[preview.*(ERROR|failed|no button|kicked)|KICK |WARN \((server|client:[^)]*)\): .*(failed|error|Error)|!!ERROR" "$f" | cut -c1-260 | sort -u | head -12 | sed "s|^|  $tag: |"
	grep -h "^\[preview.*done:" "$f" | sed "s|^.*done: |  $tag: |"
done
# a contact sheet of everything in the output folder
python3 - "$out" <<'PYEOF'
import html, os, sys
out = sys.argv[1]
pngs = sorted(f for f in os.listdir(out) if f.endswith(".png") and not f.endswith(("_ui.png", "_boxes.png")))
rows = []
for f in pngs:
    rows.append('<figure><a href="%s"><img src="%s" loading="lazy"></a><figcaption>%s</figcaption></figure>' % (html.escape(f), html.escape(f), html.escape(f[:-4])))
page = """<!doctype html><meta charset="utf-8"><title>Byte-Size Studio preview</title>
<style>body{font:14px system-ui,sans-serif;margin:16px;background:#2f2740;color:#fff6e6}
main{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;background:#463b5c;padding:8px;border:2px solid #2b1e2e}
img{display:block;max-width:560px;max-height:340px;image-rendering:pixelated}figcaption{margin-top:6px;font-weight:600}</style>
<h1>Byte-Size Studio preview</h1><main>%s</main>""" % "\n".join(rows)
open(os.path.join(out, "index.html"), "w").write(page)
PYEOF
if [ -n "${PREVIEW_KEEP:-}" ]; then
	mkdir -p "$out/_logs" && cp "$work"/dump_*.txt "$out/_logs/" 2>/dev/null
fi
rm -rf "$work"
exit $status
