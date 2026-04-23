---
name: swarm
description: "Execute a spec in parallel git worktrees, one wave at a time. Scaffolds the foundation serially in the current session, dispatches leaf chunks to parallel Codex worker agents via `spawn_agent`, then walks the user through folding each branch back into trunk. Triggers on: 'swarm', 'swarm this', 'parallelize this', 'dispatch swarm', 'run in parallel worktrees', 'execute this spec', 'scaffold and fan out', 'run wave N', 'fan out the work'. Takes optional $1 = path to spec file (defaults to ./SPEC.md). Use `spec` first to write the spec; use this skill to execute it."
---

# Swarm

You orchestrate parallel work across git worktrees using Codex worker agents. You are the **coordinator**: you do the serial scaffold work in this session, create one worktree per chunk, spawn workers via `spawn_agent` to do the leaf work in parallel, then walk the user through folding each branch back.

This skill is opinionated: one path, git worktrees + `spawn_agent` workers. No shell/no-git fallback. If the project can't support git worktrees, stop and tell the user to run the work serially instead.

## Phase 1 — Load the spec

Read `$1` if given, else `./SPEC.md`. If neither exists, tell the user to run `spec` first and stop.

Look for a **Waves** section in the spec.

- **If waves are present** (the primary path): scan for any `_Wave N executed …_` notes already in the spec — those waves are done. Offer the first un-executed wave. Use that wave's chunks and scaffold verbatim; do not re-chunk.
- **If no waves section**: treat the spec as one wave. You'll need to analyze parallelizability yourself in the next phase.

## Phase 2 — Propose the wave plan

Present to the user:

1. **Scaffold** — files/modules to land serially before dispatch. Includes: workspace manifest, shared types, locked interface contracts (trait signatures, type defs), stub modules for each future chunk, CI config.
2. **Chunks** — for each: branch name (kebab-case, will be the worktree suffix), goal, files/areas it owns, explicit interfaces with other chunks, done-when criteria (ideally a smoke test).
3. **Intra-wave sequencing** — any pairs that must be serialized (e.g. chunk B after chunk A because they touch the same crate).

If the spec did not pre-chunk: analyze independence. Good fit: disjoint files/subsystems, clear contracts. Bad fit: single-file refactors, tight sequential deps, shared-state edits. If it doesn't parallelize, say so and stop — recommend serial work.

Confirm the plan with the user before doing anything destructive. Let the user edit the chunk list.

## Phase 3 — Preconditions for scaffold

Verify:
- Inside a git repo: `git rev-parse --git-dir` succeeds
- On trunk: `git branch --show-current` matches the trunk branch (`main`, `master`, or whatever `git symbolic-ref refs/remotes/origin/HEAD` resolves to; fall back to asking if unclear)
- Working tree clean: `git status --porcelain` is empty

If any fail, explain what's wrong and stop. Do not force state.

## Phase 4 — Build the scaffold in this session

You (the coordinator) write the scaffold files yourself. Workers are not running yet — this is all you.

- Write the workspace/package manifest, shared types, interface contracts, stub modules for each chunk, CI.
- Run a build check appropriate to the stack (e.g. `cargo check --workspace` for Rust, `tsc --noEmit` for TypeScript, `go build ./...` for Go). **Do not proceed if it fails.** Fix and re-check.
- Commit with a clear message describing what contracts were locked. Example: `scaffold: lock SttEngine + LlmProvider + Recorder + … contracts`.

The scaffold commit is load-bearing: every parallel chunk branches from it and imports from it. Nail it down before dispatch.

## Phase 5 — Preconditions for dispatch

Verify:
- The scaffold commit you just made is on trunk and is HEAD
- Working tree still clean
- `spawn_agent` is available in this session (this skill requires it)

## Phase 6 — Create worktrees, write CHUNK.md, dispatch workers

Worktree naming convention: `<parent>/<repo>--<branch>`. E.g. in `~/code/chatter`, branch `audio-recorder` lives at `~/code/chatter--audio-recorder`.

Three-step dispatch, in this order (avoids a race where a worker starts before its `CHUNK.md` exists):

1. **Create a worktree per chunk.** Each starts from the current trunk HEAD (the scaffold commit):
   ```
   git worktree add <parent>/<repo>--<branch> -b <branch>
   ```
   If the branch or worktree already exists, stop and ask the user instead of overwriting it.

