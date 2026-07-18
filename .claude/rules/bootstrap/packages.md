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
  `install_mise` backs the Linux CLI tools (eza, gum, starship, atuin, bat, fd, ripgrep, zoxide, direnv, tmux) via mise's aqua backend: it guards on `command -v <bin>`, resolves mise through `resolve_mise` (mise's shims are not on PATH during a non-interactive apply), then runs `mise use -g <tool>`; the separate `mise use -g` block later in the script installs toolchains (node/python/rust/go/fzf/bun/neovim/uv) plus the npm-distributed pi and Hunk CLIs and is NOT part of the manifest.

## Vendor script installers

- The `script` method (the curl-style vendor installers: mise, pfetch, brev, treehouse, no-mistakes, herdr, voquill) is emitted VERBATIM inline by the loop rather than through a helper, because those commands carry shell quoting (`'=https'`, `"$(curl ...)"`, embedded `jq` with `"..."`) that cannot round-trip through a positional argument.
  Its guard is `command -v <bin>` (plus an optional `altpath` for mise, or a `dpkg -s <pkg>` guard for voquill whose installed binary name differs) - keep those guards on the manifest entry, not hand-coded.
  `run_once_before_10` does `mkdir -p "$HOME/.local/bin"` + `prepend_path "$HOME/.local/bin"` on EVERY OS before the loop; the two lines are load-bearing for different installers, so keep both.
  `prepend_path` serves treehouse (`grep -qx` over `$PATH`) and no-mistakes (`case ":$PATH:"`, for its symlink dir), the only two that choose a target dir by `$PATH` MEMBERSHIP alone - the directory's existence is never part of that choice - and otherwise fall back to `/usr/local/bin`, where treehouse `sudo mv`s its binary and no-mistakes `sudo ln -s`es a symlink (its binary always goes to `$HOME/.no-mistakes/bin`, never through sudo); under the inlined `set -euo pipefail` a failed sudo there aborts the whole bootstrap.
  `mkdir` serves pfetch, whose Linux command curls straight into `$HOME/.local/bin/pfetch`, and it is also what keeps treehouse off that sudo branch: treehouse guards its plain `mv` on `[ -w "$INSTALL_DIR" ]`, which a nonexistent dir fails, so PATH membership without the dir would leave a root-owned `~/.local/bin` inside `$HOME`.
  mise, brev and herdr need neither line - each writes to `~/.local/bin` unconditionally and creates it itself, and herdr never invokes sudo at all.
  The `mkdir` used to live inside the linux-only prep branch, so on macOS it never ran at all - keep both lines OS-agnostic and ahead of the loop, and note that `prepend_path` also makes the loop's own `command -v <bin>` guards see what a previous apply installed there.

## Linux CLI package choices

- The Linux CLI tools now install via mise (aqua backend): eza/gum (previously third-party apt-repo+keyring), starship/atuin (previously curl vendor installers), and bat/fd/ripgrep/zoxide/tmux (previously apt) all use the `mise:` method; tmux specifically moved off apt so Linux gets tmux 3.5+ (Ubuntu 24.04 apt ships 3.4, which lacks the `extended-keys-format` option `tmux.conf` sets), while macOS stays on brew tmux.
  `jq` and `op` (1Password) deliberately stay native on Linux: `jq` is a `command -v jq || exit 1` bootstrap dependency of the apply-time MCP/plugin scripts (and is used bare in obsidian's installer) so it must not rely on mise shims absent from a fresh-apply PATH, and `op` unlocks chezmoi's secret reads at apply time before mise is active.
  Because of the flip the eza/gum apt-repos (and their `aptrepos.*` lookup entries) and the post-loop batcat->bat / fdfind->fd symlink fixup were removed, and the eza `ls` aliases in `config.fish` moved to after `mise activate` so a mise-installed eza is on PATH when probed; 1Password keeps its debsig setup (`install_debsig` before `install_aptrepo`, with the dynamic `$(dpkg --print-architecture)` in the repo line) and obsidian keeps resolving its `.deb` URL from the GitHub releases API at runtime.
  The manifest is order-sensitive on Linux (curl + ca-certificates before mise, mise before every `mise:` tool because `install_mise` no-ops until mise resolves, gnupg before the op and gh apt-repos, software-properties-common before the ghostty PPA); macOS is brew/cask plus the three self-contained curl `script` installers (treehouse, no-mistakes, herdr), and order-independent.
  `gh` deliberately stays native, NOT mise: brew on macOS and GitHub's official apt-repo on Linux (`aptrepos.gh`, sharing op's `install_aptrepo` path - gh's keyring is already binary but `gpg --dearmor` passes binary OpenPGP through byte-for-byte, and gh needs no debsig).
  This reverses an earlier gh-on-mise consolidation: a mise-shim gh is invisible to any process launched with a sanitized PATH that drops the mise shims dir (notably the no-mistakes daemon's git subprocess), which a one-off `~/.local/bin/gh -> mise shim` symlink had been the stopgap for; an apt gh at `/usr/bin/gh` is on the plain system PATH everything sees, so that symlink is removed and no per-machine hack is needed.
  atuin's manifest flipped to mise but its vendor runtime remnants (`~/.atuin/bin` on the fish `fish_add_path`, the `~/.atuin/bin/atuin-update` branch in `update-all.fish`) were left in place on purpose: `install_mise` skips the install on an existing machine that already has vendor atuin (`command -v` guard), so pruning them in the same change would strand it; they are harmless on a fresh machine where `~/.atuin/bin` never exists.
  Prove equivalence by rendering the script for darwin / linux / WSL (force `.chezmoi.os` + `.isWSL` via `sed` on a copy, render with `chezmoi --source "$PWD" execute-template`) and diffing the canonical install actions against a known-good baseline.
