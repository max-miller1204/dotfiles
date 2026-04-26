# Command reference

All commands defined in `~/.config/fish/functions/`. The user's interactive shell is fish, but Claude Code's `Bash` tool defaults to bash — fish functions like `gwc`/`gwa`/`tslw`/`tslwm` aren't callable directly. Wrap them: `fish -c 'gwc <branch>'`. (For commands that need the user's full env including `$PATH` additions and aliases, use `fish -lc '...'` to source the login profile.)

Worktree naming convention: `<parent-dir>/<repo-basename>--<branch>`. E.g. in `~/code/chatter`, branch `audio-recorder` lives at `~/code/chatter--audio-recorder`.

## Worktree commands (`gw*`, `ga`)

### `ga <branch>`
Create a worktree at `../<repo>--<branch>`, create the branch, `cd` into the worktree.
- **Use when:** creating a single worktree serially. For parallel dispatch prefer `tslw`/`tslwm`, which create worktrees *and* launch panes in one call.

### `gwa [branch]`
Apply worktree changes to the main worktree's currently-checked-out branch (the integration branch — trunk in solo mode, the wave branch in fork mode). Runs `git diff HEAD | git apply --index -` first (cached), falling back to `--3way` on failure. Copies untracked files.
- With no arg: applies the current worktree (must `cd` into it first).
- With branch: applies the worktree at `../<repo>--<branch>`.
- **On conflict:** `git apply --3way` leaves conflict markers. Surface the conflict to the user, wait for manual resolution, do not continue.
- **Only applies uncommitted work** (`git diff HEAD`). If the chunk branch has commits ahead of the integration branch, `gwa` reports "Nothing to apply." For committed branches (the swarm case), use `gwc`.
- **Use when:** integrating an in-progress worktree's changes into the integration branch without deleting the worktree.

### `gwc [branch]`
Git-worktree-cherry-pick. Cherry-picks every commit on `<branch>` that is not on the main worktree's currently-checked-out branch (the integration branch — `main`/`master` in solo mode, the wave branch in fork mode), in order, onto the main worktree.
- With no arg: cherry-picks the current worktree's branch (must `cd` into it first).
- With branch: cherry-picks from the worktree at `../<repo>--<branch>`.
- **No-op if the branch has no commits ahead of the integration branch** — prints a hint pointing at `gwa`.
- **On conflict:** cherry-pick stops with markers in the main worktree. Stop, surface the files, wait for manual `cherry-pick --continue` or `--abort`. Do not advance.
- **Use when:** folding back a swarm chunk whose agent already committed. Preferred over `gwa` for committed work because it preserves each commit (with its message) as its own entry on the integration branch.
- **Important:** the helper does not hardcode `main`. It targets whatever branch the main worktree currently has checked out. So in fork mode, make sure the wave branch is checked out before running `gwc`.

### `gwf [branch]`
Fold worktree: apply (uncommitted diff) + stage + remove worktree + delete branch + kill tmux panes in that directory. Uses `gum confirm`.
- **Cannot be invoked from Claude's Bash tool** — `gum confirm` blocks on stdin and the tool is non-interactive. The command will hang.
- Shares the `gwa` limitation: only picks up uncommitted work. For committed swarm chunks, the fold-back substitute uses `gwc` instead.
- **Substitute (non-interactive, covers both cases):**
  ```
  # committed work (swarm default):
  gwc <branch>
  # OR uncommitted work:
  gwa <branch>
  git -C <main> add .

  git -C <main> worktree remove <parent>/<repo>--<branch> --force
  rmdir -p "$(dirname <parent>/<repo>--<branch>)" 2>/dev/null || true   # cleans up intermediate parent dirs from slashed branch names
  git -C <main> branch -D <branch>
  # plus: kill tmux panes whose pane_current_path starts with the worktree path
  ```
- **Use when:** the user asks to fully fold a chunk. Always use the substitute sequence, not `gwf` itself.

  **Why the rmdir:** if `<branch>` contains `/` (e.g. `swarm/foo-wave-2-bar`), the worktree path `<parent>/<repo>--swarm/foo-wave-2-bar` has an intermediate dir `<parent>/<repo>--swarm/`. `git worktree remove` only removes the leaf, leaving the parent empty. `rmdir -p` walks up and stops at the first non-empty parent, so it's safe — if other sibling worktrees still exist under the same parent, the parent stays.

