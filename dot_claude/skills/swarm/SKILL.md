---
name: swarm
description: "Execute a spec in parallel git worktrees, one wave at a time. Scaffolds the foundation serially in the current session, dispatches leaf chunks to parallel Claude agents via tmux, then walks the user through folding each branch back into trunk. Triggers on: 'swarm', 'swarm this', 'parallelize this', 'dispatch swarm', 'run in parallel worktrees', 'execute this spec', 'scaffold and fan out', 'run wave N', 'fan out the work'. Takes optional $1 = path to spec file (defaults to ./SPEC.md). Use /spec first to write the spec; use this skill to execute it."
---

You orchestrate parallel work across git worktrees using the user's fish commands (`ga`, `gwa`, `gwc`, `gwf`, `gwr`, `gwra`, `tsl`, `tslw`, `tslwm`, `tdl`, `tdlm`). You are the **coordinator**: you do the serial scaffold work in this session, spawn other Claude agents in tmux panes/windows to do leaf work in parallel, then walk the user through folding each branch back.

Consult `references/commands.md` whenever you need to pick a command — don't guess at behavior or flags.

This skill supports two **delivery modes**, declared per-spec:

- **solo-local** (default) — fold each wave's work directly onto trunk. No remotes, no PRs. The flow documented inline below.
- **fork-pr** — each wave lands on its own branch, gets pushed to a fork, and is reviewed via PR upstream. Phases 1.5, 3.5, and 8.5 are fork-only and live in `references/fork-mode.md`. Read that file in full before doing fork-mode work.

The term **integration branch** is used throughout. In solo mode it's trunk. In fork mode it's the wave branch. Substitute accordingly.

## Phase 1 — Load the spec

Read `$1` if given, else `./SPEC.md`. If neither exists, tell the user to run `/spec` first and stop.

### 1a — Pick a wave

Look for a **Waves** section in the spec.

