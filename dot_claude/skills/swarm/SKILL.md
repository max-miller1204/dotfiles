---
name: swarm
description: "Execute a spec in parallel git worktrees, one wave at a time. Scaffolds the foundation serially in the current session, dispatches leaf chunks to parallel Claude agents via tmux, then walks the user through folding each branch back into trunk. Triggers on: 'swarm', 'swarm this', 'parallelize this', 'dispatch swarm', 'run in parallel worktrees', 'execute this spec', 'scaffold and fan out', 'run wave N', 'fan out the work'. Takes optional $1 = path to spec file (defaults to ./SPEC.md). Use /spec first to write the spec; use this skill to execute it."
---

You orchestrate parallel work across git worktrees using the user's fish commands (`ga`, `gwa`, `gwf`, `gwr`, `gwra`, `tsl`, `tslw`, `tslwm`, `tdl`, `tdlm`). You are the **coordinator**: you do the serial scaffold work in this session, spawn other Claude agents in tmux panes/windows to do leaf work in parallel, then walk the user through folding each branch back.

Consult `references/commands.md` whenever you need to pick a command — don't guess at behavior or flags.

## Phase 1 — Load the spec

Read `$1` if given, else `./SPEC.md`. If neither exists, tell the user to run `/spec` first and stop.

Look for a **Waves** section in the spec.

- **If waves are present** (the primary path): scan for any `_Wave N executed …_` notes already in the spec — those waves are done. Offer the first un-executed wave via `AskUserQuestion`. Use that wave's chunks and scaffold verbatim; do not re-chunk.
- **If no waves section**: treat the spec as one wave. You'll need to analyze parallelizability yourself in the next phase.

## Phase 2 — Propose the wave plan

Present to the user:

1. **Scaffold** — files/modules to land serially before dispatch. Includes: workspace manifest, shared types, locked interface contracts (trait signatures, type defs), stub modules for each future chunk, CI config.
2. **Chunks** — for each: branch name (kebab-case, will be the worktree suffix), goal, files/areas it owns, explicit interfaces with other chunks, done-when criteria (ideally a smoke test).
3. **Intra-wave sequencing** — any pairs that must be serialized (e.g. chunk B after chunk A because they touch the same crate).

If the spec did not pre-chunk: analyze independence. Good fit: disjoint files/subsystems, clear contracts. Bad fit: single-file refactors, tight sequential deps, shared-state edits. If it doesn't parallelize, say so and stop — recommend serial work.

Use `AskUserQuestion` to confirm the plan before doing anything destructive. Let the user edit the chunk list.

## Phase 3 — Preconditions for scaffold

Verify:
- Inside a git repo: `git rev-parse --git-dir` succeeds
- On trunk: `git branch --show-current` matches the trunk branch (`main`, `master`, or whatever `git symbolic-ref refs/remotes/origin/HEAD` resolves to; fall back to asking if unclear)
- Working tree clean: `git status --porcelain` is empty

If any fail, explain what's wrong and stop. Do not force state.

## Phase 4 — Build the scaffold in this session

You (the coordinator) write the scaffold files yourself. The other agents aren't running yet — this is all you.

- Write the workspace/package manifest, shared types, interface contracts, stub modules for each chunk, CI.
- Run a build check appropriate to the stack (e.g. `cargo check --workspace` for Rust, `tsc --noEmit` for TypeScript, `go build ./...` for Go). **Do not proceed if it fails.** Fix and re-check.
- Commit with a clear message describing what contracts were locked. Example: `scaffold: lock SttEngine + LlmProvider + Recorder + … contracts`.

The scaffold commit is load-bearing: every parallel chunk imports from it. Nail it down before dispatch.

## Phase 5 — Preconditions for dispatch

Verify:
- `$TMUX` is set (inside a tmux session)
- The scaffold commit you just made is on trunk and is HEAD
- Working tree still clean

## Phase 6 — Dispatch

Pick the primitive by chunk count:
- **≤4 chunks** → `tslw`
- **>4 chunks** → `tslwm`

Three-step dispatch, in this order (avoids a race where Claude starts before its `CHUNK.md` exists):

1. **Create worktrees + panes/windows silently.** Call with empty cmd:
   ```
   tslw "" branch1 branch2 ...
   ```
   or
   ```
   tslwm "" branch1 branch2 ...
   ```
   This creates the worktrees at `<parent>/<repo>--<branch>` and opens panes/windows cd'd into each. **These functions do not print pane IDs** — you have to discover them yourself in step 3.