### `gwr [branch]`
Remove a single worktree and its branch. Kills tmux panes in that directory. Uses `gum confirm`.
- **Cannot be invoked from Claude's Bash tool** (same reason as `gwf`).
- **Substitute:**
  ```
  git -C <main> worktree remove <parent>/<repo>--<branch> --force
  rmdir -p "$(dirname <parent>/<repo>--<branch>)" 2>/dev/null || true   # cleans up intermediate parent dirs from slashed branch names
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

Swarm agents commit their work (see `chunk-template.md` → "Commit your work to this branch when done"), so the default fold primitive is **`gwc`** (cherry-pick). Fall back to `gwa` only if the agent left work uncommitted.

In fork mode, make sure the main worktree has the wave branch checked out before any `gwc` call — `gwc` cherry-picks onto whatever HEAD is.

```
# for each branch, ask user: apply-only / full-fold / skip

# apply-only (committed work — default for swarm):
gwc <branch>     # safe — no gum

# apply-only (uncommitted work):
gwa <branch>     # safe — no gum

# full-fold (substitute for gwf, since gwf blocks on gum):
gwc <branch>                  # or gwa <branch> if uncommitted; then git -C <main> add .
git -C <main> worktree remove <parent>/<repo>--<branch> --force
rmdir -p "$(dirname <parent>/<repo>--<branch>)" 2>/dev/null || true   # cleans up intermediate parent dirs from slashed branch names (e.g. swarm/foo-wave-2-bar)
git -C <main> branch -D <branch>
# then kill tmux panes whose pane_current_path starts with that worktree path:
tmux list-panes -a -F "#{pane_id} #{pane_current_path}" \
  | awk -v p="<worktree-path>" '$2==p || index($2,p"/")==1 {print $1}' \
  | xargs -r -n1 tmux kill-pane -t

# on conflict (either gwc's cherry-pick or gwa's 3way): stop, surface the
# conflicted files, wait for manual resolution (resolve in the main worktree,
# then `git cherry-pick --continue` or `git add . && git commit`).
# Check cleanliness with:
#   git -C <main> status --porcelain
# before advancing.

# Lockfile conflicts are common when parallel chunks each add deps. The pattern
# is the same across stacks: take the integration branch's lock (`git checkout
# --ours <lockfile>`), let the stack's resolver regenerate it, then
# `git add <lockfile> && git cherry-pick --continue`. See the per-stack table
# below for the regenerate command.

# final sweep (substitute for gwra):
git -C <main> worktree list --porcelain   # parse, filter <parent>/<repo>--*
# confirm list with user, then loop:
#   git worktree remove --force <path>
#   rmdir -p "$(dirname <path>)" 2>/dev/null || true   # cleans up intermediate parent dirs from slashed branch names; rmdir -p stops at the first non-empty parent so it's safe across the loop
#   git branch -D <branch>
# wave branches in fork mode are NOT in this filter (they live in the main
# worktree, not in <parent>/<repo>--*), so they're preserved automatically.
```

### Lockfile conflict regeneration

| Stack | Lockfile | Regenerate command |
|-------|----------|--------------------|
| Cargo (Rust) | `Cargo.lock` | `cargo check --workspace` |
| npm | `package-lock.json` | `npm install` |
| pnpm | `pnpm-lock.yaml` | `pnpm install` |
| Bun | `bun.lockb` / `bun.lock` | `bun install` |
| Go modules | `go.sum` | `go mod tidy` |
| uv (Python) | `uv.lock` | `uv sync` |
| Poetry | `poetry.lock` | `poetry lock --no-update` |

Pattern in all cases: `git checkout --ours <lockfile>` → run the regenerate command → `git add <lockfile> && git cherry-pick --continue`. Taking `--ours` is correct because the integration branch's lock is the merge base for the next chunk; the regenerator re-adds the missing deps from the chunk branch.

**This pattern is for *derived* lockfiles only.** When the conflict is in the manifest itself (e.g. `pyproject.toml`'s `dependencies = [...]` line, `package.json`'s `dependencies` block, `Cargo.toml`'s `[dependencies]`), the manifest IS the source of truth — there's no upstream to regenerate from. `--ours` would silently drop the chunk branch's contribution and the regenerator wouldn't restore it. Resolve manifest-level conflicts by hand: edit the conflicted region to union both branches' changes, `git add <manifest>`, then `git cherry-pick --continue`. The skill's general "stop on conflict, surface, resolve, continue" discipline still applies — just don't reach for the lockfile recipe when the conflict is in the manifest.
