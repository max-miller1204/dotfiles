#!/usr/bin/env bash
# Every `model:` pinned in a pi subagent definition must appear in the
# enabledModels allowlist of pi's settings: the subagents package's opt-in
# scopeModels guardrail matches that list by exact entry and warns on every
# spawn for a pin outside it.
#
#   check-pi-model-pins.sh <agents-dir> <settings-json>
#
# Both inputs are plain (non-templated) files, so this runs against the source
# tree in CI and against the applied ~/.pi tree in the native E2E.
# Offenders are reported on stdout, one per line.
# Exit: 0 = all pins in the allowlist, 1 = offenders found, 2 = bad input.
set -uo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: check-pi-model-pins.sh <agents-dir> <settings-json>" >&2
	exit 2
fi

AGENTS_DIR="$1"
SETTINGS="$2"

if [[ ! -d "$AGENTS_DIR" ]]; then
	echo "check-pi-model-pins: agents dir not found: $AGENTS_DIR" >&2
	exit 2
fi
if [[ ! -f "$SETTINGS" ]]; then
	echo "check-pi-model-pins: settings file not found: $SETTINGS" >&2
	exit 2
fi

# Read `model:` from the leading `---` frontmatter block ONLY, so a prompt-body
# line that happens to start with `model:` is never mistaken for a pin.
frontmatter_model() {
	awk '
		NR == 1 && $0 == "---" { in_fm = 1; next }
		in_fm && $0 == "---" { exit }
		in_fm && /^model:[[:space:]]*/ {
			sub(/^model:[[:space:]]*/, "")
			sub(/[[:space:]]+$/, "")
			print
			exit
		}
	' "$1"
}

rc=0
checked=0
for def in "$AGENTS_DIR"/*.md; do
	[[ -e "$def" ]] || continue
	pin="$(frontmatter_model "$def")"
	# YAML permits quoting the scalar; enabledModels holds bare ids.
	case "$pin" in
	'"'*'"')
		pin="${pin#\"}"
		pin="${pin%\"}"
		;;
	"'"*"'")
		pin="${pin#\'}"
		pin="${pin%\'}"
		;;
	esac
	# No pin means the agent inherits defaultModel, which needs no allowlist entry.
	[[ -n "$pin" ]] || continue
	checked=$((checked + 1))
	if ! jq -e --arg m "$pin" '.enabledModels | index($m) != null' "$SETTINGS" >/dev/null; then
		echo "  $(basename "$def") pins \"$pin\", absent from enabledModels in $SETTINGS"
		rc=1
	fi
done

if [[ "$rc" -eq 0 ]]; then
	echo "check-pi-model-pins: $checked pinned model(s), all present in enabledModels"
fi
exit "$rc"
