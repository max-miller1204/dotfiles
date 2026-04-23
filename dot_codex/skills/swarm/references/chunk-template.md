# Chunk: {{name}}

You are one of several parallel Codex worker agents implementing a shared spec. Other workers may be changing sibling workspaces, forked workspaces, or worktrees at the same time.

## Goal
{{one-sentence goal}}

## Execution context
- Mode: `{{codex-app-agent-mode-or-git-worktree-mode}}`
- Workspace/worktree path: `{{workspace-or-worktree-path}}`
- Branch, if applicable: `{{branch}}`

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

1. Stay inside your assigned workspace or worktree.
2. You are not alone in the codebase. Do not revert or overwrite unrelated edits.
3. Do not touch files owned by sibling chunks.
4. In Codex app agent mode, edit files directly in your forked workspace and report changed files.
5. In git worktree mode, commit your work locally when done, but do not push and do not merge.
6. Report validation results, files changed, and any blockers that remain.
