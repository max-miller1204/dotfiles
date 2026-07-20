---
paths:
  - ".chezmoidata/{packages,runtimes}.yaml"
  - ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
  - ".chezmoiscripts/run_onchange_after_{16-ensure-native-runtimes,17-install-npm-tools}.sh.tmpl"
  - ".chezmoitemplates/{lib-install.sh,lib-apt.sh,lib-resolve.sh}"
  - ".github/e2e/verify.sh"
  - "dot_config/fish/{config.fish.tmpl,functions/update-all.fish.tmpl}"
  - "dot_config/tmux/tmux.conf"
  - "dot_config/tmux/executable_agent-switch.sh"
---

<!-- markdownlint-disable MD013 -->

# Package and runtime installation context

## Package manifest

- `.chezmoidata/packages.yaml` describes each native or vendor-installed package once, plus the `aptrepos` lookup table.
- `run_once_before_10-install-packages.sh.tmpl` walks the package list in one loop and dispatches each entry to a helper in `lib-install.sh` by OS and method.
- The method vocabulary is `brew`, `cask`, `apt` with an optional `ppa`, `aptrepo`, `flatpak`, `deburl`, and `script`.
- A package carries its method under `darwin:`, `linux:`, or the shared `any:` fallback.
- `any:` is only for byte-identical installers on both supported operating systems.
- Home Manager packages must never appear in this manifest.
- mise is not an install method or package owner in Phase 5.
- Existing mise binaries and data are retained for rollback but are never invoked by active bootstrap, shell, or update code.

## Vendor script installers

- The `script` method is emitted verbatim because vendor commands contain quoting that cannot safely round-trip through a positional argument.
- Its guard is `command -v <bin>`, with an optional `dpkg -s <pkg>` guard when the package and binary names differ.
- `run_once_before_10` must create and prepend `~/.local/bin` on every operating system before the package loop.
- That setup keeps treehouse and no-mistakes out of their sudo fallback paths and gives pfetch a valid destination.
- The Determinate Nix installer must retain its explicit root `HOME` and `XDG_CONFIG_HOME` protection.

## Phase 5 runtime ownership

- Home Manager owns only the `fnm`, `uv`, and `rustup` executables plus global Go and Bun fallbacks.
- `nix/modules/runtimes.nix` narrows Bun, uv, and rustup outputs so undeclared commands such as `bunx`, `uvx`, and Rust toolchain proxies do not leak into `~/.nix-profile/bin`.
- fnm owns the current Node LTS plus `node`, `npm`, and `npx`.
- Corepack is an optional fnm-owned command because not every future Node LTS is guaranteed to bundle it.
- uv owns exact global Python `3.14.6` and its `python`, `python3`, and `python3.14` links.
- rustup owns the stable Rust toolchain and the selected proxies under `~/.cargo/bin`.
- npm owns Pi and Hunk under the stable `~/.local/share/npm` prefix at their `latest` channels.
- `.chezmoidata/runtimes.yaml` is the single source for mutable runtime selectors, Rust proxies, npm package channels, and the npm prefix.
- `run_onchange_after_16` configures Node, Python, and Rust only after Home Manager activation provides their manager executables.
- `run_onchange_after_17` installs Pi and Hunk through fnm's selected npm.
- Neither script removes old runtime data, and both must fail visibly on ownership collisions.
- Rust toolchains are installed and verified before proxy switching, and any failed proxy switch restores archived paths.
- Fish must expose global paths in this order: fnm Node, npm prefix, Home Manager, rustup proxies, `~/.local/bin`, OpenCode, then native paths.
- fnm automatic project switching stays disabled because project flakes own directory-scoped overrides.
- `update-all` updates mutable runtime channels and npm tools but never updates `nix/flake.lock`.
- Go, Bun, and manager executable updates move only through the separately reviewed `hm-update` flow.

## Native package boundaries

- `jq`, `gh`, and `op` stay native because bootstrap and sanitized-path processes require them before user runtime initialization.
- Linux uses apt or official apt repositories, and macOS uses Homebrew.
- The chezmoi-owned direnvrc sources `$HOME/.nix-profile/share/nix-direnv/direnvrc`.
- The chezmoi-owned tmux helper falls back to `~/.nix-profile/bin/fzf` when tmux sanitizes PATH.
- The Linux manifest remains order-sensitive: gnupg precedes the op and gh repositories, and software-properties-common precedes the ghostty PPA.
