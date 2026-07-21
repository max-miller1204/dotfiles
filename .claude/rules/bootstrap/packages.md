---
paths:
  - ".chezmoidata/packages.yaml"
  - ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
  - ".chezmoiscripts/run_onchange_before_{15-install-nix-profile,16-install-language-runtimes,17-install-hunk}.sh.tmpl"
  - ".chezmoiscripts/run_onchange_after_50-install-lsp-servers.sh.tmpl"
  - ".chezmoitemplates/{lib-install.sh,lib-apt.sh,lib-resolve.sh}"
  - ".github/e2e/verify.sh"
  - "dot_config/fish/{config.fish.tmpl,functions/update-all.fish.tmpl,functions/lsp-upgrade.fish.tmpl}"
  - "dot_config/tmux/{tmux.conf,executable_agent-switch.sh}"
  - "nix/**/*"
  - "renovate.json"
---

<!-- markdownlint-disable MD013 -->

# Package installation context

## Package manifest

- `.chezmoidata/packages.yaml` is the data source for native bootstrap packages, and `run_once_before_10-install-packages.sh.tmpl` walks it in one template loop that dispatches each entry to a per-method `install_*` helper in `.chezmoitemplates/lib-install.sh` by OS and method.
  Executables owned by the checked-in Nix bundle must be absent from this manifest on every platform.
  Adding or removing a native tool is a manifest edit plus its mirror in `.github/e2e/verify.sh`.
  The only helper change should be for a genuinely new install method.
  The method vocabulary is `brew` / `cask` / `apt` (optional sibling `ppa`) / `aptrepo` / `flatpak` / `deburl` / `script`, and each helper reproduces exactly that method's pre-refactor idempotency guard (`brew`/`cask` lean on brew's own idempotency, `apt`/`flatpak`/`deburl` guard on `command -v` or `flatpak info`, `aptrepo` is guarded at the call site).
  A package carries its method under `darwin:`, `linux:`, or the shared fallback `any:`; the loop takes the current OS's key when the package has one and falls back to `any:` otherwise, so an explicit `darwin:`/`linux:` always overrides `any:` and a package with neither is skipped on that OS.
  `any:` is for tools whose installer command is byte-identical on both OSes - today the three curl `script` installers treehouse, no-mistakes, and herdr - so the command is single-sourced and cannot drift on one OS during a URL or flag change; the `any:` branch is additionally gated on `$supportedOS` (darwin or linux) so an unsupported OS still installs nothing.
  mise is not an active package owner or install method.

## Checked-in Nix bundle

- Only the `nix/` subtree is a flake source.
  Use an explicit `path:.../nix` flake reference even when running from inside that directory.
  An implicit Git flake can select the repository root and copy unrelated tracked files into the store.
  Never point a Nix command at the chezmoi repository root because future encrypted data or secret templates elsewhere in the source must not enter the store.
- `nix/flake.nix` exposes `core`, cumulative `headless`, cumulative `lsp`, cumulative `workstation`, and `default` as an alias of `workstation` for x86_64/aarch64 Linux and Darwin.
  Unstable nixpkgs serves Linux and Apple Silicon Darwin, while the separate `nixpkgs-darwin-intel` input (the `nixpkgs-26.05-darwin` branch) serves Intel Darwin through its final support line.
- Every bundle uses `pkgs.buildEnv` with `/bin` and `/share`, and `ignoreCollisions = false`.
  Do not hide duplicate ownership with priorities or ignored collisions.
- `run_onchange_before_15-install-nix-profile.sh.tmpl` hashes every flake file plus machine bundle data, builds and smoke-tests before activation, and manages one `dotfiles-workstation` element in `${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/dotfiles`.
  A failed build must leave the prior profile generation active.
  Never add other packages to this profile and never install overlapping bundle outputs separately.
- The profile PATH is explicit in bootstrap and Fish.
  Fish puts the dedicated profile above native package-manager paths, prepends uv Python, rustup, Bun, and fnm runtime paths, and removes any stale mise shim path inherited from an older shell.
  Do not restore mise activation or dynamic project hooks; project-specific environments belong to direnv and flakes.
  Project direnv environments remain highest priority.

## Mutable language runtimes

- `run_onchange_before_16-install-language-runtimes.sh.tmpl` runs after the Nix profile is active.
  Nix owns the `fnm` and `uv` executables, while fnm owns Node LTS and uv owns Python 3 installations and environments.
  `UV_PYTHON_BIN_DIR` is isolated under the uv data directory so Python can outrank stale mise shims without moving every command in `~/.local/bin` above Nix.
  Official rustup owns stable Rust, Cargo, targets, and rust-analyzer under `${CARGO_HOME:-~/.cargo}`.
  Bun remains under `${BUN_INSTALL:-~/.bun}` through its official installer.
  The Bun destination is placed on PATH before invoking the installer so the installer does not append unmanaged lines to Fish config.
  Existing mise declarations and installations are audited but never deleted automatically.
