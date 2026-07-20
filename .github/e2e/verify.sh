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

# Expected command names, mirroring the native manifest, checked-in Nix bundle,
# mutable runtime managers, remaining mise tools, coding agents, and LSP servers.
# Kept explicit so this file doubles as the ownership checklist specification.
MANIFEST_BINS=(fish git jq curl wget gpg unzip add-apt-repository zenity mise
	gh op pfetch brev treehouse no-mistakes herdr)
NIX_BINS=(eza bat fd rg fzf gum starship atuin zoxide direnv tmux nvim go gopls fnm uv)
GUI_BINS=(ghostty discord google-chrome-stable 1password obsidian)
FLATPAK_APPS=(net.ankiweb.Anki com.spotify.Client us.zoom.Zoom)
RUNTIME_BINS=(node npm python python3 rustup rustc cargo bun hunk)
AGENT_BINS=(claude codex opencode pi)
LSP_BINS=(rust-analyzer pyright-langserver typescript-language-server gopls clangd)

# Resolve through a login+interactive fish so PATH reflects the real UX the
# dotfiles set up: project hooks, native runtime managers, the dedicated profile,
# native package managers, and finally transitional mise shims.
fish_has() { fish -l -i -c "command -q $1" 2>/dev/null; }
fish_path() {
	fish -l -i -c "command -v $1" 2>/dev/null |
		sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | tail -1
}
DOTFILES_NIX_PROFILE="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/dotfiles"
fish_uses_dotfiles_profile() {
	[[ "$(fish_path "$1")" == "$DOTFILES_NIX_PROFILE/bin/$1" ]]
}
fish_uses_fnm() {
	[[ "$(fish_path "$1")" == *"/fnm_multishells/"*"/bin/$1" ]]
}
fish_uses_uv_python() {
	[[ "$(fish_path "$1")" == "${XDG_DATA_HOME:-$HOME/.local/share}/uv/python-bin/$1" ]]
}
fish_uses_rustup() {
	[[ "$(fish_path "$1")" == "${CARGO_HOME:-$HOME/.cargo}/bin/$1" ]]
}
fish_uses_bun() {
	[[ "$(fish_path "$1")" == "${BUN_INSTALL:-$HOME/.bun}/bin/$1" ]]
}
profile_has_one_workstation() {
	nix profile list --profile "$DOTFILES_NIX_PROFILE" --json |
		jq -e '.elements | length == 1 and ([.[] | .storePaths[]? | contains("dotfiles-workstation")] | any)'
}
mise_has_no_runtime_declarations() {
	"$HOME/.local/bin/mise" ls --global --json |
		jq -e '. as $tools | (["node", "python", "rust", "go", "bun", "uv", "go:golang.org/x/tools/gopls"] | any(. as $key | $tools | has($key))) | not'
}

if [[ "$MODE" == "preflight" ]]; then
	echo "== preflight inventory (bins present BEFORE apply; install NOT proven for these) =="
	for b in "${MANIFEST_BINS[@]}" "${NIX_BINS[@]}" "${GUI_BINS[@]}" "${RUNTIME_BINS[@]}" "${AGENT_BINS[@]}" "${LSP_BINS[@]}"; do
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
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc"
		FAIL=$((FAIL + 1))
	fi
}
info() { # info "<desc>" <cmd...>  (recorded, never gates)
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "INFO-OK: $desc"
	else
		echo "INFO-MISS: $desc"
	fi
}

echo "== manifest CLI bins (via login+interactive fish PATH) =="
for b in "${MANIFEST_BINS[@]}"; do hard "bin $b" fish_has "$b"; done

echo "== dedicated Nix profile =="
hard "dedicated profile is active" test -L "$DOTFILES_NIX_PROFILE"
hard "profile has exactly one dotfiles-workstation element" profile_has_one_workstation
for b in "${NIX_BINS[@]}"; do
	hard "Nix bundle bin $b" fish_has "$b"
	hard "$b resolves through dedicated profile" fish_uses_dotfiles_profile "$b"
