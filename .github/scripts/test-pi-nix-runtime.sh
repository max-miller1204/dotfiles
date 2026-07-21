#!/usr/bin/env bash
# Prove the Nix-owned Pi can load the managed local extensions without a model call.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pi_bin="${1:-}"
if [[ -z "$pi_bin" || ! -x "$pi_bin" ]]; then
    echo "usage: test-pi-nix-runtime.sh /path/to/pi" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/agent/extensions"
cp -R "$repo_root/dot_pi/agent/extensions/." "$tmp/agent/extensions/"
printf '%s\n' '{"packages":[],"skills":[],"enabledModels":[]}' \
    >"$tmp/agent/settings.json"

printf '%s\n' '{"id":"commands","type":"get_commands"}' \
    | PI_CODING_AGENT_DIR="$tmp/agent" \
        PI_WORKTREE_GUARD_MODE=prompt \
        "$pi_bin" --approve --mode rpc --no-session \
        >"$tmp/rpc.jsonl" 2>"$tmp/stderr"

if [[ -s "$tmp/stderr" ]]; then
    cat "$tmp/stderr" >&2
    exit 1
fi

python3 - "$tmp/rpc.jsonl" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    events = [json.loads(line) for line in path.read_text().splitlines() if line]
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"could not parse Pi RPC output: {error}") from error

extension_errors = [event for event in events if event.get("type") == "extension_error"]
responses = [
    event
    for event in events
    if event.get("type") == "response" and event.get("command") == "get_commands"
]
if extension_errors or len(responses) != 1 or not responses[0].get("success"):
    raise SystemExit(
        f"Pi extension smoke failed: errors={extension_errors!r} responses={responses!r}"
    )

commands = {command["name"] for command in responses[0]["data"]["commands"]}
required = {"handoff", "worktree-guard"}
if not required <= commands:
    raise SystemExit(f"Pi extension smoke is missing commands: {sorted(required - commands)}")
print("Nix Pi loaded managed extensions: " + ", ".join(sorted(required)))
PY
