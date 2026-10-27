#!/usr/bin/env bash
# Full release of Brickstellar to itch.io (https://pixalab.itch.io/brickstellar).
#
#   tools/release_itch.sh             # build macOS / Windows / Linux, snapshot OTA baseline, push with butler
#   tools/release_itch.sh --dry-run   # build + snapshot only, no upload
#   tools/release_itch.sh --force     # rebuild a version that was already released (overwrites its baseline)
#
# Version comes from config/version in project.godot (one full build per version).
# OTA patches for this version are made later with tools/build_patch.sh.
#
# Env: ITCH_TARGET (default pixalab/brickstellar), PLATFORMS (default "macos windows linux"),
#      ADMIN_TOKEN (optional: also tells the OTA manifest this is the newest full build),
#      GODOT=/path/to/godot.
# Needs: export templates for the Godot version, butler (`butler login` once).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${ITCH_TARGET:-pixalab/brickstellar}"
platforms="${PLATFORMS:-macos windows linux}"
godot="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
dry_run=0
force=0
for a in "$@"; do
	case "$a" in
		--dry-run) dry_run=1 ;;
		--force) force=1 ;;
	esac
done

version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$root/project.godot")"
[ -n "$version" ] || { echo "could not read config/version from project.godot" >&2; exit 1; }
out="$root/build/release/$version"

if [ $dry_run -eq 0 ]; then
	command -v butler >/dev/null || { echo "butler not found: https://itch.io/docs/butler/" >&2; exit 1; }
	butler status "$target" >/dev/null 2>&1 || { echo "butler can't see $target - run 'butler login' first" >&2; exit 1; }
	if [ -n "$(git -C "$root" status --porcelain -- . ':!*.uid')" ]; then
		echo "working tree has uncommitted changes - commit before a release build" >&2
		exit 1
	fi
fi

# A released version's OTA baseline must never change: every patch for it is a
# delta against it. New content for an already-released version goes out as an
# OTA patch (tools/build_patch.sh); a new full release bumps config/version.
if [ -d "$root/build/ota_base/$version" ] && [ $force -eq 0 ] && [ $dry_run -eq 0 ]; then
	echo "v$version already has an OTA baseline (it was released)." >&2
	echo "  - small fix for players:  ADMIN_TOKEN=... tools/build_patch.sh <x.y.z> --upload" >&2
	echo "  - new full release:       bump config/version in project.godot, then run this again" >&2
	echo "  - really rebuild v$version: add --force (breaks existing patches for it)" >&2
	exit 1
fi

echo "==> Brickstellar $version  ($platforms)"
"$godot" --headless --path "$root" --import >/dev/null 2>&1 || true
rm -rf "$out"
mkdir -p "$out"

channel_for() {
	case "$1" in
		macos) echo "osx" ;;
		windows) echo "windows" ;;
		linux) echo "linux" ;;
		*) echo "unknown platform $1" >&2; exit 1 ;;
	esac
}

for p in $platforms; do
	dir="$out/$p"
	mkdir -p "$dir"
	echo "==> export $p"
	case "$p" in
		macos)
			"$godot" --headless --path "$root" --export-release "macOS" "$out/Brickstellar-macos.zip" >/dev/null 2>&1
			unzip -q "$out/Brickstellar-macos.zip" -d "$dir"   # butler pushes the .app folder
			rm "$out/Brickstellar-macos.zip"
			;;
		windows)
			"$godot" --headless --path "$root" --export-release "Windows Desktop" "$dir/Brickstellar.exe" >/dev/null 2>&1
			;;
		linux)
			"$godot" --headless --path "$root" --export-release "Linux" "$dir/Brickstellar.x86_64" >/dev/null 2>&1
			;;
	esac
	[ -n "$(ls -A "$dir")" ] || { echo "export for $p produced nothing (missing export templates?)" >&2; exit 1; }
	printf '    %s  %s\n' "$p" "$(du -sh "$dir" | cut -f1)"
done

# OTA baseline for this version, always re-taken from this exact commit:
# patches are deltas against what players actually installed.
if [ $dry_run -eq 1 ] && [ -d "$root/build/ota_base/$version" ] && [ $force -eq 0 ]; then
	echo "Dry run: builds in build/release/$version/; released OTA baseline left untouched."
	exit 0
fi
echo "==> OTA baseline ($platforms)"
rm -rf "$root/build/ota_base/$version"
PLATFORMS="$platforms" "$root/tools/build_patch.sh" snapshot >/dev/null 2>&1
for p in $platforms; do
	[ -f "$root/build/ota_base/$version/$p.pck" ] || { echo "baseline for $p missing" >&2; exit 1; }
done

if [ $dry_run -eq 1 ]; then
	echo "Dry run: builds in build/release/$version/, nothing uploaded."
	exit 0
fi

for p in $platforms; do
	echo "==> butler push $p -> $target:$(channel_for "$p")"
	butler push "$out/$p" "$target:$(channel_for "$p")" --userversion "$version"
done

if [ -n "${ADMIN_TOKEN:-}" ]; then
	echo "==> OTA manifest: newest full build is $version"
	FULL_DOWNLOAD_URL="https://${target%%/*}.itch.io/${target#*/}" "$root/tools/build_patch.sh" announce --upload
fi

git -C "$root" tag -f "v$version" >/dev/null
echo "Done: https://${target%%/*}.itch.io/${target#*/}  (tagged v$version locally)"