done
hard "nix-direnv integration comes from dedicated profile" \
	test -r "$DOTFILES_NIX_PROFILE/share/nix-direnv/direnvrc"

echo "== GUI desktop apps (desktop profile must install these) =="
for b in "${GUI_BINS[@]}"; do hard "gui bin $b" fish_has "$b"; done
hard "voquill-desktop installed (dpkg)" dpkg -s voquill-desktop
for app in "${FLATPAK_APPS[@]}"; do hard "flatpak $app" flatpak info "$app"; done

echo "== mutable language runtimes =="
for b in "${RUNTIME_BINS[@]}"; do hard "runtime/tool $b" fish_has "$b"; done
hard "node resolves through fnm" fish_uses_fnm node
hard "npm resolves through fnm" fish_uses_fnm npm
hard "python resolves through uv" fish_uses_uv_python python
hard "python3 resolves through uv" fish_uses_uv_python python3
for b in rustup rustc cargo; do hard "$b resolves through rustup" fish_uses_rustup "$b"; done
hard "bun resolves through native installer" fish_uses_bun bun
hard "fresh mise config has no runtime declarations" mise_has_no_runtime_declarations

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
hard "tmux-sensible installed" test -f "$HOME/.config/tmux/plugins/tmux-sensible/sensible.tmux"
hard "tmux-yank installed" test -f "$HOME/.config/tmux/plugins/tmux-yank/yank.tmux"
hard "Catppuccin tmux plugin installed" test -f "$HOME/.config/tmux/plugins/tmux/catppuccin.tmux"
hard "fish config present" test -f "$HOME/.config/fish/config.fish"
hard "pi settings materialized" test -f "$HOME/.pi/agent/settings.json"
hard "pi git-diff package declared" \
	jq -e '.packages | index("npm:pi-git-diff") != null' "$HOME/.pi/agent/settings.json"
hard "pi local git-diff extension absent" test ! -e "$HOME/.pi/agent/extensions/git-diff"
hard "pi Treehouse worktree guard materialized" \
	test -f "$HOME/.pi/agent/extensions/worktree-guard/index.ts"
hard "pi Treehouse worktree guard policy materialized" \
	test -f "$HOME/.pi/agent/extensions/worktree-guard/policy.mjs"
hard "pi subagents package declared" \
	jq -e '.packages | index("npm:@tintinweb/pi-subagents") != null' "$HOME/.pi/agent/settings.json"
