---
paths:
  - ".chezmoidata/packages.yaml"
  - ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
  - ".chezmoitemplates/{lib-install.sh,lib-apt.sh,lib-resolve.sh}"
  - ".github/e2e/verify.sh"
  - "dot_config/fish/{config.fish.tmpl,functions/update-all.fish}"
  - "dot_config/tmux/tmux.conf"
---

<!-- markdownlint-disable MD013 -->

# Package installation context

## Package manifest

- The package set the bootstrap installs is data, not code: `.chezmoidata/packages.yaml` describes each package once (`.packages`, plus an `.aptrepos` lookup table), and `run_once_before_10-install-packages.sh.tmpl` walks it in ONE template loop that dispatches each entry to a per-method `install_*` helper in `.chezmoitemplates/lib-install.sh` by OS + method.
  Adding or removing a tool is a one-line manifest edit (plus its mirror line in `.github/e2e/verify.sh`'s expected-bin arrays - see the [CI and E2E rule](../quality/ci-and-e2e.md)); the only shell that changes is `lib-install.sh` when a genuinely new install *method* appears.
  The method vocabulary is `brew` / `cask` / `apt` (optional sibling `ppa`) / `aptrepo` / `flatpak` / `deburl` / `script` / `mise`, and each helper reproduces exactly that method's pre-refactor idempotency guard (`brew`/`cask` lean on brew's own idempotency, `apt`/`flatpak`/`deburl` guard on `command -v` or `flatpak info`, `aptrepo` is guarded at the call site).
  A package carries its method under `darwin:`, `linux:`, or the shared fallback `any:`; the loop takes the current OS's key when the package has one and falls back to `any:` otherwise, so an explicit `darwin:`/`linux:` always overrides `any:` and a package with neither is skipped on that OS.
  `any:` is for tools whose installer command is byte-identical on both OSes - today the three curl `script` installers treehouse, no-mistakes, and herdr - so the command is single-sourced and cannot drift on one OS during a URL or flag change; the `any:` branch is additionally gated on `$supportedOS` (darwin or linux) so an unsupported OS still installs nothing.
  In Phase 2, `install_mise` backs only direnv from the package manifest.
  The separate `mise use -g` block installs the remaining runtimes (node/python/rust/go/bun/uv) plus the npm-distributed Pi and Hunk CLIs.
  Home Manager owns eza, gum, starship, atuin, bat, fd, ripgrep, zoxide, tmux, fzf, and Neovim, so none may appear in the package manifest or mise toolchain block.

## Vendor script installers

- The `script` method (the curl-style vendor installers: mise, pfetch, brev, treehouse, no-mistakes, herdr, voquill) is emitted VERBATIM inline by the loop rather than through a helper, because those commands carry shell quoting (`'=https'`, `"$(curl ...)"`, embedded `jq` with `"..."`) that cannot round-trip through a positional argument.
  Its guard is `command -v <bin>` (plus an optional `altpath` for mise, or a `dpkg -s <pkg>` guard for voquill whose installed binary name differs) - keep those guards on the manifest entry, not hand-coded.
  `run_once_before_10` does `mkdir -p "$HOME/.local/bin"` + `prepend_path "$HOME/.local/bin"` on EVERY OS before the loop; the two lines are load-bearing for different installers, so keep both.
  `prepend_path` serves treehouse (`grep -qx` over `$PATH`) and no-mistakes (`case ":$PATH:"`, for its symlink dir), the only two that choose a target dir by `$PATH` MEMBERSHIP alone - the directory's existence is never part of that choice - and otherwise fall back to `/usr/local/bin`, where treehouse `sudo mv`s its binary and no-mistakes `sudo ln -s`es a symlink (its binary always goes to `$HOME/.no-mistakes/bin`, never through sudo); under the inlined `set -euo pipefail` a failed sudo there aborts the whole bootstrap.
  `mkdir` serves pfetch, whose Linux command curls straight into `$HOME/.local/bin/pfetch`, and it is also what keeps treehouse off that sudo branch: treehouse guards its plain `mv` on `[ -w "$INSTALL_DIR" ]`, which a nonexistent dir fails, so PATH membership without the dir would leave a root-owned `~/.local/bin` inside `$HOME`.
  mise, brev and herdr need neither line - each writes to `~/.local/bin` unconditionally and creates it itself, and herdr never invokes sudo at all.
  The `mkdir` used to live inside the linux-only prep branch, so on macOS it never ran at all - keep both lines OS-agnostic and ahead of the loop, and note that `prepend_path` also makes the loop's own `command -v <bin>` guards see what a previous apply installed there.

## Phase 2 CLI ownership

- Home Manager owns eza, gum, starship, atuin, bat, fd, ripgrep, zoxide, tmux, fzf, and Neovim on every platform.
  The package manifest and mise toolchain block must not claim them.
  Existing mise or Homebrew copies remain installed for rollback, but Fish re-prepends `~/.nix-profile/bin` after mise and Homebrew initialization.
- `jq`, `gh`, and `op` remain native because bootstrap and sanitized-path processes require them before runtime-manager activation.
  Linux uses apt or official apt repositories, and macOS uses Homebrew.
- direnv remains mise-managed on Linux and Homebrew-managed on macOS until Phase 3.
- The Linux manifest remains order-sensitive: curl and ca-certificates precede mise, gnupg precedes the op and gh repositories, and software-properties-common precedes the ghostty PPA.
- The chezmoi-owned tmux helper falls back to `~/.nix-profile/bin/fzf` when tmux sanitizes PATH.
- Do not uninstall old package implementations during the Phase 2 rollback window.
