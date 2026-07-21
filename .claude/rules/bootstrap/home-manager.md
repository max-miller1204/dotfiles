---
paths:
  - "nix/**/*"
  - ".chezmoiscripts/*home-manager*"
  - "dot_config/fish/functions/hm-update.fish"
  - "dot_config/fish/functions/update-all.fish.tmpl"
  - ".github/workflows/ci.yml"
  - ".github/workflows/e2e-native-ubuntu.yml"
---

<!-- markdownlint-disable MD013 -->

# Home Manager migration context

## Direction and ownership

- Chezmoi may invoke standalone Home Manager, but Home Manager must never invoke chezmoi.
- Every global command has exactly one active owner.
- `nix/data/tool-ownership.json` records the exact Phase 5 Home Manager package and command surface plus each external runtime owner.
- Home Manager must not manage chezmoi-owned writable dotfiles during this migration.
- Do not use `xdg.configFile`, Fish configuration ownership, or Home Manager tool modules that generate writable configuration files.
- The only permitted `home.file` assignment is `lib.mkForce { }` in `base.nix`, which suppresses Home Manager 26.05's automatic `.cache/.keep` and `.local/state/.keep` links so the evaluated file set remains empty.
- Do not use a Home Manager backup extension because a target collision must fail visibly.

## Flake boundary and purity

- The standalone flake is nested under `nix/`, and every command must address it as an explicit `path:` flake such as `path:$CHEZMOI_SOURCE/nix`.
- Never evaluate the repository root as a flake because that would copy unrelated dotfiles into the Nix store.
- Keep secrets out of Nix evaluation, derivations, build inputs, logs, and the Nix store.
- Do not use `builtins.getEnv`, `--impure`, secret-bearing `specialArgs`, authenticated flake URLs, `op`, or secret values in Home Manager service definitions.
- A Home Manager module may eventually refer only to a runtime secret file path that chezmoi materializes with restrictive permissions.

## Generations and updates

- Home Manager activation must remain atomic, and a failed build must leave the previous generation active.
- If failure occurs after a profile changes, rollback must restore the exact captured Home Manager profile version with `nix profile rollback --to`, then restore the package profile through activation; a failed first activation must remove newly created profiles.
- The activation script creates the XDG Nix profiles directory before recording state and switching, because a fresh machine has no `~/.local/state/nix/profiles` and the first standalone switch fails without it.
- Do not add ad hoc `nix profile install` commands.
- `update-all` must never update `nix/flake.lock`.
- The dedicated `hm-update` command introduced in the activation phase owns lock updates and must leave the updated lock file for review and commit.
- Phase 6 retains every generation and profile-history entry throughout the platform soak.
- Do not add automatic Nix garbage collection, generation expiry, history wiping, or manual store cleanup until the Phase 6 ledger records two successful primary-machine cycles and an approved no-GC attestation.

## Phase 5 active package bundles

- Phase 5 activates Home Manager on every apply before chezmoi changes managed target files.
- Home Manager actively owns the Phase 4 CLI, direnv, and LSP bundles plus fnm, uv, rustup, Go, and Bun.
- The runtime module exposes only bun, fnm, go, gofmt, rustup, and uv so Home Manager does not claim native-manager payloads or extra package commands.
- The LSP packages expose pyright-langserver, tsc, tsserver, and clangd alongside their primary commands, and all exposed global commands are recorded in the ownership metadata.
- `run_before_15` runs the LSP health checks inside the Home Manager switch transaction, so a failure restores both profiles or removes a failed first generation.
- `run_after_50-verify-lsp-servers` repeats Home Manager profile resolution plus startup or version checks after target updates on every apply.
- The TypeScript initialize probe runs without `NODE_PATH`, proving the Nix package closure replaces the former mise-prefix workaround.
- The `clang-tools` input is narrowed to a clangd-only profile output so unrelated clang commands do not become accidental global Home Manager owners.
- Package narrowing goes through the shared `nix/lib/command-only.nix` helper, and the CLI module narrows every package it owns, so the built profile's bin listing must equal the recorded command claims.
- Home Manager still owns no writable configuration or user service.
- The activation script validates the selected flake output against the current username, home directory, and Nix system.
- Before evaluation and switching, the script prepends the resolved Nix binary's directory to `PATH` because `nix run` launches Home Manager with the inherited PATH and Home Manager invokes `nix` by name, so a Determinate installation completed earlier in the same apply stays visible.
- That identity check evaluates one `nix eval --json` attribute set and parses it with the native `jq`, which the script resolves through `prepend_path` and requires before evaluation.
- WSL selection wins over the Linux headless profile.
- `DOTFILES_HM_CONFIGURATION` is restricted to declared real or CI outputs.
- Existing configurations that predate the Home Manager data keys default to enabled activation and derive the matching real-user class output.
- The real host records are `max` at `/home/max` on Linux and `/Users/max` on macOS.
- CI host records are `runner` at `/home/runner` on Linux and `/Users/runner` on macOS.
- Class profiles are used until a hostname-specific requirement is demonstrated.
- Keep old mise or Homebrew installations during the rollback window, but never activate or update mise from Phase 5 code.
- Full Phase 5 rollback requires the previous Home Manager generation and the reverted Phase 5 repository commit because Fish and native runtime ownership change together.
- Phase 6 changes validation only and must not alter this ownership model, flake structure, activation transaction, or rollback procedure.
- Native Ubuntu desktop/headless and hosted native macOS evidence may be automated, but real WSL2 and physical Apple Silicon GUI acceptance remain manual release gates recorded in `.github/phase-6-acceptance.md`.
