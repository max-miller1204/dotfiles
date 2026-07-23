---
paths:
  - "dot_pi/**/*"
  - ".chezmoiscripts/run_onchange_before_17-install-hunk.sh.tmpl"
  - ".chezmoiscripts/run_onchange_before_18-install-pi.sh.tmpl"
  - ".github/e2e/verify.sh"
  - ".github/scripts/{check-agent-tool-ownership.py,check-pi-model-pins.sh,test-pi-nix-runtime.sh,test-worktree-guard.mjs}"
---

<!-- markdownlint-disable MD013 -->

# Pi coding agent context

- The pi coding agent installs through fnm-managed npm into the stable `~/.local/share/npm-pi` prefix (`run_onchange_before_18-install-pi.sh.tmpl`, `latest` channel), with its CLI linked into `~/.local/bin`.
  Pi stays outside the Nix bundle so npm releases land immediately instead of trailing the nixpkgs `pi-coding-agent` package bump and a `flake.lock` advance; `update-all` refreshes it alongside Hunk.
  Pi's own npm package extensions continue to install under its unmanaged package directory by invoking fnm-managed npm from the interactive PATH; do not add a second Node runtime owner or a settings-level `npmCommand`.
  Hunk stays outside Nix with Pi: nixpkgs does not package hunkdiff, and npm releases land immediately.
  `run_onchange_before_17-install-hunk.sh.tmpl` installs `hunkdiff@latest` through fnm-managed npm into `~/.local/share/npm-hunkdiff`, links its CLI into `~/.local/bin`, and gives Pi a stable bundled review skill path that survives fnm Node upgrades.
  mise is no longer installed or activated, but stale mise state is never deleted automatically.
  Pi's config lives under `dot_pi/` (settings, extensions, prompts, web-search provider, plus the rendered `agent/mcp.json`); pi's runtime state - credentials, sessions, run history, npm package checkouts, the mcp adapter caches, the generated models store, and scratch dirs - is deliberately unmanaged, and `.chezmoiignore`'s pi block is the authoritative list of those paths.
  The locally vendored extensions stay under `dot_pi/agent/extensions/` (the README's pi config ownership section lists them), while the Git diff viewer is the published `npm:pi-git-diff` package declared in `agent/settings.json`; do not vendor a second local copy.
  The `worktree-guard` extension is globally loaded but activates only when `TREEHOUSE_DIR` or an ancestor `treehouse-state.json` proves the current directory belongs to a managed tree.
  Its direct write/edit boundary allows only the active worktree and Node's canonical `os.tmpdir()`.
  Ambiguous Bash commands default to `auto` mode, where an isolated, tool-less model returns a strict allow/deny/ask judgment; only approvals at or above the configured confidence threshold run without interaction.
  Explicit protected-path references remain deterministic hard blocks, while an unavailable, malformed, uncertain, or ask judgment falls back to interactive approval and fails closed without UI.
  `/worktree-guard auto|prompt|status` controls the current session, and the `PI_WORKTREE_GUARD_*` environment variables provide startup overrides.
  Canonicalize both existing and not-yet-created targets before checking the boundary, reject temporary-directory symlinks that resolve into protected paths, and do not broaden the exception to arbitrary external directories.
  Tool-path resolution must mirror pi's own normalization exactly - `@` prefix, `file://` URL, then `~/` - because a branch missing here checks a different path than the one pi writes.
  Canonicalization follows dangling symlinks to their target, since a not-yet-created target still decides where a write lands.
  Every discovered protected candidate - sibling worktrees from `treehouse-state.json` and the linked live source alike - is kept only when it neither contains nor lives inside the workspace: treehouse supports a repository-relative root, so protecting an ancestor would block every write and command in the assigned worktree, and a candidate inside the workspace would carve a hole out of the writable tree.
  Protected-path references are matched by canonicalizing every path-shaped command operand, not by substring comparison, so a traversal spelling or macOS's `/var` alias cannot slip past the deterministic hard block.
  That classification lives only in `policy.mjs`; `index.ts` runs it once through `bashGuardReason` and recognizes the hard-block class by the reason's protected-path prefix, so the canonicalizing scan is never duplicated on the Bash path and stays reload-safe.
  The judge prompt reports the real session cwd alongside the workspace, and a confident `allow` whose own `affectedPaths` name a protected path falls back to interactive approval.
  Keep deterministic path and command classification dependency-free in `policy.mjs`, and keep strict model prompt/response validation in `auto-judge.mjs`.
  `.github/scripts/test-worktree-guard.mjs` must exercise custom-root detection, temporary-file access, sibling and live-source protection, bare-repository and repository-relative live sources, `file://` tool paths, existing and dangling symlink escapes, non-canonical protected-path spellings (including the macOS `/var` alias), parent-directory traversal spellings, deterministic classification, session-cwd reporting, the `affectedPaths` backstop, malformed model output, confidence fallback, and the default judge model's presence in `enabledModels` without making a network call.
  It must pass unchanged on both Linux and macOS.
  This extension prevents accidental cross-tree edits but is not an OS security sandbox and must never be documented as one.
  `verify.sh` hard-gates that the package remains declared and that the obsolete local extension directory does not materialize on the E2E box.
  Subagents come from the published `npm:@tintinweb/pi-subagents` package, which discovers agent definitions from `~/.pi/agent/agents/*.md` (source `dot_pi/agent/agents/`); that Markdown frontmatter is the whole routing surface, so do not reintroduce a `subagents.agentOverrides` block in `agent/settings.json` - the package never reads one.
  The frontmatter accepts a single `model:` and has no `fallbackModels` key, so do not hand-add one expecting the fallback chain the old settings-level overrides had; a pinned model that fails to resolve already falls back silently to the parent session's model.
  `Explore.md` and `Plan.md` deliberately SHADOW the package's own built-in agents of the same name: the package ships `general-purpose`, `Explore`, and `Plan` defaults, and a definition file whose name matches one of them overrides it wholesale.
  The managed copies exist for the deltas - Explore's `model:` pin and both agents' `thinking` levels - so their tool lists, `prompt_mode: replace`, and prompt bodies are hand-maintained restatements of upstream defaults that will not track package updates; re-check them against the package's built-ins when bumping `npm:@tintinweb/pi-subagents`, and note that deleting either file silently restores the upstream default rather than removing the agent.
  Keep any model pinned here present in `enabledModels` in `agent/settings.json` too: the package's opt-in `scopeModels` guardrail matches that allowlist exactly and warns on a frontmatter pin outside it.
  That invariant is enforced by `.github/scripts/check-pi-model-pins.sh`, which reads the pin from the leading frontmatter block only (a prompt-body `model:` line is not a pin) and accepts the quoted YAML form; both agents dir and settings file are plain non-templated files, so the SAME script runs against the source tree in CI's `config-syntax` job on every PR and against the applied `~/.pi` tree in the dispatch-only E2E - extend that one script rather than duplicating the logic.
  Both agent definitions are gated in `verify.sh` the same way `npm:pi-git-diff` is, so a rename or a dropped file surfaces on the E2E box.
  pi rewrites `agent/settings.json` at runtime (model switches, `lastChangelogVersion`), so `.pi/agent/settings.json` can show as drift in `chezmoi status`; fold deliberate changes back with `chezmoi add`, and do not "fix" the drift by unmanaging the file.
  pi needs no `AGENTS.md` symlink: it walks every ancestor directory of the cwd collecting `AGENTS.md` files, so it picks up the applied `~/AGENTS.md` natively, and a `~/.pi/agent/AGENTS.md` symlink would load the same content twice (the global agent-dir file and the ancestor walk are separate lookups).
