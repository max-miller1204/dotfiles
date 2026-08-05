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
#   check-pi-model-pins.sh <agents-dir> <settings-json> [models-store-json]
#
# The first two inputs are plain (non-templated) files, so this runs against the
# source tree in CI and against the applied ~/.pi tree in the native E2E.
#
# The optional third input is pi's generated models store, which only exists on
# a real machine. Given it, every pinned THINKING level is additionally checked
# against what its model actually supports, because a level the model does not
# support resolves to nothing and the agent silently runs with thinking OFF.
# Thinking lives beside the model in both frontmatter and settings, so it is
# validated here rather than in a second script that would have to re-parse the
# same frontmatter.
#
# Offenders are reported on stdout, one per line.
# Exit: 0 = all pins valid, 1 = offenders found, 2 = bad input.
set -uo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
	echo "usage: check-pi-model-pins.sh <agents-dir> <settings-json> [models-store-json]" >&2
	exit 2
fi

AGENTS_DIR="$1"
SETTINGS="$2"
STORE="${3:-}"

if [[ -n "$STORE" && ! -f "$STORE" ]]; then
	echo "check-pi-model-pins: models store not found: $STORE" >&2
	exit 2
fi

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
		BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34) }
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
			# Unquote the COMPLETE scalar before splitting. YAML permits quoting
			# the whole comma-separated list, and splitting first would leave one
			# unmatched quote on the first and last fragment.
			q = substr(value, 1, 1)
			if (length(value) >= 2 && (q == DQ || q == SQ) && substr(value, length(value), 1) == q) {
				value = substr(value, 2, length(value) - 2)
			}
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

# Emit `<model>\t<thinking>` for an agent definition that pins both. A thinking
# level with no model pin inherits the model, whose support cannot be resolved
# from this file alone, so those are left to the settings-level default.
frontmatter_model_thinking() {
	awk '
		NR == 1 && $0 == "---" { in_fm = 1; next }
		in_fm && $0 == "---" { exit }
		!in_fm { next }
		/^model:[[:space:]]*/ { v = $0; sub(/^model:[[:space:]]*/, "", v); model = v; next }
		/^thinking:[[:space:]]*/ { v = $0; sub(/^thinking:[[:space:]]*/, "", v); think = v; next }
		END { if (model != "" && think != "") print model "\t" think }
	' "$1"
}

# Mirrors getSupportedThinkingLevels in the fork's src/shared/model-info.ts: an
# explicit null means unsupported, an ABSENT key means supported (it is
# undefined, not null), a missing map means every level except max, and
# xhigh/max require an explicit mapping.
thinking_supported() {
	local model="$1" level="$2" provider id
	provider="${model%%/*}"
	id="${model#*/}"
	jq -r --arg p "$provider" --arg i "$id" --arg l "$level" '
		(.[$p].models // [])[] | select(.id == $i)
		| if .reasoning == false then ($l == "off")
		  elif (.thinkingLevelMap == null) then ($l != "max")
		  elif (.thinkingLevelMap | has($l) | not) then ($l != "xhigh" and $l != "max")
		  elif (.thinkingLevelMap[$l] == null) then false
		  else true end
	' "$STORE" 2>/dev/null | head -1
}

rc=0
checked=0
thinking_checked=0

check_thinking() {
	local source="$1" model level supported
	model="$(normalize_pin "$2")"
	level="$(normalize_pin "$3")"
	[[ -n "$STORE" && -n "$model" && -n "$level" ]] || return 0
	# A bare `thinking: false` is the documented opt-out, not a level.
	[[ "$level" != "false" ]] || return 0
	supported="$(thinking_supported "$model" "$level")"
	# An unknown model is check_pin's finding, not this one's.
	[[ -n "$supported" ]] || return 0
	thinking_checked=$((thinking_checked + 1))
	if [[ "$supported" != "true" ]]; then
		echo "  $source pins thinking \"$level\" on \"$model\", which does not support it (it would run with thinking OFF)"
		rc=1
	fi
}

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

# Capture each extractor's output AND status before iterating. Reading straight
# from a process substitution discards the extractor's exit code, so a malformed
# agent file or a settings file whose subagents block has an unexpected shape
# would emit nothing and let the loop report that every pin passed.
for def in "$AGENTS_DIR"/*.md; do
	[[ -e "$def" ]] || continue
	if ! fm_pins="$(frontmatter_pins "$def")"; then
		echo "check-pi-model-pins: could not read frontmatter pins from $def" >&2
		exit 2
	fi
	while IFS= read -r pin; do
		check_pin "$(basename "$def")" "$pin"
	done <<<"$fm_pins"
	if ! fm_thinking="$(frontmatter_model_thinking "$def")"; then
		echo "check-pi-model-pins: could not read frontmatter thinking from $def" >&2
		exit 2
	fi
	while IFS=$'\t' read -r fm_model fm_level; do
		[[ -n "$fm_model" ]] || continue
		check_thinking "$(basename "$def")" "$fm_model" "$fm_level"
	done <<<"$fm_thinking"
done

if ! settings_pin_rows="$(settings_pins "$SETTINGS")"; then
	echo "check-pi-model-pins: could not read settings pins from $SETTINGS" >&2
	exit 2
fi
while IFS=$'\t' read -r source pin; do
	[[ -n "$source" ]] || continue
	check_pin "$source" "$pin"
done <<<"$settings_pin_rows"

if ! settings_thinking_rows="$(jq -r '
	(.subagents.watchdog.main // {} | select(.model != null and .thinking != null)
		| "subagents.watchdog.main\t" + .model + "\t" + .thinking),
	(.subagents.watchdog.children // {} | select(.model != null and .thinking != null)
		| "subagents.watchdog.children\t" + .model + "\t" + .thinking),
	(.subagents.agentOverrides // {} | to_entries[] | select(.value.model != null and .value.thinking != null)
		| "subagents.agentOverrides." + .key + "\t" + .value.model + "\t" + .value.thinking)
' "$SETTINGS")"; then
	echo "check-pi-model-pins: could not read settings thinking levels from $SETTINGS" >&2
	exit 2
fi
while IFS=$'\t' read -r source s_model s_level; do
	[[ -n "$source" ]] || continue
	check_thinking "$source" "$s_model" "$s_level"
done <<<"$settings_thinking_rows"

if [[ "$rc" -eq 0 ]]; then
	if [[ -n "$STORE" ]]; then
		echo "check-pi-model-pins: $checked pinned model(s) in enabledModels, $thinking_checked thinking level(s) supported by their model"
	else
		echo "check-pi-model-pins: $checked pinned model(s), all present in enabledModels"
	fi
fi
exit "$rc"
