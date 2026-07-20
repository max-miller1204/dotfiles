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
- If failure occurs after a profile changes, rollback must restore both the Home Manager generation profile and the package profile; a failed first activation must remove newly created profiles.
- Do not add ad hoc `nix profile install` commands.
- `update-all` must never update `nix/flake.lock`.
- The dedicated `hm-update` command introduced in the activation phase owns lock updates and must leave the updated lock file for review and commit.
- Do not add automatic Nix garbage collection until a generation retention policy and soak period have been approved.

## Phase 2 active CLI bundle

- Phase 2 activates Home Manager on every apply before chezmoi changes managed target files.
- Home Manager actively owns eza, gum, starship, atuin, bat, fd, ripgrep, zoxide, tmux, fzf, and Neovim binaries.
- Home Manager still owns no writable configuration or user service.
- The activation script validates the selected flake output against the current username, home directory, and Nix system.
- WSL selection wins over the Linux headless profile.
- `DOTFILES_HM_CONFIGURATION` is restricted to declared real or CI outputs.
- Existing configurations that predate the Phase 2 data keys default to enabled activation and derive the matching real-user class output.
- The real host records are `max` at `/home/max` on Linux and `/Users/max` on macOS.
- CI host records are `runner` at `/home/runner` on Linux and `/Users/runner` on macOS.
- Class profiles are used until a hostname-specific requirement is demonstrated.
- Keep old mise or Homebrew installations during the rollback window, but ensure `~/.nix-profile/bin` wins command resolution.
