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

Cross-platform:
- `dot_gitconfig` — git identity, aliases, sane defaults, gh credential helper
- `dot_config/fish/config.fish.tmpl` — fish shell (aliases, env, prompt init, PATH-resolved tools)
- `dot_config/fish/functions/*.fish` — 19 custom fish functions (compress, ga, gwf, n, open, ...)
- `dot_config/fish/themes/catppuccin-mocha.theme`
- `dot_config/tmux/tmux.conf` — tmux (TPM-based plugins)
- `dot_config/ghostty/config` + `themes/catppuccin-mocha`
- `dot_config/atuin/*` — shell history sync config + theme
- `dot_config/bat/*` — bat pager syntax + theme
- `dot_config/starship.toml` — prompt
- `dot_config/stt-nix/config.toml` — hold-to-talk transcription (needs nix-installed stt-nix)
- `dot_config/claude-code/mcp-servers.json.tmpl` + `dot_config/codex/mcp-servers.toml.tmpl` — MCP runners
- `dot_claude/settings.json` + `executable_statusline.sh`
- `dot_claude/executable_run-context7.sh` + `executable_run-youtube.sh` — MCP server launchers
- `dot_claude/plugins/lsp-servers/` — Claude Code LSP plugin manifest
- `dot_claude/skills/spec/` — Claude skills

macOS-only (gated via `.chezmoiignore`):
- `dot_config/karabiner/karabiner.json`
- `dot_config/aerospace/aerospace.toml`

## Secrets

The MCP runner scripts read API keys from plain files at `~/.config/secrets/`:

```
mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets
echo -n '<context7-key>' > ~/.config/secrets/context7_api_key && chmod 600 ~/.config/secrets/context7_api_key
echo -n '<youtube-key>'  > ~/.config/secrets/youtube_api_key  && chmod 600 ~/.config/secrets/youtube_api_key
```

On NixOS, these are managed by sops-nix separately (keys live at `~/.config/sops-nix/secrets/`). If you want the same workflow on Ubuntu/Mac, install sops + age manually and encrypt a secrets file.

## Nix coexistence

This repo only manages dotfiles. Package installation and dev environments stay with Nix:
- `nix shell nixpkgs#<pkg>` for one-off tools
- Project flakes (`flake.nix` in a project dir) for dev environments
- `direnv` + `nix-direnv` for auto-loading project envs
