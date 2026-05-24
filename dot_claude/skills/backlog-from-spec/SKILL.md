---
name: backlog-from-spec
description: >-
  Turn a project's design docs or a list of work items into a deduplicated,
  dependency-linked GitHub issue backlog via the `gh` CLI. Use when the user
  wants to "file issues for the remaining work", "turn the spec into issues",
  "create the backlog from SPEC.md/ROADMAP.md", "what are the gaps", "do a
  gap analysis", or hands you a list of tasks to file as GitHub issues. Auto-detects gap-analysis
  mode (read intent docs + scan codebase for missing capabilities) vs list
  mode (items already supplied). Always writes a local preview artifact and
  requires explicit confirmation before any `gh` write; dedupes against
  existing issues; classifies hard vs soft dependencies; marks blocked work.
  Requires a github.com remote and authenticated `gh`. Do NOT trigger for:
  filing one ad-hoc issue, opening/reviewing PRs, label management alone,
  or non-GitHub trackers (Jira, Linear, GitLab).
---

# backlog-from-spec

Analyze what's left and file it as a clean, linked GitHub backlog.

**Hard invariant:** nothing is written to GitHub until the user sees the local
preview and explicitly approves it. Phases 0–4 are read-only and reversible;
Phases 5–8 touch GitHub and run **only after** the confirm gate.

**Scope: GitHub only.** Requires a git remote on github.com (or a configured
GitHub Enterprise host) plus an authenticated `gh`. For other trackers (Jira,
Linear, GitLab, …), the preview artifact still builds but Phases 5–8 cannot run.

## Modes

- **gap-analysis** — you find the work: read the project's intent docs (SPEC,
  ROADMAP, README, `docs/`, RFCs/ADRs, …) and scan the codebase.
- **list** — the user supplies the items; you just structure and file them.

Both produce the same artifact and pass the same gate; only Phase 2 differs.

## Phases

### 0 — Detect mode

- Explicit bullet/numbered list in the message or a passed file → **list**.
- Intent docs present and no list → **gap-analysis** (a plain README is enough).
- Neither → ask. This is the only place to ask about mode.

### 1 — Detect environment (read-only)

Run the detection block in `references/gh-cookbook.md` (§Environment): remote,
`gh auth`, repo, labels, bulk issue fetch. Also list `.github/ISSUE_TEMPLATE/`
(and the legacy `.github/ISSUE_TEMPLATE.md`). If a template exists, every issue
body must **conform to it** — see `references/issue-conventions.md`
(§Conforming to a repo issue template).

Degrade gracefully:

- No git remote, or the remote is not GitHub → **hard stop**.
- `gh` missing / not authenticated → still build the preview (it has standalone
  value), stop at Phase 4, and tell the user to run `gh auth login`.

### 2 — Analyze (gap-analysis) or collect (list)

**gap-analysis.** Read the intent docs end to end. A spec/ROADMAP is the
*should* side of the diff — used to compute gaps, **never filed verbatim**.

1. **Enumerate candidate gaps.** A gap is a *specific* missing capability
   ("normalize step has no unit-magnitude check"), never a vague theme. Group
   by **area** (data, targets, harness, …); tag `near-term` or `deferred`
   (deferred = the docs explicitly push it out of scope). Cite the source
   doc/section.

2. **Exclude work already tracked elsewhere.** One quick sweep — don't go
   fishing — for separate trackers: `changes/`, `todo/`, `planning/`,
   `proposals/`; `TODO.md`/`BACKLOG.md`/`ROADMAP.md`; "tracked in <X>"
   references in `README`/`docs/`; external tracker keys (`JIRA-1234`,
   `LIN-567`) in recent `git log` or PR bodies; `.github/projects/`, linked
   GitHub Projects. If found, list overlapping candidates under "Tracked
   elsewhere" instead of filing them. No tracker → no-op, move on.

3. **Verification gate (mandatory).** Docs lag code on established repos — the
   biggest failure is filing work that's already done. For *every* candidate,
   actively look for evidence it is resolved before it enters the plan: grep
   the relevant module/CLI flag/config, look for exercising tests, scan
   `git log` / CHANGELOG, check the project's tracker. Three outcomes:
   - **implemented** → drop;
   - **partially implemented** → narrow the issue to *only* the missing part;
   - **no evidence found** → keep, and record exactly what you searched in the
     issue's `evidence` field (shown at the gate so the user can audit the
     "not done" claim). A gap-analysis issue with no `evidence` is not ready
     to file.

**list.** Structure each supplied bullet into one issue. Do not invent extra
work or run a gap analysis the user declined. List-mode issues need no
`evidence` — the user asserted the work.

