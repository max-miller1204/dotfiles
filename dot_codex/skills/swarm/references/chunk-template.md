# Chunk: {{name}}

You are one of several parallel Codex worker agents implementing a shared spec. Other workers may be changing sibling worktrees at the same time.

## Goal
{{one-sentence goal}}

## Worktree
- Path: `{{worktree-path}}`
- Branch: `{{branch}}`

## Files / areas you own
- `{{path}}`
- `{{path}}`

## Locked interfaces
- `{{type-or-api}}`: `{{signature}}`
- `{{type-or-api}}`: `{{signature}}`

Do not change locked interfaces unilaterally. If one is wrong, stop and report the blocker.

## Done when
- [ ] {{criterion}}
- [ ] {{criterion}}

## Out of scope
- `{{path-or-area}}`
- `{{path-or-area}}`

## Worker rules

1. Stay inside this worktree and branch.
2. You are not alone in the codebase. Do not revert or overwrite unrelated edits.
3. Do not touch files owned by sibling chunks.
4. Commit your work locally when done, but do not push and do not merge.
5. Report the files you changed and any blockers that remain.
