#!/usr/bin/env bash
# Structural invariants for pi's subagent configuration in agent/settings.json.
#
#   check-pi-subagent-config.sh <settings-json>
#
# These are pure-JSON invariants over a plain, non-templated file, so the SAME
# script runs against the source tree in CI's config-syntax job on every PR and
# against the applied ~/.pi tree in the dispatch-only E2E. They previously lived
# inline in verify.sh, which meant a regression could merge freely: the E2E is
# dispatch-only and never runs on a PR.
#
# Thinking-level validity is NOT checked here: a thinking level is meaningful
# only next to its model, and both live in agent frontmatter as well as settings,
# so check-pi-model-pins.sh owns that check rather than re-parsing frontmatter.
#
# Failures are reported on stdout, one per line.
# Exit: 0 = all invariants hold, 1 = violations found, 2 = bad input.
set -uo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: check-pi-subagent-config.sh <settings-json>" >&2
	exit 2
fi

SETTINGS="$1"

if [[ ! -f "$SETTINGS" ]]; then
	echo "check-pi-subagent-config: settings file not found: $SETTINGS" >&2
	exit 2
fi
if ! jq empty "$SETTINGS" 2>/dev/null; then
	echo "check-pi-subagent-config: settings file is not valid JSON: $SETTINGS" >&2
	exit 2
fi

# The builtin roster the fork ships, one name per definition file in its agents/
# directory. A builtin missing a tier override silently falls back to
# subagents.defaultModel instead of the tier it was assigned. `advisor` is NOT a
# member: it is an alias on oracle.md, and both override appliers key off
# agent.name, so an override under that key would never match anything.
BUILTINS='["context-builder","delegate","oracle","planner","researcher","reviewer","scout","worker"]'

# Every string-valued invariant below asserts a USABLE value, not mere presence.
# The fork accepts a literal `false` wherever it accepts a model or a thinking
# level, and `false` DELETES the inherited value instead of setting one, so a
# non-null test reports an invariant as met by a config that unsets the very
# field the invariant is about; an absent key and an empty string read the same
# way. One predicate, applied everywhere, keeps that from being re-decided.
JQ_PRELUDE='def usable: type == "string" and length > 0;
	# Mirrors globToRegExp in the fork: every RegExp special except `*` is
	# escaped, `*` becomes `.*`, the result is anchored, and matching is
	# case-insensitive against the full provider/id.
	def scope_regex: "^" + (gsub("(?<c>[.+^${}()|\\[\\]\\\\])"; "\\" + .c) | gsub("\\*"; ".*")) + "$";
	def banned_models: ["anthropic/claude-opus-5", "anthropic/claude-sonnet-5", "anthropic/claude-haiku-4-5-20251001"];
	def matches_banned: scope_regex as $re | any(banned_models[]; test($re; "i"));'

rc=0
fail() {
	echo "  $1"
	rc=1
}

check() {
	local label="$1" filter="$2"
	jq -e "$JQ_PRELUDE $filter" "$SETTINGS" >/dev/null 2>&1 || fail "$label"
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
	"([.subagents.agentOverrides // {} | to_entries[] | select(.value.model | usable) | .key] | sort) == ($BUILTINS | sort)"

# An override that omits `thinking` inherits the level from the builtin's own
# upstream definition, falling back to subagents.defaultThinking - neither of
# which this repo can see, so the level that would actually run is unverifiable
# and check-pi-model-pins.sh cannot resolve it against the model. Declaring the
# key (a level, or `false` for none) keeps the pairing local and checkable.
check "every builtin subagent override must declare its own thinking level" \
	'all(.subagents.agentOverrides // {} | .[];
		type == "object" and ((.thinking | usable) or .thinking == false))'

check "watchdog must be enabled with both a model and a thinking level" \
	'.subagents.watchdog.enabled == true
		and (.subagents.watchdog.main.model | usable)
		and (.subagents.watchdog.main.thinking | usable)'

# The watchdog reviews what the session just wrote, so sharing defaultProvider
# would give it the same blind spots as the code's author. defaultProvider must
# itself be set: jq reads a missing one as null, `null + "/"` is "/", and no
# model id starts with that, so the comparison would pass without comparing.
check "defaultProvider must be set and the watchdog must review from another provider" \
	'. as $s | ($s.defaultProvider | usable)
		and ($s.subagents.watchdog.main.model | startswith($s.defaultProvider + "/") | not)'

# modelScope is the mechanism that rejects a model reached through a per-run
# override or a fuzzy id match, so an empty allow list would silently disarm it.
check "modelScope must be enforced with a non-empty allow list" \
	'.subagents.modelScope.enforce == true
		and (.subagents.modelScope.allow | type) == "array"
		and (.subagents.modelScope.allow | length) > 0
		and all(.subagents.modelScope.allow[]; usable)'

# An allow list disarms the Anthropic ban just as thoroughly by being too broad
# as by being empty: `*` admits every provider. The sibling scan above cannot see
# it, because the banned name never appears in the file - it arrives at runtime -
# so the patterns are matched against Anthropic ids the way the fork would.
check "no modelScope allow pattern may match an Anthropic model" \
	'all(.subagents.modelScope.allow[]; matches_banned | not)'

if [[ "$rc" -eq 0 ]]; then
	echo "check-pi-subagent-config: pi subagent configuration invariants hold"
fi
exit "$rc"
