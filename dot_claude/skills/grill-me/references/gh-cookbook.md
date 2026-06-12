# gh cookbook

Every GitHub command this skill runs, verbatim. `gh` runs directly under the
Bash tool — no fish/shell wrapping. Read-only commands are safe any time; the
write commands (§Labels, §Create, §Link) run **only after the confirm gate**.

## Environment (Phase 1, read-only)

```bash
git remote -v
gh auth status
gh repo view --json nameWithOwner -q .nameWithOwner
gh label list --limit 200
# bulk fetch existing issues once for local dedupe (avoid N searches):
gh issue list --state all --limit 1000 --json number,title,state,body
```

Decision rules:
- `git remote -v` empty, or the URL host is not `github.com` (and not a
  configured GitHub Enterprise host) → **hard stop**.
- `gh auth status` non-zero / "not logged in" → build the preview but do not
  pass the gate; tell the user to run `gh auth login`.

## Labels (Phase 6, idempotent)

`--force` creates the label or updates its color/description if it already
exists, so it is safe to run every time:

```bash
gh label create "area:data" --color "1d76db" --description "Data pipeline / DB" --force
gh label create "blocked"   --color "b60205" --description "Has an unmet hard prerequisite" --force
```

The helper does this for every label in `ISSUES_PLAN.json.labels`.

## Create (Phase 6)

Body is delivered on **stdin** via `--body-file -`. Never put a multi-line body
in a shell-quoted `--body` argument — that is the failure mode this skill
exists to avoid.

```bash
gh issue create \
  --title "Add deterministic fixture loader" \
  --body-file - \
  --label "area:data" --label "type:harness" <<'BODY'
## Problem
...
<!-- backlog-id: data-loader-fixture -->
<!-- DEPS_PLACEHOLDER -->
BODY
```

`gh issue create` prints the new issue URL on stdout; the trailing path segment
is the issue number, captured into `github_issue_number`.

## Link (Phase 7)

Issue numbers do not exist until creation, so bodies are filed with
`<!-- DEPS_PLACEHOLDER -->` and rewritten afterward:

```bash
# replace the placeholder with the resolved dependency section:
gh issue edit 42 --body-file -        # full new body on stdin
# mark a hard-blocked issue:
gh issue edit 42 --add-label "blocked"
```

## Filter views (Phase 8 — paste these for the user)

```bash
# Work that can start now:
gh issue list --search '-label:blocked -label:deferred state:open'
# Blocked on a hard prerequisite:
gh issue list --search 'label:blocked state:open'
# Explicitly deferred / out of near-term scope:
gh issue list --search 'label:deferred'
# Everything in one area:
gh issue list --label 'area:data' --state open
```
