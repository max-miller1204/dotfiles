---
name: claude-review
description: A standalone adversarial PLAN-review loop where Codex (builder) and Claude Code (read-only critic) tag-team an implementation plan before any code is written. This is the mirror of the codex-review skill for when Codex is your main agent and you want Claude as the second-model reviewer. Use it when you ALREADY have a plan or a clear idea and just want the cross-model stress-test - no requirements interview first. Codex drafts/loads the plan into PLAN.md, Claude reviews it in a read-only (plan-mode) session and returns VERDICT:APPROVED or VERDICT:REVISE, Codex revises and re-submits to the SAME Claude session (context preserved) until APPROVED or a configurable MAX_ROUNDS cap is hit. Human approves the converged plan before code. Use when the user says "claude-review", "$claude-review", "claude review my plan", "have Claude review my plan", "argue this plan with Claude", "adversarial plan review with Claude", "make Codex and Claude argue/fight over the plan", or is about to build something high-stakes (auth, schema, concurrency, migrations, payments) and wants a second-model sanity check on the PLAN before implementation. NOT for reviewing already-written CODE and NOT for trivial changes.
---

# Claude-Review - Adversarial Plan-Review Loop

Two models, one plan, a bounded argument. **Codex is the builder and orchestrator. Claude Code is a read-only critic** that can read the repo and the plan but cannot modify a single file. They communicate strictly through `PLAN.md` + a Claude session that persists across rounds. The human enters at exactly two points: kickoff and final sign-off.

This is the mirror of the `codex-review` skill: there Claude builds and Codex critiques; here **you (Codex) build and Claude critiques.** Reach for it on the same high-stakes work - auth, data models, concurrency, migrations, payments, anything expensive to get wrong. Skip it for obvious/cheap work.

## How Claude's read-only guarantee differs from Codex's (read this)

The `codex-review` skill spends most of its prerequisites fighting an OS-level sandbox: Codex's read-only mode is `bwrap`/Landlock, which fails to initialize when nested and then silently falls back to a stale GitHub-indexed view. **Claude has none of that machinery and none of that failure mode.** Claude's read-only guarantee is enforced by its own permission system in-process (`--permission-mode plan`), not by an OS namespace, so there is nothing to fail-to-initialize when nested, and Claude reads the LOCAL working tree directly through its Read/Grep tools - it has no GitHub-index fallback to drift to. So this skill is simpler than its mirror. The one real failure mode to guard is auth/billing (below), which the per-round success check catches.

## Prerequisites (verify once, fast)

- Claude Code CLI installed and recent: `claude --version`. Verified end-to-end on 2.1.206, the floor this skill assumes.
- Authenticated: `claude auth status` should show `"loggedIn": true`. A claude.ai subscription login (Max/Pro) or an API key with credit both work. If a run returns an auth/model error, surface it to the user - do not silently retry.
- **Auth precedence gotcha - the one thing that will actually break this.** If `ANTHROPIC_API_KEY` (or `ANTHROPIC_AUTH_TOKEN`) is set in the environment, it OVERRIDES the claude.ai subscription login. If that key is stale or has no credit, EVERY review fails with `.is_error == true` and `.result == "Credit balance is too low"` (verified). The per-round success check catches this and stops. To fall back to the subscription login, run the `claude` calls with the key stripped: `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude -p ...`. Do NOT force-unset unconditionally if the user deliberately uses their API key - only strip it when you hit the billing error and `claude auth status` (with the key unset) shows a valid subscription login.
- **Read-only is `--permission-mode plan`, and it is not optional.** In plan mode Claude may Read/Grep/Glob and run read-only shell, but every mutating action (Write, Edit, and any file-mutating Bash) is blocked in-process. Verified: asked in one turn to read a file AND create `BREACH.txt`, Claude read the file and refused the write - no file was created, and it reported "I'm currently in plan mode, which permits only read-only actions." Re-pass `--permission-mode plan` on EVERY call, resumes included.
- **Never "fix" a permission denial by adding `--dangerously-skip-permissions` or `--permission-mode bypassPermissions`/`acceptEdits`.** Those let Claude WRITE files, which destroys the read-only guarantee that is the whole point of this skill. Plan mode is the correct read-only mode; those flags are not.
- Do NOT pin `--model` or `--effort` unless the user asks. Use the user's claude defaults, exactly as the mirror skill leaves Codex's model unpinned. (Higher effort makes a sharper but slower critique; a round can take 30-90s, which is fine for a deliberate high-stakes review.)
- `--output-format json` is required: it returns a single JSON object where `.result` is Claude's final message (the critique), `.is_error` is the success gate, and `.session_id` is the thread to resume. Parse it with `jq` (a native bootstrap dependency, always on PATH here).
- **`--session-id <uuid>` must be a FRESH, unused UUID.** It fixes the session id so you can resume it. Reusing an id errors `Session ID <uuid> is already in use` (verified) - so generate a new one per review with `uuidgen` and never hardcode it.
- **Resume with `claude -p --resume <uuid>` continues the SAME session with full prior context** (verified: on resume Claude recalled earlier file content without re-reading it). `--resume` takes no fresh `--session-id`; just re-pass `--permission-mode plan` to keep it read-only. Do NOT pass `--fork-session` (that would branch a new thread and lose the shared argument).
- **Close stdin on every call (`</dev/null`).** Run non-interactively without it and a harness pipe can leave `claude -p` waiting on stdin. Redirect `</dev/null` so it always returns.

