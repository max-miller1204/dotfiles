<!-- markdownlint-disable MD013 -->

# Agent context map

Claude Code discovers the path-scoped rules under `.claude/rules/` recursively and loads them when it reads a matching file.
Other agents should use this map after reading the root `CLAUDE.md`.
Before editing, load every rule whose triggers overlap the task.
Some changes cross scopes and require more than one rule.

## Home Manager and Nix

Read [`.claude/rules/bootstrap/home-manager.md`](.claude/rules/bootstrap/home-manager.md) for changes involving:

- the standalone flake and any file under `nix/`
- Home Manager ownership, profiles, host records, activation, updates, generations, or rollback
- Home Manager checks in `.github/workflows/ci.yml` or the native Ubuntu E2E workflow
- the Home Manager activation script or `hm-update` command
- Nix purity, secret isolation, or the nested `path:` flake boundary

Also read the package and CI rules below when an ownership change moves a command or changes validation.

## Package manifest and bootstrap behavior

Read [`.claude/rules/bootstrap/packages.md`](.claude/rules/bootstrap/packages.md) for changes involving:

- `.chezmoidata/packages.yaml` or `.chezmoidata/runtimes.yaml`
- `.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl`
- `.chezmoitemplates/lib-install.sh`, `lib-apt.sh`, or `lib-resolve.sh`
- package ordering, native runtime managers, npm-prefix tools, vendor install scripts, or native packages

## Script and tool-owned configuration

Read [`.claude/rules/bootstrap/scripts-and-config.md`](.claude/rules/bootstrap/scripts-and-config.md) for changes involving:

- `.chezmoiscripts/` or `.chezmoitemplates/` files
- Claude plugins, marketplace state, or `dot_claude/settings.json`
- the Brev skill installer
- shell partials, path resolution, apt repositories, or Codex sync helpers
- `.chezmoidata/mcp.yaml` or any generated Claude, Codex, OpenCode, or pi MCP target
- Claude or Codex MCP synchronization scripts
- `.chezmoi.toml.tmpl`, `.chezmoiignore`, GUI package gating, `headless`, or WSL behavior

Also read [`.claude/rules/bootstrap/packages.md`](.claude/rules/bootstrap/packages.md) when a script change affects package installation semantics.

## Pi coding agent

Read [`.claude/rules/agents/pi.md`](.claude/rules/agents/pi.md) for changes involving:

- any managed file under `dot_pi/`
- pi installation, packages, extensions, prompts, web search, MCP configuration, or runtime drift
- pi-related checks in `.github/e2e/verify.sh`, and the shared `.github/scripts/check-pi-model-pins.sh` enforcing the pin/`enabledModels` invariant

## CI and native Ubuntu E2E

Read [`.claude/rules/quality/ci-and-e2e.md`](.claude/rules/quality/ci-and-e2e.md) for changes involving:

- any workflow, action, E2E file, or shared `.github/scripts/` helper under `.github/`
- CI OS matrices, template rendering, shellcheck, fish syntax, or config syntax
- the native Ubuntu bootstrap workflow, prompt PTY test, or drift checks
- expected binary lists or verification coverage

For package, headless, MCP, or pi changes, also read the corresponding scoped document above.

## Other configuration

No extra scoped document is currently required for unrelated files under `dot_config/`, `dot_claude/`, `dot_agents/`, or `private_dot_local/`.
Follow the root instructions and add a narrowly scoped rule plus a map entry if durable subsystem-specific guidance emerges.