- **If waves are present** (the primary path): scan for completion markers. The canonical form is `_Wave N executed YYYY-MM-DD: ..._` (italic, written by Phase 10) but accept reasonable variants — optional underscores, and any of `executed|done|completed|finished|shipped` for the verb. If a line mentions "Wave N" but matches neither the canonical nor the permissive form, **stop and surface it to the user** — silently ignoring is the failure mode where you re-execute already-completed work.

  Filter completed waves out. Of what remains: if exactly one un-executed wave is left, proceed with it directly (no prompt — there's nothing to ask). If multiple remain, offer the first via `AskUserQuestion`. Use the chosen wave's chunks and scaffold verbatim; do not re-chunk.
- **If no waves section**: treat the spec as one wave. You'll need to analyze parallelizability yourself in the next phase.

### 1b — Resolve delivery mode

Look for an `## Execution` section in the spec. Parse it line-by-line, splitting each line on the first `:` into a key/value pair. Apply these tolerance rules:

- **Case-insensitive keys** — `Delivery mode`, `delivery mode`, `DELIVERY MODE` all match.
- **Whitespace-lenient** — accept any amount of whitespace around `:`, trim values.
- **Ignore unknown keys and free text** — only known `Key: value` lines count.
- **First match wins** — if a key appears twice, take the first and warn.

Then:

- If `Delivery mode: solo-local` is present → solo mode. Continue with this file.
- If `Delivery mode: fork-pr` is present → fork mode. Read `references/fork-mode.md` now, then come back. Don't ask about other fork-mode fields yet (remotes, base strategy) — those are deferred to the phases that need them.
- If the section is missing or `Delivery mode:` is absent → `AskUserQuestion` for delivery mode only:
  - `solo` (current behavior; fold to trunk)
  - `fork` (wave branches; opt-in push/PR — see references/fork-mode.md)

  After the user answers, write a minimal `## Execution` section with `Delivery mode: <answer>` back into the spec so subsequent invocations skip this question. **Place it before `## Waves` and after the spec's meta sections (Why/Stack/Interfaces/Verification/etc.)** — not at the bottom of the file, since the bottom is reserved for Phase 10's wave annotations.

  Commit the spec edit immediately as its own commit (e.g. `spec: declare delivery mode (<answer>)`) before advancing to Phase 3 — Phase 3's working-tree-clean check needs the edit committed, not lingering as an unstaged change. Surface the write in plain text ("Updated SPEC.md → set Delivery mode: solo-local; committed as <sha>").

Also parse `Dispatch:` from the same `## Execution` section, with the same tolerance rules:

- `Dispatch: tmux` (default) — current behavior; spawn Claude CLI sessions in tmux panes via `tslw`/`tslwm`.
- `Dispatch: agents` — experimental; use Claude Code's Agent fork feature with `isolation: "worktree"`. Replaces Phases 5–7 with the flow in `references/agents-dispatch.md`. Read that file now if this is the chosen mode.

If `Dispatch:` is absent from `## Execution`, default to `tmux` silently — do not prompt. The default is backward-compatible with every spec written before this option existed. Only ask the user if they explicitly want to switch.

The remaining phases are written in solo-mode terms with notes for fork mode. **Solo mode is byte-identical to the previous version of this skill.**

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
- Working tree clean: `git status --porcelain` is empty
- Starting branch is appropriate for the mode:
  - **solo**: on trunk (`main`, `master`, or whatever `git symbolic-ref refs/remotes/origin/HEAD` resolves to; fall back to asking if unclear).
  - **fork**: on trunk OR on the wave-base branch resolved in Phase 1.5 (see `references/fork-mode.md`). The wave branch itself doesn't exist yet; it's created in Phase 3.5.

If any fail, explain what's wrong and stop. Do not force state.

In fork mode, the next step is Phase 3.5 (create the wave branch) before scaffolding — see `references/fork-mode.md`.

## Phase 4 — Build the scaffold in this session

You (the coordinator) write the scaffold files yourself. The other agents aren't running yet — this is all you.

- Write the workspace/package manifest, shared types, interface contracts, stub modules for each chunk, CI.
- Run a build check. If the spec gives an explicit one (e.g. a "build/typecheck command for scaffold gate" line under Stack), use that. Otherwise fall back to the stack's standard fast-fail check — e.g. `cargo check --workspace` (Rust), `tsc --noEmit` (TypeScript), `bun run typecheck` (Bun), `go build ./...` (Go), `uv run mypy src/ && uv run pytest -q` (Python with uv). **Do not proceed if it fails.** Fix and re-check.
- Commit with a clear message describing what contracts were locked. Example: `scaffold: lock SttEngine + LlmProvider + Recorder + … contracts`.

The scaffold commit lands on the integration branch — trunk in solo mode, the wave branch in fork mode (since Phase 3.5 already checked it out). Either way, it's load-bearing: every parallel chunk imports from it. Nail it down before dispatch.

In fork mode, this means trunk is **not** modified — it stays at upstream's HEAD until the PR merges upstream.

## Phase 5 — Preconditions for dispatch

**If `Dispatch: agents` was resolved in Phase 1b, stop reading here and follow `references/agents-dispatch.md` for Phases 5–7. Resume this file at Phase 8.** The rest of this section is the `Dispatch: tmux` (default) flow.

Verify:
- `$TMUX` is set (inside a tmux session)
- The scaffold commit you just made is HEAD on the integration branch (trunk in solo mode, the wave branch in fork mode)
- Working tree still clean

If any fail, explain what's wrong and stop. Do not force state — don't `tmux new-session` to manufacture a session, don't ignore a dirty tree, don't reset HEAD.

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
   Send to each pane individually and verify each got the command before moving on. `tmux send-keys` doesn't error when a pane ID is stale or wrong — it just silently does nothing — so per-pane verification is how you catch a missed dispatch.

Report the pane/window IDs and worktree paths so the user can navigate.

## Phase 7 — Watch for completion

Each chunk agent writes `<worktree>/.swarm-done` when it finishes (per the CHUNK.md template), or `<worktree>/.swarm-blocker` if it stops on a blocker. The coordinator uses `Monitor` to stream these as they appear — no manual polling, no waking up to check.

Build the watcher from the worktree paths you already know (from Phase 6). For each branch, the path is `<parent>/<repo>--<branch>`. Then arm a single `Monitor` call:

```bash
PATHS=(
  "<parent>/<repo>--<branch1>"
  "<parent>/<repo>--<branch2>"
  ...
)

remaining=("${PATHS[@]}")
while (( ${#remaining[@]} > 0 )); do
  next=()
  for p in "${remaining[@]}"; do
    if [ -f "$p/.swarm-done" ]; then
      echo "DONE: $p"
    elif [ -f "$p/.swarm-blocker" ]; then
      echo "BLOCKED: $p — $(head -1 "$p/.swarm-blocker")"
    elif [ ! -d "$p" ]; then
      echo "MISSING: $p (worktree disappeared)"
    else
      next+=("$p")
    fi
  done
  remaining=("${next[@]}")
  (( ${#remaining[@]} > 0 )) && sleep 5
done
echo "ALL_DONE"
```

Call `Monitor` with this command and a description like "swarm wave N completion". You'll get one notification per chunk as it transitions, and `ALL_DONE` when the wave is finished.

**Pick the deadline based on the longest chunk in the wave:**

- **Default (≤1h expected):** `timeout_ms: 3600000`, `persistent: false`. The 1h cap is a backstop — if every chunk hangs silently, you still get woken up to surface it.
- **Long-running (model training, large dataset processing, multi-hour builds, anything open-ended):** `persistent: true`. `Monitor`'s max `timeout_ms` is 3600000, so anything longer than an hour must use persistent mode. The watcher still exits cleanly on `ALL_DONE`; persistent only matters if the script never exits on its own (i.e. some chunk hangs without writing a sentinel). If the user abandons the wave, `TaskStop` the monitor.

If you're not sure which bucket the wave falls into, ask the user once via `AskUserQuestion` ("Longest expected chunk runtime: under 1h / over 1h?") rather than guessing — the cost of a bad guess is either a premature timeout or a watcher that needs manual `TaskStop`.

**Coverage caveat.** Silence is not success. A chunk agent can hang or hit an internal error without writing either sentinel — the watcher will stay silent for that path. The user is still watching the panes for visible failures; if they say "kill chunk X, it's stuck", drop X from the watcher (restart Monitor with X removed from `PATHS`, or just `touch <X-path>/.swarm-done` to satisfy it) and proceed.

If `MISSING` or `BLOCKED` fires, surface it to the user immediately — don't wait for `ALL_DONE`. They decide whether to fold the partial branch, retry, or abandon.

If the user explicitly tells you a chunk is done before its sentinel arrives (e.g. they're folding manually), that overrides the watcher — proceed with Phase 8 for that branch and let the watcher continue for the rest. You may still inspect a worktree on user request, but do not steer sub-agents.

## Phase 8 — Fold back

When the user says chunks are done, walk through each branch **one at a time**. For each, ask via `AskUserQuestion`:

- **Apply only** — keep the worktree for inspection
- **Full fold** — apply + stage + remove worktree + delete branch
- **Skip** — leave this one for later

**Primitive choice:** swarm agents commit their work (per the CHUNK.md template), so the default fold primitive is **`gwc`** (git-worktree-cherry-pick). It cherry-picks every commit on the chunk branch that is ahead of the main worktree's currently-checked-out branch — i.e. the integration branch — preserving each commit's message as its own entry on the integration branch. Fall back to `gwa` only if the agent left work uncommitted — `gwa` only applies the uncommitted diff and will say "Nothing to apply" on a committed branch.

In fork mode, make sure the main worktree has the wave branch checked out before running `gwc`. The fish helpers don't hardcode `main` — they target whatever HEAD is.

**If the chunk's pane was closed before fold-back**, that's not a problem — `gwc` cherry-picks from the branch, not the pane. The branch and worktree typically still exist on disk; verify with `git -C <main> rev-parse <branch>` if uncertain. If the worktree was also removed (e.g. user ran `gwr` manually), the branch alone is sufficient for `gwc`. If the branch itself is gone, that work is lost — surface this and stop rather than guessing.

**Critical:** `gwf`, `gwr`, and `gwra` all use `gum confirm`, which blocks on stdin. You cannot answer it from the Bash tool — the command will hang. `gwa` and `gwc` do not use gum and are safe to run. So:

- **Apply only** → run `gwc <branch>` (committed) or `gwa <branch>` (uncommitted).
- **Full fold** → do the steps manually (no gum). From the main repo root (`cd` into it first):
  ```
  gwc <branch>                              # cherry-pick commits onto integration branch
  # OR: gwa <branch>                        # for uncommitted work (also stages copied untracked files)
  git -C <main> worktree remove <path> --force
  rmdir -p "$(dirname <path>)" 2>/dev/null || true  # cleans up intermediate parent dirs from slashed branch names (e.g. swarm/foo-wave-2 → <repo>--swarm/foo-wave-2)
  git -C <main> branch -D <branch>
  ```
  Where `<path>` is `<parent>/<repo>--<branch>`. Also kill any tmux panes whose `pane_current_path` starts with that worktree path:
  ```
  tmux list-panes -a -F "#{pane_id} #{pane_current_path}" \
    | awk -v p="<path>" '$2==p || index($2,p"/")==1 {print $1}' \
    | xargs -r -n1 tmux kill-pane -t
  ```

**On conflict** (either `gwc`'s cherry-pick or `gwa`'s `--3way` fallback leaves markers): stop immediately. Print the conflicted files. Resolve in the main repo, then `git cherry-pick --continue`. For lockfile conflicts (common when parallel chunks each add deps), the pattern is `git checkout --ours <lockfile>` → regenerate via the stack's resolver → `git add <lockfile>` → `--continue`; see `references/commands.md` for the per-stack regenerate command. **Do not advance to the next branch until the current state is clean.** Check with `git -C <main> status --porcelain`.

In fork mode, after Phase 8 completes successfully, continue to Phase 8.5 (push and open PR) — see `references/fork-mode.md`. In solo mode, skip Phase 8.5 and go straight to Phase 9.

## Phase 9 — Cleanup

After all branches are folded or skipped, ask the user whether to sweep remaining swarm worktrees. Again, `gwra` blocks on `gum confirm` — do it manually:

```
git -C <main> worktree list --porcelain
```

Parse for `worktree <path>` entries whose path matches `<parent>/<repo>--*` (excluding the main worktree itself). For each match: `git worktree remove --force <path>` + `rmdir -p "$(dirname <path>)" 2>/dev/null || true` (cleans up intermediate parent dirs created when branch names contain `/`, e.g. `swarm/foo-wave-2-bar` → `<repo>--swarm/foo-wave-2-bar`; rmdir -p walks up and stops at the first non-empty parent, so it's safe) + `git branch -D <branch>`. Kill lingering tmux panes the same way as Phase 8.

Confirm the list with the user before removing — show them the paths and branches you're about to delete.

**Wave branches are preserved**, never swept. They live in the main worktree (just `git checkout`ed there), so they're already excluded by the `<parent>/<repo>--*` filter — no special-casing needed. Their PR may still be open and depending on the branch.

## Phase 10 — Record the wave

Append a one-line note to the spec file. The format depends on delivery mode:

- **solo**:
  ```
  _Wave {{N}} executed {{YYYY-MM-DD}}: branches {{comma-separated list}}_
  ```
- **fork**:
  ```
  _Wave {{N}} executed {{YYYY-MM-DD}} on branch {{wave-branch}}; chunks {{list}}; PR {{url-or-"not pushed"}}_
  ```

Use today's date (from the environment context). This is per-run history — on the next `/swarm` invocation, this note is how you know which wave to offer next.

The annotation lives at the bottom of the spec, **not** inside the `## Execution` section. Execution captures durable preferences; annotations capture per-run history. Don't conflate them.

If the spec had no Waves section, append instead:

```
_Executed {{YYYY-MM-DD}}: branches {{list}}_
```

## Ground rules

- **You don't merge.** Even in fork mode, opening a PR is the boundary — merging is the human's decision upstream.
- **You push only with explicit confirmation, only in fork mode, and only the wave branch.** Chunk branches are never pushed by this skill. Solo mode never pushes anything.
- **You never `--force` push.** If a push is rejected, surface the output and let the user diagnose.
- **You don't skip hooks** (no `--no-verify`). If a commit hook fails during the scaffold, fix the underlying issue.
- **You stop on conflict.** Never pass `-Xtheirs` or similar to paper over a 3way conflict.
- **You do not unilaterally edit locked interfaces.** If a chunk turns out to need a different signature mid-dispatch, that's a spec change — stop and surface it.
- **The human is the clock.** You don't poll agents, don't time out chunks, don't retry. The user drives when each phase advances.
