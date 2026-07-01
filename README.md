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

> **Migrating from an existing Mac?** See [Migrating to a new Mac](#migrating-to-a-new-mac) for the pre/post-migration checklist (Raycast re-export, SSH, etc.) before running the commands above.

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
  `rust@latest`, `go@latest`, `fzf@latest`, `bun@latest`, `neovim@latest`,
  `uv@latest` (so fzf/bun/neovim are mise-managed, not apt/brew)
- installs **Nix** via the Determinate installer
- installs **Claude Code** via the official installer
  (`curl -fsSL https://claude.ai/install.sh | bash`) — lands in
  `~/.local/bin/claude` and self-updates in the background
- installs the **Codex** and **OpenCode** agents via their own official
  installers too, so all three coding agents (Claude, Codex, OpenCode) are
  present and interchangeable - see
  [Agents (multi-agent)](#agents-multi-agent)
- installs the **agent "axi" CLIs** (`gh-axi`, `chrome-devtools-axi`,
  `lavish-axi`, `tasks-axi`) - ergonomic wrappers the coding agents drive from their
  SessionStart hooks, installed as mise-managed npm tools so they survive a node upgrade
  instead of orphaning in the version-pinned runtime dir. `run_after_60` then
  wires their hooks into every agent (Claude, Codex, OpenCode) on every apply - see
  [Agents (multi-agent)](#agents-multi-agent)
- installs the **language servers** Claude Code's LSP plugins need: pyright,
  typescript-language-server (+ typescript) and gopls as mise-managed tools,
  rust-analyzer via the rustup component, and clangd from apt (Linux) or
  Homebrew `llvm` (macOS). Driven by `run_onchange_after_50` so it reruns
  when that script changes. The language set (plugin + server install method)
  lives once in the `lspLanguages` table in `.chezmoi.toml.tmpl`, shared by the
  server install and the plugin install so the two can't drift
- installs/enables the **Claude Code plugins** from the official marketplace via
  the `claude plugin` CLI (`run_after_65`, every apply) rather than vendoring
  `enabledPlugins` into `settings.json` - see
  [Agents (multi-agent)](#agents-multi-agent)
- installs the **1Password CLI** (`op`) — the secrets backend (Homebrew cask
  `1password-cli` on macOS, official apt repo on Linux); see
  [Secrets](#secrets-1password)
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

Secrets live in 1Password, not in this repo — nothing encrypted is committed
to git, and nothing plaintext lands in the source tree. There are currently
**no secrets in use**; this is the pattern for when one is needed:

- **chezmoi template** (value rendered into a target file at apply time):

  ```
  {{ onepasswordRead "op://Personal/MyService/credential" }}
  ```

- **Runner script** (value fetched at invocation time, never on disk):

  ```sh
  MY_KEY="$(op read 'op://Personal/MyService/credential')"
  ```

### First-time setup on a new machine

1. **Install the 1Password CLI.** The bootstrap script installs it for you
   (Homebrew cask `1password-cli` on macOS, official apt repo on Linux). If
   you're setting up before the first `chezmoi apply`, install it yourself —
   see [developer.1password.com/docs/cli](https://developer.1password.com/docs/cli/get-started/).

2. **Sign in.** The smoothest path is biometric unlock via the desktop app:
   1Password desktop → Settings → Developer → "Integrate with 1Password CLI."
   Then `op signin` once and `op` will resolve transparently from any shell.
   Without the desktop app, `eval "$(op signin)"` per shell session works too.

3. **Verify** with `op whoami` (or `op.exe whoami` inside WSL).

Platform notes:

- **macOS** — the desktop app provides Touch ID unlock for `op`.
- **Ubuntu** — install the desktop app too if you want biometric-style
  unlock; otherwise `op signin` works standalone.
- **WSL Ubuntu** — `.chezmoi.toml.tmpl` detects WSL and points chezmoi at the
  **Windows-side `op.exe`**, so chezmoi secret reads unlock via the Windows
  1Password app (Windows Hello). Install 1Password + the CLI integration on
  the Windows side; WSL's PATH interop makes `op.exe` callable from Linux.
  The apt-installed Linux `op` remains available for runner scripts and
  manual `op signin`.

### Adding or rotating a secret

```sh
# Create a new item:
op item create --category=apicredential --vault=Personal \
  --title=NAME "credential[concealed]=THE-SECRET"

# Rotate an existing one:
op item edit NAME --vault=Personal "credential[concealed]=NEW-SECRET"
```

Then reference it via `op://Personal/NAME/credential` from a template or
runner script as above.

## MCP servers (Claude Code + Codex)

Declared once in `dot_config/claude-code/mcp-servers.json.tmpl` and
`dot_config/codex/mcp-servers.toml.tmpl` — these are staging files. On every
`chezmoi apply` where either changes, a `run_onchange_after_*` script syncs
them in place:

- `~/.claude.json` (user scope) — via `claude mcp remove` + `claude mcp add-json`
- `~/.codex/config.toml` — via awk-strip + append

The Claude sync touches only the server names declared in its own staging JSON
(`.mcpServers` keys); the Codex sync touches only the section names declared in
its staging TOML. Neither keeps a second hand-maintained name list. Anything
else you've added manually (or that
Codex's own plugin registry manages) in `~/.claude.json` or
`~/.codex/config.toml` is preserved. One consequence: removing a server from
the staging files means deleting its leftover section from
`~/.codex/config.toml` by hand once. Verify with `claude mcp list`.

## Agents (multi-agent)

Three coding agents are first-class and interchangeable: **Claude Code**, **Codex**, and **OpenCode**.
They share one set of global instructions and one set of ambient-context hooks, so you can switch between them with the same tools and the same rules.

All three agents install via their own official installers (each ships a user-level `curl | sh` installer that works on Linux and macOS), so a fresh apply has all three present.

### Shared instructions (single-source AGENTS.md)

The global agent instructions live in one real file at `~/AGENTS.md` (source: the chezmoi-root `AGENTS.md`).
No agent directory is the privileged home; every agent reaches that one file through a relative symlink, so there is exactly one place to edit:

- `~/.claude/CLAUDE.md` -> `../AGENTS.md` (source: `dot_claude/symlink_CLAUDE.md`) for Claude Code.
- `~/.codex/AGENTS.md` -> `../AGENTS.md` (source: `dot_codex/symlink_AGENTS.md`) for Codex, which reads the `AGENTS.md` convention natively.
- `~/.config/opencode/AGENTS.md` -> `../../AGENTS.md` (source: `dot_config/opencode/symlink_AGENTS.md`) for OpenCode, whose documented global-rules path is `~/.config/opencode/AGENTS.md`.

(The chezmoi-root `AGENTS.md` is both the source of `~/AGENTS.md` and this repo's own agent-memory file; `README.md`, `CLAUDE.md`, and `raycast-export` stay `.chezmoiignore`d, but `AGENTS.md` is intentionally applied.)

### Ambient-context hooks (axi)

Each axi CLI ships a `<tool> setup hooks` subcommand (from the shared `axi-sdk-js`) that, in one idempotent call, wires that tool into all three agents:

- Claude: a SessionStart hook in `~/.claude/settings.json`.
- Codex: a SessionStart hook in `~/.codex/hooks.json` plus `[features] hooks = true` in `~/.codex/config.toml`.
- OpenCode: an ambient-context plugin at `~/.config/opencode/plugins/axi-<tool>.js`.

`run_after_60-setup-axi-hooks.sh.tmpl` runs `setup hooks` for all four CLIs, after the CLIs are installed and after the agent config files are applied.
It puts the mise shim dir on `PATH` and skips (rather than fails) any CLI that is not yet installed, so a partial first apply self-heals on the next run.

**Single source of truth for the hooks - the CLI owns them, nothing is vendored.**
`setup hooks` is the one mechanism that wires axi hooks across all three agents; the axi SessionStart hooks are no longer hand-vendored into `dot_claude/settings.json`.
That is why this is a plain `run_after_` script (runs on every apply), not a `run_onchange_after_`.
Claude's SessionStart hooks live only in the settings.json family, which chezmoi fully manages: every `chezmoi apply` rewrites `~/.claude/settings.json` from source and strips anything a CLI appended.
A `run_onchange_` keyed to the script's own hash would not re-fire after that strip (its hash is unchanged), so the Claude hooks would be silently lost; running every apply re-asserts them.
The consequence is intended: after an apply, `chezmoi status` shows `dot_claude/settings.json` as locally modified because `setup hooks` (and the plugin re-assert below) re-add their blocks. That drift is by design, not a bug (see [AGENTS.md](AGENTS.md)).
Codex's `hooks.json` and the OpenCode plugins are not chezmoi-managed targets, so re-running is a cheap no-op there.

**Claude plugins + marketplace (CLI-owned, same story as the hooks).**
The Claude Code plugins and their marketplace are owned by the `claude plugin` CLI, not hand-vendored into `dot_claude/settings.json` (`enabledPlugins` / `extraKnownMarketplaces`).
`run_after_65-setup-claude-plugins.sh.tmpl` registers the `claude-plugins-official` marketplace and installs/enables each plugin on every apply, for the same reason the hooks script does: that state lives only in the chezmoi-rewritten settings.json, so it must be re-asserted each apply (a `run_onchange_` would not re-fire after the strip).
It is cheap on re-apply - the plugin clones and the marketplace persist under `~/.claude/plugins` (not chezmoi-managed), so an installed-but-disabled plugin is a settings.json re-enable, not a fresh clone.
The five LSP plugins are not hand-listed here: they derive from the single-source `lspLanguages` table in `.chezmoi.toml.tmpl` (the same table that drives the LSP-server install in `run_onchange_after_50`), so the plugin set and the server set can never drift. Only the two non-LSP plugins (`agent-sdk-dev`, `skill-creator`) are a small separate `extraClaudePlugins` list.

**Codex config ownership.**
`~/.codex/config.toml` is assembled (not a single chezmoi target) so several managed mechanisms can each own their own keys without clobbering the machine-specific ones (`[projects.*]` trust, `[tui.*]`) or sections Codex adds itself:

- `run_onchange_after_42-sync-codex-base.sh.tmpl` owns a marker-delimited block at the top of the file with the durable base settings (`model`, `model_reasoning_effort`), sourced from `dot_config/codex/config-base.toml.tmpl`.
- `run_onchange_after_41-sync-codex-mcp.sh.tmpl` owns the `[mcp_servers.*]` sections (appended at the end).
- `run_after_60-setup-axi-hooks.sh.tmpl` owns `[features] hooks = true`.

**Codex hook-trust caveat (one manual follow-up on Ubuntu).**
Codex gates hooks behind persisted trust, so the first Codex session after a fresh apply may prompt to trust the hooks (or need `--dangerously-bypass-hook-trust`).
Running a Codex session once and accepting that prompt is the only manual step; the exact `hooks.json` shape is left to the official `setup hooks` command so it stays correct against the installed Codex version.

## What's here

Cross-platform:
- `dot_gitconfig` — git identity, aliases, sane defaults, gh credential helper
- `dot_config/fish/config.fish.tmpl` — fish shell (aliases, env, prompt init)
- `dot_config/fish/functions/*.fish` — custom fish functions (includes `update-all`, which refreshes the system package manager — brew on macOS, apt + flatpak on Ubuntu — plus mise, chezmoi, and atuin in one go; `lsp-upgrade` and `axi-upgrade` do targeted upgrades of just the Claude Code language servers or just the agent axi CLIs)
- `dot_config/fish/themes/Catppuccin Mocha.theme`
- `dot_config/tmux/tmux.conf` — tmux (TPM-based plugins)
- `dot_config/ghostty/config` + `themes/catppuccin-mocha`
- `dot_config/atuin/*` — shell history sync config + theme
- `dot_config/bat/*` — bat pager syntax + theme
- `dot_config/starship.toml` — prompt
- `dot_config/claude-code/mcp-servers.json.tmpl` — staging JSON; sync'd into `~/.claude.json` by `run_onchange_after_40-sync-claude-mcp.sh.tmpl`
- `dot_config/codex/mcp-servers.toml.tmpl` — staging TOML; sync'd into `~/.codex/config.toml` by `run_onchange_after_41-sync-codex-mcp.sh.tmpl`
- `dot_config/codex/config-base.toml.tmpl` - staging TOML; base Codex settings (`model`, reasoning effort) sync'd into `~/.codex/config.toml` by `run_onchange_after_42-sync-codex-base.sh.tmpl`
- `AGENTS.md` - the single real copy of the global agent instructions; applied to `~/AGENTS.md` (see [Agents (multi-agent)](#agents-multi-agent))
- `dot_claude/symlink_CLAUDE.md` - materializes `~/.claude/CLAUDE.md` -> `~/AGENTS.md`
- `dot_codex/symlink_AGENTS.md` - materializes `~/.codex/AGENTS.md` -> `~/AGENTS.md`
- `dot_config/opencode/symlink_AGENTS.md` - materializes `~/.config/opencode/AGENTS.md` -> `~/AGENTS.md`
- `dot_claude/settings.json` + `executable_statusline.sh`
- `dot_claude/skills/` — vendored Claude skills (codex-review). The brev-cli
  skill is not vendored: `brev agent-skill` writes it into every agent harness
  (`run_once_after_70`), so the brev CLI owns it

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
  obsidian, anki, spotify, zoom) so WSL only gets CLI tools
- chezmoi uses the Windows-side `op.exe` for 1Password reads (see
  [Secrets](#secrets-1password))

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
- `.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl` — packages, toolchains, Nix, the coding agents (Claude, Codex, OpenCode), agent axi CLIs, fish-as-login-shell
- `.chezmoiscripts/run_once_after_20-install-tpm.sh.tmpl` — TPM + tmux plugins
- `.chezmoiscripts/run_once_after_30-install-lazyvim.sh.tmpl` — LazyVim starter (only if `~/.config/nvim` is missing)
- `.chezmoiscripts/run_onchange_after_40-sync-claude-mcp.sh.tmpl` — re-syncs MCPs into `~/.claude.json` whenever the staging JSON changes
- `.chezmoiscripts/run_onchange_after_41-sync-codex-mcp.sh.tmpl` — re-syncs MCPs into `~/.codex/config.toml` whenever the staging TOML changes
- `.chezmoiscripts/run_onchange_after_42-sync-codex-base.sh.tmpl` - syncs base Codex settings (`model`, reasoning effort) into a marker block at the top of `~/.codex/config.toml` whenever the staging TOML changes
- `.chezmoiscripts/run_onchange_after_50-install-lsp-servers.sh.tmpl` — installs the language servers Claude Code's LSP plugins need (pyright, typescript-language-server, typescript, gopls via mise; rust-analyzer via rustup; clangd via apt/brew), all derived from the single-source `lspLanguages` table, whenever the script changes
- `.chezmoiscripts/run_after_60-setup-axi-hooks.sh.tmpl` - wires the axi ambient-context hooks into all three agents (Claude, Codex, OpenCode) via each CLI's `setup hooks`, on every apply (Claude's hooks live in the chezmoi-rewritten settings.json, so they must be re-asserted each time; see [Agents (multi-agent)](#agents-multi-agent))
- `.chezmoiscripts/run_after_65-setup-claude-plugins.sh.tmpl` - registers the `claude-plugins-official` marketplace and installs/enables the Claude Code plugins (LSP plugins derived from `lspLanguages`, plus `extraClaudePlugins`) via the `claude plugin` CLI, on every apply (same chezmoi-rewritten-settings.json reason as the hooks; see [Agents (multi-agent)](#agents-multi-agent))
- `.chezmoiscripts/run_once_after_70-install-brev-skill.sh.tmpl` - runs `brev agent-skill` once to write the brev-cli agent skill into every agent harness (Claude, Codex, OpenCode); the skill is `.chezmoiignore`d, so brev owns it with no chezmoi conflict

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

# Clone + apply
chezmoi init --apply max-miller1204/dotfiles
```

The first apply installs CLIs, mise toolchains, Nix, the coding agents
(Claude, Codex, OpenCode), and the 1Password CLI, then sets fish as your
login shell.

### 1Password sign-in from WSL

chezmoi is configured (via `.chezmoi.toml.tmpl`) to call the **Windows-side
`op.exe`** for secret reads, so the cleanest setup is: install 1Password for
Windows, enable Settings → Developer → "Integrate with 1Password CLI," and
unlocks happen via Windows Hello. Verify from WSL with `op.exe whoami`.

For shell-level use of the Linux `op` (runner scripts, ad-hoc reads), sign in
with `op signin` once, or `eval "$(op signin)"` per shell session without the
desktop app.

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
   [Secrets](#secrets-1password)), so anything stored in your vaults is
   already on the new machine once you sign in.

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

2. **Copy SSH keys** (or log in with `gh auth login` after chezmoi finishes —
   the gitconfig uses `gh auth git-credential` for HTTPS, so HTTPS clones
   work without SSH at all):

   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cp /path/to/backup/id_* ~/.ssh/
   chmod 600 ~/.ssh/id_*
   ```

3. **Bootstrap** — same command as the top of this README:

   ```sh
   brew install chezmoi
   chezmoi init --apply max-miller1204/dotfiles
   ```

4. **Open a new Ghostty tab** so fish picks up as the login shell. If fish
   isn't the default yet, run `chsh -s "$(command -v fish)"` manually — the
   bootstrap's `chsh` can silently fail inside some TTYs.

5. **Import Raycast** — see [Raycast settings](#raycast-settings) for the
   two-step dance (import `.rayconfig`, point Raycast at
   `~/.config/raycast-scripts`).

6. **Sign in to everything**: 1Password (desktop app + CLI integration, see
   [Secrets](#secrets-1password) — `chezmoi apply` doesn't depend on it while
   the repo has no secrets, so this can wait until after bootstrap),
   GitHub (`gh auth login`), Atuin (`atuin login` + `atuin sync` —
   `auto_sync` is off by default), Discord, Spotify, Obsidian, Zed account,
   Claude Code, Codex, and OpenCode (run `claude`, `codex`, and `opencode`
   and follow each login flow).

7. **Verify**:

   ```sh
   claude mcp list           # should show nixos + playwright
   mise list                 # node, python, rust, go, fzf, bun, neovim, uv (+ LSP servers & axi CLIs)
   which brew fish claude codex opencode op # sanity-check everything's on PATH
   op whoami                 # confirms 1Password sign-in
   ```

8. **macOS system defaults** (Dock, Finder, trackpad, etc.) are **not**
   managed by this repo — configure them manually via System Settings, or
   add a `defaults write` script later if that becomes worth automating.

## Updating

- `chezmoi edit <file>` to edit a managed file, or `chezmoi cd` to jump into the source repo
- `chezmoi diff` to preview, `chezmoi apply` to write changes
- The install script is `run_once` — it only reruns if its content changes
- `update-all` (fish function) refreshes everything the bootstrap installs: brew (formulae + casks) on macOS or apt (+ PPAs) + flatpak on Ubuntu, plus mise toolchains, chezmoi itself, and atuin
- `lsp-upgrade` and `axi-upgrade` (fish functions) do targeted upgrades of just the Claude Code language servers or just the agent axi CLIs. `update-all`'s `mise upgrade` already covers the mise-managed ones, but `lsp-upgrade` also refreshes rust-analyzer (rustup) and clangd (apt/brew), which mise doesn't manage