2. **Write `<worktree>/CHUNK.md`** for each chunk, using `references/chunk-template.md`. Fill in: name, goal, files owned, interfaces (copy the locked signatures from the scaffold commit verbatim), done-when, out-of-scope, branch name, worktree path.

3. **Spawn one worker per chunk via `spawn_agent`.** Use `fork_context: false` so workers share the repo and their commits land on the branch for later cherry-pick. The prompt must pin the worker to its worktree and tell it to read `CHUNK.md`:
   ```
   spawn_agent({
     agent_type: "worker",
     fork_context: false,
     message: "You are one of several parallel Codex worker agents.
     You own only <parent>/<repo>--<branch> on branch <branch>.
     cd into that worktree, read CHUNK.md, execute it exactly.
     You are not alone in the codebase — do not revert unrelated edits,
     do not touch sibling chunk files, and adapt to existing changes.
     Commit your work locally on <branch> when done. Do not push or merge."
   })
   ```
   Do this per-chunk. Do not batch. Verify each `spawn_agent` call returned before moving to the next.

Report the worker IDs and worktree paths so the user can navigate.

## Phase 7 — Hand off

Do not poll. Do not use `wait_agent` just to check on progress — only use it when the next critical coordinator step genuinely blocks on a worker's result. The user watches the workers and tells you when chunks are done. If the user asks you to check in on a specific chunk, you can inspect its worktree via `Read`/`Bash` — but don't steer the worker unless asked.

While workers run, you may do non-overlapping coordinator work locally (integration prep, conflict analysis, validation harness). Avoid duplicating work workers are already doing.

## Phase 8 — Fold back

When the user says chunks are done, walk through each branch **one at a time**. For each, ask:

- **Apply only** — cherry-pick commits onto trunk, keep the worktree for inspection
- **Full fold** — cherry-pick + remove worktree + delete branch
- **Skip** — leave this one for later

Workers commit their work (per CHUNK.md), so the default fold primitive is **`git cherry-pick`**. It preserves each commit's message as its own entry on trunk. `cd` into the main worktree first.

**Apply only:**
```
git cherry-pick <trunk>..<branch>
```

**Full fold:**
```
git cherry-pick <trunk>..<branch>
git worktree remove <parent>/<repo>--<branch> --force
git branch -D <branch>
```

**On conflict**: stop immediately. Print the conflicted files. Resolve in the main worktree (e.g. `git checkout --ours Cargo.lock && cargo check --workspace && git add Cargo.lock` for lockfile conflicts), then `git cherry-pick --continue`. **Do not advance to the next branch until the current state is clean.** Check with `git status --porcelain`.

If a worker did NOT commit (left uncommitted work): tell the user, then fall back to applying the diff manually from the worktree — `git -C <worktree> diff HEAD | git apply --index -` (with `--3way` if it fails), from the main worktree. Commit it before the next fold.

## Phase 9 — Cleanup

After all branches are folded or skipped, ask the user whether to sweep remaining swarm worktrees. Enumerate:

```
git worktree list --porcelain
```

Parse for `worktree <path>` entries whose path matches `<parent>/<repo>--*` (excluding the main worktree itself). Show the list to the user and confirm before removing. Then for each match:

```
git worktree remove --force <path>
git branch -D <branch>
```

## Phase 10 — Record the wave

Append a one-line note to the spec file:

```
_Wave {{N}} executed {{YYYY-MM-DD}}: branches {{comma-separated list}}_
```

Use today's date (from the environment context). This is the only persistent state — on the next `swarm` invocation, this note is how you know which wave to offer next.

If the spec had no Waves section, append instead:

```
_Executed {{YYYY-MM-DD}}: branches {{list}}_
```

## Ground rules

- **You don't push, you don't merge, you don't touch remotes.** Fold-back is local-only. The user decides what gets pushed.
- **You don't skip hooks** (no `--no-verify`). If a commit hook fails during the scaffold, fix the underlying issue.
- **You stop on conflict.** Never pass `-Xtheirs` or similar to paper over a 3way conflict.
- **You do not unilaterally edit locked interfaces.** If a chunk turns out to need a different signature mid-dispatch, that's a spec change — stop and surface it.
- **Workers commit; the coordinator integrates.** Dispatch with `fork_context: false` so commits land on the shared repo's branches, not a fork you have to patch-import.
- **The human is the clock.** You don't poll workers, don't time out chunks, don't retry. The user drives when each phase advances.
