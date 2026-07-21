---
paths:
  - ".github/**/*"
---

<!-- markdownlint-disable MD013 -->

# CI and E2E context

- CI (`.github/workflows/ci.yml`) renders templates with `chezmoi execute-template`, which uses the runner's OS, so a `{{ if eq .chezmoi.os "darwin" }}` branch is only exercised on a macOS runner.
  The `shellcheck` and `fish-syntax` jobs therefore carry a `strategy.matrix.os` of `[ubuntu-latest, macos-latest]` purely to render and lint the darwin half of every template; that macos leg is the only darwin template coverage, so do not drop it.
  Keep the macOS legs STATIC (render + shellcheck + `fish -n` only, tools via `brew install`) - never let the mac runner perform the real package-manifest installs that the bootstrap scripts do.
  All OS-conditional template logic lives in `.chezmoiscripts/*.sh.tmpl` and `dot_config/fish/*.fish.tmpl`; the TOML/JSON templates have no darwin branch, which is why `config-syntax` and `chezmoi-dry-run` stay ubuntu-only.
- The `nix-evaluation` CI job evaluates all four supported systems without building.
  The `nix-build` matrix renders and executes `run_once_before_12-install-nix.sh.tmpl` twice before building, so native x86_64 Linux, aarch64 Darwin, and x86_64 Darwin runners prove the production bootstrap and its idempotency instead of relying on unrelated setup actions.
  Linux uses the Determinate shell installer and Apple Silicon uses Determinate's signed macOS package; Intel macOS is unsupported and the bootstrap refuses it.
  The matrix then builds every bundle, runs smoke checks, reports closure size, and tests temporary-profile idempotency and rollback.
  Temporary profile tests canonicalize macOS's `/var` symlink before direnv records allow state, so allow and exec use the same physical fixture path.
  Standard CI has no native aarch64 Linux runner, so that system remains evaluation-only until a runner is added.
- The on-demand E2E workflow (`.github/workflows/e2e-native-ubuntu.yml`) runs the real bootstrap (`chezmoi init --apply --promptDefaults`) on a clean GitHub-hosted Ubuntu VM and verifies the installed end state with `.github/e2e/verify.sh`.
  It is dispatch-only ON PURPOSE (it installs multi-GB toolchains and GUI packages and takes about an hour) - never add a push/PR trigger - and it pins `runs-on: ubuntu-24.04`, not `ubuntu-latest`, because the claim it proves is "works on Ubuntu 24.04", the target machine's release.
  It also deliberately mutates the runner before the apply (a conditional `Defaults always_set_home` sudoers drop-in, deleting `XDG_CONFIG_HOME=` from `/etc/environment`, `unset XDG_CONFIG_HOME` in the apply step) to make the runner faithful to stock Ubuntu: runner images preserve the caller's env through sudo and export an expanded `XDG_CONFIG_HOME`, which stock Ubuntu never does, and that leak let the Nix installer's root-run fish self-test create a root-owned `~/.config/fish` that broke chezmoi's later chmod.
  The `sudo HOME=/root XDG_CONFIG_HOME=/root/.config` pins on the Linux installer line in `run_once_before_12` and verify.sh's no-root-owned-files check guard that same class of bug on any host with similar env leaks - keep all three.
  After the real apply installs Nix, the workflow writes `/nix/var/nix/profiles/default/bin` to `$GITHUB_PATH` because an installer subprocess cannot update later Actions step environments; the standalone profile test also sources the daemon environment defensively.
  The E2E performs a second apply and requires the dedicated profile symlink to remain on the same generation.
  That TTY-less second apply must use `--force` because the first apply's Claude plugin setup intentionally mutates the managed settings file; this explicitly selects the source version before the always-run plugin script re-asserts its tool-owned state.
  It also runs the temporary profile upgrade and rollback fixture without mutating the user's dedicated profile.
  `.github/scripts/create-direnv-flake-fixture.sh` owns the shared nix-direnv smoke flake used by that focused profile test and by `verify.sh`; keep both callers on the helper so their project-environment assertions cannot drift.
  The E2E verifier copies the applied `~/.config/direnv/direnvrc` into isolated XDG config and data directories before running that fixture, invokes direnv explicitly from `$DOTFILES_NIX_PROFILE/bin`, and prints captured output before gating on its exit code so runner-global binaries and allow state cannot affect the result or hide the cause of a failure.
  `verify.sh` doubles as the package checklist spec: `MANIFEST_BINS` mirrors `.chezmoidata/packages.yaml`, `NIX_BINS` mirrors the checked-in cumulative bundle, `RUNTIME_BINS` mirrors native mutable runtimes and remaining native tools, and the remaining arrays mirror GUI packages, coding agents, and LSP languages.
  Runtime, agent-tool, and LSP ownership checks must assert exact Fish resolution through fnm, uv, rustup, native Bun, the stable native Hunk launcher, or the dedicated Nix profile rather than merely checking command presence.
  The Pyright and TypeScript smoke sends Claude-like initialize, hover, shutdown, and exit messages with `NODE_PATH` removed, proving server startup and pinned TypeScript module resolution.
  `check-lsp-ownership.py` statically proves exact language-server ownership in CI and E2E.
  `check-agent-tool-ownership.py` separately proves that stable native npm prefixes own Pi and Hunk, that neither ships in the Nix bundle, and that no active source declaration owns tools through mise.
  `test-pi-nix-runtime.sh` uses RPC `get_commands` without a model call to prove Pi loads the managed local extensions; CI runs it against a throwaway `@latest` npm-prefix install, and E2E additionally installs Pi's npm packages through fnm npm and repeats that RPC smoke against the applied configuration.
  `.github/scripts/test-runtime-path-order.sh` supplies isolated fake commands to prove the precedence chain on every Linux CI run without downloading mutable runtimes.
  Every ownership change needs the matching verification edit.
  Invariants that hold over plain, non-templated source files belong in a script under `.github/scripts/` that BOTH `ci.yml` and the native E2E call, not inline in `verify.sh` alone: the E2E is dispatch-only, so a check that lives only there never runs on a PR.
  `check-nix-bootstrap.py` is the ordering and ownership guard for native prerequisites, Nix installation, profile activation, runtimes, Hunk, Pi, and LSP setup; CI and the E2E source-check step both run it.
  `check-pi-model-pins.sh` is the reference shape - CI runs it against the source tree in `config-syntax`, the E2E runs the same script against the applied `~/.pi` tree, and `verify.sh` calls it OUTSIDE `hard` because `hard` redirects both of its command's output streams to `/dev/null`, which would swallow any per-item diagnostic; capture the report, echo it, then gate on the exit code.
  Its chezmoi-drift check excludes `.claude/settings.json` (the by-design drift documented in the [scripts and config rule](../bootstrap/scripts-and-config.md)) and `.chezmoiscripts/` (plain `run_after_` scripts are always-pending in `chezmoi status` by design), so only genuinely unexpected drift fails.
  `.github/e2e/prompt-test.sh` PTY-tests the interactive `headless` promptBoolOnce path via expect; its choreography (a real pty size via `stty_init`, syncing on the input line's "bool, default false" placeholder rather than the question text, sending the answer and the Enter as separate writes with pauses) encodes bubbletea TUI determinism rules - do not "simplify" it, and run it after the main E2E, never as part of it.
