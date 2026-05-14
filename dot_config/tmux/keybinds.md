# Keybinds & Shortcuts Reference

Complete shortcut list across shell, tmux, and git.

---

## Shell Aliases

| Alias | Command |
|-------|---------|
| `c` | `claude` |
| `cx` | `clear; claude --dangerously-skip-permissions` |
| `t` | `tmux attach \|\| tmux new -s Work` |
| `g` | `git` |
| `gs` | `git status` |
| `gc` | `git commit` |
| `gp` | `git push` |
| `gl` | `git log --oneline` |
| `gcm` | `git commit -m` |
| `gcam` | `git commit -a -m` |
| `gcad` | `git commit -a --amend` |
| `d` | `docker` |
| `ls` | `eza -lh --group-directories-first --icons=auto` |
| `lsa` | `eza -lah --group-directories-first --icons=auto` |
| `lt` | `eza --tree --level=2 --long --icons --git` |
| `lta` | `eza --tree --level=2 --long --icons --git -a` |
| `ll` | `ls -la` |
| `la` | `ls -a` |
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `....` | `cd ../../..` |
| `decompress` | `tar -xzf` |
| `tmux-help` | `bat ~/.config/tmux/keybinds.md` |

---

## Shell Functions

Grouped by workflow rather than alphabetically — each section lists commands in the order you'd typically call them.

### Files & editing

| Function | Usage | Description |
|----------|-------|-------------|
| `n` | `n [files]` | Open nvim (`.` if no args) |
| `ff` | `ff` | fzf file finder with bat preview |
| `eff` | `eff` | Open fzf-selected file in $EDITOR |
| `sff` | `sff host:/tmp/` | Find recent file via fzf, scp to destination |
| `open` | `open file.pdf` | xdg-open (backgrounded, silenced) |
| `compress` | `compress mydir` | Create `mydir.tar.gz` |

### Git worktree lifecycle

All worktree commands start with `gw` (git worktree); the trailing letter is the verb. Typical flow: `ga` to spawn → work in it → `gwa` to sync back (keep the worktree) **or** `gwf` to sync + destroy. Use `gwr` to drop a single worktree, `gwra` to nuke an entire swarm. `gwa`, `gwf`, and `gwr` each accept an optional branch name so you can target another worktree from the main checkout.

| Function | Usage | Description |
|----------|-------|-------------|
| `ga` | `ga feature-x` | **A**dd: create git worktree `../repo--feature-x/`, cd into it |
| `gwa` | `gwa [branch]` | worktree **a**pply: apply the worktree's `git diff HEAD` + untracked files to the main checkout. Worktree stays. With no arg, operates on the current worktree; with a branch arg, targets `../repo--<branch>/` from main. Requires a valid `HEAD`. |
| `gwf` | `gwf [branch]` | worktree **f**inish: `gwa` + `git add .` in main + remove the worktree and branch + kill its tmux pane(s) (gum confirm). With no arg, folds the current worktree; with a branch arg, folds `../repo--<branch>/` from main. |
| `gwr` | `gwr [branch]` | worktree **r**emove: delete the worktree + branch and kill its tmux pane(s) (gum confirm). With no arg, removes the current worktree; with a branch arg, removes `../repo--<branch>/` from main. |
| `gwra` | `gwra` | worktree **r**emove **a**ll: every `<repo>--*` swarm path plus its branch, single gum confirm. Kills all matching tmux panes, including the current one once cleanup finishes. |

> **Worktrees:** A worktree is a second checkout of the same repo — same Git database, separate directory, separate branch. A branch can only be checked out in one worktree at a time, so `cd` into an existing worktree rather than `git switch`. Remove the worktree (`gwr`) to free the branch for switching elsewhere.

### Tmux dev layouts

| Function | Usage | Description |
|----------|-------|-------------|
| `tdl` | `tdl claude` | **D**ev **l**ayout: editor 70% + AI 30% + terminal 15% |
| `tdl` | `tdl claude codex` | Dev layout with two AI panes (split vertically) |
| `tdlm` | `tdlm claude` | **M**ulti-project: one `tdl` window per subdirectory |

