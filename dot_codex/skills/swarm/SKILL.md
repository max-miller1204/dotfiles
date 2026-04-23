---
name: swarm
description: "Execute a spec in parallel git worktrees with Codex worker agents. Use when the user wants to fan out implementation from a SPEC.md, run a wave of parallel work, scaffold shared contracts, dispatch chunk owners, and fold completed branches back into the integration branch."
---

# Swarm

Coordinate parallel work across git worktrees. You are the coordinator: you do the serial scaffold work in the current session, create one worktree per chunk, dispatch worker agents for the leaf work, then fold each branch back into the integration branch one at a time.

Read `references/chunk-template.md` when preparing worker instructions.

## Phase 1 - Load the spec

- Read the user-specified spec path, or `./SPEC.md` by default.
- If no spec exists, stop and tell the user to run `spec` first.
- Look for a `Waves` section.

If waves are present:
- find any execution notes such as `_Wave N executed YYYY-MM-DD: ..._`
- treat those waves as complete
- offer the first unexecuted wave unless the user explicitly asks for another
- use the wave's scaffold, chunk list, and sequencing verbatim; do not silently re-chunk it

If no waves section exists:
- treat the spec as a single candidate wave
- analyze whether the work is actually parallelizable
- only continue if the chunks can be isolated by ownership and interface

## Phase 2 - Propose the execution plan

Present the wave plan before making changes:
- scaffold work that must land first
- chunk list with branch names, ownership, interfaces, and done-when checks
- sequencing constraints inside the wave

If the spec did not pre-chunk the work:
- split only when boundaries are genuinely clean
- stop and recommend serial execution when the work is mostly one-file, tightly sequential, or interface-unstable

Confirm the plan with a concise direct question before creating worktrees.

## Phase 3 - Preconditions

Verify all of the following:
- inside a git repository
- the working tree is clean
- the current branch is the intended integration branch

Prefer `main` or `master`, but another local branch is acceptable if the user intends to fold all worker branches back there. If that intent is unclear, ask before proceeding.

Do not force state. If the repo is dirty or the target branch is unclear, stop and explain the blocker.

## Phase 4 - Build the scaffold locally

Do the serial scaffold work yourself in the current session before dispatching workers:
- shared manifests or config
- common types and interface contracts
- stub modules for each chunk if needed
- tests or smoke-test harnesses required by all chunks

Run the appropriate validation before dispatch:
- TypeScript: `tsc --noEmit`, project tests, or the repo's standard check
- Python: targeted tests or lint/type checks
- Rust: `cargo check` or `cargo test`
- Go: `go test ./...` or targeted packages
- otherwise use the repo's normal verification command

Do not dispatch workers until the scaffold passes.

Commit the scaffold with a message that makes the locked contracts explicit. Workers should branch from this exact point.

## Phase 5 - Create worktrees

For each chunk in the chosen wave:
- create a sibling worktree on its own branch, typically `codex/<chunk-name>`
- use a predictable sibling path such as `../<repo>-<chunk-name>`
- if a branch or worktree already exists, stop and ask instead of overwriting it

Each worktree must contain:
- the scaffold commit
- a `CHUNK.md` file derived from `references/chunk-template.md`
- only the instructions relevant to that chunk

## Phase 6 - Dispatch Codex workers

Dispatch one worker agent per chunk only because `swarm` is an explicit request for delegated parallel work.

Each worker prompt must include:
- the worktree path and branch name
- exact ownership boundaries
- locked interfaces that must not change
- done-when checks
- the rule that the worker is not alone in the codebase and must not revert unrelated edits
- the requirement to commit finished work locally and report changed files

Use worker agents for implementation. Keep the coordinator focused on integration readiness, validation strategy, and conflict risk.

## Phase 7 - While workers run

- do non-overlapping coordinator work locally
- inspect for integration risks across chunk boundaries
- avoid redundant implementation work
- use `wait_agent` sparingly; only wait when the next critical step depends on a worker result

## Phase 8 - Fold branches back

Process one completed chunk at a time:
1. verify the worker branch is committed and the worktree is clean
2. fold commits back into the integration branch, preferably by cherry-picking the branch's ahead commits in order
3. run the relevant validation after each fold
4. if conflicts occur, stop and resolve them before touching the next branch
5. once folded successfully, remove the worktree and delete the branch

Do not batch-fold multiple branches at once. Keep the integration branch clean between folds.

## Phase 9 - Record execution

Append an execution note to the spec:

- wave-based spec: `_Wave N executed YYYY-MM-DD: branches branch-a, branch-b_`
- single-wave spec: `_Executed YYYY-MM-DD: branches branch-a, branch-b_`

This note is the durable record of progress for the next `swarm` run.

## Ground rules

- Do not push, merge to remote, or modify remotes unless the user explicitly asks.
- Do not change locked interfaces mid-wave without surfacing it as a spec change.
- Stop on conflicts rather than papering over them.
- Prefer explicit ownership over clever parallelism.
- If the plan is not actually parallel-safe, say so and keep the work serial.
