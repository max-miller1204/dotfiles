# Artifact schema

One source of truth, two faces:

- **`ISSUES_PLAN.json`** — authoritative, machine-read by `scripts/backlog.py`.
- **`ISSUES_PLAN.md`** — a human render of the same data, shown at the confirm
  gate. Regenerate it from the JSON whenever the JSON changes; never let them
  drift.

Both live at the repo root (or cwd if not a repo).

## `ISSUES_PLAN.json`

```json
{
  "schema_version": 1,
  "repo": "owner/name",
  "mode": "gap-analysis",
  "source_docs": ["SPEC.md", "ROADMAP.md"],
  "generated_at": "2026-05-19T16:00:00Z",
  "labels": [
    { "name": "area:data",    "color": "1d76db", "description": "Data pipeline / DB" },
    { "name": "type:harness", "color": "5319e7", "description": "Test/eval harness" },
    { "name": "blocked",      "color": "b60205", "description": "Has an unmet hard prerequisite" },
    { "name": "deferred",     "color": "cccccc", "description": "Out of near-term scope" }
  ],
  "excluded": [
    {
      "backlog_id": "auth-refresh-tokens",
      "reason": "tracked",
      "detail": "already on the project's planning board / tracker"
    }
  ],
  "issues": [
    {
      "backlog_id": "data-loader-fixture",
      "title": "Add deterministic fixture loader for the dataset",
      "body": "## Problem\n...\n_Source: SPEC.md §3.2_\n\n<!-- backlog-id: data-loader-fixture -->\n<!-- DEPS_PLACEHOLDER -->",
      "labels": ["area:data", "type:harness"],
      "horizon": "near-term",
      "depends_on_hard": ["schema-finalize"],
      "depends_on_soft": ["metrics-baseline"],
      "evidence": "grepped src/ for fixture/loader, tests/ — none found; not on any project tracker",
      "status": "pending",
      "github_issue_number": null,
      "error": null
    }
  ]
}
```

### Field reference

| Field | Required | Notes |
|-------|----------|-------|
| `schema_version` | yes | Always `1` for now. |
| `repo` | yes | `owner/name` from `gh repo view`. |
| `mode` | yes | `gap-analysis` or `list`. |
| `source_docs` | gap-analysis | Docs the gaps were derived from. `[]` in list mode. |
| `generated_at` | yes | ISO 8601 UTC. |
| `labels[]` | yes | Every label any issue uses, with `color` (6-hex, no `#`) and `description`. `create` makes these idempotently. |
| `issues[].backlog_id` | yes | Stable kebab-case slug. **Unique.** Primary dedupe key; embedded in the body as `<!-- backlog-id: <slug> -->`. |
| `issues[].title` | yes | Imperative, concise. Should also be unique. |
| `issues[].body` | yes | Full markdown. Must end with the `backlog-id` marker then `<!-- DEPS_PLACEHOLDER -->` (see issue-conventions.md). |
| `issues[].labels[]` | yes | Subset of `labels[].name`. |
| `issues[].horizon` | yes | `near-term` or `deferred`. `deferred` → gets the `deferred` label. |
| `issues[].depends_on_hard[]` | yes (may be `[]`) | `backlog_id` refs. Each ref must exist in `issues`. |
| `issues[].depends_on_soft[]` | yes (may be `[]`) | `backlog_id` refs. |
| `issues[].evidence` | gap-analysis | What you searched in the codebase to confirm the gap is *not already resolved* (paths/symbols/tests, plus the project's tracker if it has one). Required in gap-analysis mode — an issue with no evidence is not ready to file. `null`/omit in list mode. |
| `excluded[]` | optional | Candidates deliberately NOT filed because they are already tracked elsewhere or already done. Each: `backlog_id`, `reason` (`tracked` \| `implemented`), `detail` (which tracker/board entry, or the symbol/test proving it's done). Rendered under "Tracked elsewhere" so omissions are visible, not silent. Leave empty if the project has no separate tracker. |
| `issues[].status` | yes | `pending` → `created` / `failed`. Drives resumability. Start at `pending`. |
| `issues[].github_issue_number` | yes | `null` until created, then the integer. |
| `issues[].error` | yes | `null` unless the last `create`/`link` call failed; then the stderr. |

## `ISSUES_PLAN.md` (render shown at the gate)

```markdown
# Backlog plan — owner/name  (mode: gap-analysis)

Source: SPEC.md, ROADMAP.md · 17 issues · 4 new labels

## Keystones & critical path
- **schema-finalize** unblocks 5 issues — do first.
- Critical path: schema-finalize → data-loader-fixture → metrics-baseline

## Proposed issues
| backlog_id | Title | Area | Type | Horizon | Hard deps | Soft deps |
|---|---|---|---|---|---|---|
| schema-finalize | Finalize the on-disk schema | data | feature | near-term | — | — |
| data-loader-fixture | Add deterministic fixture loader | data | harness | near-term | schema-finalize | metrics-baseline |
| … | | | | | | |

## New labels
`area:data` (#1d76db), `type:harness` (#5319e7), `blocked` (#b60205), `deferred` (#cccccc)

## Tracked elsewhere (not filed)
- `auth-refresh-tokens` — tracked: already on the project's planning board
- `rate-limit-redis` — implemented: `src/limiter/redis.py` + tests cover it

## Dedupe
- `metrics-baseline` already exists as #7 (matched by backlog-id) — will be skipped.
```

The **Tracked elsewhere** section is the proof you considered those capabilities
and consciously did not double-track them — it is as important as the issue
list on an established project.

Keep the `.md` skimmable: the table is what the user scans at the gate; the
keystone/critical-path notes are the analytical payload.