## Tunable variables (read from skill args, else default)

| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates at this. |
| `PLAN_FILE` | `PLAN.md` | Where the evolving plan lives (repo root). |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only transcript of the argument (every round's critique + what changed). The artifact. |

If the user invoked the skill with an argument like `rounds=3`, use that for `MAX_ROUNDS`. Echo the resolved values back before starting.

### Scratch files are per-worktree (no cross-session collision)

`PLAN_FILE` and `LOG_FILE` live at the repo root, which git already isolates per worktree - two worktrees have two different roots, so they never share a plan or log. The Claude prompt + verdict scratch files must NOT be a shared hardcoded path like `/tmp/claude-verdict.txt`: concurrent sessions would then read/clobber each other's verdicts. Resolve the repo root once and derive a scratch dir keyed by it. Recompute this inline in each fresh shell rather than relying on a variable surviving between calls (shell state does not persist between the orchestrator's Bash calls):

```bash
REPO_ROOT="$( git rev-parse --show-toplevel 2>/dev/null || pwd )"
CR_DIR="${TMPDIR:-/tmp}/claude-review-$( printf '%s\n' "$REPO_ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$CR_DIR"
```

Write the review prompt to `$CR_DIR/prompt.txt`, capture each round's raw JSON at `$CR_DIR/review.json`, and the extracted critique at `$CR_DIR/verdict.txt`. Persist the generated session id to `$CR_DIR/session-id.txt` so resume rounds (each a fresh shell) can read it back. The key folds in the worktree root so two worktrees never share; unlike the mirror skill it does NOT fold in a Codex session id, because Codex does not export a stable per-session env var the way Claude Code sets `$CLAUDE_CODE_SESSION_ID` - so keep to **one review per worktree at a time**. `cksum` is chosen over `sha256sum` because it exists on both Linux and macOS. Run every Claude call from the repo root (`cd "$REPO_ROOT"` first) so a plan written at the repo root is found even when the skill is invoked from a subdirectory.

## Flow

### Step 0 - Kickoff (human gate #1)

The invocation itself is the kickoff. Confirm scope in one line: what is being planned. If the user gave no task, ask for it (one question). Then proceed - do NOT ask for approval round-by-round; that comes at the end.

### Step 1 - Codex plans

Do real planning: read the relevant code, think through the approach, surface decisions and tradeoffs. Then write the plan to `PLAN_FILE` in this structure:

```markdown
# Plan: <task>
_Round 0 - initial draft by Codex_

## Goal
<one paragraph>

## Approach
<numbered steps, concrete>

## Key decisions & tradeoffs
<the contestable choices - name them explicitly so Claude has something to bite>

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

Show the user the plan inline and say you're sending it to Claude for adversarial review.

### Step 2 - The loop

Maintain `ROUND` (start 1) and `PLAN_FILE` (the resolved plan filename). Resolve `CR_DIR` (above) first and write the review prompt to `$CR_DIR/prompt.txt`.

**The review prompt** written to `$CR_DIR/prompt.txt` (adjust the task line):

> You are an adversarial reviewer for an implementation plan. Be skeptical and specific - your job is to find what breaks, not to be agreeable. Read the plan at `PLAN.md` (substitute the resolved filename) and any repo files you need; you are read-only (plan mode). Identify concrete flaws: security holes, race conditions, missing edge cases, schema conflicts, wrong assumptions, observability gaps, simpler alternatives. Cite exact `file:line` where relevant. For each flaw, give a one-line fix. Do NOT modify any files. End your reply with EXACTLY one line: `VERDICT: APPROVED` if the plan is sound enough to implement, or `VERDICT: REVISE` if it still has material problems.

**Round 1** (creates the session - you generate the fresh id):

```bash
# Self-contained: shell state does not survive between Bash calls, so re-derive
# REPO_ROOT + CR_DIR with the same one-liner as the scratch-dir section. The
# session id is generated HERE and persisted to a file for the resume rounds;
# PLAN_FILE (the resolved plan filename) is carried by the orchestrator.
REPO_ROOT="$( git rev-parse --show-toplevel 2>/dev/null || pwd )"
CR_DIR="${TMPDIR:-/tmp}/claude-review-$( printf '%s\n' "$REPO_ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$CR_DIR"
test -s "$CR_DIR/prompt.txt" \
  || { echo "review prompt missing at $CR_DIR/prompt.txt - write it first (Step 2)" >&2; exit 1; }
