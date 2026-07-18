<!-- markdownlint-disable MD013 -->

# Dotfiles repository - notes for agents working here

These notes are agent memory for THIS repository only.
This file is a real file, not a symlink, and is `.chezmoiignore`d so it never gets applied to `$HOME`.
Never add repo-specific notes to `AGENTS.md`.
The chezmoi-root `AGENTS.md` is applied verbatim to `~/AGENTS.md` as the global instructions every agent reads in every project, so repo-specific content there leaks into all of them.

Claude Code loads matching path-scoped rules from `.claude/rules/` automatically.
Other agents must read [`context-map.md`](context-map.md).
Then load only the rules relevant to the files and systems the task touches.
Put new repository guidance in the narrowest relevant path-scoped rule, and update the context map when adding a new scope.
When a rule is the authority for a specific file - it explains why that file exists or what invariant it enforces - list that file in that rule's `paths:`, because a broader rule matching the same path does not substitute.
Merely cross-referencing a file another rule owns does not earn a `paths:` entry; keep each list to the files its rule actually explains.
