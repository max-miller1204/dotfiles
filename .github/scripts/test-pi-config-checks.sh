#!/usr/bin/env bash
# Regression coverage for the two pi configuration guards, check-pi-model-pins.sh
# and check-pi-subagent-config.sh.
#
#   test-pi-config-checks.sh
#
# Both are now non-trivial: a jq reimplementation of the fork's globToRegExp, a
# thinking-level precedence chain mirroring resolveEffectiveThinking and
# applySubagentDefaultThinking, and type-not-null selection over values the fork
# lets be a literal `false`. A guard that silently stops catching a violation is
# invisible, because the only signal is the same "invariants hold" line a working
# guard prints, so every invariant gets a fixture that violates exactly it.
#
# Each case INVOKES the real checker against a mutated copy of the committed
# configuration and asserts the observable result: the exit status and the
# finding on stdout. Nothing here inspects the checkers' source.
#
# The thinking cases need a models store, which is machine state the checkers
# take as an optional argument, so this file ships a fixture one. It is a
# fixture for the STORE FORMAT pi generates - `{provider: {models: [{id,
# reasoning, thinkingLevelMap}]}}` - carrying only the map shapes the cases
# need; the real catalog is what the E2E validates the committed pins against.
#
# Exit: 0 = every case behaved as specified, 1 = at least one did not.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO_ROOT/.github/scripts"
PINS="$SCRIPTS/check-pi-model-pins.sh"
CONFIG="$SCRIPTS/check-pi-subagent-config.sh"
SETTINGS="$REPO_ROOT/dot_pi/agent/settings.json"
AGENTS="$REPO_ROOT/dot_pi/agent/agents"

for required in "$PINS" "$CONFIG" "$SETTINGS"; do
	if [[ ! -e "$required" ]]; then
		echo "test-pi-config-checks: missing input: $required" >&2
		exit 2
	fi
done
if ! command -v jq >/dev/null 2>&1; then
	echo "test-pi-config-checks: jq is required" >&2
	exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Mirrors the thinkingLevelMap shapes pi writes for these models, which are the
# four cases getSupportedThinkingLevels distinguishes: every level mapped to
# null except max (kimi-k3), a map that only overrides some levels so an absent
# key stays supported (gpt-5.6-*), and no map at all (minimax-m3).
cat >"$WORK/store.json" <<'JSON'
{
  "opencode-go": {
    "models": [
      {
        "id": "kimi-k3",
        "reasoning": true,
        "thinkingLevelMap": {
          "off": null, "minimal": null, "low": null, "medium": null,
          "high": null, "xhigh": null, "max": "max"
        }
      },
      { "id": "minimax-m3", "reasoning": true },
      { "id": "deepseek-v4-flash", "reasoning": true }
    ]
  },
  "openai-codex": {
    "models": [
      {
        "id": "gpt-5.6-sol",
        "reasoning": true,
        "thinkingLevelMap": { "xhigh": "xhigh", "max": "max", "minimal": "low" }
      },
      {
        "id": "gpt-5.6-terra",
        "reasoning": true,
        "thinkingLevelMap": { "xhigh": "xhigh", "max": "max", "minimal": "low" }
      },
      {
        "id": "gpt-5.6-luna",
        "reasoning": true,
        "thinkingLevelMap": { "xhigh": "xhigh", "max": "max", "minimal": "low" }
      }
    ]
  }
}
JSON

PASS=0
FAIL=0

# Both helpers run inside `$( )`, so a shared counter would increment in a
# subshell and never reach here: every fixture would reuse one path, and a case
# needing two of them would silently hand the checker the same file twice.
# mktemp keeps them distinct and names the fixture a failing case used.

# settings_from '<jq filter>' -> path to a mutated copy of the committed settings
settings_from() {
	local out
	out="$(mktemp "$WORK/settings-XXXXXX.json")"
	jq "$1" "$SETTINGS" >"$out" || return 1
	printf '%s' "$out"
}

# agents_from '<frontmatter body>' -> path to an agents dir holding one definition
agents_from() {
	local dir
	dir="$(mktemp -d "$WORK/agents-XXXXXX")"
	printf '%s\n' "$1" >"$dir/fixture.md"
	printf '%s' "$dir"
}