- Go, gopls, Pyright, TypeScript, and typescript-language-server are Nix-owned and live in the cumulative `lsp` bundle.
  Never split Go from gopls because gopls invokes Go from PATH.
  Never split TypeScript from typescript-language-server because the server loads that module at runtime.
  The Nix package supplies its pinned TypeScript fallback internally, so Fish must not export a mise-specific `NODE_PATH`.

## Vendor script installers

- The `script` method (the curl-style vendor installers: pfetch, brev, treehouse, no-mistakes, herdr, voquill) is emitted VERBATIM inline by the loop rather than through a helper, because those commands carry shell quoting (`'=https'`, `"$(curl ...)"`, embedded `jq` with `"..."`) that cannot round-trip through a positional argument.
  Its guard is `command -v <bin>` or a `dpkg -s <pkg>` guard for voquill whose installed binary name differs; keep those guards on the manifest entry, not hand-coded.
  `run_once_before_10` does `mkdir -p "$HOME/.local/bin"` + `prepend_path "$HOME/.local/bin"` on EVERY OS before the loop; the two lines are load-bearing for different installers, so keep both.
  `prepend_path` serves treehouse (`grep -qx` over `$PATH`) and no-mistakes (`case ":$PATH:"`, for its symlink dir), the only two that choose a target dir by `$PATH` MEMBERSHIP alone - the directory's existence is never part of that choice - and otherwise fall back to `/usr/local/bin`, where treehouse `sudo mv`s its binary and no-mistakes `sudo ln -s`es a symlink (its binary always goes to `$HOME/.no-mistakes/bin`, never through sudo); under the inlined `set -euo pipefail` a failed sudo there aborts the whole bootstrap.
  `mkdir` serves pfetch, whose Linux command curls straight into `$HOME/.local/bin/pfetch`, and it is also what keeps treehouse off that sudo branch: treehouse guards its plain `mv` on `[ -w "$INSTALL_DIR" ]`, which a nonexistent dir fails, so PATH membership without the dir would leave a root-owned `~/.local/bin` inside `$HOME`.
  brev and herdr need neither line - each writes to `~/.local/bin` unconditionally and creates it itself, and herdr never invokes sudo at all.
  The `mkdir` used to live inside the linux-only prep branch, so on macOS it never ran at all - keep both lines OS-agnostic and ahead of the loop, and note that `prepend_path` also makes the loop's own `command -v <bin>` guards see what a previous apply installed there.

## Package ownership choices

- The checked-in `nix/` flake owns eza, bat, fd, ripgrep, fzf, gum, starship, atuin, zoxide, direnv, tmux, Neovim, nix-direnv, Go, gopls, Pyright, TypeScript, typescript-language-server, fnm, uv, and Pi on every supported system.
  They are absent from the native manifest.
  Hunk remains outside Nix because the pinned Intel Darwin package set does not provide it; `run_onchange_before_17` installs `hunkdiff@latest` through fnm-managed npm into the stable `~/.local/share/npm-hunkdiff` prefix and links `hunk` into `~/.local/bin`.
  Existing stale installs are not automatically deleted, and Fish removes stale mise shims from PATH so migrated owners win.
  Nix also gives Linux a tmux release new enough for the `extended-keys-format` option used by `tmux.conf` instead of Ubuntu 24.04's tmux 3.4.
  `jq` and `op` (1Password) deliberately stay native on Linux: `jq` is a `command -v jq || exit 1` bootstrap dependency of the apply-time MCP/plugin scripts (and is used bare in obsidian's installer), and `op` unlocks chezmoi's secret reads before the dedicated Nix profile is active.
  The eza `ls` aliases are probed after the dedicated Nix profile PATH addition.
  1Password keeps its debsig setup, and Obsidian keeps resolving its `.deb` URL from the GitHub releases API at runtime.
  The manifest is order-sensitive on Linux (curl + ca-certificates before HTTPS vendor installers, gnupg before the op and gh apt-repos, software-properties-common before the ghostty PPA); macOS is brew/cask plus the three self-contained curl `script` installers (treehouse, no-mistakes, herdr), and order-independent.
  `gh` deliberately stays native, NOT mise: brew on macOS and GitHub's official apt-repo on Linux (`aptrepos.gh`, sharing op's `install_aptrepo` path - gh's keyring is already binary but `gpg --dearmor` passes binary OpenPGP through byte-for-byte, and gh needs no debsig).
  This reverses an earlier gh-on-mise consolidation: a mise-shim gh is invisible to any process launched with a sanitized PATH that drops the mise shims dir (notably the no-mistakes daemon's git subprocess), which a one-off `~/.local/bin/gh -> mise shim` symlink had been the stopgap for; an apt gh at `/usr/bin/gh` is on the plain system PATH everything sees, so that symlink is removed and no per-machine hack is needed.
  Atuin self-update is disabled now that Nix owns the executable.
  The legacy `~/.atuin/bin` PATH entry remains for non-executable vendor state and stale-install auditing, but the later dedicated-profile prepend guarantees its `atuin` wins.
  Prove equivalence by rendering the script for darwin / linux / WSL (force `.chezmoi.os` + `.isWSL` via `sed` on a copy, render with `chezmoi --source "$PWD" execute-template`) and diffing the canonical install actions against a known-good baseline.
