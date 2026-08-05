#!/usr/bin/env bash
# Every model pinned for a pi subagent must appear in the enabledModels
# allowlist of pi's settings. enabledModels is the one curated list of models
# this machine is meant to spawn; a pin outside it is either a typo or a model
# the user deliberately did not enable, and pi-subagents resolves model ids
# fuzzily, so such a pin silently lands on a neighbouring model instead of
# failing loudly.
#
# Pins live in two places since the switch to the nicobailon `npm:pi-subagents`
# fork, and both are checked:
#
#   - agent definition frontmatter: `model:` and `fallbackModels:`
#   - settings: `subagents.defaultModel`, `subagents.agentOverrides.<agent>`
#     (`model` and `fallbackModels`), and the `subagents.watchdog` models
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

# Read pins from the leading `---` frontmatter block ONLY, so a prompt-body line
# that happens to start with `model:` is never mistaken for a pin. Both the
# inline comma-separated and the `- item` block form of `fallbackModels:` are
# emitted, one model per line.
frontmatter_pins() {
	awk '
		NR == 1 && $0 == "---" { in_fm = 1; next }
		in_fm && $0 == "---" { exit }
		!in_fm { next }
		# Any new top-level key closes an open block list.
		/^[A-Za-z_]/ { list = "" }
		/^model:[[:space:]]*/ {
			value = $0
			sub(/^model:[[:space:]]*/, "", value)
			if (value != "") print value
			next
		}
		/^fallbackModels:[[:space:]]*/ {
			value = $0
			sub(/^fallbackModels:[[:space:]]*/, "", value)
			if (value == "") { list = "fallbackModels"; next }
			count = split(value, parts, ",")
			for (i = 1; i <= count; i++) print parts[i]
			next
		}
		list != "" && /^[[:space:]]+-[[:space:]]*/ {
			value = $0
			sub(/^[[:space:]]+-[[:space:]]*/, "", value)
			if (value != "") print value
			next
		}
	' "$1"
}

# Emit `<source>\t<model>` for every model pinned in the settings file.
settings_pins() {
	jq -r '
		(.subagents.defaultModel // empty | "subagents.defaultModel\t" + .),
		(.subagents.agentOverrides // {} | to_entries[] | . as $entry
			| ($entry.value.model // empty | "subagents.agentOverrides." + $entry.key + ".model\t" + .),
			  ($entry.value.fallbackModels // [] | .[] | "subagents.agentOverrides." + $entry.key + ".fallbackModels\t" + .)),
		(.subagents.watchdog.main.model // empty | "subagents.watchdog.main.model\t" + .),
		(.subagents.watchdog.children.model // empty | "subagents.watchdog.children.model\t" + .),
		(.subagents.watchdog.children.overrides // {} | to_entries[] | . as $entry
			| ($entry.value.model // empty | "subagents.watchdog.children.overrides." + $entry.key + ".model\t" + .))
	' "$1"
}

# enabledModels holds bare `provider/id` entries, while a pin may be quoted and
# may carry the `:<level>` thinking suffix pi-subagents appends at runtime.
normalize_pin() {
	local pin="$1"
	pin="${pin#"${pin%%[![:space:]]*}"}"
	pin="${pin%"${pin##*[![:space:]]}"}"
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
	case "$pin" in
	*/*:none | */*:off | */*:minimal | */*:low | */*:medium | */*:high | */*:xhigh | */*:max)
		pin="${pin%:*}"
		;;
	esac
	printf '%s' "$pin"
}

rc=0
checked=0

check_pin() {
	local source="$1" pin
	pin="$(normalize_pin "$2")"
	# No pin means the agent inherits a default model, which needs no entry.
	[[ -n "$pin" ]] || return 0
	checked=$((checked + 1))
	if ! jq -e --arg m "$pin" '.enabledModels | index($m) != null' "$SETTINGS" >/dev/null; then
		echo "  $source pins \"$pin\", absent from enabledModels in $SETTINGS"
		rc=1
	fi
}

for def in "$AGENTS_DIR"/*.md; do
	[[ -e "$def" ]] || continue
	while IFS= read -r pin; do
		check_pin "$(basename "$def")" "$pin"
	done < <(frontmatter_pins "$def")
done

while IFS=$'\t' read -r source pin; do
	[[ -n "$source" ]] || continue
	check_pin "$source" "$pin"
done < <(settings_pins "$SETTINGS")

if [[ "$rc" -eq 0 ]]; then
	echo "check-pi-model-pins: $checked pinned model(s), all present in enabledModels"
fi
exit "$rc"