# expect <label> <want-rc> <want-substring-or-empty> -- <command...>
expect() {
	local label="$1" want_rc="$2" want_out="$3"
	shift 4
	local out rc
	out="$("$@" 2>&1)"
	rc=$?
	if [[ "$rc" != "$want_rc" ]]; then
		echo "FAIL: $label"
		echo "      expected exit $want_rc, got $rc"
		echo "$out" | sed 's/^/      /'
		FAIL=$((FAIL + 1))
		return
	fi
	if [[ -n "$want_out" && "$out" != *"$want_out"* ]]; then
		echo "FAIL: $label"
		echo "      expected output to mention: $want_out"
		echo "$out" | sed 's/^/      /'
		FAIL=$((FAIL + 1))
		return
	fi
	echo "PASS: $label"
	PASS=$((PASS + 1))
}

pins() { bash "$PINS" "$1" "$2" "$WORK/store.json"; }
pins_no_store() { bash "$PINS" "$1" "$2"; }
config() { bash "$CONFIG" "$1"; }

echo "== the committed configuration passes =="
expect "committed settings satisfy every structural invariant" 0 "invariants hold" \
	-- config "$SETTINGS"
expect "committed pins resolve, with thinking checked" 0 "thinking level(s) supported" \
	-- pins "$AGENTS" "$SETTINGS"
expect "committed pins resolve in CI mode, with no models store" 0 "all present in enabledModels" \
	-- pins_no_store "$AGENTS" "$SETTINGS"

echo "== modelScope must not readmit the banned provider =="
expect "a bare * allow pattern reopens the Anthropic ban" 1 "may match an Anthropic model" \
	-- config "$(settings_from '.subagents.modelScope.allow = ["*"]')"
expect "a cross-provider */claude-* pattern reopens it" 1 "may match an Anthropic model" \
	-- config "$(settings_from '.subagents.modelScope.allow = ["openai-codex/*", "*/claude-*"]')"
expect "an empty allow list disarms enforcement" 1 "non-empty allow list" \
	-- config "$(settings_from '.subagents.modelScope.allow = []')"
expect "enforcement turned off" 1 "non-empty allow list" \
	-- config "$(settings_from '.subagents.modelScope.enforce = false')"

echo "== the Anthropic ban itself =="
expect "an Anthropic model named anywhere in settings" 1 "no Anthropic model" \
	-- config "$(settings_from '.enabledModels += ["anthropic/claude-opus-5"]')"

echo "== the package the fork switch is about =="
expect "the fork package dropped from packages" 1 "must declare npm:pi-subagents" \
	-- config "$(settings_from '.packages -= ["npm:pi-subagents"]')"
expect "the superseded @tintinweb package reintroduced" 1 "superseded npm:@tintinweb/pi-subagents" \
	-- config "$(settings_from '.packages += ["npm:@tintinweb/pi-subagents"]')"

echo "== builtin tier coverage =="
expect "a builtin left without a tier override" 1 "capability-tier model override" \
	-- config "$(settings_from 'del(.subagents.agentOverrides.oracle)')"
expect "a typo in a builtin key" 1 "capability-tier model override" \
	-- config "$(settings_from '.subagents.agentOverrides.reviewr = .subagents.agentOverrides.reviewer | del(.subagents.agentOverrides.reviewer)')"
expect "an override whose model is cleared with false" 1 "capability-tier model override" \
	-- config "$(settings_from '.subagents.agentOverrides.scout.model = false')"
expect "an override that leaves its thinking level to upstream" 1 "declare its own thinking level" \
	-- config "$(settings_from 'del(.subagents.agentOverrides.scout.thinking)')"

echo "== watchdog presence and independence =="
expect "a watchdog turned off" 1 "enabled with both a model and a thinking level" \
	-- config "$(settings_from '.subagents.watchdog.enabled = false')"
expect "a watchdog with no thinking level" 1 "enabled with both a model and a thinking level" \
	-- config "$(settings_from 'del(.subagents.watchdog.main.thinking)')"
expect "a watchdog with no model" 1 "enabled with both a model and a thinking level" \
	-- config "$(settings_from 'del(.subagents.watchdog.main.model)')"
expect "a watchdog sharing defaultProvider with the session" 1 "review from another provider" \
	-- config "$(settings_from '.subagents.watchdog.main.model = "openai-codex/gpt-5.6-sol"')"
expect "a missing defaultProvider makes the comparison vacuous" 1 "defaultProvider must be set" \
	-- config "$(settings_from 'del(.defaultProvider)')"

echo "== thinking levels a model does not support =="
expect "a primary pin at an unsupported level" 1 "would run with thinking OFF" \
	-- pins "$AGENTS" "$(settings_from '.subagents.watchdog.main.thinking = "high"')"