SID="$( uuidgen | tr 'A-Z' 'a-z' )"; echo "$SID" > "$CR_DIR/session-id.txt"
rm -f "$CR_DIR/review.json" "$CR_DIR/verdict.txt"   # never let a stale result be read as fresh
cd "$REPO_ROOT" && claude -p --permission-mode plan --output-format json --session-id "$SID" \
  "$(cat "$CR_DIR/prompt.txt")" \
  </dev/null >"$CR_DIR/review.json" 2>"$CR_DIR/err.txt"
CLAUDE_RC=$?
IS_ERR="$( jq -r '.is_error' "$CR_DIR/review.json" 2>/dev/null )"
jq -r '.result // empty' "$CR_DIR/review.json" > "$CR_DIR/verdict.txt" 2>/dev/null
test "$CLAUDE_RC" -eq 0 && test "$IS_ERR" = "false" && test -s "$CR_DIR/verdict.txt" \
  || { echo "ROUND 1 FAILED (rc=$CLAUDE_RC is_error=$IS_ERR) - inspect $CR_DIR/err.txt and $CR_DIR/review.json; STOP, do not trust any verdict" >&2; exit 1; }
echo "SID=$SID"
```
The critique text lands in `$CR_DIR/verdict.txt` (Claude's last message); read that file.

> Note: stderr (a cosmetic connector/auth warning on some setups, plus any real error) is captured to `$CR_DIR/err.txt`, not discarded - inspect it whenever a round fails its success check. Success = exit 0 + `.is_error == false` + a fresh non-empty verdict. If any is missing the run failed (auth/billing/model), so stop and tell the user. The single most common real failure is the auth-precedence gotcha above: `.is_error` true with `.result` == "Credit balance is too low" means a stale `ANTHROPIC_API_KEY` is shadowing the subscription login - re-run with `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude ...`.

**Rounds 2..MAX** (resume the SAME session - Claude remembers its earlier critiques, won't re-litigate settled points):

```bash
# resume takes no fresh --session-id; re-pass --permission-mode plan so the
# session stays read-only. Self-contained: re-derive REPO_ROOT + CR_DIR and read
# the persisted session id (fresh shell has no prior vars). PLAN_FILE is carried
# by the orchestrator.
REPO_ROOT="$( git rev-parse --show-toplevel 2>/dev/null || pwd )"
CR_DIR="${TMPDIR:-/tmp}/claude-review-$( printf '%s\n' "$REPO_ROOT" | cksum | cut -d' ' -f1)"
mkdir -p "$CR_DIR"
SID="$( cat "$CR_DIR/session-id.txt" )"
rm -f "$CR_DIR/review.json" "$CR_DIR/verdict.txt"   # stale-result guard, same as round 1
cd "$REPO_ROOT" && claude -p --resume "$SID" --permission-mode plan --output-format json \
  "I revised PLAN.md. Re-review it and any changed files. Same rules. Note which of your earlier points I addressed and which remain. End with VERDICT: APPROVED or VERDICT: REVISE." \
  </dev/null >"$CR_DIR/review.json" 2>"$CR_DIR/err.txt"
CLAUDE_RC=$?
IS_ERR="$( jq -r '.is_error' "$CR_DIR/review.json" 2>/dev/null )"
jq -r '.result // empty' "$CR_DIR/review.json" > "$CR_DIR/verdict.txt" 2>/dev/null
test "$CLAUDE_RC" -eq 0 && test "$IS_ERR" = "false" && test -s "$CR_DIR/verdict.txt" \
  || { echo "RESUME FAILED (rc=$CLAUDE_RC is_error=$IS_ERR) - inspect $CR_DIR/err.txt; STOP, do not trust any verdict" >&2; exit 1; }