**Empty results.** Gap-analysis with zero gaps → say so and offer (a) review
docs for omissions or (b) stop. Don't invent filler issues. List mode with an
empty list → ask for items, or offer to switch to gap-analysis if docs exist.

### 3 — Build the artifact + dependency pass

Write `ISSUES_PLAN.json` (authoritative) and immediately render
`ISSUES_PLAN.md` (human summary) at the repo root. Schema, body format, and
label conventions: `references/artifact-schema.md`,
`references/issue-conventions.md`. Carry each verification `evidence`; put
tracker-excluded items in `excluded[]` so they surface under "Tracked
elsewhere".

If Phase 1 found a repo issue template, every `body` must follow its section
structure and carry its declared labels — plus the skill's `area:`/`type:`
labels. The two HTML-comment markers (`backlog-id`, `DEPS_PLACEHOLDER`) stay
either way; they're invisible in the rendered issue.

Then add the analytical payload:

- Classify each dependency **hard** (true blocker — dependent cannot land
  until the prerequisite does) vs **soft** (works standalone, materially
  better after). Record both as `backlog_id` references.
- Identify **keystones** (unblock 3+ others) and the **critical path** (longest
  hard chain). Note both in `ISSUES_PLAN.md` — they tell the user where to start.

Run `python3 scripts/backlog.py validate --plan ISSUES_PLAN.json`. It catches
duplicate ids, dangling dependency references, and **hard-dependency cycles**
before the user sees a green preview. Common fixes: rename a duplicate
`backlog_id`; add the missing issue (or fix the typo) behind a dangling ref;
demote one edge of a cycle from `hard` to `soft` (soft cycles are fine).

### 4 — Preview + confirm gate (mandatory, non-negotiable)

Show the summary table from `ISSUES_PLAN.md`: titles, area, horizon, dependency
counts, proposed labels, dedupe matches. Then **stop and ask explicitly:**
"Ready to file these to GitHub? Reply `yes` / `file` / `go ahead`, or tell me
what to change."

Pass the gate: `yes`, `file`, `file them`, `go`, `go ahead`, `proceed`,
`ship it`, `do it`.

Do **not** pass (treat as still reviewing): silence, a new question, "looks
good" / "nice" / "interesting" without an action verb, "maybe", any reply that
asks about an item rather than approving the batch.

On change requests: edit `ISSUES_PLAN.json`, re-render, re-validate, show the
gate again. Never infer approval — when in doubt, ask once more.

### 5 — Dedupe against what exists

`python3 scripts/backlog.py dedupe --plan ISSUES_PLAN.json`. Marks issues
whose `backlog-id` marker already exists on GitHub as `created`; surfaces
fuzzy title matches as advisories for your judgment — never auto-skip on a
fuzzy match alone.

### 6 — Create

`python3 scripts/backlog.py create --plan ISSUES_PLAN.json`. Idempotent label
creation first, then one issue per pending item with the body delivered on
stdin (`--body-file -`). The artifact is written back after every call, so an
interrupted run resumes cleanly on re-invocation.

### 7 — Link dependencies

`python3 scripts/backlog.py link --plan ISSUES_PLAN.json`. Replaces
`<!-- DEPS_PLACEHOLDER -->` with the resolved `### Dependencies` section
("Blocked by: #12, #14" / "Soft: #9") and adds the `blocked` label to any
issue with an unmet hard prerequisite.

### 8 — Report

Show a table of created issues (number, title, status) and paste the
ready-to-use filter views from `references/gh-cookbook.md` (§Filter views):
unblocked work, blocked work, deferred. Call out the keystones and critical
path so the user knows what to pick up first.

## References

- `references/gh-cookbook.md` — every `gh` command this skill runs, verbatim.
- `references/issue-conventions.md` — issue body template, the `backlog-id`
  marker, label taxonomy + colors, `### Dependencies` format, conforming to a
  repo template.
- `references/artifact-schema.md` — `ISSUES_PLAN.json` schema + `.md` render.

## Notes

- `gh` runs fine directly under the Bash tool — no shell wrapping. Never
  hand-build `gh issue create --body "<multi-line>"`; bodies always go on
  stdin via `--body-file -`.
- The artifact is the contract with the helper. Hand-edits must stay valid
  against the schema and re-pass `validate`.
- Re-running on a repo that already has a backlog is safe: dedupe + the
  `status` field make creation a no-op for existing items. The skill files
  *new* gaps; it does **not** reconcile drift on existing issues (renames,
  swapped labels, rewritten bodies). For bulk reconciliation, drive a
  separate audit from the artifact.
