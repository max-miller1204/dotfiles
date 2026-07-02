#!/usr/bin/env bash
# Post-apply verification for the native-Ubuntu E2E of these dotfiles.
# Modes:
#   verify.sh preflight        - inventory only: which expected bins already exist
#                                (used on preloaded GitHub runners BEFORE apply, so
#                                preexisting tools are excluded from install-proof)
#   verify.sh verify [sandbox|runner]
#                              - full post-apply checklist; APPLY_LOG may point at
#                                the captured apply log for the warning/skip scan
# Exit code: number of HARD failures (0 = all hard checks passed).
set -uo pipefail

MODE="${1:-verify}"
ENVIRONMENT="${2:-sandbox}"
APPLY_LOG="${APPLY_LOG:-}"

# Expected command names, mirroring .chezmoidata/packages.yaml (linux desktop
# profile) plus the mise toolchains block, axi CLIs, coding agents, and LSP
# servers. Kept as an explicit list so this file doubles as the checklist spec.
MANIFEST_BINS=(fish git tmux jq curl wget gpg add-apt-repository zenity mise
    eza gum starship atuin bat fd rg zoxide gh op pfetch brev)
GUI_BINS=(ghostty discord obsidian)
FLATPAK_APPS=(net.ankiweb.Anki com.spotify.Client us.zoom.Zoom)
TOOLCHAIN_BINS=(node python cargo go fzf bun nvim uv)
AXI_BINS=(gh-axi chrome-devtools-axi lavish-axi tasks-axi)
AGENT_BINS=(claude codex opencode)
LSP_BINS=(rust-analyzer pyright-langserver typescript-language-server gopls clangd)

# Resolve through a login+interactive fish so PATH reflects the real UX the
# dotfiles set up (mise shims/activation are gated on interactive in config.fish).
fish_has() { fish -l -i -c "command -q $1" 2>/dev/null; }

if [[ "$MODE" == "preflight" ]]; then
    echo "== preflight inventory (bins present BEFORE apply; install NOT proven for these) =="
    for b in "${MANIFEST_BINS[@]}" "${GUI_BINS[@]}" "${TOOLCHAIN_BINS[@]}" "${AXI_BINS[@]}" "${AGENT_BINS[@]}" "${LSP_BINS[@]}"; do
        if command -v "$b" >/dev/null 2>&1; then
            echo "PREEXISTING: $b -> $(command -v "$b")"
        else
            echo "ABSENT: $b"
        fi
    done
    exit 0
fi

PASS=0
FAIL=0
hard() { # hard "<desc>" <cmd...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "FAIL: $desc"; FAIL=$((FAIL + 1))
    fi
}
info() { # info "<desc>" <cmd...>  (recorded, never gates)
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "INFO-OK: $desc"
    else
        echo "INFO-MISS: $desc"
    fi
}

echo "== manifest CLI bins (via login+interactive fish PATH) =="
for b in "${MANIFEST_BINS[@]}"; do hard "bin $b" fish_has "$b"; done

echo "== GUI desktop apps (desktop profile must install these) =="
for b in "${GUI_BINS[@]}"; do hard "gui bin $b" fish_has "$b"; done
hard "voquill-desktop installed (dpkg)" dpkg -s voquill-desktop
for app in "${FLATPAK_APPS[@]}"; do hard "flatpak $app" flatpak info "$app"; done

echo "== mise toolchains =="
for b in "${TOOLCHAIN_BINS[@]}"; do hard "toolchain $b" fish_has "$b"; done

echo "== axi CLIs =="
for b in "${AXI_BINS[@]}"; do hard "axi $b" fish_has "$b"; done

echo "== coding agents + nix =="
for b in "${AGENT_BINS[@]}"; do hard "agent $b" fish_has "$b"; done
hard "nix" fish_has nix

echo "== LSP servers =="
for b in "${LSP_BINS[@]}"; do hard "lsp $b" fish_has "$b"; done

echo "== login shell =="
FISH_PATH="$(command -v fish || true)"
hard "fish present" test -n "$FISH_PATH"
hard "fish registered in /etc/shells" grep -qx "$FISH_PATH" /etc/shells
info "login shell already fish (chsh needs TTY; day-1 item if MISS)" \
    test "$(getent passwd "$USER" | cut -d: -f7)" = "$FISH_PATH"

echo "== materialized configs =="
hard "ghostty config present (native desktop must NOT ignore it)" test -d "$HOME/.config/ghostty"
hard "nvim seeded with LazyVim starter" test -e "$HOME/.config/nvim/init.lua"
hard "TPM cloned" test -d "$HOME/.config/tmux/plugins/tpm"
hard "fish config present" test -f "$HOME/.config/fish/config.fish"

echo "== home ownership (root-elevated installers must not write here) =="
# Guards the class behind the run-28558929981 failure: a root-run installer
# step (nix's fish self-test) creating root-owned dirs in the user's home.
ROOT_OWNED="$(find "$HOME/.config" "$HOME/.local" "$HOME/.cache" -user root 2>/dev/null || true)"
if [[ -z "$ROOT_OWNED" ]]; then
    echo "PASS: no root-owned files under ~/.config ~/.local ~/.cache"; PASS=$((PASS + 1))