2. **Write `<worktree>/CHUNK.md`** for each chunk, using `references/chunk-template.md` as the template. Fill in: name, goal, files owned, interfaces (copy the locked signatures from the scaffold commit verbatim), done-when, out-of-scope, branch name, worktree path.

3. **Discover pane/window IDs and launch the agents.** Use `tmux list-panes` to find the panes you just created:
   ```
   tmux list-panes -a -F "#{pane_id} #{pane_current_path}"
   ```
   For each branch, find the pane whose `pane_current_path` equals `<parent>/<repo>--<branch>`. Then send the command:
   ```
   tmux send-keys -t <pane_id> 'c "read CHUNK.md and execute it"' C-m
   ```
   Do this per-pane, not in a loop that might race. Verify each pane got the command before moving to the next.

Report the pane/window IDs and worktree paths so the user can navigate.

## Phase 7 — Hand off

Do not poll. Do not wake up and check on agents. The user watches the panes and tells you when chunks are done. If the user asks you to check in on a specific chunk, you can inspect its worktree via `Read`/`Bash` — but don't steer the sub-agent unless asked.

## Phase 8 — Fold back

When the user says chunks are done, walk through each branch **one at a time**. For each, ask via `AskUserQuestion`:

- **Apply only** — keep the worktree for inspection
- **Full fold** — apply + stage + remove worktree + delete branch
- **Skip** — leave this one for later

**Critical:** `gwf`, `gwr`, and `gwra` all use `gum confirm`, which blocks on stdin. You cannot answer it from the Bash tool — the command will hang. So:

- **Apply only** → run `gwa <branch>` directly. `gwa` does not use gum. Safe to run.
- **Full fold** → do the steps manually (no gum). From the main repo root (`cd` into it first):
  ```
  gwa <branch>                              # apply (cached then 3way fallback)
  git -C <main> add .                       # stage
  git -C <main> worktree remove <path> --force
  git -C <main> branch -D <branch>
  ```
  Where `<path>` is `<parent>/<repo>--<branch>`. Also kill any tmux panes whose `pane_current_path` starts with that worktree path:
  ```
  tmux list-panes -a -F "#{pane_id} #{pane_current_path}" \
    | awk -v p="<path>" '$2==p || index($2,p"/")==1 {print $1}' \
    | xargs -r -n1 tmux kill-pane -t
  ```

**On conflict** (either `gwa`'s `git apply --index` fails *and* the `--3way` fallback leaves conflict markers): stop immediately. Print the conflicted files. Tell the user to resolve them — either in the main repo or in the worktree — and come back when clean. **Do not advance to the next branch until the current state is clean.** Check with `git -C <main> status --porcelain`.

## Phase 9 — Cleanup

After all branches are folded or skipped, ask the user whether to sweep remaining swarm worktrees. Again, `gwra` blocks on `gum confirm` — do it manually:

```
git -C <main> worktree list --porcelain
```

Parse for `worktree <path>` entries whose path matches `<parent>/<repo>--*` (excluding the main worktree itself). For each match: `git worktree remove --force <path>` + `git branch -D <branch>`. Kill lingering tmux panes the same way as Phase 8.

Confirm the list with the user before removing — show them the paths and branches you're about to delete.

## Phase 10 — Record the wave

Append a one-line note to the spec file:

```
_Wave {{N}} executed {{YYYY-MM-DD}}: branches {{comma-separated list}}_
```

Use today's date (from the environment context). This is the only persistent state — on the next `/swarm` invocation, this note is how you know which wave to offer next.

If the spec had no Waves section, append instead:

```
_Executed {{YYYY-MM-DD}}: branches {{list}}_
```

## Ground rules

- **You don't push, you don't merge, you don't touch remotes.** Fold-back is local-only. The user decides what gets pushed.
- **You don't skip hooks** (no `--no-verify`). If a commit hook fails during the scaffold, fix the underlying issue.
- **You stop on conflict.** Never pass `-Xtheirs` or similar to paper over a 3way conflict.
- **You do not unilaterally edit locked interfaces.** If a chunk turns out to need a different signature mid-dispatch, that's a spec change — stop and surface it.
- **The human is the clock.** You don't poll agents, don't time out chunks, don't retry. The user drives when each phase advances.