expect "a level carried as a :<level> suffix on the model" 1 "would run with thinking OFF" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.model = "opencode-go/kimi-k3:high"')"
expect "a fallback inheriting the entry's own level" 1 "would run with thinking OFF" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.fallbackModels = ["opencode-go/kimi-k3"]')"
expect "defaultThinking reaching an override that declares no level" 1 "would run with thinking OFF" \
	-- pins "$AGENTS" "$(settings_from '.subagents.defaultThinking = "high"
		| .subagents.agentOverrides.scout = {"model": "opencode-go/kimi-k3"}')"
expect "defaultThinking reaching defaultModel" 1 "would run with thinking OFF" \
	-- pins "$AGENTS" "$(settings_from '.subagents.defaultModel = "opencode-go/kimi-k3"
		| .subagents.defaultThinking = "high"')"
expect "a definition file's level reaching its fallback" 1 "would run with thinking OFF" \
	-- pins "$(agents_from '---
name: fixture
description: d
model: opencode-go/minimax-m3
thinking: high
fallbackModels: opencode-go/kimi-k3
---
body')" "$SETTINGS"
expect "a definition file inheriting defaultThinking" 1 "would run with thinking OFF" \
	-- pins "$(agents_from '---
name: fixture
description: d
model: opencode-go/kimi-k3
---
body')" "$(settings_from '.subagents.defaultThinking = "high"')"
expect "a definition file that pins a level but no model" 1 "would run with thinking OFF" \
	-- pins "$(agents_from '---
name: fixture
description: d
thinking: high
---
body')" "$(settings_from '.subagents.defaultModel = "opencode-go/kimi-k3"')"

echo "== an override on an agent that ships a definition file =="
# applyCustomAgentOverride fills only the fields the file leaves out, so the
# override's level lands on the FILE's model, not on subagents.defaultModel.
expect "an override level landing on the definition file's own model" 1 "would run with thinking OFF" \
	-- pins "$(agents_from '---
name: fixture
description: d
model: opencode-go/minimax-m3
---
body')" "$(settings_from '.subagents.agentOverrides.fixture = {"thinking": "max"}')"
expect "an override fallback landing on the definition file's own level" 1 "would run with thinking OFF" \
	-- pins "$(agents_from '---
name: fixture
description: d
model: openai-codex/gpt-5.6-terra
thinking: medium
---
body')" "$(settings_from '.subagents.agentOverrides.fixture = {"fallbackModels": ["opencode-go/kimi-k3"]}')"
# The file already declares the field, so the override never reaches the agent
# and must not be resolved against anything.
expect "an override the definition file overrides back is inert" 0 "" \
	-- pins "$(agents_from '---
name: fixture
description: d
model: openai-codex/gpt-5.6-terra
thinking: medium
---
body')" "$(settings_from '.subagents.defaultModel = "opencode-go/kimi-k3"
		| .subagents.agentOverrides.fixture = {"thinking": "high"}')"

echo "== levels the fork treats as no level at all =="
expect "thinking cleared with false is not a level to resolve" 0 "" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.model = "opencode-go/kimi-k3"
		| .subagents.agentOverrides.worker.thinking = false
		| .enabledModels += ["opencode-go/kimi-k3"]')"
expect "an explicit suffix wins over an unsupported sibling key" 0 "" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.model = "opencode-go/kimi-k3:max"
		| .subagents.agentOverrides.worker.thinking = "high"
		| .enabledModels += ["opencode-go/kimi-k3"]')"

echo "== enabledModels remains the curated allowlist =="
expect "a pin outside enabledModels" 1 "absent from enabledModels" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.model = "opencode-go/not-a-real-model"')"
expect "a fallback outside enabledModels" 1 "absent from enabledModels" \
	-- pins "$AGENTS" "$(settings_from '.subagents.agentOverrides.worker.fallbackModels = ["opencode-go/not-a-real-model"]')"

echo "== bad input is reported, never mistaken for a pass =="
printf 'not json' >"$WORK/malformed.json"
expect "a malformed settings file fails the config checker" 2 "not valid JSON" \
	-- config "$WORK/malformed.json"
expect "a malformed settings file fails the pin checker" 2 "not valid JSON" \
	-- pins "$AGENTS" "$WORK/malformed.json"
expect "a missing models store is bad input, not a silent skip" 2 "models store not found" \
	-- bash "$PINS" "$AGENTS" "$SETTINGS" "$WORK/absent-store.json"

echo
if [[ "$FAIL" -eq 0 ]]; then
	echo "test-pi-config-checks: $PASS case(s) passed"
	exit 0
fi
echo "test-pi-config-checks: $FAIL of $((PASS + FAIL)) case(s) failed"
exit 1
