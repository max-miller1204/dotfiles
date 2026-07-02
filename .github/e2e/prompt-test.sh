#!/usr/bin/env bash
# PTY test of the real interactive `chezmoi init` promptBoolOnce path (the
# linux-only `headless` question). Two throwaway environments: accept the
# default (headless=false) and answer yes (=true). Needs `expect` and network
# access to clone the repo; run it AFTER the main E2E, never as part of it.
#
# Overridable via env:
#   CHEZMOI_BIN      chezmoi binary (default: chezmoi on PATH)
#   DOTFILES_REPO    repo argument for chezmoi init (default: this repo)
#   DOTFILES_BRANCH  branch to init from (default: main)
#
# Determinism notes (hard-won; violating any of these makes the test flaky):
# - chezmoi's bool prompt is a bubbletea TUI that defers drawing on a 0x0 pty,
#   so stty_init must give the pty a real size before spawn;
# - the question text prints BEFORE the TUI enters raw mode, so sync on the
#   input line's "bool, default false" placeholder (drawn after raw mode is
#   on), never on the question text - input sent early lands in the cooked
#   tty and is re-delivered as \n, which the TUI does not treat as Enter;
# - send the answer and the confirming \r as SEPARATE writes with a pause,
#   or the Enter can win the race against the answer keystroke;
# - TERM is pinned so the TUI renders the same regardless of the host shell.
set -uo pipefail

CHEZMOI_BIN="${CHEZMOI_BIN:-chezmoi}"
DOTFILES_REPO="${DOTFILES_REPO:-max-miller1204/dotfiles}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"

FAILURES=0

run_case() {
    local answer="$1" expected="$2" tmp
    tmp="$(mktemp -d)"
    HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_DATA_HOME="$tmp/.local/share" \
    XDG_CACHE_HOME="$tmp/.cache" expect <<EOF >/dev/null 2>&1
set timeout 180
set stty_init "rows 40 cols 120"
spawn env HOME=$tmp XDG_CONFIG_HOME=$tmp/.config XDG_DATA_HOME=$tmp/.local/share XDG_CACHE_HOME=$tmp/.cache TERM=xterm-256color $CHEZMOI_BIN init $DOTFILES_REPO --branch $DOTFILES_BRANCH
expect {
    -ex {ool, default false} { sleep 1; send "$answer"; sleep 1; send "\r" }
    timeout { exit 2 }
}
expect eof
EOF
    local got
    got="$(grep -E '^\s*headless' "$tmp/.config/chezmoi/chezmoi.toml" 2>/dev/null | tr -d ' ')"
    if [ "$got" = "headless=$expected" ]; then
        echo "PROMPT-TEST PASS: answer '$answer' -> $got"
    else
        echo "PROMPT-TEST FAIL: answer '$answer' -> '$got' (expected headless=$expected)"
        echo "--- config was:"; head -20 "$tmp/.config/chezmoi/chezmoi.toml" 2>/dev/null
        FAILURES=$((FAILURES + 1))
    fi
    rm -rf "$tmp"
}

run_case "" false
run_case "y" true
exit "$FAILURES"
