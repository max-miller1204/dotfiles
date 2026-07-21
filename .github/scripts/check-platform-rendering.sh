#!/usr/bin/env bash
# Prove desktop, headless Linux, and WSL render distinct GUI ownership surfaces.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PACKAGE_TEMPLATE="$ROOT/.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
IGNORE_TEMPLATE="$ROOT/.chezmoiignore"

for required_file in "$PACKAGE_TEMPLATE" "$IGNORE_TEMPLATE"; do
	if [[ ! -f "$required_file" ]]; then
		echo "Missing platform-rendering input: $required_file" >&2
		exit 1
	fi
done
if ! command -v chezmoi >/dev/null 2>&1; then
	echo "chezmoi is required for platform-rendering checks" >&2
	exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

gui_patterns=(
	'ppa:mkasberg/ghostty-ubuntu'
	'https://discord.com/api/download'
	'google-chrome-stable_current_amd64.deb'
	'/stable/1password-latest.deb'
	'voquill.github.io/apt/install.sh'
	'obsidianmd/obsidian-releases'
	'net.ankiweb.Anki'
	'com.spotify.Client'
	'us.zoom.Zoom'
)

render_profile() {
	local data="$1" name="$2"
	chezmoi --source "$ROOT" execute-template --override-data "$data" \
		<"$PACKAGE_TEMPLATE" >"$test_root/$name-packages.sh"
	chezmoi --source "$ROOT" execute-template --override-data "$data" \
		<"$IGNORE_TEMPLATE" >"$test_root/$name-ignore"
}

render_profile '{"headless":false,"isWSL":false}' desktop
render_profile '{"headless":true,"isWSL":false}' headless
render_profile '{"headless":true,"isWSL":true}' wsl

if grep -Fq 'headless/WSL - skipping GUI desktop apps' \
	"$test_root/desktop-packages.sh"; then
	echo "Desktop rendering unexpectedly skips GUI packages" >&2
	exit 1
fi
if grep -Fxq '.config/ghostty' "$test_root/desktop-ignore"; then
	echo "Desktop rendering unexpectedly ignores Ghostty configuration" >&2
	exit 1
fi

for pattern in "${gui_patterns[@]}"; do
	if ! grep -Fq "$pattern" "$test_root/desktop-packages.sh"; then
		echo "Desktop rendering is missing GUI package marker: $pattern" >&2
		exit 1
	fi
	for profile in headless wsl; do
		if grep -Fq "$pattern" "$test_root/$profile-packages.sh"; then
			echo "$profile rendering leaked GUI package marker: $pattern" >&2
			exit 1
		fi
	done
done

for profile in headless wsl; do
	if ! grep -Fq 'headless/WSL - skipping GUI desktop apps' \
		"$test_root/$profile-packages.sh"; then
		echo "$profile rendering lacks the GUI omission diagnostic" >&2
		exit 1
	fi
	if ! grep -Fxq '.config/ghostty' "$test_root/$profile-ignore"; then
		echo "$profile rendering does not ignore Ghostty configuration" >&2
		exit 1
	fi
done
