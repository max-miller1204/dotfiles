# Command reference

All commands defined in `~/.config/fish/functions/`. Invoke via `Bash` tool (fish is the user's shell).

Worktree naming convention: `<parent-dir>/<repo-basename>--<branch>`. E.g. in `~/code/chatter`, branch `audio-recorder` lives at `~/code/chatter--audio-recorder`.

## Worktree commands (`gw*`, `ga`)

### `ga <branch>`
Create a worktree at `../<repo>--<branch>`, create the branch, `cd` into the worktree.
- **Use when:** creating a single worktree serially. For parallel dispatch prefer `tslw`/`tslwm`, which create worktrees *and* launch panes in one call.

### `gwa [branch]`
Apply worktree changes to main. Runs `git diff HEAD | git apply --index -` first (cached), falling back to `--3way` on failure. Copies untracked files.
- With no arg: applies the current worktree (must `cd` into it first).
- With branch: applies the worktree at `../<repo>--<branch>`.
- **On conflict:** `git apply --3way` leaves conflict markers. Surface the conflict to the user, wait for manual resolution, do not continue.
- **Use when:** integrating a worktree's changes into main without deleting the worktree.

### `gwf [branch]`
Fold worktree: apply + stage + remove worktree + delete branch + kill tmux panes in that directory. Uses `gum confirm`.
- **Cannot be invoked from Claude's Bash tool** — `gum confirm` blocks on stdin and the tool is non-interactive. The command will hang.
- **Substitute (non-interactive, same effect):**
  ```
  gwa <branch>
  git -C <main> add .
  git -C <main> worktree remove <parent>/<repo>--<branch> --force
  git -C <main> branch -D <branch>
  # plus: kill tmux panes whose pane_current_path starts with the worktree path
  ```
- **Use when:** the user asks to fully fold a chunk. Always use the substitute sequence, not `gwf` itself.

### `gwr [branch]`
Remove a single worktree and its branch. Kills tmux panes in that directory. Uses `gum confirm`.
- **Cannot be invoked from Claude's Bash tool** (same reason as `gwf`).
- **Substitute:**
  ```
  git -C <main> worktree remove <parent>/<repo>--<branch> --force
  git -C <main> branch -D <branch>
  # plus: kill tmux panes whose pane_current_path starts with the worktree path
  ```

### `gwra`
Remove **all** swarm worktrees (any worktree matching `<parent>/<repo>--*`) at once. Uses `gum confirm`.
- **Cannot be invoked from Claude's Bash tool.**
- **Substitute:** enumerate worktrees with `git worktree list --porcelain`, filter for paths matching `<parent>/<repo>--*` (excluding main), confirm the list with the user, then loop `git worktree remove --force <path>` + `git branch -D <branch>` per match.

## Tmux layout commands (`ts*`, `td*`)

### `tsl <count> <cmd>`
Split the current pane into `<count>` tiled panes, run `<cmd>` in each. Does not touch worktrees.
- **Use when:** you want N panes running the same thing in the current working directory. Not the primary dispatch primitive for this skill.

### `tslw <cmd> <branch1> [branch2 …]`
**Primary dispatch primitive for ≤4 chunks.** For each branch:
1. Create the worktree at `<parent>/<repo>--<branch>` (if it doesn't exist), creating the branch if needed.
2. Split the current pane horizontally, cd into that worktree.
3. If `<cmd>` is non-empty, run it in the pane.

Apply tiled layout. Pass `""` as cmd to skip auto-running anything — useful so you can write `CHUNK.md` *then* `tmux send-keys` the actual command (avoiding the race where `c` starts before `CHUNK.md` exists).

- **Precondition:** must be inside `tmux` ($TMUX set).
- **Use when:** ≤4 chunks, you want all agents visible in one window.

### `tslwm <cmd> <branch1> [branch2 …]`
**Primary dispatch primitive for >4 chunks.** Same as `tslw` but creates one tmux **window** per branch instead of splitting panes. Each window is named after the branch.

- **Precondition:** must be inside `tmux`.
- **Use when:** >4 chunks, or you want each agent in a clean dedicated window.

### `tdl <ai> [<ai2>]`
Tmux Dev Layout: editor (70% top) + AI tool (30% bottom-right) + optional second AI. Runs `$EDITOR .` in the editor pane.
- **Use when:** not a parallel-dispatch primitive. Useful for setting up a human-driven session in a single worktree.

### `tdlm <ai> [<ai2>]`
Multi-window dev layout: for each subdirectory in the current dir, open a new tmux window and run `tdl` in it. Named after `basename $PWD`.
- **Use when:** you've already created N worktrees under a parent directory and want to open human-driven dev layouts in each. Not the primary dispatch primitive — use `tslwm` for swarm work.

## Dispatch recipe (what this skill uses)

```
# chunks <= 4
tslw "" branch1 branch2 branch3                   # create worktrees + panes, no cmd
# for each worktree: write CHUNK.md
# for each pane: tmux send-keys -t $pane_id 'c "read CHUNK.md and execute it"' C-m

# chunks > 4
tslwm "" branch1 branch2 ... branch8
# same follow-up: write CHUNK.md, then send-keys the command per window
```

`c` is `alias c 'claude --plugin-dir ~/.claude/plugins/lsp-servers'` in `~/.config/fish/config.fish`. Passing a positional string starts a Claude session with that prompt pre-filled.

## Fold-back recipe (non-interactive — what Claude actually runs)

```
# for each branch, ask user: apply-only / full-fold / skip

# apply-only:
gwa <branch>     # safe — no gum

# full-fold (substitute for gwf, since gwf blocks on gum):
gwa <branch>
git -C <main> add .
git -C <main> worktree remove <parent>/<repo>--<branch> --force
git -C <main> branch -D <branch>
# then kill tmux panes whose pane_current_path starts with that worktree path:
tmux list-panes -a -F "#{pane_id} #{pane_current_path}" \
  | awk -v p="<worktree-path>" '$2==p || index($2,p"/")==1 {print $1}' \
  | xargs -r -n1 tmux kill-pane -t

# on gwa conflict: stop, surface the conflict, wait. Check cleanliness with
#   git -C <main> status --porcelain
# before advancing.

# final sweep (substitute for gwra):
git -C <main> worktree list --porcelain   # parse, filter <parent>/<repo>--*
# confirm list with user, then loop:
#   git worktree remove --force <path>
#   git branch -D <branch>
```
