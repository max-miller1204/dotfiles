#!/usr/bin/env bash
# Regression probes for Phase 6's no-GC and manual-mise-cleanup policy.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CHECKER="$ROOT/.github/scripts/check-tool-ownership.sh"

if [[ ! -x "$CHECKER" ]]; then
	echo "Missing executable migration-safety checker: $CHECKER" >&2
	exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/source"
tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$test_root/source" -xf -
source_root="$test_root/source"

bash "$source_root/.github/scripts/check-tool-ownership.sh" "$source_root"

printf '{ config, ... }: { nix%s }\n' '.gc.automatic = true;' \
	>"$source_root/nix/modules/forbidden-gc-probe.nix"
if bash "$source_root/.github/scripts/check-tool-ownership.sh" "$source_root" \
	>"$test_root/gc.log" 2>&1; then
	echo "Migration-safety checker missed Nix GC automation" >&2
	exit 1
fi
grep -Fq 'Automated Nix garbage collection is forbidden' "$test_root/gc.log"
rm -f "$source_root/nix/modules/forbidden-gc-probe.nix"

{
	printf '%s\n' 'name: forbidden-store-delete-probe' 'runs:' \
		'  using: composite' '  steps:' '    - shell: bash'
	printf '      run: nix --extra-experimental-features %s store %s target\n' \
		'nix-command' delete
} >"$source_root/.github/actions/forbidden-store-probe.yml"
if bash "$source_root/.github/scripts/check-tool-ownership.sh" "$source_root" \
	>"$test_root/store.log" 2>&1; then
	echo "Migration-safety checker missed Nix store deletion" >&2
	exit 1
fi
grep -Fq 'Automated Nix garbage collection is forbidden' \
	"$test_root/store.log"
rm -f "$source_root/.github/actions/forbidden-store-probe.yml"

{
	printf '%s\n' 'name: forbidden-mise-cleanup-probe' 'runs:' '  using: composite'
	printf '  steps:\n    - shell: bash\n      run: brew %s %s\n' uninstall mise
} >"$source_root/.github/actions/forbidden-mise-probe.yml"
if bash "$source_root/.github/scripts/check-tool-ownership.sh" "$source_root" \
	>"$test_root/mise.log" 2>&1; then
	echo "Migration-safety checker missed automated mise cleanup" >&2
	exit 1
fi
grep -Fq 'mise cleanup must remain a manual post-soak operation' \
	"$test_root/mise.log"
rm -f "$source_root/.github/actions/forbidden-mise-probe.yml"

archive_tool_name=mise
{
	printf '%s\n' 'name: forbidden-mise-archive-probe' 'runs:' \
		'  using: composite' '  steps:' '    - shell: bash'
	printf '      run: tar -cf archive.tar "$%s/%s"\n' \
		XDG_DATA_HOME "$archive_tool_name"
} >"$source_root/.github/actions/forbidden-archive-probe.yml"
if bash "$source_root/.github/scripts/check-tool-ownership.sh" "$source_root" \
	>"$test_root/archive.log" 2>&1; then
	echo "Migration-safety checker missed automated mise archival" >&2
	exit 1
fi
grep -Fq 'mise cleanup must remain a manual post-soak operation' \
	"$test_root/archive.log"
