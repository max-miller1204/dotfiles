#!/usr/bin/env bash
# fzf agent switcher for tmux: fuzzy-jump across every window in every session
# with a live preview of each pane. Bound to `prefix f` (see tmux.conf).
set -euo pipefail

# Resolve fzf through PATH first, then the Home Manager profile for tmux
# display-popup environments that sanitize PATH.
fzf_bin="$(command -v fzf || true)"
if [ -z "$fzf_bin" ] && [ -x "$HOME/.nix-profile/bin/fzf" ]; then
	fzf_bin="$HOME/.nix-profile/bin/fzf"
fi
if [ -z "$fzf_bin" ]; then
	printf 'agent-switch: fzf not found (PATH or Home Manager). Press any key.'
	read -r -n 1 -s _
	exit 1
fi

# Field 1 = stable pane_id (%N, hidden from the list); fields 2+ = display.
fmt=$'#{pane_id}\t#S  #I  #{window_name}  #T'
if ! list="$(tmux list-windows -a -F "$fmt")"; then
	printf 'agent-switch: tmux list-windows failed. Press any key.'
	read -r -n 1 -s _
	exit 1
fi

# Capture fzf's exit without set -e aborting the script.
if sel="$(printf '%s\n' "$list" | "$fzf_bin" --reverse --with-nth='2..' --delimiter=$'\t' \
	--preview 'tmux capture-pane -ep -t {1}' --preview-window=right:60%)"; then
	rc=0
else
	rc=$?
fi
[ "$rc" -eq 130 ] && exit 0 # 130 = Esc/Ctrl-C: benign cancel
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
	printf 'agent-switch: fzf failed (rc=%s). Press any key.' "$rc"
	read -r -n 1 -s _
	exit "$rc"
fi
[ -z "${sel:-}" ] && exit 0

pid="$(printf '%s' "$sel" | cut -f1)"
# switch-client -t accepts a pane target (contains %): changes session+window+pane
# atomically, no separate select-window, no wrong-window flash.
tmux switch-client -t "$pid"
