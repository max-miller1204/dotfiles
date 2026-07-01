# Shared file-prep preamble for the two Codex config-sync scripts
# (run_onchange_after_41-sync-codex-mcp, run_onchange_after_42-sync-codex-base).
# Both read a staging source and rewrite ~/.codex/config.toml via an awk strip
# into a .tmp, then recombine and mv. Only this preamble dedups cleanly: the awk
# programs and the recombine differ (41 strips [mcp_servers.*] and APPENDS the
# staging TOML at the end; 42 strips a marker block + stray top-level keys and
# PREPENDS a fresh marker block at the top), and their blank-line-separator
# idioms differ with them, so each script keeps its own awk + recombine.
# Deliberately no log()/lib-log.sh dependency: these scripts keep a bare
# `set -euo pipefail` and use `echo` (see AGENTS.md / repo notes).
#
# Caller contract: the including script must have run `set -euo pipefail` and
# defined STAGING_SOURCE (the staging file to read) before this include. This
# defines CODEX_CONFIG, verifies STAGING_SOURCE is readable, and ensures the
# target's parent dir and an empty target file exist. (mkdir/touch run before
# any script-specific input validation; the only reachable effect is that a
# fresh empty ~/.codex/config.toml is created, which is benign and idempotent.)
CODEX_CONFIG="${HOME}/.codex/config.toml"

[ -r "$STAGING_SOURCE" ] || { echo "staging file missing: $STAGING_SOURCE" >&2; exit 1; }

mkdir -p "$(dirname "$CODEX_CONFIG")"
[ -f "$CODEX_CONFIG" ] || : > "$CODEX_CONFIG"