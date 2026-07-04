#!/usr/bin/env bash
# fzf agent switcher for tmux: fuzzy-jump across every window in every session
# with a live preview of each pane. Bound to `prefix f` (see tmux.conf).
set -euo pipefail

# Resolve fzf: PATH first (mise shims when a shell is active), then the mise
# install location (display-popup can run with a sanitized PATH), else a
# visible error rather than a silent no-op.
fzf_bin="$(command -v fzf || true)"
if [ -z "$fzf_bin" ] && [ -x "$HOME/.local/share/mise/installs/fzf/latest/fzf" ]; then
  fzf_bin="$HOME/.local/share/mise/installs/fzf/latest/fzf"
fi
if [ -z "$fzf_bin" ]; then
  printf 'agent-switch: fzf not found (PATH or mise). Press any key.'; read -r -n 1 -s _; exit 1
fi

# Field 1 = stable pane_id (%N, hidden from the list); fields 2+ = display.
fmt=$'#{pane_id}\t#S  #I  #{window_name}  #T'
if ! list="$(tmux list-windows -a -F "$fmt")"; then
  printf 'agent-switch: tmux list-windows failed. Press any key.'; read -r -n 1 -s _; exit 1
fi

# Capture fzf's exit without set -e aborting the script.
if sel="$(printf '%s\n' "$list" | "$fzf_bin" --reverse --with-nth='2..' --delimiter=$'\t' \
            --preview 'tmux capture-pane -ep -t {1}' --preview-window=right:60%)"; then
  rc=0
else
  rc=$?
fi
[ "$rc" -eq 130 ] && exit 0                      # 130 = Esc/Ctrl-C: benign cancel
if [ "$rc" -ne 0 ]; then printf 'agent-switch: fzf failed (rc=%s). Press any key.' "$rc"; read -r -n 1 -s _; exit "$rc"; fi
[ -z "${sel:-}" ] && exit 0

pid="$(printf '%s' "$sel" | cut -f1)"
# switch-client -t accepts a pane target (contains %): changes session+window+pane
# atomically, no separate select-window, no wrong-window flash.
tmux switch-client -t "$pid"