hard "pi Explore subagent definition materialized" test -f "$HOME/.pi/agent/agents/Explore.md"
hard "pi Plan subagent definition materialized" test -f "$HOME/.pi/agent/agents/Plan.md"
# Shared with the CI job of the same name; run outside `hard` so its per-file
# diagnostic survives (hard discards both of its command's output streams).
PIN_REPORT=$(bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/check-pi-model-pins.sh" \
	"$HOME/.pi/agent/agents" "$HOME/.pi/agent/settings.json" 2>&1)
PIN_RC=$?
[[ -n "$PIN_REPORT" ]] && echo "$PIN_REPORT"
hard "pi subagent model pins are all in enabledModels" test "$PIN_RC" -eq 0
hard "pi Hunk review skill declared" \
	jq -e '.skills | index("~/.local/share/mise/installs/npm-hunkdiff/latest/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md") != null' \
	"$HOME/.pi/agent/settings.json"
hard "Hunk review skill installed" \
	test -f "$HOME/.local/share/mise/installs/npm-hunkdiff/latest/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md"
hard "generated no-mistakes skills synchronized" \
	bash -c 'test -f "$HOME/.agents/skills/no-mistakes/SKILL.md" && cmp -s "$HOME/.agents/skills/no-mistakes/SKILL.md" "$HOME/.claude/skills/no-mistakes/SKILL.md"'

echo "== home ownership (root-elevated installers must not write here) =="
# Guards the class behind the run-28558929981 failure: a root-run installer
# step (nix's fish self-test) creating root-owned dirs in the user's home.
ROOT_OWNED="$(find "$HOME/.config" "$HOME/.local" "$HOME/.cache" "$HOME/.cargo" "$HOME/.rustup" "$HOME/.bun" -user root 2>/dev/null || true)"
if [[ -z "$ROOT_OWNED" ]]; then
	echo "PASS: no root-owned files under user-managed config, data, cache, and runtime directories"
	PASS=$((PASS + 1))
else
	echo "FAIL: root-owned files in user home:"
	echo "$ROOT_OWNED" | sed 's/^/    /'
	FAIL=$((FAIL + 1))
fi

echo "== interactive fish sanity =="
hard "login fish runs" fish -l -i -c status
FISH_ERR="$(fish -l -i -c 'echo ok' 2>&1 >/dev/null || true)"
if [[ -n "$FISH_ERR" ]]; then
	echo "INFO-MISS: fish startup stderr not empty:"
	echo "$FISH_ERR" | sed 's/^/    /'
else
	echo "INFO-OK: fish startup stderr empty"
fi
hard "ls aliased to eza" bash -c "fish -l -i -c 'type ls' 2>/dev/null | grep -q eza"

direnv_flake_fixture() {
	(
		set -euo pipefail
		local tmp system source
		tmp="$(mktemp -d)"
		trap 'rm -rf "$tmp"' EXIT
		system="$(nix eval --impure --raw --expr builtins.currentSystem)"
		source="$(chezmoi source-path)"
		bash "$source/.github/scripts/create-direnv-flake-fixture.sh" \
			"$tmp/flake.nix" "$source/nix" "$system"
		printf 'use flake\n' >"$tmp/.envrc"
		direnv allow "$tmp" >/dev/null
		direnv exec "$tmp" bash -c 'test "$DOTFILES_DIRENV_FIXTURE" = 1'
	)
}
echo "== nix-direnv use flake fixture =="
hard "direnv loads a project flake" direnv_flake_fixture

echo "== agent config end state (not exit codes - the scripts swallow failures) =="
hard "claude plugins: 7 enabled (5 LSP + agent-sdk-dev + skill-creator)" \
	bash -c "PATH=\"\$HOME/.local/bin:\$PATH\" claude plugin list --json 2>/dev/null | jq -e 'map(select(.enabled)) | length >= 7'"
hard "claude MCP servers synced into ~/.claude.json" \
	bash -c "jq -e '.mcpServers | has(\"playwright\") and has(\"playwright-chrome\")' \"\$HOME/.claude.json\""
hard "codex MCP servers in ~/.codex/config.toml" \
	bash -c "grep -q '^\[mcp_servers\.playwright\]' \"\$HOME/.codex/config.toml\" \
        && grep -q '^\[mcp_servers\.playwright-chrome\]' \"\$HOME/.codex/config.toml\""
hard "pi MCP config rendered with playwright + playwright-chrome" \
	bash -c "jq -e '.mcpServers | has(\"playwright\") and has(\"playwright-chrome\")' \"\$HOME/.pi/agent/mcp.json\""
# HARD gate: assert opencode's RESOLVED config carries the managed server, which
# proves opencode LOADED and merged the chezmoi-written opencode.json with the
# user's hand-owned opencode.jsonc (an empty/absent .mcp would also
# catch any future .json/.jsonc shadowing regression). `opencode debug config`
# only resolves config - it never connects to the MCP servers - so it does no
# network I/O and cannot hang or flake; no timeout needed. From a neutral cwd
# with ~/.opencode/bin on PATH.
opencode_mcp_resolved() {
	(cd "$HOME" && PATH="$HOME/.opencode/bin:$PATH" opencode debug config 2>/dev/null) |
		jq -e '.mcp // {} | has("playwright") and has("playwright-chrome")'
}
hard "opencode loaded+merged the MCP servers (resolved config, not just the rendered file)" \
	opencode_mcp_resolved

# INFO (never gates): the live-connectivity signal. `opencode mcp list` connects
# to each server to report state, which on a fresh box triggers first-run
# package fetches (npx @playwright/mcp), so it must never be an
# un-timeouted hard gate - wrap it in a timeout like every other network check
# here and match on server NAMES (listed for every configured server regardless
# of connect state).
opencode_mcp_listed() {
	local out
	out="$(cd "$HOME" && PATH="$HOME/.opencode/bin:$PATH" timeout 120 opencode mcp list 2>/dev/null |
		sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g')"
	printf '%s\n' "$out" | grep -q 'playwright' &&
		printf '%s\n' "$out" | grep -q 'playwright-chrome'
}
info "opencode mcp list shows playwright + playwright-chrome (live connectivity)" \
	opencode_mcp_listed

echo "== chezmoi drift (only settings.json may differ, by design) =="
# .chezmoiscripts/ entries are pending SCRIPT runs, not file drift: the plain
# run_after_ hook/plugin re-assert scripts fire on every apply by design (see
# .claude/rules/bootstrap/scripts-and-config.md), so chezmoi status always
# lists them.
UNEXPECTED_DRIFT="$(chezmoi status 2>/dev/null | awk '{print $NF}' |
	grep -v '^\.claude/settings\.json$' | grep -v '^\.chezmoiscripts/' || true)"
