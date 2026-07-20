---
paths:
  - "nix/**/*"
  - ".chezmoiscripts/*home-manager*"
  - "dot_config/fish/functions/hm-update.fish"
  - ".github/workflows/ci.yml"
---

<!-- markdownlint-disable MD013 -->

# Home Manager migration context

## Direction and ownership

- Chezmoi may invoke standalone Home Manager, but Home Manager must never invoke chezmoi.
- Every global command has exactly one active owner.
- `nix/data/tool-ownership.json` records active Home Manager ownership separately from the final target ownership so inactive migration phases do not claim commands that mise or an OS package manager still provides.
- Home Manager must not manage chezmoi-owned writable dotfiles during this migration.
- Do not use `home.file`, `xdg.configFile`, Fish configuration ownership, or Home Manager tool modules that generate writable configuration files.
- Do not use a Home Manager backup extension because a target collision must fail visibly.

## Flake boundary and purity

- The standalone flake is nested under `nix/`, and every command must address it as an explicit `path:` flake such as `path:$CHEZMOI_SOURCE/nix`.
- Never evaluate the repository root as a flake because that would copy unrelated dotfiles into the Nix store.
- Keep secrets out of Nix evaluation, derivations, build inputs, logs, and the Nix store.
- Do not use `builtins.getEnv`, `--impure`, secret-bearing `specialArgs`, authenticated flake URLs, `op`, or secret values in Home Manager service definitions.
- A Home Manager module may eventually refer only to a runtime secret file path that chezmoi materializes with restrictive permissions.

## Generations and updates

- Home Manager activation must remain atomic, and a failed build must leave the previous generation active.
- Do not add ad hoc `nix profile install` commands.
- `update-all` must never update `nix/flake.lock`.
- The dedicated `hm-update` command introduced in the activation phase owns lock updates and must leave the updated lock file for review and commit.
- Do not add automatic Nix garbage collection until a generation retention policy and soak period have been approved.

## Phase 1 inactive foundation

- Phase 1 evaluates and builds configurations but does not activate them.
- Its active Home Manager package, command, writable-config, and service ownership lists must remain empty.
- The real host records are `max` at `/home/max` on Linux and `/Users/max` on macOS.
- CI host records are `runner` at `/home/runner` on Linux and `/Users/runner` on macOS.
- Class profiles are used until a hostname-specific requirement is demonstrated.
