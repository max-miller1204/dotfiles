#!/usr/bin/env bash
# Static single-owner policy shared by pull-request CI and the native E2E.
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