if [[ -z "$UNEXPECTED_DRIFT" ]]; then
	echo "PASS: chezmoi status shows only the by-design settings.json drift"
	PASS=$((PASS + 1))
else
	echo "FAIL: unexpected chezmoi drift:"
	echo "$UNEXPECTED_DRIFT" | sed 's/^/    /'
	FAIL=$((FAIL + 1))
fi

echo "== apply-log warning scan (scripts deliberately swallow these) =="
if [[ -n "$APPLY_LOG" && -f "$APPLY_LOG" ]]; then
	# chezmoi apply -v prints each script's SOURCE as a diff before running it;
	# those '+'-prefixed listing lines contain the warn/skip patterns verbatim
	# and are not runtime warnings - exclude them. The sandbox driver prefixes
	# its re-apply section with "SECOND-APPLY: ", so allow one such label
	# between the line number and the '+'.
	SWALLOWED="$(grep -En 'warn:|skip:' "$APPLY_LOG" | grep -vE '^[0-9]+:([A-Z-]+: )?\+' || true)"
	if [[ -z "$SWALLOWED" ]]; then
		echo "PASS: no swallowed warn:/skip: lines in apply log"
		PASS=$((PASS + 1))
	else
		echo "FAIL: swallowed warnings/skips found in apply log:"
		echo "$SWALLOWED" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
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
# pipefail), then invoke the binary directly for its version. pfetch's last
# escape sequence (ESC[?7h) has no trailing newline and lands on the path's
# line, so strip ANSI/DEC escapes before picking the line.
for b in chezmoi nix mise fish eza bat fd rg fzf gum starship atuin zoxide direnv tmux nvim fnm uv go gopls node python rustup rustc cargo bun gh op; do
	p="$(fish -l -i -c "command -v $b" 2>/dev/null | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | tail -1 || true)"
	if [[ -n "$p" && -x "$p" ]]; then
		case "$b" in
		direnv | go | gopls) version=$("$p" version 2>/dev/null | head -1) ;;
		tmux) version=$("$p" -V 2>/dev/null | head -1) ;;
		*) version=$("$p" --version 2>/dev/null | head -1) ;;
		esac
		echo "VERSION: $b = $version"
	else
		echo "VERSION: $b = absent"
	fi
done

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
