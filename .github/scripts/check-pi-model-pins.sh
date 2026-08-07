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
# a real machine and only once a configured provider has refreshed its catalog.
# Given it, every pinned THINKING level is additionally checked against what its
# model actually supports, because a level the model does not support resolves
# to nothing and the agent silently runs with thinking OFF. A level counts
# whether it is written as a `thinking:` key or as a `:<level>` suffix on the
# model, and the suffix wins where both appear, as resolveEffectiveThinking
# resolves it. A sibling key is checked against EVERY model it reaches - the
# primary pin, each fallback, and `defaultModel` for `defaultThinking` - because
# the fork appends it to whichever candidate it ends up launching.
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

# Every pin is enumerated as `<model>\t<sibling-level>`, because a model and the
# thinking level that will be applied to it are only meaningful together. The
# sibling level reaches EVERY candidate, not just the primary: buildModelCandidates
# builds `[model, ...fallbackModels]` and each candidate is mapped through
# applyThinkingSuffix, which appends `:<level>` to any candidate that does not
# already carry one. Enumerating models and levels separately is what let a
# fallback inherit an unsupported level unchecked.

# Read pins from the leading `---` frontmatter block ONLY, so a prompt-body line
# that happens to start with `model:` is never mistaken for a pin. Both the
# inline comma-separated and the `- item` block form of `fallbackModels:` are
# emitted, one model per line, each paired with the file's `thinking:` key.
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
			if (value != "") pins[++n] = value
			next
		}
		/^thinking:[[:space:]]*/ {
			value = $0
			sub(/^thinking:[[:space:]]*/, "", value)
			think = value
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
			for (i = 1; i <= count; i++) pins[++n] = parts[i]
			next
		}
		list != "" && /^[[:space:]]+-[[:space:]]*/ {
			value = $0
			sub(/^[[:space:]]+-[[:space:]]*/, "", value)
			if (value != "") pins[++n] = value
			next
		}
		# The `thinking:` key may follow the pins it applies to, so pair at the end.
		END { for (i = 1; i <= n; i++) print pins[i] "\t" think }
	' "$1"
}

# Emit `<source>\t<model>\t<sibling-level>` for every model pinned in settings.
# Select by TYPE: the fork accepts a literal `false` for a model, a fallback list
# and a thinking level alike, and a `false` clears the value rather than setting
# one, so a null check would hand a boolean to the string concatenation below.
settings_pins() {
	jq -r '
		def level($v): if ($v | type) == "string" then $v else "" end;
		def row($source; $model; $thinking):
			select(($model | type) == "string" and ($model | length) > 0)
			| $source + "\t" + $model + "\t" + level($thinking);
		def fallbacks($v): if ($v | type) == "array" then $v[] else empty end;
		(.subagents // {}) as $s
		| row("subagents.defaultModel"; $s.defaultModel; $s.defaultThinking),
		  ($s.agentOverrides // {} | to_entries[] | . as $entry
			| row("subagents.agentOverrides." + $entry.key + ".model";
				$entry.value.model; $entry.value.thinking),
			  (fallbacks($entry.value.fallbackModels)
				| row("subagents.agentOverrides." + $entry.key + ".fallbackModels";
					.; $entry.value.thinking))),
		  ($s.watchdog.main // {}
			| row("subagents.watchdog.main.model"; .model; .thinking)),
		  ($s.watchdog.children // {}
			| row("subagents.watchdog.children.model"; .model; .thinking)),
		  ($s.watchdog.children.overrides // {} | to_entries[] | . as $entry
			| row("subagents.watchdog.children.overrides." + $entry.key + ".model";
				$entry.value.model; $entry.value.thinking))
	' "$1"
}

# A pin may be quoted in YAML; strip surrounding whitespace and one quote layer.
unquote_pin() {
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
	printf '%s' "$pin"
}

# enabledModels holds bare `provider/id` entries, while a pin may carry the
# `:<level>` thinking suffix pi-subagents appends at runtime. The recognized
# suffixes are exactly the fork's THINKING_LEVELS (src/shared/model-info.ts):
# splitKnownThinkingSuffix leaves anything else as part of the model id, so
# stripping a level the fork does not know would hide a broken pin.
normalize_pin() {
	local pin
	pin="$(unquote_pin "$1")"
	case "$pin" in
	*/*:off | */*:minimal | */*:low | */*:medium | */*:high | */*:xhigh | */*:max)
		pin="${pin%:*}"
		;;
	esac
	printf '%s' "$pin"
}

# The thinking level a pin carries in suffix form, empty when it carries none.
# resolveEffectiveThinking returns this suffix ahead of any sibling `thinking:`
# key, so it - not the key - is the level that actually runs.
pin_thinking_level() {
	local pin
	pin="$(unquote_pin "$1")"
	case "$pin" in
	*/*:off | */*:minimal | */*:low | */*:medium | */*:high | */*:xhigh | */*:max)
		printf '%s' "${pin##*:}"
		;;
	esac
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
	local source="$1" model level suffix supported
	model="$(normalize_pin "$2")"
	level="$(normalize_pin "$3")"
	suffix="$(pin_thinking_level "$2")"
	# Mirror resolveEffectiveThinking: a `:<level>` suffix on the model wins over
	# whatever a sibling key says, so validate the level that really runs.
	[[ -z "$suffix" ]] || level="$suffix"
	[[ -n "$STORE" && -n "$model" && -n "$level" ]] || return 0
	# `false` is the documented opt-out and `inherit` defers to the session, so
	# neither is a level to resolve against the model.
	[[ "$level" != "false" && "$level" != "inherit" ]] || return 0
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
	check_thinking "$source" "$2" "$3"
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
	while IFS=$'\t' read -r pin level; do
		[[ -n "$pin" ]] || continue
		check_pin "$(basename "$def")" "$pin" "$level"
	done <<<"$fm_pins"
done

if ! settings_pin_rows="$(settings_pins "$SETTINGS")"; then
	echo "check-pi-model-pins: could not read settings pins from $SETTINGS" >&2
	exit 2
fi
while IFS=$'\t' read -r source pin level; do
	[[ -n "$source" ]] || continue
	check_pin "$source" "$pin" "$level"
done <<<"$settings_pin_rows"

if [[ "$rc" -eq 0 ]]; then
	if [[ -n "$STORE" && "$thinking_checked" -eq 0 ]]; then
		# A store pi wrote without provider credentials holds no catalog, so every
		# pinned model is unknown to it and every level goes unresolved. Say so
		# rather than reporting a pass for a check that examined nothing.
		echo "check-pi-model-pins: $checked pinned model(s) in enabledModels; NO thinking level could be resolved against $STORE, so thinking support went unchecked"
	elif [[ -n "$STORE" ]]; then
		echo "check-pi-model-pins: $checked pinned model(s) in enabledModels, $thinking_checked thinking level(s) supported by their model"
	else
		echo "check-pi-model-pins: $checked pinned model(s), all present in enabledModels"
	fi
fi
exit "$rc"
