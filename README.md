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

That's it — the install scripts run during `apply` and handle the rest:

- installs CLIs (apt on Ubuntu, Homebrew on macOS): fish, tmux, eza, zoxide,
  starship, bat, fd, ripgrep, jq, atuin, mise, gh, gum, pfetch
- installs **GUI apps** (casks on macOS; PPA/.deb/flatpak on Ubuntu):
  ghostty, discord, zed, voquill, zoom, anki, obsidian, spotify, plus
  aerospace + karabiner-elements on macOS
- installs **toolchains via mise**: `node@lts`, `python@latest`,
  `rust@latest`, `go@latest`, `fzf@latest`, `bun@latest`, `neovim@latest`
  (so fzf/bun/neovim are mise-managed, not apt/brew)
- installs **Nix** via the Determinate installer
- installs **Claude Code** via the official installer
  (`curl -fsSL https://claude.ai/install.sh | bash`) — lands in
  `~/.local/bin/claude` and self-updates in the background
- creates `~/.config/secrets` (mode 700) for the context7 API key
- adds fish to `/etc/shells` and sets it as your login shell
- clones TPM and installs tmux plugins
- drops the LazyVim starter into `~/.config/nvim` if nothing's there yet

Open a new terminal after the first run so fish picks up. You may need to log
out/in for the shell change to take effect. If `chsh` was skipped (it can
silently fail inside some TTYs), run it manually:

```sh
chsh -s "$(command -v fish)"
```

## Secrets

The context7 MCP runner reads its API key from a plain file. Chezmoi does not
manage it — drop it in yourself:

```sh
mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets
echo -n '<context7-key>' > ~/.config/secrets/context7_api_key
chmod 600 ~/.config/secrets/context7_api_key
```

## What's here

Cross-platform:
- `dot_gitconfig` — git identity, aliases, sane defaults, gh credential helper
- `dot_config/fish/config.fish.tmpl` — fish shell (aliases, env, prompt init)
- `dot_config/fish/functions/*.fish` — custom fish functions (includes `update-all`, which refreshes apt, mise, flatpak, chezmoi, and atuin in one go)
- `dot_config/fish/themes/Catppuccin Mocha.theme`
- `dot_config/tmux/tmux.conf` — tmux (TPM-based plugins)
- `dot_config/ghostty/config` + `themes/catppuccin-mocha`
- `dot_config/atuin/*` — shell history sync config + theme
- `dot_config/bat/*` — bat pager syntax + theme
- `dot_config/starship.toml` — prompt
- `dot_config/claude-code/mcp-servers.json.tmpl` — MCP runners for Claude Code
- `dot_claude/settings.json` + `executable_statusline.sh`
- `dot_claude/executable_run-context7.sh` — context7 MCP launcher
- `dot_claude/skills/spec/` — Claude skills

macOS-only (gated via `.chezmoiignore`):
- `dot_config/karabiner/karabiner.json`
- `dot_config/aerospace/aerospace.toml`

Bootstrap scripts (not applied to `$HOME`, run during `chezmoi apply`):
- `.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl` — packages, toolchains, Nix, Claude Code, fish-as-login-shell
- `.chezmoiscripts/run_once_after_20-install-tpm.sh.tmpl` — TPM + tmux plugins
- `.chezmoiscripts/run_once_after_30-install-lazyvim.sh.tmpl` — LazyVim starter (only if `~/.config/nvim` is missing)

## Updating

- `chezmoi edit <file>` to edit a managed file, or `chezmoi cd` to jump into the source repo
- `chezmoi diff` to preview, `chezmoi apply` to write changes
- The install script is `run_once` — it only reruns if its content changes
- `update-all` (fish function) refreshes everything the bootstrap installs: apt (+ PPAs), mise toolchains, flatpak apps, chezmoi itself, and atuin
