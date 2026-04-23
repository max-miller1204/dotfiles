---
name: swarm
description: "Execute a spec with Codex worker agents in parallel. Use when the user wants to fan out implementation from a SPEC.md, run a wave of parallel work, scaffold shared contracts, dispatch chunk owners, integrate completed worker changes, or optionally coordinate git worktrees and fold completed branches back into an integration branch."
---

# Swarm

Coordinate parallel work from a spec. You are the coordinator: you do serial scaffold work in the current session, split leaf work into isolated chunks, dispatch Codex worker agents, review their results, then integrate each chunk one at a time.

Prefer **Codex app agent mode** in the Codex desktop app. Use **git worktree mode** only when shell/git are available and local worktrees are useful or explicitly requested.

Read `references/chunk-template.md` when preparing worker instructions.

## Execution modes

### Codex app agent mode

Use this mode by default in the Codex app.

- Dispatch one worker agent per chunk with `spawn_agent` because `swarm` is an explicit request for parallel delegated work.
- Give each worker a disjoint write scope and tell it to edit files directly in its forked workspace.
- Tell workers they are not alone in the codebase, must not revert unrelated edits, and must adapt to existing changes.
- Do not require git worktrees, local commits, or a clean repository before dispatching workers.
- Use shell/git commands only when available and helpful. If they are unavailable, continue with app-native worker delegation and manual patch integration.
- When workers return, review their changed paths and content before applying or accepting changes in the coordinator workspace.
- Integrate one chunk at a time, run focused validation after each integration, and resolve conflicts before integrating the next chunk.

### Git worktree mode

Use this mode when the user asks for worktrees, the repo is suitable for branch-based integration, or shell/git are available and the task benefits from isolated local branches.

- Create one sibling worktree per chunk.
- Require a clean integration branch before creating worktrees.
- Ask before overwriting existing worktrees or branches.
- Have workers commit locally but not push.
- Fold branches back by cherry-picking or merging one completed branch at a time.

### Serial fallback

Stop and recommend serial execution when:

- the work is mostly one file or one tightly coupled behavior
- chunk ownership cannot be made disjoint
- shared interfaces are unstable
- worker agents are unavailable
- the user wants only planning or review, not implementation

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
- selected execution mode: Codex app agent mode, git worktree mode, or serial fallback
- scaffold work that must land first
- chunk list with worker names, ownership, interfaces, and done-when checks
- branch/worktree names, only if using git worktree mode
- sequencing constraints inside the wave

If the spec did not pre-chunk the work:
- split only when boundaries are genuinely clean
- stop and recommend serial execution when the work is mostly one-file, tightly sequential, or interface-unstable

Confirm the plan with a concise direct question before dispatching workers or creating worktrees.

## Phase 3 - Preconditions

For Codex app agent mode:

- inspect the workspace enough to identify existing patterns and likely conflict zones
- check git status when shell/git are available, but do not block solely because the tree is dirty
- never revert or overwrite user changes
- stop and ask only when existing changes overlap a planned chunk or make integration ambiguous
- ensure each chunk has a disjoint write scope before dispatch

For git worktree mode, verify all of the following:

- inside a git repository
- the working tree is clean
- the current branch is the intended integration branch

Prefer `main` or `master`, but another local branch is acceptable if the user intends to fold all worker branches back there. If that intent is unclear, ask before proceeding.

Do not force state. In git worktree mode, if the repo is dirty or the target branch is unclear, stop and explain the blocker.

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

Do not dispatch workers until the scaffold passes, unless validation tooling is unavailable. If validation cannot run, state the gap in the worker prompt and in the final report.

In git worktree mode, commit the scaffold with a message that makes the locked contracts explicit. Workers should branch from this exact point.

In Codex app agent mode, do not commit solely for the swarm unless the user asked for commits. Keep scaffold edits in the coordinator workspace and include the locked interfaces in each worker prompt.

## Phase 5 - Prepare worker inputs

For each chunk in the chosen wave, prepare a concise `CHUNK.md`-style instruction from `references/chunk-template.md` containing only that chunk's relevant details.

In Codex app agent mode:

- no physical `CHUNK.md` file is required unless it helps coordination
- include the worker's exact file/module ownership in the prompt
- include known files that are out of scope
- include done-when checks and validation commands
- instruct the worker to edit files directly in its forked workspace and report changed paths

In git worktree mode:

- create a sibling worktree on its own branch, typically `codex/<chunk-name>`
- use a predictable sibling path such as `../<repo>-<chunk-name>`
- if a branch or worktree already exists, stop and ask instead of overwriting it
- ensure each worktree contains the scaffold commit
- write a `CHUNK.md` file into each worktree

## Phase 6 - Dispatch Codex workers

Dispatch one worker agent per chunk only because `swarm` is an explicit request for delegated parallel work.

Each worker prompt must include:
- the execution mode
- the worktree path and branch name, if using git worktree mode
- the coordinator workspace path, if useful for context
- exact ownership boundaries
- locked interfaces that must not change
- done-when checks
- the rule that the worker is not alone in the codebase and must not revert unrelated edits
- the requirement to report changed files and validation results
- in Codex app agent mode, the requirement to edit directly in the worker's forked workspace
- in git worktree mode, the requirement to commit finished work locally

Use worker agents for implementation. Keep the coordinator focused on integration readiness, validation strategy, and conflict risk.

## Phase 7 - While workers run

- do non-overlapping coordinator work locally
- inspect for integration risks across chunk boundaries
- avoid redundant implementation work
- use `wait_agent` sparingly; only wait when the next critical step depends on a worker result

## Phase 8 - Fold branches back

In Codex app agent mode, process one completed worker at a time:

1. read the worker's final report and changed path list
2. review the returned patch/content before integrating
3. apply or accept the worker changes into the coordinator workspace
4. run focused validation for that chunk
5. resolve conflicts or regressions before touching the next chunk
6. record any manual coordinator edits made during integration

If a worker cannot provide an applicable patch or changed files are unavailable, ask that worker for a focused diff or implementation summary before redoing any work locally.

In git worktree mode, process one completed chunk at a time:

1. verify the worker branch is committed and the worktree is clean
2. fold commits back into the integration branch, preferably by cherry-picking the branch's ahead commits in order
3. run the relevant validation after each fold
4. if conflicts occur, stop and resolve them before touching the next branch
5. once folded successfully, remove the worktree and delete the branch

Do not batch-fold multiple branches at once. Keep the integration branch clean between folds.

## Phase 9 - Record execution

Append an execution note to the spec:

- wave-based spec, Codex app mode: `_Wave N executed YYYY-MM-DD: workers chunk-a, chunk-b_`
- wave-based spec, git mode: `_Wave N executed YYYY-MM-DD: branches branch-a, branch-b_`
- single-wave spec, Codex app mode: `_Executed YYYY-MM-DD: workers chunk-a, chunk-b_`
- single-wave spec, git mode: `_Executed YYYY-MM-DD: branches branch-a, branch-b_`

This note is the durable record of progress for the next `swarm` run.

## Ground rules

- Do not push, merge to remote, or modify remotes unless the user explicitly asks.
- Do not create commits unless the execution mode or user request calls for them.
- Do not change locked interfaces mid-wave without surfacing it as a spec change.
- Stop on conflicts rather than papering over them.
- Prefer explicit ownership over clever parallelism.
- If the plan is not actually parallel-safe, say so and keep the work serial.
