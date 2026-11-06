#!/bin/sh
# Installs the command-line tools scripts/check.sh, tools/sim and tools/preview use into $TOOLS/bin (default
# ~/.local/rbx-tools/bin): rojo, luau (with luau-analyze and luau-compile), luau-lsp. Linux x86_64. Needs curl and
# unzip; downloads from GitHub releases. Safe to run again (a tool already there is kept). For a cloud environment,
# put "sh tools/setup.sh" in the environment's setup script so every new session has them.
#   ROJO_VERSION    default 7.4.4 (rokit.toml pins the same)
#   LUAU_VERSION    default latest
#   LUAU_LSP_VERSION default 1.70.1
set -eu
TOOLS="${TOOLS:-$HOME/.local/rbx-tools}"
ROJO_VERSION="${ROJO_VERSION:-7.4.4}"
LUAU_VERSION="${LUAU_VERSION:-latest}"
LUAU_LSP_VERSION="${LUAU_LSP_VERSION:-1.70.1}"
mkdir -p "$TOOLS/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fetch <name> <url...>: the first url that downloads, unzipped into $tmp/<name>
fetch() {
	name=$1
	shift
	for url in "$@"; do
		if curl -fsSL -o "$tmp/$name.zip" "$url"; then
			mkdir -p "$tmp/$name"
			unzip -oq "$tmp/$name.zip" -d "$tmp/$name"
			return 0
		fi
	done
	echo "setup: could not download $name (tried: $*)" >&2
	return 1
}

if [ ! -x "$TOOLS/bin/rojo" ]; then
	fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/rojo-$ROJO_VERSION-linux-x86_64.zip"
	cp "$tmp/rojo/rojo" "$TOOLS/bin/"
fi
if [ ! -x "$TOOLS/bin/luau" ]; then
	if [ "$LUAU_VERSION" = latest ]; then
		fetch luau "https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip"
	else
		fetch luau "https://github.com/luau-lang/luau/releases/download/$LUAU_VERSION/luau-ubuntu.zip"
	fi
	for b in luau luau-analyze luau-compile luau-ast; do
		[ -f "$tmp/luau/$b" ] && cp "$tmp/luau/$b" "$TOOLS/bin/"
	done
fi
if [ ! -x "$TOOLS/bin/luau-lsp" ]; then
	fetch luau-lsp \
		"https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP_VERSION/luau-lsp-linux-x86_64.zip" \
		"https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP_VERSION/luau-lsp-linux.zip"
	cp "$tmp/luau-lsp/luau-lsp" "$TOOLS/bin/"
fi
chmod +x "$TOOLS/bin/"*
echo "tools in $TOOLS/bin:"
ls "$TOOLS/bin"
