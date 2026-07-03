---
name: codex-review
description: A standalone adversarial PLAN-review loop where Claude Code (builder) and OpenAI Codex (read-only critic) tag-team an implementation plan before any code is written. Use this when you ALREADY have a plan or a clear idea and just want the cross-model stress-test - no requirements interview first. Claude drafts/loads the plan into PLAN.md, Codex reviews it in a read-only sandbox and returns VERDICT:APPROVED or VERDICT:REVISE, Claude revises and re-submits to the SAME Codex session (context preserved) until APPROVED or a configurable MAX_ROUNDS cap is hit. Human approves the converged plan before code. Use when the user says "/codex-review", "codex review my plan", "have Codex review my plan", "argue this plan with Codex", "adversarial plan review", "make Claude and Codex argue/fight over the plan", or is about to build something high-stakes (auth, schema, concurrency, migrations, payments) and wants a second-model sanity check on the PLAN before implementation. For a guided requirements interview BEFORE the review, use /grill-me-codex instead. NOT for reviewing already-written CODE (that is the Codex plugin's /codex:review) and NOT for trivial changes.
---

# Codex-Review - Adversarial Plan-Review Loop

Two models, one plan, a bounded argument. **Claude is the builder and orchestrator. Codex is a read-only critic** that can read the repo and the plan; its model-generated shell commands cannot modify a single repo file (the Codex CLI process itself still writes its own session state and the `-o` verdict file to known locations - those are not repo edits). They communicate strictly through `PLAN.md` + a Codex session that persists across rounds. The human enters at exactly two points: kickoff and final sign-off.

This is a **deliberate, high-stakes tool** - reach for it on auth, data models, concurrency, migrations, payments, anything expensive to get wrong. Skip it for obvious/cheap work.

## Prerequisites (verify once, fast)

- Codex CLI installed and recent: `codex --version`. Verified end-to-end on codex-cli 0.142.5, the floor this skill assumes - the `features.use_legacy_landlock` override below is only confirmed there (≥ 0.130 is needed just for the `gpt-5.5` default model). Preflight the override on older CLIs and do NOT silently downgrade the sandbox if the key is rejected; stop and surface it.
- Codex authenticated: a prior `codex login` (ChatGPT account is fine). If a run returns an auth/model error, surface it to the user - do not silently retry.
- Do NOT pin `-m` unless the user asks. The user's `~/.codex/config.toml` default model is used. Pinning `gpt-5.x-codex` variants fails on ChatGPT-account auth.
- **The read-only sandbox MUST use the legacy Landlock backend, or it cannot initialize when nested.** Codex's default Linux sandbox is bubblewrap, which always runs `bwrap --unshare-net`. Nested inside another sandbox (a Claude Code session, a treehouse/git-worktree dev box, most CI) that fails with `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. A failed sandbox means Codex cannot run ANY shell command - so it never reads the plan or the repo and silently falls back to its stale GitHub-indexed view, producing a confident but uninformed verdict. Force the older Landlock+seccomp backend with `-c features.use_legacy_landlock=true` on EVERY call. It enforces the SAME security properties as the bubblewrap read-only sandbox, both verified in this nested environment: Codex's writes fail with `Permission denied`, AND its network is blocked (an in-sandbox `curl https://example.com` cannot even resolve DNS, while the ambient shell gets HTTP 200). Landlock+seccomp achieves the network block via seccomp syscall filtering instead of a network namespace, which is exactly why it initializes when nested and bubblewrap does not. This knob targets the Linux sandbox; macOS uses a different sandbox (Seatbelt) and this skill has not been verified there - treat macOS as untested, not guaranteed-inert.
- **Never "fix" a sandbox error by removing the sandbox.** `--dangerously-bypass-approvals-and-sandbox` and `-s danger-full-access` both make Codex able to READ - but they also let it WRITE files (verified: it created a file on demand), which destroys the read-only guarantee that is the whole point of this skill. The legacy-landlock backend is the correct fix; those flags are not.
- **Sandbox flag differs between the two commands.** `codex exec` accepts `-s read-only`. `codex exec resume` does NOT - it rejects `-s` ("unexpected argument"), and likewise rejects `-C`/`--cd` (`cd` into the repo root before resuming instead). On resume you MUST force read-only via `-c sandbox_mode="read-only"`, because `config.toml` may default `sandbox_mode` to `danger-full-access` (+ `approval_policy="never"`) - which would let Codex WRITE files mid-loop. Pair it with the same `-c features.use_legacy_landlock=true`. This pair (read-only + legacy landlock) is the single most important safety detail in this skill: verified end-to-end on 2026-07-03.
- **Close stdin on every call (`</dev/null`).** Run non-interactively, `codex exec` blocks forever on "Reading additional input from stdin..." - when a prompt arg AND a piped stdin are both present it waits to append stdin as a `<stdin>` block, and a harness pipe never sends EOF. Redirect `</dev/null` so it always returns.

## Tunable variables (read from skill args, else default)

| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates at this. |
| `PLAN_FILE` | `PLAN.md` | Where the evolving plan lives (repo root). |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only transcript of the argument (every round's critique + what changed). The artifact. |

If the user invoked the skill with an argument like `rounds=3`, use that for `MAX_ROUNDS`. Echo the resolved values back before starting.

### Scratch files are per-worktree (no cross-session collision)

`PLAN_FILE` and `LOG_FILE` live at the repo root, which git already isolates per worktree - two treehouse instances have two different roots, so they never share a plan or log. But the Codex prompt + verdict scratch files must NOT be a shared hardcoded path like `/tmp/codex-verdict.txt`: concurrent sessions would then read/clobber each other's verdicts (one session "seeing another session's command"). Resolve the repo root once and derive a scratch dir keyed by it. The key stays deterministic, so recompute this inline in each fresh shell rather than relying on a variable surviving between calls:

```bash
REPO_ROOT="$( git rev-parse --show-toplevel 2>/dev/null || pwd )"
CR_DIR="${TMPDIR:-/tmp}/codex-review-$( printf '%s\n%s\n' "$REPO_ROOT" "${CLAUDE_CODE_SESSION_ID:-}" | cksum | cut -d' ' -f1)"
mkdir -p "$CR_DIR"
```

Write the review prompt to `$CR_DIR/prompt.txt` and capture each round's verdict at `$CR_DIR/verdict.txt`. The key folds in both the worktree root (so two treehouse instances never share) and `$CLAUDE_CODE_SESSION_ID` (so two concurrent Claude sessions never share, even in one worktree). If that env var is empty (running outside Claude Code), the key falls back to worktree-only, so in that case keep to one review per worktree at a time. `cksum` is chosen over `sha256sum` because it exists on both Linux and macOS. Run every Codex call from the repo root (`cd "$REPO_ROOT"` first) so a plan written at the repo root is found even when the skill is invoked from a subdirectory. (`codex exec` also accepts `-C DIR`, but `codex exec resume` rejects it - verified - so `cd` is the one portable way to set the working dir for both.) Never use `codex exec resume --last` here - it would pick up the most recent session globally, i.e. another worktree's thread; always resume the explicit `$THREAD_ID`. (Two runs in the SAME session and worktree would still share `PLAN_FILE`/`LOG_FILE`; that is inherent - run one review per worktree at a time.)

## Flow

### Step 0 - Kickoff (human gate #1)

The invocation itself is the kickoff. Confirm scope in one line: what is being planned. If the user gave no task, ask for it (one question). Then proceed - do NOT ask for approval round-by-round; that comes at the end.

### Step 1 - Claude plans

Do real planning: read the relevant code, think through the approach, surface decisions and tradeoffs. Then write the plan to `PLAN_FILE` in this structure:

```markdown
# Plan: <task>
_Round 0 - initial draft by Claude_

## Goal
<one paragraph>

## Approach
<numbered steps, concrete>

## Key decisions & tradeoffs
<the contestable choices - name them explicitly so Codex has something to bite>

## Risks / open questions
<what you're unsure about>

## Out of scope
<bounds>
```

Initialize `LOG_FILE`:
```markdown
# Plan Review Log: <task>
Started <stamp the user's local time if known, else "session start">. MAX_ROUNDS=<n>.
```

Show the user the plan inline and say you're sending it to Codex for adversarial review.

### Step 2 - The loop

Maintain `ROUND` (start 1) and `THREAD_ID` (empty until round 1 returns). Resolve `CR_DIR` (above) first and write the review prompt to `$CR_DIR/prompt.txt`.

**The review prompt** written to `$CR_DIR/prompt.txt` (adjust the task line):

> You are an adversarial reviewer for an implementation plan. Be skeptical and specific - your job is to find what breaks, not to be agreeable. Read the plan at `$PLAN_FILE` (substitute the resolved filename, default `PLAN.md`) and any repo files you need; you are read-only. Identify concrete flaws: security holes, race conditions, missing edge cases, schema conflicts, wrong assumptions, observability gaps, simpler alternatives. For each, give a one-line fix. Do NOT modify any files. End your reply with EXACTLY one line: `VERDICT: APPROVED` if the plan is sound enough to implement, or `VERDICT: REVISE` if it still has material problems.

**Round 1** (creates the session - capture `thread_id`):

```bash
rm -f "$CR_DIR/verdict.txt"                         # never let a stale verdict from a prior/failed round be read as fresh
cd "$REPO_ROOT" && codex exec -s read-only -c features.use_legacy_landlock=true --json \
  -o "$CR_DIR/verdict.txt" \
  "$(cat "$CR_DIR/prompt.txt")" \
  </dev/null 2>"$CR_DIR/err.txt" >"$CR_DIR/stream.jsonl"
CODEX_RC=$?
THREAD_ID="$(grep -o '"thread_id":"[^"]*"' "$CR_DIR/stream.jsonl" | head -1 | cut -d'"' -f4)"
test "$CODEX_RC" -eq 0 && test -n "$THREAD_ID" && test -s "$CR_DIR/verdict.txt" \
  || { echo "ROUND 1 FAILED (exit=$CODEX_RC thread='$THREAD_ID') - inspect $CR_DIR/err.txt; STOP, do not trust any verdict" >&2; exit 1; }
echo "THREAD_ID=$THREAD_ID"
```
`THREAD_ID` is captured by the snippet above (empty capture is treated as a failure). The critique text lands in `$CR_DIR/verdict.txt` (Codex's last message); read that file.

> Note: stderr (cosmetic MCP/auth noise on some setups, plus any real error) is captured to `$CR_DIR/err.txt`, not discarded - inspect it whenever a round fails its success check. Success = exit 0 + a non-empty captured `THREAD_ID` + a fresh non-empty verdict; if any is missing the run failed (auth/model/sandbox), so stop and tell the user.
>
> **Sanity-check that Codex actually read the LOCAL repo.** If the verdict text says it is blocked, mentions `bwrap`/`sandbox`/`loopback`/`Operation not permitted`, says it "could not read" the plan, or reviews the repo via GitHub / a connector / "the indexed version" instead of the local file, then the sandbox failed to initialize and the verdict is worthless - stop and report it (this is exactly what `-c features.use_legacy_landlock=true` prevents; confirm the flag is present). A strong positive signal it read locally: the critique cites exact file:line locations for your uncommitted changes, which are absent from any GitHub view. Do NOT continue the loop on a fallback verdict.

**Rounds 2..MAX** (resume the SAME session - Codex remembers its earlier critiques, won't re-litigate settled points):

```bash
# resume rejects -s AND -C: force read-only via -c sandbox_mode (else Codex
# inherits config.toml, possibly danger-full-access, and could WRITE files),
# and cd into the repo root instead of passing --cd. Same legacy-landlock
# backend so the read-only sandbox initializes when nested.
rm -f "$CR_DIR/verdict.txt"                         # stale-verdict guard, same as round 1
cd "$REPO_ROOT" && codex exec resume "$THREAD_ID" \
  -c sandbox_mode="read-only" -c features.use_legacy_landlock=true --json \
  -o "$CR_DIR/verdict.txt" \
  "I revised $PLAN_FILE. Re-review it and any changed files. Same rules. End with VERDICT: APPROVED or VERDICT: REVISE." \
  </dev/null 2>"$CR_DIR/err.txt" >"$CR_DIR/stream.jsonl"
test "$?" -eq 0 && test -s "$CR_DIR/verdict.txt" \
  || { echo "RESUME FAILED - inspect $CR_DIR/err.txt; STOP, do not trust any verdict" >&2; exit 1; }
```

Both `codex exec` and `codex exec resume` support `--json` (stream -> parse `thread_id` first round) and `-o/--output-last-message` (verdict capture).

**Each round, after Codex returns:**
1. Confirm the call actually succeeded before trusting it: exit 0, a freshly written non-empty `$CR_DIR/verdict.txt` (it was `rm`-ed just before the call, so a non-empty file proves THIS round produced it - not a leftover), and on round 1 a non-empty `THREAD_ID`. The snippets above already `exit 1` on failure; never fall through to a stale verdict.
2. Require a WELL-FORMED verdict before acting: the last non-blank line of `$CR_DIR/verdict.txt` must be exactly `VERDICT: APPROVED` or `VERDICT: REVISE`. Anything else (truncated/garbled output, missing verdict line) is malformed - stop and report, do not guess a verdict.
   ```bash
   verdict_line="$(grep -v '^[[:space:]]*$' "$CR_DIR/verdict.txt" | tail -1)"
   case "$verdict_line" in
     "VERDICT: APPROVED"|"VERDICT: REVISE") echo "verdict: $verdict_line" ;;
     *) echo "MALFORMED verdict (last non-blank line: '$verdict_line') - STOP" >&2; exit 1 ;;
   esac
   ```
3. Append to `LOG_FILE`: `## Round <n> - Codex` + the full critique. Then branch on `$verdict_line`:
   - `VERDICT: APPROVED` -> break the loop, go to Step 3 (converged).
   - `VERDICT: REVISE` -> Claude reads the critique, decides **what's actually worth acting on** (Claude has final say - Codex advises, it does not command). Revise `PLAN_FILE`. Append to `LOG_FILE`: `### Claude's response` + what you changed and what you rejected and why. Increment `ROUND`.
4. If `ROUND > MAX_ROUNDS` -> break to Step 3 (deadlock).

### Step 3 - Resolution (human gate #2)

**If APPROVED:** Present to the user - the final `PLAN_FILE`, a 3-bullet summary of what the argument improved, and the round count. Ask: *"Plan survived N rounds of Codex. Implement it now?"* Only on a yes does Claude write code. **No code is written during the loop.**

**If MAX_ROUNDS hit without APPROVED (deadlock):** Do NOT pretend it converged. Surface the unresolved disagreements explicitly: list each point Codex still flags and Claude's counter-position. Hand it to the human to break the tie. This is a legitimate, useful outcome - a flagged disagreement beats a false "approved."

## Hard rules

- Codex is read-only EVERY round - `-s read-only` for the first call, `-c sandbox_mode="read-only"` for every resume (resume has no `-s`), plus `-c features.use_legacy_landlock=true` on both so the read-only sandbox actually initializes when nested (this backend enforces both a read-only filesystem and a blocked network, verified). It never writes repo files. If you're tempted to give it write access, stop - that's a different skill.
- Clear `$CR_DIR/verdict.txt` before every call and require exit 0 + a fresh non-empty verdict after it; a suppressed error must never let a stale verdict pass as this round's result.
- Never bypass the sandbox to work around a `bwrap`/loopback error. `--dangerously-bypass-approvals-and-sandbox` and `-s danger-full-access` grant WRITE access (verified). The legacy-landlock backend is the correct, read-only-preserving fix.
- Scratch files (prompt + verdict) live in the per-worktree `$CR_DIR`, never a shared hardcoded `/tmp` path, so concurrent worktree sessions cannot collide. Resume the explicit `$THREAD_ID`, never `--last`.
- The loop ALWAYS terminates at `MAX_ROUNDS`. No unbounded recursion.
- Claude is the final arbiter on every REVISE - incorporate good critiques, reject bad ones *with a reason logged*. Don't cave to Codex on everything (that defeats the cross-model check) and don't ignore it (that defeats the point).
- Code only after human gate #2.
- `LOG_FILE` is the deliverable - it tells the whole story of the argument. Keep it complete.

## What NOT to do

- Don't use this to review existing code - that's `/codex:review`.
- Don't pin a `-codex` model variant on ChatGPT-account auth - it 400s.
- Don't skip the log - the argument transcript is the most valuable artifact.
- Don't let Codex edit files. Read-only, always - and verify it actually read the local repo, not a stale GitHub view.
