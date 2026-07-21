---
paths:
  - ".github/**/*"
---

<!-- markdownlint-disable MD013 -->

# CI and E2E context

- CI (`.github/workflows/ci.yml`) renders templates with `chezmoi execute-template`, which uses the runner's OS, so a `{{ if eq .chezmoi.os "darwin" }}` branch is only exercised on a macOS runner.
  The `shellcheck` and `fish-syntax` jobs therefore carry a `strategy.matrix.os` of `[ubuntu-latest, macos-latest]` purely to render and lint the darwin half of every template; that macos leg is the only darwin template coverage, so do not drop it.
  Keep the macOS shellcheck and Fish legs static, and never let a hosted macOS runner perform package-manifest or cask installs.
  The Home Manager macOS legs may execute the rendered activation wrapper twice because that installs only the pinned package profile and supplies native activation/idempotence evidence.
  All OS-conditional template logic lives in `.chezmoiscripts/*.sh.tmpl` and `dot_config/fish/*.fish.tmpl`; the TOML/JSON templates have no darwin branch, which is why `config-syntax` and `chezmoi-dry-run` stay ubuntu-only.
- The on-demand E2E workflow (`.github/workflows/e2e-native-ubuntu.yml`) runs the real bootstrap on fresh GitHub-hosted user state and verifies the installed end state with `.github/e2e/verify.sh`.
  Its matrix uses `--promptDefaults` for desktop and `--promptBool headless=true` for headless Linux, with an exact CI Home Manager configuration for each profile.
  It is dispatch-only ON PURPOSE because it installs multi-GB toolchains and GUI packages - never add a push/PR trigger - and it pins `runs-on: ubuntu-24.04`, not `ubuntu-latest`, because the claim it proves is "works on Ubuntu 24.04", the target machine's release.
  It also deliberately mutates the runner before the apply (a conditional `Defaults always_set_home` sudoers drop-in, deleting `XDG_CONFIG_HOME=` from `/etc/environment`, `unset XDG_CONFIG_HOME` in the apply step) to make the runner faithful to stock Ubuntu: runner images preserve the caller's env through sudo and export an expanded `XDG_CONFIG_HOME`, which stock Ubuntu never does, and that leak let the Nix installer's root-run fish self-test create a root-owned `~/.config/fish` that broke chezmoi's later chmod.
  The `sudo HOME=/root XDG_CONFIG_HOME=/root/.config` pins on the Nix installer line in `run_once_before_10` and verify.sh's no-root-owned-files check guard that same class of bug on any host with similar env leaks - keep all three.
  `verify.sh` doubles as the ownership checklist spec: its manifest, Home Manager, fnm, uv, rustup, npm-prefix, agent, GUI, and LSP arrays mirror the active Phase 5 owners.
  Phase 5 verifies every command's owning path rather than checking presence alone, because GitHub runners preload several runtimes.
  LSP checks include version probes plus initialize handshakes for pyright and TypeScript, with `NODE_PATH` removed for TypeScript.
  Native Linux and macOS Home Manager CI runs those probes from each built profile, and template CI covers persisted Phase 3 data without the newer probe fields.
  The same native job diffs the built profile's full bin listing against the ownership metadata's command claims and version-probes the five runtime-manager executables, so an undeclared bundled command fails CI.
  The Ubuntu E2E proves an LSP health-check failure restores existing profiles and removes profiles after a failed first activation.
  It also tests plain direnv loading, `use flake`, and the nix-direnv GC root.
  The native Ubuntu workflow performs a second apply, requires the Home Manager generation to remain unchanged, and rejects unchanged native-runtime scripts rerunning.
  It preserves representative mise files, proves fnm automatic switching is disabled, checks exact Python and stable Rust ownership, performs a bounded Playwright MCP initialize handshake through fnm npx, and verifies project-flake runtime overrides inside Fish before restoring global paths.
  It also proves invalid selection and build failure preserve profiles, activation-time failure restores generation and package profiles, and failed first activation removes newly created profiles.
  Invariants that hold over plain, non-templated source files belong in a script under `.github/scripts/` that BOTH `ci.yml` and `verify.sh` call, not inline in `verify.sh` alone: the E2E is dispatch-only, so a check that lives only there never runs on a PR.
  `check-pi-model-pins.sh` is the reference shape - CI runs it against the source tree in `config-syntax`, the E2E runs the same script against the applied `~/.pi` tree, and `verify.sh` calls it OUTSIDE `hard` because `hard` redirects both of its command's output streams to `/dev/null`, which would swallow any per-item diagnostic; capture the report, echo it, then gate on the exit code.
  Its chezmoi-drift check excludes `.claude/settings.json` (the by-design drift documented in the [scripts and config rule](../bootstrap/scripts-and-config.md)) and `.chezmoiscripts/` (plain `run_after_` scripts are always-pending in `chezmoi status` by design), so only genuinely unexpected drift fails.
  `check-tool-ownership.sh` follows the same shared shape for the Phase 5 single-owner policy: CI's `home-manager` job and `verify.sh` both run it to validate `nix/data/tool-ownership.json` against the rendered `.chezmoidata/runtimes.yaml` policy, reject duplicate command owners and package-manifest overlap, and grep active bootstrap, Fish, and Pi files for forbidden mise or `--use-on-cd` patterns.
  `.github/e2e/prompt-test.sh` PTY-tests the interactive `headless` promptBoolOnce path via expect; its choreography (a real pty size via `stty_init`, syncing on the input line's "bool, default false" placeholder rather than the question text, sending the answer and the Enter as separate writes with pauses) encodes bubbletea TUI determinism rules - do not "simplify" it, and run it only after both main E2E matrix jobs pass.
- Phase 6 is an assurance and soak phase that does not change Phase 5 ownership.
  The dispatch workflow requires an immutable candidate SHA, runs native Ubuntu desktop and headless jobs, and uploads separate checksummed evidence artifacts.
  `verify.sh verify` requires the exact expected configuration and applies profile-specific GUI, WSL2, selection, direnv, and ownership checks.
  Real WSL2, physical Apple Silicon GUI acceptance, two primary-machine cycles, and the no-GC attestation remain manual gates in `.github/phase-6-acceptance.md`.
  Do not represent hosted macOS activation as physical GUI acceptance.
- Phase 6 CI must reject executable automation that performs Nix garbage collection, generation expiry, profile-history wiping, or mise cleanup.
  Manual cleanup commands belong only in the acceptance ledger and must never move into chezmoi, Home Manager, Fish, or workflow code.
  Retain the native E2E's representative mise fixtures permanently so every candidate proves that an apply leaves rollback data untouched.