### Tmux swarms

Run the same command across N panes/windows. `tsl` is directory-only; `tslw`/`tslwm` spin up a worktree per branch first.

| Function | Usage | Description |
|----------|-------|-------------|
| `tsl` | `tsl 3 claude` | **S**warm **l**ayout: 3 tiled panes each running claude |
| `tslw` | `tslw cx feat-a feat-b feat-c` | Swarm across **w**orktrees by pane: one tiled pane per branch, each inside its own worktree, running the given command (pass `""` as cmd to skip auto-run) |
| `tslwm` | `tslwm cx feat-a feat-b feat-c` | Swarm across worktrees by window (**m**ultiwindow): one tmux window per branch |

### SSH port forwarding

| Function | Usage | Description |
|----------|-------|-------------|
| `fip` | `fip server 8080 3000` | **F**orward **IP**orts to remote host |
| `lip` | `lip` | **L**ist active SSH port forwards |
| `dip` | `dip 8080 3000` | **D**isconnect SSH port forwards |

---

## Git Aliases

| Alias | Command |
|-------|---------|
| `git co` | `git checkout` |
| `git br` | `git branch` |
| `git ci` | `git commit` |
| `git st` | `git status` |
| `git sync` | stash, pull --rebase, pop |

---

## Tmux (prefix: Ctrl-a)

### Pane Management

| Key | Action |
|-----|--------|
| `prefix` + `h` | Split horizontal (top/bottom) |
| `prefix` + `v` | Split vertical (left/right) |
| `prefix` + `x` | Kill pane |
| `Ctrl+Alt+Left` | Focus pane left |
| `Ctrl+Alt+Right` | Focus pane right |
| `Ctrl+Alt+Up` | Focus pane up |
| `Ctrl+Alt+Down` | Focus pane down |
| `Ctrl+Alt+Shift+Left` | Resize pane left |
| `Ctrl+Alt+Shift+Right` | Resize pane right |
| `Ctrl+Alt+Shift+Up` | Resize pane up |
| `Ctrl+Alt+Shift+Down` | Resize pane down |

### Window Management

| Key | Action |
|-----|--------|
| `prefix` + `c` | New window |
| `prefix` + `k` | Kill window |
| `prefix` + `r` | Rename window |
| `Alt+1` - `Alt+9` | Switch to window 1-9 |
| `Alt+Left` | Previous window |
| `Alt+Right` | Next window |
| `Alt+Shift+Left` | Swap window left |
| `Alt+Shift+Right` | Swap window right |

### Session CLI Commands

| Command | Action |
|---------|--------|
| `tmux ls` | List sessions |
| `tmux new -s <name>` | New named session |
| `tmux attach -t <name>` | Attach to session |
| `tmux kill-session -t <name>` | Kill a specific session |
| `tmux kill-session` | Kill current session |

### Session Management

| Key | Action |
|-----|--------|
| `prefix` + `C` | New session |
| `prefix` + `K` | Kill session |
| `prefix` + `R` | Rename session |
| `prefix` + `P` | Previous session |
| `prefix` + `N` | Next session |
| `Alt+Up` | Previous session |
| `Alt+Down` | Next session |

### Mac alternates

Option is reserved for Aerospace on macOS, so the Linux `Alt+*` binds don't fire. These `Ctrl+Shift` binds are equivalents.

| Key | Action |
|-----|--------|
| `Ctrl+Shift+Left` | Focus pane left |
| `Ctrl+Shift+Down` | Focus pane down |
| `Ctrl+Shift+Up` | Focus pane up |
| `Ctrl+Shift+Right` | Focus pane right |

### Copy Mode (vi)

| Key | Action |
|-----|--------|
| `prefix` + `[` | Enter copy mode |
| `v` | Begin selection |
| `y` | Copy selection |

### Other

| Key | Action |
|-----|--------|
| `prefix` + `q` | Reload config |
