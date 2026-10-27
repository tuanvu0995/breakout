#!/usr/bin/env bash
# OTA patches for Breakout (client: autoload/ota.gd, server: server/api/src/index.ts).
# Same workflow as drivedrive's tools/build/build_patch.sh.
#
#   tools/build_patch.sh snapshot             # save the shipped build's PCK as the patch baseline.
#                                             # Run it from the exact commit you released as a full build.
#   tools/build_patch.sh 0.1.1                # build patch PCK(s) against that baseline (no upload)
#   tools/build_patch.sh 0.1.1 --upload       # ...then upload the PCK(s), then the manifest
#   tools/build_patch.sh announce --upload    # no patch: tell clients the newest full build is config/version
#   tools/build_patch.sh revoke 0.1.1         # pull a bad patch: players drop it on their next launch
#
# A patch is a full delta from the baseline (not from the previous patch); only the latest one matters.
# Patch numbers must keep going up and never be reused. config/version stays the base version
# (bumping it means a new full build + a new snapshot).
#
# Env: ADMIN_TOKEN (to upload), API (the worker, e.g. https://breakout-api.example.com/v1),
#      PLATFORMS (default "macos web"; any of windows macos linux android web), FULL_DOWNLOAD_URL (optional),
#      GODOT=/path/to/godot. If .script_encryption_key exists, PCKs are encrypted with it.
# Written for macOS's stock bash 3.2.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
api="${API:-$(sed -n 's/^api_url="\(.*\)"$/\1/p' "$root/project.godot")}"
platforms="${PLATFORMS:-macos web}"
godot="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
mode="${1:?usage: build_patch.sh snapshot | <patch_version> [--upload] | announce --upload | revoke <version>}"

base_version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$root/project.godot")"
[ -n "$base_version" ] || { echo "could not read config/version from project.godot" >&2; exit 1; }
base_dir="$root/build/ota_base/$base_version"
out="$root/build/patches"

preset_for() {   # must match export_presets.cfg names
	case "$1" in
		windows) echo "Windows Desktop" ;;
		macos) echo "macOS" ;;
		linux) echo "Linux" ;;
		android) echo "Android" ;;
		web) echo "Web" ;;
		*) echo "unknown platform $1" >&2; exit 1 ;;
	esac
}

need_api() { [ -n "$api" ] || { echo "set API or breakout/api_url in project.godot" >&2; exit 1; }; }
need_token() { need_api; [ -n "${ADMIN_TOKEN:-}" ] || { echo "set ADMIN_TOKEN (the breakout-api admin secret)" >&2; exit 1; }; }

put_manifest() {   # $1 = JSON body
	need_token
	echo "==> manifest"
	curl --fail-with-body -sS -X PUT "$api/admin/ota/manifest" -H "Authorization: Bearer $ADMIN_TOKEN" \
		-H "Content-Type: application/json" --data "$1"
	echo
}

full_fields() {
	printf '"latest_full_version": "%s"' "$base_version"
	[ -z "${FULL_DOWNLOAD_URL:-}" ] || printf ', "full_download_url": "%s"' "$FULL_DOWNLOAD_URL"
}

current_revoke() {
	need_api
	curl -fsS "$api/ota/manifest" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("revoke", [])))'
}

if [ "$mode" = "announce" ]; then
	[ "${2:-}" = "--upload" ] || { echo "announce only makes sense with --upload" >&2; exit 1; }
	put_manifest "{$(full_fields), \"revoke\": $(current_revoke), \"patch\": {}}"
	exit 0
fi

if [ "$mode" = "revoke" ]; then
	bad="${2:?usage: build_patch.sh revoke <patch_version>}"
	revoke="$(current_revoke | python3 -c "import json,sys; l=json.load(sys.stdin); l.append('$bad'); print(json.dumps(sorted(set(l))))")"
	put_manifest "{$(full_fields), \"revoke\": $revoke, \"patch\": {}}"
	exit 0
fi

# Optional encryption: baseline and patches must use the same key as the shipped build.
key_file="$root/.script_encryption_key"
if [ -f "$key_file" ]; then
	GODOT_SCRIPT_ENCRYPTION_KEY="$(tr -dc '0-9a-fA-F' < "$key_file")"
	[ ${#GODOT_SCRIPT_ENCRYPTION_KEY} -eq 64 ] || { echo "$key_file must be 64 hex chars" >&2; exit 1; }
	export GODOT_SCRIPT_ENCRYPTION_KEY
fi

verify_pck() {
	[ "$(xxd -l 4 -p "$1")" = "47445043" ] || { echo "$1: not a Godot PCK" >&2; exit 1; }
}

"$godot" --headless --path "$root" --import >/dev/null

if [ "$mode" = "snapshot" ]; then
	mkdir -p "$base_dir"
	for key in $platforms; do
		echo "==> baseline $key"
		"$godot" --headless --path "$root" --export-pack "$(preset_for "$key")" "$base_dir/$key.pck"
		verify_pck "$base_dir/$key.pck"
	done
	echo "Baseline for v$base_version saved in build/ota_base/$base_version/ (back it up: every patch needs it)"
	exit 0
fi

patch_version="$mode"
[[ "$patch_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad patch version '$patch_version' (x.y.z)" >&2; exit 1; }
mkdir -p "$out"
sha_entries=""; sep=""
for key in $platforms; do
	baseline="$base_dir/$key.pck"
	[ -f "$baseline" ] || { echo "missing $baseline: run 'build_patch.sh snapshot' on the released commit first" >&2; exit 1; }
	pck="$out/patch-$patch_version-$key.pck"
	echo "==> patch $key"
	rm -f "$pck"
	"$godot" --headless --path "$root" --patches "$baseline" --export-patch "$(preset_for "$key")" "$pck" \
		|| { rm -f "$pck"; echo "patch export failed for $key (\"No files or changes\" = nothing differs)" >&2; exit 1; }
	[ -f "$pck" ] || { echo "export produced no file for $key" >&2; exit 1; }
	verify_pck "$pck"
	sha="$(shasum -a 256 "$pck" | cut -d' ' -f1)"
	printf '    %s  %s  %s\n' "$key" "$(du -h "$pck" | cut -f1)" "$sha"
	sha_entries="$sha_entries$sep\"$key\": \"$sha\""; sep=", "
done

[ "${2:-}" = "--upload" ] || { echo "Built in build/patches/. Add --upload to publish."; exit 0; }
need_token
for key in $platforms; do
	name="patch-$patch_version-$key.pck"
	echo "==> upload $name"
	curl --fail-with-body -sS --http1.1 -X PUT "$api/admin/ota/files/$name" -H "Authorization: Bearer $ADMIN_TOKEN" \
		-H "X-Sha256: $(shasum -a 256 "$out/$name" | cut -d' ' -f1)" \
		-H "Content-Type: application/octet-stream" --data-binary "@$out/$name"
	echo
done
# Manifest last: the server refuses it until every file it names is uploaded.
put_manifest "{$(full_fields), \"revoke\": $(current_revoke), \"patch\": {\"base_version\": \"$base_version\", \"patch_version\": \"$patch_version\", \"sha256\": {$sha_entries}}}"
