---
paths:
  - "dot_pi/**/*"
  - ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
  - ".github/e2e/verify.sh"
---

<!-- markdownlint-disable MD013 -->

# Pi coding agent context

- The pi coding agent and Hunk install as mise-managed npm tools (`npm:@earendil-works/pi-coding-agent` and `npm:hunkdiff` via `mise use -g` in `run_once_before_10`, after the toolchains block so node exists) rather than plain `npm -g`, so they survive node upgrades instead of becoming orphaned in a version-pinned runtime directory.
  Pi loads Hunk's bundled review skill from the stable `npm-hunkdiff/latest` mise path in `agent/settings.json`, which works on both macOS and Linux without a Homebrew-specific branch.
  Pi's config lives under `dot_pi/` (settings, extensions, prompts, web-search provider, plus the rendered `agent/mcp.json`); pi's runtime state - credentials, sessions, run history, npm package checkouts, the mcp adapter caches, the generated models store, and scratch dirs - is deliberately unmanaged, and `.chezmoiignore`'s pi block is the authoritative list of those paths.
  The locally vendored extensions stay under `dot_pi/agent/extensions/` (the README's pi config ownership section lists them), while the Git diff viewer is the published `npm:pi-git-diff` package declared in `agent/settings.json`; do not vendor a second local copy.
  `verify.sh` hard-gates that the package remains declared and that the obsolete local extension directory does not materialize on the E2E box.
  Subagents come from the published `npm:@tintinweb/pi-subagents` package, which discovers agent definitions from `~/.pi/agent/agents/*.md` (source `dot_pi/agent/agents/`); that Markdown frontmatter is the whole routing surface, so do not reintroduce a `subagents.agentOverrides` block in `agent/settings.json` - the package never reads one.
  The frontmatter accepts a single `model:` and has no `fallbackModels` key, so do not hand-add one expecting the fallback chain the old settings-level overrides had; a pinned model that fails to resolve already falls back silently to the parent session's model.
  `Explore.md` and `Plan.md` deliberately SHADOW the package's own built-in agents of the same name: the package ships `general-purpose`, `Explore`, and `Plan` defaults, and a definition file whose name matches one of them overrides it wholesale.
  The managed copies exist for the deltas - Explore's `model:` pin and both agents' `thinking` levels - so their tool lists, `prompt_mode: replace`, and prompt bodies are hand-maintained restatements of upstream defaults that will not track package updates; re-check them against the package's built-ins when bumping `npm:@tintinweb/pi-subagents`, and note that deleting either file silently restores the upstream default rather than removing the agent.
  Keep any model pinned here present in `enabledModels` in `agent/settings.json` too: the package's opt-in `scopeModels` guardrail matches that allowlist exactly and warns on a frontmatter pin outside it.
  Both agent definitions are gated in `verify.sh` the same way `npm:pi-git-diff` is, so a rename or a dropped file surfaces on the E2E box.
  pi rewrites `agent/settings.json` at runtime (model switches, `lastChangelogVersion`), so `.pi/agent/settings.json` can show as drift in `chezmoi status`; fold deliberate changes back with `chezmoi add`, and do not "fix" the drift by unmanaging the file.
  pi needs no `AGENTS.md` symlink: it walks every ancestor directory of the cwd collecting `AGENTS.md` files, so it picks up the applied `~/AGENTS.md` natively, and a `~/.pi/agent/AGENTS.md` symlink would load the same content twice (the global agent-dir file and the ancestor walk are separate lookups).