```
(Substitute the resolved `PLAN_FILE` for `PLAN.md` in the resume prompt.)

**Each round, after Claude returns:**
1. Confirm the call actually succeeded before trusting it: exit 0, `.is_error == false`, and a freshly written non-empty `$CR_DIR/verdict.txt` (it was `rm`-ed just before the call, so a non-empty file proves THIS round produced it - not a leftover). The snippets above already `exit 1` on failure; never fall through to a stale verdict.
2. Sanity-check that Claude actually engaged the LOCAL plan. This is far lighter than the mirror skill's sandbox check, because Claude reads the local working tree directly and has no stale-index fallback to drift to - so you are only guarding against a wrong/empty plan path. Read the critique in `$CR_DIR/verdict.txt` and confirm it references the ACTUAL plan content (its specific decisions, `file:line` citations, or quotes of the plan/repo), not a generic answer. A generic reply that never touches the plan's specifics usually means `PLAN_FILE` was empty or the path in the prompt was wrong - fix that and re-run, do not act on it.
3. Require a WELL-FORMED verdict before acting: take the last non-blank line of `$CR_DIR/verdict.txt`, strip surrounding whitespace and markdown emphasis (`*`, `_`, `` ` ``) so realistic output like `**VERDICT: APPROVED**` or a trailing space still matches, then require it to CONTAIN `VERDICT: APPROVED` or `VERDICT: REVISE` (checked in that order, APPROVED first). Anything else (truncated/garbled output, missing verdict line) is malformed - stop and report, do not guess a verdict. This stays fail-closed: a genuinely missing verdict falls through to the `*` case and hard-stops.
   ```bash
   # Self-contained: re-derive REPO_ROOT + CR_DIR (fresh shell has no prior vars).
   REPO_ROOT="$( git rev-parse --show-toplevel 2>/dev/null || pwd )"
   CR_DIR="${TMPDIR:-/tmp}/claude-review-$( printf '%s\n' "$REPO_ROOT" | cksum | cut -d' ' -f1)"
   raw_line="$(grep -v '^[[:space:]]*$' "$CR_DIR/verdict.txt" | tail -1)"
   verdict_line="$(printf '%s' "$raw_line" | sed 's/^[[:space:]*_`]*//; s/[[:space:]*_`]*$//')"
   case "$verdict_line" in
     *"VERDICT: APPROVED"*) verdict_line="VERDICT: APPROVED"; echo "verdict: $verdict_line" ;;
     *"VERDICT: REVISE"*)   verdict_line="VERDICT: REVISE";   echo "verdict: $verdict_line" ;;
     *) echo "MALFORMED verdict (last non-blank line: '$raw_line') - STOP" >&2; exit 1 ;;
   esac
   ```
4. Append to `LOG_FILE`: `## Round <n> - Claude` + the full critique. Then branch on `$verdict_line`:
   - `VERDICT: APPROVED` -> break the loop, go to Step 3 (converged).
   - `VERDICT: REVISE` -> Codex reads the critique, decides **what's actually worth acting on** (Codex has final say - Claude advises, it does not command). Revise `PLAN_FILE`. Append to `LOG_FILE`: `### Codex's response` + what you changed and what you rejected and why. Increment `ROUND`.
5. If `ROUND > MAX_ROUNDS` -> break to Step 3 (deadlock).

### Step 3 - Resolution (human gate #2)

**If APPROVED:** Present to the user - the final `PLAN_FILE`, a 3-bullet summary of what the argument improved, and the round count. Ask: *"Plan survived N rounds of Claude. Implement it now?"* Only on a yes does Codex write code. **No code is written during the loop.**

**If MAX_ROUNDS hit without APPROVED (deadlock):** Do NOT pretend it converged. Surface the unresolved disagreements explicitly: list each point Claude still flags and Codex's counter-position. Hand it to the human to break the tie. This is a legitimate, useful outcome - a flagged disagreement beats a false "approved."

## Hard rules

- Claude is read-only EVERY round - `--permission-mode plan` on the first call AND every resume. It never writes repo files. If you're tempted to give it write access (`--dangerously-skip-permissions`, `--permission-mode bypassPermissions`/`acceptEdits`), stop - that's a different skill.
- Clear `$CR_DIR/review.json` + `$CR_DIR/verdict.txt` before every call and require exit 0 + `.is_error == false` + a fresh non-empty verdict after it; a suppressed error must never let a stale verdict pass as this round's result.
- Generate a FRESH `uuidgen` session id for round 1 and persist it; resume that explicit id every later round. A reused id errors "already in use".
- Scratch files (prompt + json + verdict) live in the per-worktree `$CR_DIR`, never a shared hardcoded `/tmp` path. One review per worktree at a time.
- The loop ALWAYS terminates at `MAX_ROUNDS`. No unbounded recursion.
- Codex is the final arbiter on every REVISE - incorporate good critiques, reject bad ones *with a reason logged*. Don't cave to Claude on everything (that defeats the cross-model check) and don't ignore it (that defeats the point).
- Code only after human gate #2.
- `LOG_FILE` is the deliverable - it tells the whole story of the argument. Keep it complete.

## What NOT to do

- Don't use this to review existing code - this reviews a PLAN, before code is written.
- Don't force-unset `ANTHROPIC_API_KEY` unless you actually hit the billing error and confirmed a subscription login exists - the user may deliberately use their key.
- Don't skip the log - the argument transcript is the most valuable artifact.
- Don't let Claude edit files. Read-only (plan mode), always.
