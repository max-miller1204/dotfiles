# dotfiles

Chezmoi-managed dotfiles for Max. Targets **Ubuntu**, **macOS**, and **WSL Ubuntu** (which uses the Linux path with desktop apps gated off — see [WSL Ubuntu](#wsl-ubuntu)).

## Commands

| Command | What it does |
| --- | --- |
| `chezmoi update` | `git pull` **+** `chezmoi apply`. Use on a machine to pull in changes pushed from another machine. |
| `chezmoi apply` | Apply the **local** source tree to `$HOME`. Use after editing something locally. |
| `chezmoi diff` | Preview what `apply` would change — no writes. |
| `chezmoi edit <file>` | Edit a managed file (opens the source template, not the target in `$HOME`). |
| `chezmoi cd` | Drop into a shell inside the chezmoi source repo. Exit with `exit` / Ctrl-D. |
| `chezmoi add <path>` | Start tracking a file that already exists in `$HOME`. |
| `chezmoi add --encrypt <path>` | Same, but age-encrypt it in the source tree (for secrets). |
| `chezmoi re-add` | Pull edits you made directly to files in `$HOME` back into the source. |
| `update-all` | Fish function — refreshes brew / apt / flatpak, mise toolchains, chezmoi, atuin. |

Then `git add … && git commit && git push` from inside `chezmoi cd` to share changes with your other machines.

On first `chezmoi apply`, a `run_once_before` script installs every CLI these
dotfiles expect (fish, tmux, neovim, eza, fzf, zoxide, starship, bat, fd,
ripgrep, jq, atuin, mise, gum, pfetch, plus Homebrew on macOS / an apt
repo for eza on Ubuntu). `run_once_after` scripts clone TPM + install tmux
plugins and drop the LazyVim starter into `~/.config/nvim` if it's empty.

## Bootstrap a new machine

```sh
# macOS: install chezmoi (brings curl along for the ride)
brew install chezmoi
# Ubuntu: one-liner from the chezmoi site
sh -c "$(curl -fsSL https://get.chezmoi.io)"

chezmoi init --apply max-miller1204/dotfiles
```

> **Migrating from an existing Mac?** See [Migrating to a new Mac](#migrating-to-a-new-mac) for the pre/post-migration checklist (age key, Raycast re-export, SSH, etc.) before running the commands above.

That's it — the install scripts run during `apply` and handle the rest:

- installs CLIs (apt on Ubuntu, Homebrew on macOS): fish, tmux, eza, zoxide,
  starship, bat, fd, ripgrep, jq, atuin, mise, gum, pfetch, brev
  (Nvidia cloud GPU CLI — brew tap on macOS, official curl installer on Linux).
  `gh` is macOS-only (Homebrew); on Ubuntu install it yourself if you need it
- installs **GUI apps** (casks on macOS; PPA/.deb/flatpak on Ubuntu):
  ghostty, discord, voquill, zoom, anki, obsidian, spotify, plus
  zed, aerospace, karabiner-elements, raycast, neovide-app, balenaetcher,
  macdown-3000, pearcleaner, firefox on macOS (Linux ships Firefox by
  default; zed and Chrome are macOS-only; on Ubuntu zoom installs via flatpak)
- installs the **JetBrainsMono Nerd Font** cask on macOS (required by
  the ghostty config, which specifies it with no fallback). Linux skips
  it — starship/eza icons degrade gracefully to system fallback fonts
- installs **toolchains via mise**: `node@lts`, `python@latest`,
  `rust@latest`, `go@latest`, `fzf@latest`, `bun@latest`, `neovim@latest`
  (so fzf/bun/neovim are mise-managed, not apt/brew)
- installs **Nix** via the Determinate installer
- installs **Claude Code** via the official installer
  (`curl -fsSL https://claude.ai/install.sh | bash`) — lands in
  `~/.local/bin/claude` and self-updates in the background
- installs the **1Password CLI (`op`)** — Homebrew cask `1password-cli` on macOS, the official apt repo on Linux. MCP runner scripts read secrets from 1Password at invocation time (see [Secrets](#secrets-1password))
- adds fish to `/etc/shells` and sets it as your login shell
- clones TPM and installs tmux plugins
- drops the LazyVim starter into `~/.config/nvim` if nothing's there yet

Open a new terminal after the first run so fish picks up. You may need to log
out/in for the shell change to take effect. If `chsh` was skipped (it can
silently fail inside some TTYs), run it manually:

```sh
chsh -s "$(command -v fish)"
```

## Secrets (1Password)

Secrets live in 1Password and are fetched at invocation time via the `op` CLI.
Nothing encrypted is committed to git anymore, and nothing plaintext lands on
disk — runners just `op read` the value and pass it through to the consumer.

Current items (vault `Personal`):

| Reference | Used by |
| --- | --- |
| `op://Personal/context7/credential` | `dot_codex/executable_run-context7.sh` (Upstash Context7 MCP) |

### First-time setup on a new machine

1. **Install the 1Password CLI.** The bootstrap script installs it for you
   (Homebrew cask `1password-cli` on macOS, official apt repo on Linux). If
   you're setting up before the first `chezmoi apply`, install it yourself —
   see [developer.1password.com/docs/cli](https://developer.1password.com/docs/cli/get-started/).

2. **Sign in.** The smoothest path is biometric unlock via the desktop app:
   1Password desktop → Settings → Developer → "Integrate with 1Password CLI."
   Then `op signin` once and `op` will resolve transparently from any shell.
   Without the desktop app, `eval "$(op signin)"` per shell session works too.

3. **Verify** the reference resolves:

   ```sh
   op read 'op://Personal/context7/credential' | head -c 8
   # Should print the first 8 chars of the API key (no errors)
   ```

### Adding or rotating a secret

```sh
# Create a new item:
op item create --category=apicredential --vault=Personal \
  --title=NAME "credential[concealed]=THE-SECRET"

# Rotate an existing one:
op item edit NAME --vault=Personal "credential[concealed]=NEW-SECRET"
```

Then update (or add) the runner script that consumes it to call
`op read 'op://Personal/NAME/credential'`. See
`dot_codex/executable_run-context7.sh` for the pattern.

## MCP servers (Claude Code + Codex)

Declared once in `dot_config/claude-code/mcp-servers.json.tmpl` and
`dot_config/codex/mcp-servers.toml.tmpl` — these are staging files. On every
`chezmoi apply` where either changes, a `run_onchange_after_*` script syncs
them in place:

- `~/.claude.json` (user scope) — via `claude mcp remove` + `claude mcp add-json`
- `~/.codex/config.toml` — via awk-strip + append

Managed server names are listed in `.chezmoi.toml.tmpl` under
`[data] managedMcpNames`. The sync scripts only touch those names, so anything
else you've added manually in `~/.claude.json` or `~/.codex/config.toml` is
preserved. Verify with `claude mcp list`.

## What's here

Cross-platform:
- `dot_gitconfig` — git identity, aliases, sane defaults, gh credential helper
- `dot_config/fish/config.fish.tmpl` — fish shell (aliases, env, prompt init)
- `dot_config/fish/functions/*.fish` — custom fish functions (includes `update-all`, which refreshes the system package manager — brew on macOS, apt + flatpak on Ubuntu — plus mise, chezmoi, and atuin in one go)
- `dot_config/fish/themes/Catppuccin Mocha.theme`
- `dot_config/tmux/tmux.conf` — tmux (TPM-based plugins)
- `dot_config/ghostty/config` + `themes/catppuccin-mocha`
- `dot_config/atuin/*` — shell history sync config + theme
- `dot_config/bat/*` — bat pager syntax + theme
- `dot_config/starship.toml` — prompt
- `dot_config/claude-code/mcp-servers.json.tmpl` — staging JSON; sync'd into `~/.claude.json` by `run_onchange_after_40-sync-claude-mcp.sh.tmpl`
- `dot_config/codex/mcp-servers.toml.tmpl` — staging TOML; sync'd into `~/.codex/config.toml` by `run_onchange_after_41-sync-codex-mcp.sh.tmpl`
- `dot_claude/settings.json` + `executable_statusline.sh`
- `dot_codex/executable_run-context7.sh` — context7 MCP launcher; reads the API key from 1Password (`op://Personal/context7/credential`)
- `dot_claude/skills/spec/` — Claude skills

macOS-only (gated via `.chezmoiignore`):
- `dot_config/karabiner/karabiner.json`
- `dot_config/aerospace/aerospace.toml`
- `dot_config/raycast-scripts/*.sh` — Raycast Script Commands (plaintext
  shell scripts with `@raycast.*` headers)
- `private_dot_local/bin/executable_mac-askpass` — osascript dialog used
  as `SUDO_ASKPASS` so Claude Code's `!` (no TTY) can run sudo commands

Linux-only (gated via `.chezmoiignore`):
- `private_dot_local/bin/executable_zenity-askpass` — zenity equivalent
  of mac-askpass

WSL-only adjustments (gated via the `isWSL` flag in `.chezmoi.toml.tmpl`):
- `.chezmoiignore` skips `dot_config/ghostty` (use Windows Terminal instead)
- The bootstrap skips the Linux desktop-app block (ghostty, discord, voquill,
  obsidian, anki, spotify, zoom, brev) so WSL only gets CLI tools

### Raycast settings

On a new Mac, two manual steps wire Raycast up to the managed config:

1. **Import preferences**: the exported snapshot lives at
   `raycast-export/raycast.rayconfig` (plaintext, not chezmoi-applied —
   the repo is its only home). Open Raycast → Settings → Advanced →
   Import and pick that file.
2. **Point Raycast at the script commands**: Raycast → Settings →
   Extensions → Script Commands → add `~/.config/raycast-scripts` to the
   directory list. Scripts in there are managed by chezmoi.

To update the snapshot after changing settings: re-export from Raycast
(Settings → Advanced → Export) and drop the resulting `.rayconfig` over
`raycast-export/raycast.rayconfig`.

Bootstrap scripts (not applied to `$HOME`, run during `chezmoi apply`):
- `.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl` — packages, toolchains, Nix, Claude Code, fish-as-login-shell
- `.chezmoiscripts/run_once_after_20-install-tpm.sh.tmpl` — TPM + tmux plugins
- `.chezmoiscripts/run_once_after_30-install-lazyvim.sh.tmpl` — LazyVim starter (only if `~/.config/nvim` is missing)
- `.chezmoiscripts/run_onchange_after_40-sync-claude-mcp.sh.tmpl` — re-syncs MCPs into `~/.claude.json` whenever the staging JSON changes
- `.chezmoiscripts/run_onchange_after_41-sync-codex-mcp.sh.tmpl` — re-syncs MCPs into `~/.codex/config.toml` whenever the staging TOML changes

## WSL Ubuntu

These dotfiles target Ubuntu inside WSL2 — Windows-native is not supported. The
`isWSL` flag in `.chezmoi.toml.tmpl` auto-detects the WSL kernel
(`microsoft-standard-WSL2`) and adapts: the Linux bootstrap runs, but the
desktop-app block (ghostty, discord, obsidian, anki, spotify, zoom, …) is
skipped, and `dot_config/ghostty` is ignored. Use the Windows-native versions
of those apps and Windows Terminal as your terminal emulator.

### Bootstrap inside WSL Ubuntu

Open WSL Ubuntu and run:

```sh
# Install chezmoi (one-liner from the chezmoi site)
sh -c "$(curl -fsSL https://get.chezmoi.io)"

# Install 1Password CLI (the bootstrap will do this anyway, but install
# it first if you want secrets to resolve during the very first apply)
# — see https://developer.1password.com/docs/cli/get-started/

# Clone + apply
chezmoi init --apply max-miller1204/dotfiles
```

The first apply installs CLIs, mise toolchains, Nix, Claude Code, and the
1Password CLI, then sets fish as your login shell.

### 1Password sign-in from WSL

The cleanest setup is the **desktop-app integration**: install 1Password for
Windows, enable Settings → Developer → "Integrate with 1Password CLI," then in
WSL run `op signin` once. Subsequent `op read` calls just work (Touch ID / 
Windows Hello unlocks the desktop app, which acts as the keyring for the CLI).

Without the desktop app, you can `eval "$(op signin)"` per shell session.

### WSL-specific gotchas

- **Default shell.** `chsh` works in WSL2 but the change requires a new
  WSL session (`wsl --shutdown` from PowerShell, then reopen). If `chsh`
  fails inside the bootstrap, run it manually with `chsh -s "$(command -v fish)"`.
- **systemd.** Nix (via the Determinate installer) installs cleanly on Ubuntu
  WSL with systemd enabled — it's on by default on recent Ubuntu WSL images.
  If `systemctl status` returns "System has not been booted with systemd,"
  add `[boot] systemd=true` to `/etc/wsl.conf` and `wsl --shutdown`.
- **Don't run `chezmoi apply` against `/mnt/c/...`.** Keep the chezmoi source
  inside the Linux filesystem (`~/.local/share/chezmoi`, which is where
  `chezmoi init` puts it). Running it from `/mnt/c` would lose file modes and
  be much slower over the 9P bridge.

## Migrating to a new Mac

The bootstrap above handles packages and dotfiles. A few things live outside
the repo and need manual hand-off.

### Before you leave the old Mac

1. **Make sure 1Password sync is healthy** — secrets live there now (see
   [Secrets](#secrets-1password)). Confirm the items in the `Personal` vault
   are visible in the desktop app before you wipe the old machine.

2. **Commit and push anything in flight** in this repo:

   ```sh
   chezmoi cd
   git status && git push
   ```

3. **Re-export Raycast** if you've changed any preferences, hotkeys, quicklinks,
   or Snippets since the last commit — the snapshot is plaintext under
   `raycast-export/raycast.rayconfig` and is the only copy of your Raycast
   state the new Mac will see:

   ```sh
   # Raycast → Settings → Advanced → Export → overwrite raycast-export/raycast.rayconfig
   chezmoi cd
   git add raycast-export/raycast.rayconfig && git commit -m "raycast: snapshot" && git push
   ```

4. **Back up anything not in this repo** you actually want: `~/.ssh/`,
   `~/.gnupg/` (if you sign commits), Obsidian vaults, Anki collections,
   shell history if you don't use Atuin sync, app-specific state you care
   about. This repo doesn't manage any of that.

### On the new Mac

1. **Install Xcode Command Line Tools** (Homebrew's installer will trigger
   this automatically on first `brew install`, but doing it up front avoids
   a GUI popup mid-bootstrap):

   ```sh
   xcode-select --install
   ```

2. **Sign in to 1Password** (desktop app + CLI integration is easiest, see
   [Secrets](#secrets-1password)). MCP runners need `op read` working before
   they're first invoked, but `chezmoi apply` itself doesn't depend on it —
   you can do this after.

3. **Copy SSH keys** (or log in with `gh auth login` after chezmoi finishes —
   the gitconfig uses `gh auth git-credential` for HTTPS, so HTTPS clones
   work without SSH at all):

   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cp /path/to/backup/id_* ~/.ssh/
   chmod 600 ~/.ssh/id_*
   ```

4. **Bootstrap** — same command as the top of this README:

   ```sh
   brew install chezmoi
   chezmoi init --apply max-miller1204/dotfiles
   ```

5. **Open a new Ghostty tab** so fish picks up as the login shell. If fish
   isn't the default yet, run `chsh -s "$(command -v fish)"` manually — the
   bootstrap's `chsh` can silently fail inside some TTYs.

6. **Import Raycast** — see [Raycast settings](#raycast-settings) for the
   two-step dance (import `.rayconfig`, point Raycast at
   `~/.config/raycast-scripts`).

7. **Sign in to anything that isn't in secrets**: GitHub (`gh auth login`),
   Atuin (`atuin login` + `atuin sync` — `auto_sync` is off by default),
   1Password / password manager, Discord, Spotify, Obsidian, Zed account,
   Claude Code (`claude` → follow the login flow).

8. **Verify**:

   ```sh
   claude mcp list                              # should show nixos (+ playwright if added)
   mise list                                    # should show node, python, rust, go, fzf, bun, neovim, uv
   which brew fish claude op                    # sanity-check everything's on PATH
   op read 'op://Personal/context7/credential'  # confirms 1Password sign-in
   ```

9. **macOS system defaults** (Dock, Finder, trackpad, etc.) are **not**
   managed by this repo — configure them manually via System Settings, or
   add a `defaults write` script later if that becomes worth automating.

## Updating

- `chezmoi edit <file>` to edit a managed file, or `chezmoi cd` to jump into the source repo
- `chezmoi diff` to preview, `chezmoi apply` to write changes
- The install script is `run_once` — it only reruns if its content changes
- `update-all` (fish function) refreshes everything the bootstrap installs: brew (formulae + casks) on macOS or apt (+ PPAs) + flatpak on Ubuntu, plus mise toolchains, chezmoi itself, and atuin
