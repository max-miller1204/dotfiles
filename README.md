# dotfiles

Chezmoi-managed dotfiles for Max. Used on Ubuntu and macOS.
NixOS is managed separately via [myNixOS](https://github.com/max-miller1204/myNixOs).

## Bootstrap a new machine

1. Install prerequisites:
   - **Ubuntu:** `sudo apt install fish git tmux neovim eza fzf zoxide starship bat fd-find ripgrep jq && curl -sfL https://get.chezmoi.io | sh`
   - **macOS:** `brew install chezmoi fish git tmux neovim eza fzf zoxide starship bat fd ripgrep jq atuin pfetch`

2. Initialize from this repo:
   ```
   chezmoi init max-miller1204/dotfiles
   chezmoi apply
   ```

3. Set fish as default shell:
   ```
   chsh -s $(which fish)
   ```

4. Install tmux plugins (first run only):
   ```
   git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
   tmux new -s Work   # then press prefix + I to install plugins
   ```

5. Install fish catppuccin theme (first run only):
   ```
   fish -c "curl -L https://raw.githubusercontent.com/catppuccin/fish/main/themes/Catppuccin%20Mocha.theme -o ~/.config/fish/themes/Catppuccin\\ Mocha.theme; and fish_config theme save 'Catppuccin Mocha'"
   ```

## Updating

- Edit files under `~/.local/share/chezmoi/` (or wherever chezmoi's source dir is)
- `chezmoi diff` to preview, `chezmoi apply` to write them
- `chezmoi cd` drops you into the source repo for committing changes

## What's here

| Path | Managed config |
|---|---|
| `dot_gitconfig` | git identity + gh credential helper |
| `dot_config/fish/config.fish.tmpl` | fish shell (aliases, env, prompt init) |
| `dot_config/tmux/tmux.conf` | tmux (TPM-based plugins) |
| `dot_config/ghostty/config` | ghostty terminal |
| `dot_claude/settings.json` | Claude Code settings |
| `dot_claude/statusline.sh` | Claude Code statusline |

OS-specific (gated via `.chezmoiignore`):
- `dot_config/karabiner/karabiner.json` — macOS only
- `dot_config/aerospace/aerospace.toml` — macOS only

## Nix coexistence

This repo only manages dotfiles. Package installation and dev environments stay with Nix:
- `nix shell nixpkgs#<pkg>` for one-off tools
- Project flakes (`flake.nix` in a project dir) for dev environments
- `direnv` + `nix-direnv` for auto-loading project envs
