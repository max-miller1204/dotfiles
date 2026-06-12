# Issue conventions

These conventions make the backlog dedupe-able, filterable, and self-documenting.
Follow them exactly — the helper script and the dedupe key depend on them.

## Issue body — two cases

A repo's own GitHub issue template, when it has one, is the source of truth for
*format*. The skill's job is the analysis and batch filing; it should fill the
repo's house style, not impose its own.

- **Repo has a template** (`.github/ISSUE_TEMPLATE/`) → conform to it. See
  §Conforming to a repo issue template below.
- **Repo has no template** → use the built-in default template below.

Either way, three things are non-negotiable because the helper script and
dedupe depend on them: the `_Source:`/`_Verified not done:` provenance (in
gap-analysis mode), the `<!-- backlog-id -->` marker, and the
`<!-- DEPS_PLACEHOLDER -->` marker.

### Built-in default template (used only when the repo has none)

```markdown
## Problem
<one or two sentences: the concrete missing capability or task>

## Acceptance
- <verifiable outcome 1>
- <verifiable outcome 2>

_Source: SPEC.md §3.2 "Data ingestion"_   ← gap-analysis mode only; cite the
                                             exact doc + section/heading

_Verified not done:_ grepped `src/` for `retry`/`backoff`, no matches;
no tests under `tests/` exercise this; not on the project's tracker.
                                          ← gap-analysis mode only; mirrors the
                                             `evidence` field so a reviewer on
                                             GitHub can audit the "not done"
                                             claim. Omit in list mode.

<!-- backlog-id: data-loader-fixture -->
<!-- DEPS_PLACEHOLDER -->
```

- **Problem** is specific, not a theme. "Normalize step lacks a unit-magnitude
  sanity check (mg vs g)" — not "improve data quality".
- **Acceptance** is how someone knows the issue is done. Keep it checkable.
- **`_Source:`** line is required in gap-analysis mode so the reader can trace
  the issue back to intent. Omit it in list mode (the user is the source).
- **`<!-- backlog-id: <slug> -->`** is mandatory and last-but-one. It is the
  primary dedupe key — it survives title/label edits. Slug = kebab-case, stable,
  derived from the capability, not the title wording.
- **`<!-- DEPS_PLACEHOLDER -->`** is mandatory and last. The `link` phase
  replaces it; never write the dependency section by hand at create time
  (issue numbers do not exist yet).

## Conforming to a repo issue template

GitHub repos declare their issue format in `.github/ISSUE_TEMPLATE/`. When
Phase 1 finds one, generate every issue body in *that* shape. The skill brings
the content and the markers; the repo brings the format.

GitHub uses two template forms — handle whichever the repo has:

- **Issue forms** (`.yml`, e.g. `bug.yml`) — structured. Each `body[]` element
  of type `textarea` or `input` has an `attributes.label`. Treat that ordered
  list of labels as the section headings: emit one `## <label>` block per
  field, in order, filled with the matching content. Apply any labels in the
  form's top-level `labels:` to the issue. Honor `validations.required` — never
  leave a required field empty (if you have nothing real to say, the candidate
  probably is not a well-formed issue yet).
- **Markdown templates** (`.md`) — freeform. They carry YAML frontmatter
  (`name`, `labels`, …) then a markdown body with `##`/`###` headings. Keep the
  heading structure verbatim and fill each section; apply the frontmatter
  `labels`.

Rules for the mapping:

- **Markers always survive.** Append `<!-- backlog-id: <slug> -->` then
  `<!-- DEPS_PLACEHOLDER -->` at the very end regardless of the template. They
  are HTML comments — invisible in the rendered issue, untouched by the form.
- **Provenance always survives.** The `_Source:` and `_Verified not done:`
  lines (gap-analysis mode) must appear. If the template has a fitting section
  (e.g. "Context", "References"), put them there; otherwise append them just
  before the markers.
- **Map by meaning, not by exact name.** A template "Summary" or "Description"
  field is where the skill's *Problem* content goes; "Definition of done" or
  "Checklist" is where *Acceptance* goes. Do not invent content to fill a field
  the gap genuinely has no answer for — leave optional fields empty and note it
  at the confirm gate.
- **Labels compose.** The template's labels and the skill's `area:`/`type:`
  (and `blocked`/`deferred`) labels are both applied; list every one in
  `ISSUES_PLAN.json.labels` so `create` makes them idempotently.
- **Multiple templates** → pick the one that fits a backlog item (often named
  `feature`/`task`/`enhancement`; skip `bug` and skip `config.yml`, which is
  not a template). If several plausibly fit, ask the user at the gate.
- The skill bundles `assets/issue-template.yml` (and a `.md` variant) — a
  generic starter a repo can adopt if it has none. The skill never installs it
  silently; offer it as a separate step.

## Label taxonomy

Two required dimensions plus two status labels. Keep names lowercase,
colon-namespaced, and stable.

| Label              | Color    | Meaning                                            |
|--------------------|----------|----------------------------------------------------|
| `area:<name>`      | `1d76db` | Which part of the system (data, targets, harness…) |
| `type:<name>`      | `5319e7` | Kind of work (feature, harness, bug, docs, infra)  |
| `blocked`          | `b60205` | Has an unmet **hard** prerequisite                 |
| `deferred`         | `cccccc` | Explicitly out of near-term scope per the docs     |

Rules:
- Prefer **labels over title prefixes**. `area:data` is filterable; a
  `[data]` title prefix becomes stale noise and cannot be queried.
- Pick area names from the project's own vocabulary (its module/package names
  or the doc's section structure), so the taxonomy matches how the user thinks.
- `near-term` items get no horizon label (that is the default); only `deferred`
  is labeled, because that is the exceptional, query-worthy state.
- Every proposed label (with color + description) must be listed in
  `ISSUES_PLAN.json.labels` so `create` can make it idempotently.

## Dependency section (written by `link`, Phase 7)

The placeholder is replaced with exactly this shape (omit a line if empty):

```markdown
### Dependencies
Blocked by: #12, #14
Soft: #9
Keystone: unblocks #11, #18, #22
```

- **Blocked by** = hard prerequisites (issue gets the `blocked` label).
- **Soft** = works without these but is materially better after them.
- **Keystone** line is added only to items that unblock several others — it
  tells the reader this is a high-leverage place to start.
