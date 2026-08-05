#!/usr/bin/env bash
# Structural invariants for pi's subagent configuration in agent/settings.json.
#
#   check-pi-subagent-config.sh <settings-json> [models-store-json]
#
# These are pure-JSON invariants over a plain, non-templated file, so the SAME
# script runs against the source tree in CI's config-syntax job on every PR and
# against the applied ~/.pi tree in the dispatch-only E2E. They previously lived
# inline in verify.sh, which meant a regression could merge freely: the E2E is
# dispatch-only and never runs on a PR.
#
# The optional second argument is pi's generated models store. It only exists on
# a real machine, so the thinking-level check is skipped when it is absent - the
# structural checks above it still run in CI.
#
# Failures are reported on stdout, one per line.
# Exit: 0 = all invariants hold, 1 = violations found, 2 = bad input.
set -uo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	echo "usage: check-pi-subagent-config.sh <settings-json> [models-store-json]" >&2
	exit 2
fi

SETTINGS="$1"
STORE="${2:-}"

if [[ ! -f "$SETTINGS" ]]; then
	echo "check-pi-subagent-config: settings file not found: $SETTINGS" >&2
	exit 2
fi
if ! jq empty "$SETTINGS" 2>/dev/null; then
	echo "check-pi-subagent-config: settings file is not valid JSON: $SETTINGS" >&2
	exit 2
fi

# The builtin roster the fork ships. A builtin missing a tier override silently
# falls back to subagents.defaultModel instead of the tier it was assigned.
BUILTINS='["advisor","context-builder","delegate","oracle","planner","researcher","reviewer","scout","worker"]'

rc=0
fail() {
	echo "  $1"
	rc=1
}

check() {
	local label="$1" filter="$2"
	jq -e "$filter" "$SETTINGS" >/dev/null 2>&1 || fail "$label"
}

check "packages must declare npm:pi-subagents (the nicobailon fork)" \
	'.packages | index("npm:pi-subagents") != null'
check "packages must NOT declare the superseded npm:@tintinweb/pi-subagents" \
	'.packages | index("npm:@tintinweb/pi-subagents") == null'

# Anthropic models bill the API rather than a subscription. Checking every
# string in the document catches a pin, an enabledModels entry, and a modelScope
# glob alike, including keys added after this script was written.
check "no Anthropic model may be named anywhere in pi settings" \
	'[.. | strings | select(test("anthropic"; "i"))] | length == 0'

check "every builtin subagent must carry a capability-tier model override" \
	"([.subagents.agentOverrides // {} | to_entries[] | select(.value.model != null) | .key] | sort) == ($BUILTINS | sort)"

check "watchdog must be enabled with both a model and a thinking level" \
	'.subagents.watchdog.enabled == true
		and (.subagents.watchdog.main.model | type) == "string"
		and (.subagents.watchdog.main.thinking | type) == "string"'

# The watchdog reviews what the session just wrote, so sharing defaultProvider
# would give it the same blind spots as the code's author.
check "watchdog must review from a provider other than defaultProvider" \
	'. as $s | $s.subagents.watchdog.main.model | startswith($s.defaultProvider + "/") | not'

# modelScope is the mechanism that rejects a model reached through a per-run
# override or a fuzzy id match, so an empty allow list would silently disarm it.
check "modelScope must be enforced with a non-empty allow list" \
	'.subagents.modelScope.enforce == true
		and (.subagents.modelScope.allow | type) == "array"
		and (.subagents.modelScope.allow | length) > 0'

# Thinking levels are validated against the provider catalog because a level the
# model does not support resolves to nothing and the agent silently runs with
# thinking OFF. This mirrors getSupportedThinkingLevels in the fork's
# src/shared/model-info.ts: an explicit null means unsupported, a missing map
# means every level except max, and xhigh/max need an explicit mapping.
if [[ -n "$STORE" ]]; then
	if [[ ! -f "$STORE" ]]; then
		echo "check-pi-subagent-config: models store not found: $STORE" >&2
		exit 2
	fi
	while IFS=$'\t' read -r source model level; do
		[[ -n "$model" && -n "$level" ]] || continue
		provider="${model%%/*}"
		id="${model#*/}"
		supported="$(jq -r --arg p "$provider" --arg i "$id" --arg l "$level" '
			(.[$p].models // [])[] | select(.id == $i)
			| if .reasoning == false then ($l == "off")
			  elif (.thinkingLevelMap == null) then ($l != "max")
			  elif (.thinkingLevelMap | has($l) | not) then ($l != "xhigh" and $l != "max")
			  elif (.thinkingLevelMap[$l] == null) then false
			  else true end
		' "$STORE" 2>/dev/null | head -1)"
		if [[ -z "$supported" ]]; then
			# Model absent from the catalog is check-pi-model-pins.sh's job.
			continue
		fi
		if [[ "$supported" != "true" ]]; then
			fail "$source pins thinking \"$level\" on \"$model\", which does not support it (it would run with thinking OFF)"
		fi
	done < <(jq -r '
		(.subagents.watchdog.main // {} | select(.model != null and .thinking != null)
			| "subagents.watchdog.main\t" + .model + "\t" + .thinking),
		(.subagents.agentOverrides // {} | to_entries[] | select(.value.model != null and .value.thinking != null)
			| "subagents.agentOverrides." + .key + "\t" + .value.model + "\t" + .value.thinking)
	' "$SETTINGS")
fi

if [[ "$rc" -eq 0 ]]; then
	echo "check-pi-subagent-config: pi subagent configuration invariants hold"
fi
exit "$rc"
