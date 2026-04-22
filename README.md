# dotfiles

Chezmoi-managed dotfiles for Max. Targets **Ubuntu** and **macOS**.

On first `chezmoi apply`, a `run_once_before` script installs every CLI these
dotfiles expect (fish, tmux, neovim, eza, fzf, zoxide, starship, bat, fd,
ripgrep, jq, atuin, mise, gh, gum, pfetch, plus Homebrew on macOS / an apt
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
  starship, bat, fd, ripgrep, jq, atuin, mise, gh, gum, pfetch, brev
  (Nvidia cloud GPU CLI — brew tap on macOS, official curl installer on Linux)
- installs **GUI apps** (casks on macOS; PPA/.deb/flatpak on Ubuntu):
  ghostty, discord, zed, voquill, zoom, anki, obsidian, spotify, plus
  aerospace, karabiner-elements, raycast, neovide-app, balenaetcher,
  macdown-3000, pearcleaner, firefox on macOS (Linux ships Firefox by default)
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
- creates `~/.config/secrets` (mode 700) — chezmoi also manages this dir via the `private_secrets/` source, but the bootstrap keeps a fallback mkdir so the context7 launcher script can't blow up before the first apply
- adds fish to `/etc/shells` and sets it as your login shell
- clones TPM and installs tmux plugins
- drops the LazyVim starter into `~/.config/nvim` if nothing's there yet

Open a new terminal after the first run so fish picks up. You may need to log
out/in for the shell change to take effect. If `chsh` was skipped (it can
silently fail inside some TTYs), run it manually:

```sh
chsh -s "$(command -v fish)"
```

## Secrets (age-encrypted, committed to git)

Secrets are encrypted with [age](https://github.com/FiloSottile/age) using the
recipient declared in `.chezmoi.toml.tmpl`. Encrypted files live under
`dot_config/private_secrets/` in the source tree and decrypt to
`~/.config/secrets/` at `chezmoi apply` time.

### First-time setup on a new machine

1. Install `age` (the bootstrap script pulls it in via apt/brew on first run,
   but on a brand-new box you can install it manually first).

2. Put the age **identity** (private key) at `~/.config/chezmoi/age-key.txt`,
   mode 600. On the machine that already has it, just copy it over. On a
   fresh key, generate one:

   ```sh
   mkdir -p ~/.config/chezmoi && chmod 700 ~/.config/chezmoi
   age-keygen -o ~/.config/chezmoi/age-key.txt
   chmod 600 ~/.config/chezmoi/age-key.txt
   # Back up the AGE-SECRET-KEY-1… line to a password manager!
   # Then paste the public key into .chezmoi.toml.tmpl's [age] recipient field.
   ```

3. Run `chezmoi init` once to render `.chezmoi.toml.tmpl` into
   `~/.config/chezmoi/chezmoi.toml` (it wires the identity path + recipient).

4. `chezmoi apply` — existing encrypted secrets decrypt into
   `~/.config/secrets/`.

### Adding or rotating a secret

Place the plaintext value on disk, then:

```sh
# Adds the file to chezmoi, encrypted-in-place in the source tree.
chezmoi add --encrypt ~/.config/secrets/context7_api_key
```

Commit the resulting `encrypted_*` blob. Never commit the plaintext.

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
- `dot_claude/executable_run-context7.sh` — context7 MCP launcher (reads age-decrypted key from `~/.config/secrets/context7_api_key`)
- `dot_claude/skills/spec/` — Claude skills
- `dot_config/private_secrets/encrypted_private_context7_api_key.age` — age-encrypted API key, decrypts on apply

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

## Migrating to a new Mac

The bootstrap above handles packages and dotfiles. A few things live outside
the repo and need manual hand-off.

### Before you leave the old Mac

1. **Back up the age identity** — required to decrypt any `private_secrets/*`
   on the new machine. Without it, `chezmoi apply` fails on encrypted files.

   ```sh
   cp ~/.config/chezmoi/age-key.txt ~/Desktop/age-key.txt   # or password manager / iCloud / USB
   ```

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

2. **Restore the age identity** before running chezmoi, so the first apply
   can decrypt secrets:

   ```sh
   mkdir -p ~/.config/chezmoi && chmod 700 ~/.config/chezmoi
   cp /path/to/backup/age-key.txt ~/.config/chezmoi/age-key.txt
   chmod 600 ~/.config/chezmoi/age-key.txt
   ```

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
   claude mcp list           # should show nixos + context7
   mise list                 # should show node, python, rust, go, fzf, bun, neovim, uv
   which brew fish claude    # sanity-check everything's on PATH
   ```

9. **macOS system defaults** (Dock, Finder, trackpad, etc.) are **not**
   managed by this repo — configure them manually via System Settings, or
   add a `defaults write` script later if that becomes worth automating.

## Updating

- `chezmoi edit <file>` to edit a managed file, or `chezmoi cd` to jump into the source repo
- `chezmoi diff` to preview, `chezmoi apply` to write changes
- The install script is `run_once` — it only reruns if its content changes
- `update-all` (fish function) refreshes everything the bootstrap installs: brew (formulae + casks) on macOS or apt (+ PPAs) + flatpak on Ubuntu, plus mise toolchains, chezmoi itself, and atuin
