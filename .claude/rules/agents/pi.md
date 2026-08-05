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
  Subagents come from the published `npm:pi-subagents` package, the nicobailon fork (<https://github.com/nicobailon/pi-subagents>), NOT the `npm:@tintinweb/pi-subagents` scope this repository used before.
  Both packages exist on npm under confusingly similar names and their configuration surfaces are incompatible, so check `repository.url` on the registry entry rather than trusting the bare name.
  The fork ships nine built-in agents - `scout`, `researcher`, `worker`, `reviewer`, `delegate`, `context-builder`, `planner`, `oracle`, and `advisor` - and does NOT ship `general-purpose`, `Explore`, or `Plan`.
  Routing lives in the `subagents.agentOverrides` block of `agent/settings.json`, which this fork does read; that is the reverse of the `@tintinweb` package's rule, and it is why the hand-maintained `Explore.md` and `Plan.md` definitions were retired rather than ported.
  Prefer an override to a definition file: an override changes only the fields it names, while a definition file replaces the built-in wholesale and freezes a copy of an upstream prompt that will not track package updates.
  `.chezmoiremove` deletes the retired `Explore.md` and `Plan.md` from `~/.pi/agent/agents/`, because the fork silently skips any definition without a frontmatter `name:` key and those files have only `display_name:`, so a leftover copy reads as live configuration while doing nothing.
  That same silent skip applies to every new definition file: `name:` and `description:` are both mandatory, and the fork spells the prompt mode `systemPromptMode:`, not the `@tintinweb` package's `prompt_mode:`.
  ANTHROPIC MODELS ARE OFF LIMITS in every pi config: they bill against the API rather than a subscription, unlike `openai-codex` and `opencode-go`.
  That constraint is why `subagents.modelScope` is worth enforcing rather than decorative - its `allow` list of `openai-codex/*` and `opencode-go/*` is the mechanism that rejects an Anthropic model reached by a per-run override or a fuzzy id match, and `verify.sh` separately gates that no string anywhere in the settings names Anthropic.
  The fork's README recommends specific Anthropic models for the intent tier and the watchdog; substitute, never adopt them.
  Models are routed by the four capability tiers the fork's README recommends, using task shape rather than one model everywhere: `openai-codex/gpt-5.6-luna:low` for recon (`scout`), `openai-codex/gpt-5.6-terra:medium` for well-scoped implementation and review (`worker`, `reviewer`, `delegate`, `researcher`, and `subagents.defaultModel`), `openai-codex/gpt-5.6-sol:high` for hard work that arrives with explicit completion criteria (`planner`, `context-builder`, `oracle`, `advisor`), and `opencode-go/minimax-m3` for the intent tier.
  The intent tier is the only agent that needs its own definition file, `shaper.md`, because it is not a built-in; keep its `fallbackModels` pointing at a capability-tier model on the OTHER provider so an `opencode-go` limit degrades instead of failing the run.
  The README's intent tier assumes a model chosen for reading human intent, which no `openai-codex` or `opencode-go` model is specifically known for, so treat this pin as a substitution to re-evaluate rather than a considered match.
  `subagents.watchdog` is enabled with `opencode-go/kimi-k3` at thinking high.
  The fork's own `/subagents-watchdog recommend-model` is stale here, hardcoded to Opus 4.8 or GPT 5.5 in `model-selection.ts`, so it never sees the current generation and its answer must be substituted rather than followed.
  Two properties drove the pick and both are worth preserving through any future change: the watchdog reviews what the session just wrote, so a model sharing `defaultProvider` would carry the same blind spots as the code's author; and it is an adversarial reviewer, so it must not be the cheap tier the fork's README warns against.
  Its 1M context against the session model's 272K is the third reason, and the one that matters most as a changed state grows.
  `verify.sh` gates both properties: `main.model` AND `main.thinking` must be set, because a watchdog model configured without a thinking level silently runs with thinking off, and `main.model` must not sit on `defaultProvider`.
  The watchdog is NOT the `reviewer` subagent and reads none of `subagents.defaultModel` or `subagents.agentOverrides.reviewer`.
  Only `enabled` and `main` are set because everything else this setup wants is already the fork's default: scope tracking, LSP diagnostics on changed TypeScript and JavaScript files, and blocker auto-follow at three attempts are all on out of the box, and `main.enabled` inherits the top-level `enabled`.
  Do not restate a default here just to make it visible; a restated default is a copy that silently stops matching upstream.
  `subagents.modelScope` replaces the `@tintinweb` package's `scopeModels` and takes provider glob patterns rather than an exact model list, so it does not track `enabledModels` on its own.
  Keep every model pinned for a subagent present in `enabledModels` in `agent/settings.json` anyway: that list is the one curated set of models this machine spawns, and the fork resolves model ids fuzzily, so a pin outside it lands on a neighbouring model instead of failing loudly.
  That invariant is enforced by `.github/scripts/check-pi-model-pins.sh`, which reads frontmatter `model:` and `fallbackModels:` (leading frontmatter block only, so a prompt-body `model:` line is not a pin; both the inline comma-separated and the `- item` block form are read) plus the settings-level `subagents.defaultModel`, `subagents.agentOverrides.<agent>`, and `subagents.watchdog` pins, and strips the `:<level>` thinking suffix before comparing.
  Both agents dir and settings file are plain non-templated files, so the SAME script runs against the source tree in CI's `config-syntax` job on every PR and against the applied `~/.pi` tree in the dispatch-only E2E; extend that one script rather than duplicating the logic.
  `verify.sh` gates the package name, the absence of the two retired definitions, `shaper.md`, the exact set of built-ins carrying a tier override, and the watchdog's provider independence, so a silent regression in any of them surfaces on the E2E box.
  pi rewrites `agent/settings.json` at runtime (model switches, `lastChangelogVersion`), so `.pi/agent/settings.json` can show as drift in `chezmoi status`; fold deliberate changes back with `chezmoi add`, and do not "fix" the drift by unmanaging the file.
  pi needs no `AGENTS.md` symlink: it walks every ancestor directory of the cwd collecting `AGENTS.md` files, so it picks up the applied `~/AGENTS.md` natively, and a `~/.pi/agent/AGENTS.md` symlink would load the same content twice (the global agent-dir file and the ancestor walk are separate lookups).
