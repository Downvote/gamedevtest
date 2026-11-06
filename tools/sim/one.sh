#!/bin/sh
# Run scenarios against already generated sources: sh one.sh "file.luau:log[:arg]" ...  (regen first with: sh one.sh --gen)
T=${TOOLS:-$HOME/.local/rbx-tools}
SIM=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
if [ "$1" = "--gen" ]; then
  shift
  cd "$REPO" || exit 1
  "$T/bin/rojo" sourcemap default.project.json -o "$SIM/sourcemap.json" >/dev/null || exit 1
  python3 "$SIM/gen_sources.py" "$REPO" "$SIM/sourcemap.json" "$SIM/sources.luau" >/dev/null || exit 1
fi
cd "$SIM" || exit 1
for spec in "$@"; do
  f=$(echo "$spec" | cut -d: -f1); log=$(echo "$spec" | cut -d: -f2); arg=$(echo "$spec" | cut -d: -f3)
  ( if [ -n "$arg" ]; then "$T/bin/luau" "$f" -a $arg > "$log" 2>&1; else "$T/bin/luau" "$f" > "$log" 2>&1; fi; echo "rc=$?" >> "$log" ) &
done
wait
for spec in "$@"; do
  log=$(echo "$spec" | cut -d: -f2)
  echo "===== $log"; if grep -q 'SIM REPORT' "$log"; then sed -n '/SIM REPORT/,$p' "$log" | grep -v '^WARN' | head -16; else tail -6 "$log" | cut -c1-300; fi
done
