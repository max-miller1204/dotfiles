#!/usr/bin/env bash
# Static single-owner and migration-safety policy shared by CI and native E2E.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OWNERSHIP="$ROOT/nix/data/tool-ownership.json"
PACKAGES="$ROOT/.chezmoidata/packages.yaml"

for required_file in "$OWNERSHIP" "$PACKAGES" "$ROOT/dot_pi/agent/settings.json"; do
	if [[ ! -f "$required_file" ]]; then
		echo "Missing ownership policy input file: $required_file" >&2
		exit 1
	fi
done
for scan_root in "$ROOT/.chezmoiscripts" "$ROOT/.chezmoitemplates" \
	"$ROOT/dot_config/fish"; do
	if [[ ! -d "$scan_root" ]]; then
		echo "Missing forbidden-pattern scan directory: $scan_root" >&2
		exit 1
	fi
done

runtime_policy="$(
	chezmoi --source "$ROOT" execute-template <<'EOF'
{
  "nodeChannel": {{ .runtimes.node.channel | quote }},
  "pythonVersion": {{ .runtimes.python.version | quote }},
  "rustToolchain": {{ .runtimes.rust.toolchain | quote }},
  "rustProxies": [{{ range $index, $proxy := .runtimes.rust.proxies }}{{ if $index }}, {{ end }}{{ $proxy | quote }}{{ end }}],
  "npmPrefixRel": {{ .npmTools.prefixRel | quote }},
  "npmPackages": [{{ range $index, $package := .npmTools.packages }}{{ if $index }}, {{ end }}{"name": {{ $package.name | quote }}, "channel": {{ $package.channel | quote }}}{{ end }}]
}
EOF
)"

jq -e --argjson runtime "$runtime_policy" '
  .schemaVersion == 1 and
  .migrationPhase == 5 and
  .active.homeManager == .target.homeManager and
  .active.homeManager.writableConfigs == [] and
  .active.homeManager.services == [] and
  .externalOwners.fnm.channel == $runtime.nodeChannel and
  .externalOwners.fnm.commands == ["node", "npm", "npx"] and
  .externalOwners.fnm.optionalCommands == ["corepack"] and
  .externalOwners.uv.version == $runtime.pythonVersion and
  .externalOwners.uv.commands == ["python", "python3",
    "python" + ($runtime.pythonVersion | split(".")[0:2] | join("."))] and
  .externalOwners.rustup.toolchain == $runtime.rustToolchain and
  .externalOwners.rustup.commands == $runtime.rustProxies and
  .externalOwners.npmPrefix.prefix == ("~/" + $runtime.npmPrefixRel) and
  .externalOwners.npmPrefix.packages == [
    $runtime.npmPackages[] | "\(.name)@\(.channel)"
  ]
' "$OWNERSHIP" >/dev/null

while IFS= read -r package; do
	if grep -qE "^[[:space:]]*- name: ${package}$" "$PACKAGES"; then
		echo "Duplicate package owner in packages.yaml: $package" >&2
		exit 1
	fi
done < <(jq -r '.active.homeManager.packages[]' "$OWNERSHIP")

if grep -qE '^[[:space:]]*- name: mise$|^[[:space:]]+mise:' "$PACKAGES"; then
	echo "mise remains an active package-manifest owner" >&2
	exit 1
fi

jq -e '
  ([.active.homeManager.commands[],
    .externalOwners.fnm.commands[],
    .externalOwners.fnm.optionalCommands[],
    .externalOwners.npmPrefix.commands[],
    .externalOwners.rustup.commands[],
    .externalOwners.uv.commands[]]
   | group_by(.) | map(select(length > 1)) | length) == 0
' "$OWNERSHIP" >/dev/null

forbidden_pattern='mise activate|mise use|mise upgrade|resolve_mise|install_mise'
forbidden_pattern+='|local/share/mise/shims|local/share/mise/installs/npm-hunkdiff'
forbidden_pattern+='|fnm[^#]*env[^#]*--use-on-cd'
if grep -R -n -E "$forbidden_pattern" \
	"$ROOT/.chezmoiscripts" "$ROOT/.chezmoitemplates" \
	"$ROOT/dot_config/fish" "$ROOT/dot_pi/agent/settings.json"; then
	echo "mise remains active in runtime, shell, updater, or Pi integration" >&2
	exit 1
fi

# Phase 6 is a no-GC soak followed by operator-controlled mise cleanup.
# Scan executable automation, not documentation, so the manual runbook can
# contain recovery commands while chezmoi, CI, and shell code cannot perform
# either irreversible action. Exclude this checker so its policy patterns do
# not match themselves.
automation_files=()
while IFS= read -r -d '' automation_file; do
	automation_files+=("$automation_file")
done < <(
	find "$ROOT/.chezmoiscripts" "$ROOT/.chezmoitemplates" \
		"$ROOT/dot_config/fish" "$ROOT/dot_config/tmux" \
		"$ROOT/dot_claude" "$ROOT/private_dot_local/bin" "$ROOT/nix" \
		"$ROOT/.github/actions" "$ROOT/.github/e2e" \
		"$ROOT/.github/workflows" "$ROOT/.github/scripts" \
		-type f ! -path "$ROOT/.github/scripts/check-tool-ownership.sh" \
		-print0
)
if [[ "${#automation_files[@]}" -eq 0 ]]; then
	echo "No executable automation files found for Phase 6 safety scan" >&2
	exit 1
fi

scan_automation() {
	local description="$1" pattern="$2" output status
	set +e
	output="$(grep -n -E "$pattern" "${automation_files[@]}" 2>&1)"
	status=$?
	set -e
	case "$status" in
	0)
		printf '%s\n' "$output" >&2
		echo "$description" >&2
		return 1
		;;
	1)
		return 0
		;;
	*)
		printf '%s\n' "$output" >&2
		echo "Phase 6 safety scan failed while checking: $description" >&2
		return "$status"
		;;
	esac
}

nix_cleanup_pattern='nix-collect-garbage'
nix_cleanup_pattern+='|nix[^#]*store[[:space:]]+(gc|delete)'
nix_cleanup_pattern+='|nix-store[^#]*(--gc|--delete)'
nix_cleanup_pattern+='|nix[^#]*profile[^#]*wipe-history'
nix_cleanup_pattern+='|nix-env[^#]*--delete-generations'
nix_cleanup_pattern+='|home-manager[^#]*expire-generations|nix\.gc'
scan_automation \
	"Automated Nix garbage collection is forbidden during the Phase 6 soak" \
	"$nix_cleanup_pattern"

mise_cleanup_pattern='brew[[:space:]]+(uninstall|remove)[^#]*mise'
mise_cleanup_pattern+='|mise[[:space:]]+(uninstall|implode|prune)'
mise_cleanup_pattern+='|(rm|rmdir|unlink|mv|trash)[^#]*(\.config/mise|\.cache/mise|\.local/(bin/mise|share/mise|state/mise)|/mise|XDG_[A-Z_]+[^#]*mise)'
mise_cleanup_pattern+='|(tar|zip|cp|rsync)[^#]*(\.config/mise|\.cache/mise|\.local/(bin/mise|share/mise|state/mise)|/mise|XDG_[A-Z_]+[^#]*mise)'
mise_cleanup_pattern+='|find[^#]*mise[^#]*-delete'
scan_automation \
	"mise cleanup must remain a manual post-soak operation" \
	"$mise_cleanup_pattern"