else
    echo "FAIL: root-owned files in user home:"; echo "$ROOT_OWNED" | sed 's/^/    /'; FAIL=$((FAIL + 1))
fi

echo "== interactive fish sanity =="
hard "login fish runs" fish -l -i -c status
FISH_ERR="$(fish -l -i -c 'echo ok' 2>&1 >/dev/null || true)"
if [[ -n "$FISH_ERR" ]]; then
    echo "INFO-MISS: fish startup stderr not empty:"; echo "$FISH_ERR" | sed 's/^/    /'
else
    echo "INFO-OK: fish startup stderr empty"
fi
hard "ls aliased to eza" bash -c "fish -l -i -c 'type ls' 2>/dev/null | grep -q eza"

echo "== agent config end state (not exit codes - the scripts swallow failures) =="
hard "claude settings.json has SessionStart hooks" \
    bash -c "jq -e '.hooks.SessionStart | length > 0' \"\$HOME/.claude/settings.json\""
hard "claude plugins: 7 enabled (5 LSP + agent-sdk-dev + skill-creator)" \
    bash -c "PATH=\"\$HOME/.local/bin:\$PATH\" claude plugin list --json 2>/dev/null | jq -e 'map(select(.enabled)) | length >= 7'"
hard "claude MCP servers synced into ~/.claude.json" \
    bash -c "jq -e '.mcpServers | length >= 1' \"\$HOME/.claude.json\""
hard "codex MCP servers in ~/.codex/config.toml" grep -q '^\[mcp_servers\.' "$HOME/.codex/config.toml"
hard "codex hooks.json written by axi setup" test -s "$HOME/.codex/hooks.json"
hard "opencode axi plugins written" bash -c "ls \"\$HOME/.config/opencode/plugins/\"axi-*.js"

echo "== chezmoi drift (only settings.json may differ, by design) =="
UNEXPECTED_DRIFT="$(chezmoi status 2>/dev/null | awk '{print $NF}' | grep -v '^\.claude/settings\.json$' || true)"
if [[ -z "$UNEXPECTED_DRIFT" ]]; then
    echo "PASS: chezmoi status shows only the by-design settings.json drift"; PASS=$((PASS + 1))
else
    echo "FAIL: unexpected chezmoi drift:"; echo "$UNEXPECTED_DRIFT" | sed 's/^/    /'; FAIL=$((FAIL + 1))
fi

echo "== apply-log warning scan (scripts deliberately swallow these) =="
if [[ -n "$APPLY_LOG" && -f "$APPLY_LOG" ]]; then
    # chezmoi apply -v prints each script's SOURCE as a diff before running it;
    # those '+'-prefixed listing lines contain the warn/skip patterns verbatim
    # and are not runtime warnings - exclude them.
    SWALLOWED="$(grep -En 'warn:|skip:' "$APPLY_LOG" | grep -vE '^[0-9]+:\+' || true)"
    if [[ -z "$SWALLOWED" ]]; then
        echo "PASS: no swallowed warn:/skip: lines in apply log"; PASS=$((PASS + 1))
    else
        echo "FAIL: swallowed warnings/skips found in apply log:"; echo "$SWALLOWED" | sed 's/^/    /'; FAIL=$((FAIL + 1))
    fi
else
    echo "INFO-MISS: APPLY_LOG not provided; warning scan skipped"
fi

echo "== GUI smoke (reduced form; never gates in runner env) =="
info "ghostty +version" fish -l -i -c 'ghostty +version'
if [[ "$ENVIRONMENT" == "sandbox" ]]; then
    info "obsidian --version (WSLg best-effort)" timeout 30 fish -l -i -c 'obsidian --version --no-sandbox'
fi
# desktop-file-utils is a verification-only dependency, installed here AFTER the
# judged apply, and excluded from install-proof conclusions.
sudo apt-get install -y -qq desktop-file-utils >/dev/null 2>&1 || true
for d in /usr/share/applications/discord.desktop /usr/share/applications/obsidian.desktop; do
    [[ -f "$d" ]] && info "desktop-file-validate $(basename "$d")" desktop-file-validate "$d"
done
for app in "${FLATPAK_APPS[@]}"; do
    info "flatpak run --command=true $app" timeout 60 flatpak run --command=true "$app"
done

echo "== versions (for the report) =="
# Resolve each binary's path through interactive fish (whose config prints the
# pfetch banner - take the LAST line, immune to the banner and to SIGPIPE under
# pipefail), then invoke the binary directly for its version.
for b in chezmoi mise fish starship atuin eza gh op; do
    p="$(fish -l -i -c "command -v $b" 2>/dev/null | tail -1 || true)"
    if [[ -n "$p" && -x "$p" ]]; then
        echo "VERSION: $b = $("$p" --version 2>/dev/null | head -1)"
    else
        echo "VERSION: $b = absent"
    fi
done

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
