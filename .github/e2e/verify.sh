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

# Expected command names, split by active owner so this file also verifies the
# ownership boundary instead of presence alone.
MANIFEST_BINS=(fish git jq curl wget gpg add-apt-repository zenity
	gh op pfetch brev treehouse no-mistakes herdr)
HOME_MANAGER_BINS=(atuin bat bun clangd direnv eza fd fnm fzf go gofmt gopls
	gum nvim pyright pyright-langserver rg rust-analyzer rustup starship tmux tsc
	tsserver typescript-language-server uv zoxide)
GUI_BINS=(ghostty discord google-chrome-stable 1password obsidian)
FLATPAK_APPS=(net.ankiweb.Anki com.spotify.Client us.zoom.Zoom)
FNM_BINS=(node npm npx)
UV_BINS=(python python3 python3.14)
RUSTUP_BINS=(cargo cargo-clippy cargo-fmt clippy-driver rustc rustdoc rustfmt)
NPM_PREFIX_BINS=(hunk pi)
AGENT_BINS=(claude codex opencode)
LSP_BINS=(rust-analyzer pyright-langserver typescript-language-server gopls clangd)

# Resolve through a login+interactive fish so PATH reflects the real UX and
# the configured native runtime ownership boundaries.
fish_has() { fish -l -i -c "command -q $1" 2>/dev/null; }
fish_path() {
	fish -l -i -c "command -v $1" 2>/dev/null |
		sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | tail -1
}
home_manager_owns() {
	local path resolved
	path="$(fish_path "$1")"
	[[ "$path" == "$HOME/.nix-profile/bin/"* ]] || return 1
	resolved="$(readlink -f "$path")"
	[[ "$resolved" == /nix/store/* ]]
}
fnm_owns() {
	local path resolved
	path="$(fish_path "$1")"
	resolved="$(readlink -f "$path")"
	[[ "$resolved" == "$HOME/.local/share/fnm/node-versions/"* ]]
}
uv_owns() {
	local path resolved
	path="$(fish_path "$1")"
	[[ "$path" == "$HOME/.local/bin/"* ]] || return 1
	resolved="$(readlink -f "$path")"
	[[ "$resolved" == "$HOME/.local/share/uv/python/"* ]]
}
rustup_owns() {
	local path resolved
	path="$(fish_path "$1")"
	[[ "$path" == "$HOME/.cargo/bin/$1" ]] || return 1
	resolved="$(readlink -f "$path")"
	[[ "$resolved" == /nix/store/*rustup* ]]
}
npm_prefix_owns() {
	local path resolved
	path="$(fish_path "$1")"
	[[ "$path" == "$HOME/.local/share/npm/bin/$1" ]] || return 1
	resolved="$(readlink -f "$path")"
	[[ "$resolved" == "$HOME/.local/share/npm/lib/node_modules/"* ]]
}
selected_path_is_not_mise() {
	[[ "$(fish_path "$1")" != *"/mise/"* ]]
}
retained_mise_fixtures_are_unchanged() {
	[[ -x "$HOME/.local/bin/mise" ]] &&
		grep -Fxq retained-mise-executable "$HOME/.local/bin/mise" &&
		[[ -x "$HOME/.local/share/mise/shims/legacy-node" ]] &&
		grep -Fxq retained-mise-shim \
			"$HOME/.local/share/mise/shims/legacy-node" &&
		grep -Fxq retained-mise-install \
			"$HOME/.local/share/mise/installs/legacy-runtime/marker" &&
		grep -Fxq retained-mise-config "$HOME/.config/mise/config.toml"
}
managed_path_order_works() {
	fish -l -i -c '
		set node_dir (path dirname (command -v node))
		test $PATH[1] = $node_dir
		and test $PATH[2] = $HOME/.local/share/npm/bin
		and test $PATH[3] = $HOME/.nix-profile/bin
		and test $PATH[4] = $HOME/.cargo/bin
		and test $PATH[5] = $HOME/.local/bin
		and test $PATH[6] = $HOME/.opencode/bin
		and not string match -q "*/mise/*" -- $PATH
		and not contains -- $HOME/.bun/bin $PATH
	' 2>/dev/null
}
fnm_auto_switch_is_disabled() {
	local project status
	project="$(mktemp -d)" || return 1
	printf '%s\n' v0.0.1 >"$project/.node-version"
	if fish -l -i -c "
		not functions -q _fnm_autoload_hook
		and set before (path resolve (command -v node))
		and cd '$project'
		and set after (path resolve (command -v node))
		and test \"\$before\" = \"\$after\"
	" >/dev/null 2>&1; then
		status=0
	else
		status=1
	fi
	rm -rf "$project"
	return "$status"
}
playwright_mcp_starts() {
	local input npx_bin output payload pid probe_dir result=1
	npx_bin="$(fish_path npx)" || return 1
	probe_dir="$(mktemp -d)" || return 1
	input="$probe_dir/input"
	output="$probe_dir/output"
	mkfifo "$input" || {
		rm -rf "$probe_dir"
		return 1
	}
	exec 4<>"$input"
	PATH="$(dirname "$npx_bin"):$PATH" \
		"$npx_bin" --yes @playwright/mcp@latest \
		<"$input" >"$output" 2>"$probe_dir/error" &
	pid=$!
	payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"dotfiles-e2e","version":"1"}}}'
	printf '%s\n' "$payload" >&4
	for _ in {1..360}; do
		if grep -Eq \
			'"id"[[:space:]]*:[[:space:]]*1.*"result"|"result".*"id"[[:space:]]*:[[:space:]]*1' \
			"$output"; then
			result=0
			break
		fi
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		sleep 0.5
	done
	kill "$pid" >/dev/null 2>&1 || true
	wait "$pid" 2>/dev/null || true
	exec 4>&-
	rm -rf "$probe_dir"
	return "$result"
}
lsp_initialize_response_has() {
	local member="$1"
	local output="$2"
	grep -Eq \
		"\"id\"[[:space:]]*:[[:space:]]*1.*\"$member\"|\"$member\".*\"id\"[[:space:]]*:[[:space:]]*1" \
		"$output"
}
lsp_initialize_works() {
	local command_name="$1"
	local without_node_path="$2"
	local input output payload pid probe_dir result=1 server
	server="$(fish_path "$command_name")" || return 1
	probe_dir="$(mktemp -d)" || return 1
	input="$probe_dir/input"
	output="$probe_dir/output"
	mkfifo "$input" || {
		rm -rf "$probe_dir"
		return 1
	}
	exec 3<>"$input"
	if [[ "$without_node_path" == true ]]; then
		env -u NODE_PATH "$server" --stdio <"$input" >"$output" \
			2>"$probe_dir/error" &
	else
		"$server" --stdio <"$input" >"$output" 2>"$probe_dir/error" &
	fi
	pid=$!
	payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
	printf 'Content-Length: %d\r\n\r\n%s' "${#payload}" "$payload" >&3
	for _ in {1..50}; do
		if lsp_initialize_response_has result "$output"; then
			result=0
			break
		fi
		if lsp_initialize_response_has error "$output"; then
			break
		fi
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		sleep 0.1
	done
	kill "$pid" >/dev/null 2>&1 || true
	wait "$pid" 2>/dev/null || true
	exec 3>&-
	rm -rf "$probe_dir"
	return "$result"
}
plain_direnv_works() {
	local direnv_bin project result
	direnv_bin="$(fish_path direnv)" || return 1
	project="$(mktemp -d)" || return 1
	printf '%s\n' "export DOTFILES_PLAIN_DIRENV=loaded" >"$project/.envrc"
	if ! "$direnv_bin" allow "$project" >/dev/null 2>&1; then
		rm -rf "$project"
		return 1
	fi
	result="$("$direnv_bin" exec "$project" sh -c \
		'printf %s "$DOTFILES_PLAIN_DIRENV"' 2>/dev/null)"
	rm -rf "$project"
	[[ "$result" == loaded ]]
}
nix_direnv_flake_works() {
	local command_name direnv_bin index layout nix_bin nix_path
	local nixpkgs_path project profile source_dir
	local -a global_paths=()
	direnv_bin="$(fish_path direnv)" || return 1
	nix_bin="$(fish_path nix)" || return 1
	nix_path="$(dirname "$nix_bin"):$PATH"
	source_dir="$HOME/.local/share/chezmoi"
	project="$(mktemp -d)" || return 1
	for command_name in node python cargo go bun; do
		global_paths+=("$(fish_path "$command_name")")
	done
	nixpkgs_path="$("$nix_bin" eval --raw \
		"path:$source_dir/nix#homeConfigurations.\"ci@linux-desktop\".pkgs.path")" || {
		rm -rf "$project"
		return 1
	}
	cat >"$project/flake.nix" <<EOF
{
  inputs.nixpkgs.url = "path:$nixpkgs_path";
  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      marker = name: pkgs.writeShellScriptBin name
        "printf '%s\\n' project-\${name}";
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        DOTFILES_NIX_DIRENV = "loaded";
        packages = map marker [ "node" "python" "cargo" "go" "bun" ];
      };
    };
}
EOF
	cat >"$project/.envrc" <<'EOF'
use flake
export DOTFILES_NIX_DIRENV_LAYOUT_DIR="$(direnv_layout_dir)"
EOF
	if ! PATH="$nix_path" "$direnv_bin" allow "$project" >/dev/null 2>&1; then
		rm -rf "$project"
		return 1
	fi
	layout="$(PATH="$nix_path" "$direnv_bin" exec "$project" sh -c '
		test "$DOTFILES_NIX_DIRENV" = loaded || exit 1
		for command_name in node python cargo go bun; do
			test "$("$command_name")" = "project-$command_name" || exit 1
		done
		printf %s "$DOTFILES_NIX_DIRENV_LAYOUT_DIR"
	' 2>/dev/null)" || {
		rm -rf "$project"
		return 1
	}
	if ! PATH="$nix_path" "$direnv_bin" exec "$project" fish -l -c '
		for command_name in node python cargo go bun
			test ($command_name) = project-$command_name; or exit 1
		end
	' >/dev/null 2>&1; then
		rm -rf "$project"
		return 1
	fi
	profile="$(find "$layout" -maxdepth 1 -type l -name 'flake-profile*' \
		-exec test -e {} \; -print -quit)"
	index=0
	for command_name in node python cargo go bun; do
		[[ "$(fish_path "$command_name")" == "${global_paths[$index]}" ]] || {
			rm -rf "$project"
			return 1
		}
		index=$((index + 1))
	done
	rm -rf "$project"
	[[ -n "$profile" ]]
}

if [[ "$MODE" == "preflight" ]]; then
	echo "== preflight inventory (bins present BEFORE apply; install NOT proven for these) =="
	for b in "${MANIFEST_BINS[@]}" "${HOME_MANAGER_BINS[@]}" \
		"${GUI_BINS[@]}" "${FNM_BINS[@]}" "${UV_BINS[@]}" \
		"${RUSTUP_BINS[@]}" "${NPM_PREFIX_BINS[@]}" "${AGENT_BINS[@]}"; do
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
	local desc="$1" output
	shift
	if output="$("$@" 2>&1)"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc"
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | sed 's/^/    /'
		fi
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

echo "== Home Manager CLI ownership =="
for b in "${HOME_MANAGER_BINS[@]}"; do
	hard "Home Manager owns $b" home_manager_owns "$b"
done
hard "Home Manager profile is active" test -L \
	"${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles/home-manager"
hard "active generation was recorded before activation" test -s \
	"${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/home-manager-before-switch"
hard "rollback generation state exists" test -s \
	"${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/home-manager-previous-generation"
hard "tmux starts" fish -l -i -c 'tmux -L dotfiles-e2e start-server'
hard "fzf version probe" fish -l -i -c 'fzf --version'
hard "Neovim startup probe" fish -l -i -c "nvim --headless '+quit'"
hard "source tree passes the single-owner policy" bash \
	"$HOME/.local/share/chezmoi/.github/scripts/check-tool-ownership.sh" \
	"$HOME/.local/share/chezmoi"
hard "Home Manager nix-direnv integration is installed" test -r \
	"$HOME/.nix-profile/share/nix-direnv/direnvrc"
hard "chezmoi direnvrc loads Home Manager nix-direnv" grep -Fxq \
	'source "$HOME/.nix-profile/share/nix-direnv/direnvrc"' \
	"$HOME/.config/direnv/direnvrc"
hard "plain direnv environment loads" plain_direnv_works
hard "nix-direnv use flake loads and retains a GC root" nix_direnv_flake_works

echo "== GUI desktop apps (desktop profile must install these) =="
for b in "${GUI_BINS[@]}"; do hard "gui bin $b" fish_has "$b"; done
hard "voquill-desktop installed (dpkg)" dpkg -s voquill-desktop
for app in "${FLATPAK_APPS[@]}"; do hard "flatpak $app" flatpak info "$app"; done

echo "== native runtime ownership =="
if [[ "$ENVIRONMENT" == runner ]]; then
	hard "retained mise files are unchanged" retained_mise_fixtures_are_unchanged
fi
hard "managed Fish PATH order" managed_path_order_works
for b in "${FNM_BINS[@]}"; do hard "fnm owns $b" fnm_owns "$b"; done
if fish_has corepack; then
	hard "fnm owns optional corepack" fnm_owns corepack
fi
hard "fnm selected a Node LTS" fish -l -i -c \
	'test -n "$(node -p '\''process.release.lts || ""'\'')"'
hard "fnm automatic project switching is disabled" fnm_auto_switch_is_disabled
for b in "${UV_BINS[@]}"; do hard "uv owns $b" uv_owns "$b"; done
hard "uv Python is exactly 3.14.6" fish -l -i -c \
	'test "$(python --version 2>&1)" = "Python 3.14.6"'
for b in "${RUSTUP_BINS[@]}"; do hard "rustup owns $b" rustup_owns "$b"; done
hard "Home Manager owns rustup executable" home_manager_owns rustup
hard "stable Rust toolchain is active" fish -l -i -c \
	'env -u RUSTUP_TOOLCHAIN rustup show active-toolchain | string match -qr "^stable-"'
for b in go gofmt bun; do hard "Home Manager owns $b" home_manager_owns "$b"; done
for b in "${NPM_PREFIX_BINS[@]}"; do
	hard "npm prefix owns $b" npm_prefix_owns "$b"
done
hard "npm global prefix" fish -l -i -c \
	'test "$(npm config get prefix)" = "$HOME/.local/share/npm"'
hard "Pi latest channel package installed" fish -l -i -c \
	'npm list --global --depth=0 --prefix "$HOME/.local/share/npm" @earendil-works/pi-coding-agent'
hard "Hunk latest channel package installed" fish -l -i -c \
	'npm list --global --depth=0 --prefix "$HOME/.local/share/npm" hunkdiff'
hard "Playwright MCP starts through fnm npx" playwright_mcp_starts
for b in "${HOME_MANAGER_BINS[@]}" "${FNM_BINS[@]}" "${UV_BINS[@]}" \
	"${RUSTUP_BINS[@]}" "${NPM_PREFIX_BINS[@]}"; do
	hard "selected $b path contains no mise" selected_path_is_not_mise "$b"
done

echo "== coding agents + nix =="
for b in "${AGENT_BINS[@]}"; do hard "agent $b" fish_has "$b"; done
hard "agent pi" fish_has pi
hard "nix" fish_has nix

echo "== Home Manager LSP startup/version probes =="
for b in "${LSP_BINS[@]}"; do hard "Home Manager owns LSP $b" home_manager_owns "$b"; done
hard "rust-analyzer version probe" fish -l -i -c 'rust-analyzer --version'
hard "pyright version probe" fish -l -i -c 'pyright --version'
hard "pyright language server initialize probe" \
	lsp_initialize_works pyright-langserver false
hard "TypeScript language server version probe" \
	fish -l -i -c 'typescript-language-server --version'
hard "TypeScript language server initialize probe without NODE_PATH" \
	lsp_initialize_works typescript-language-server true
hard "gopls version probe" fish -l -i -c 'gopls version'
hard "clangd version probe" fish -l -i -c 'clangd --version'
hard "Fish has no mise-specific NODE_PATH" fish -l -i -c \
	'if set -q NODE_PATH; not string match -q "*/mise/*" -- $NODE_PATH; end'

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
hard "pi settings materialized" test -f "$HOME/.pi/agent/settings.json"
hard "pi git-diff package declared" \
	jq -e '.packages | index("npm:pi-git-diff") != null' "$HOME/.pi/agent/settings.json"
hard "pi local git-diff extension absent" test ! -e "$HOME/.pi/agent/extensions/git-diff"
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
	jq -e '.skills | index("~/.local/share/npm/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md") != null' \
	"$HOME/.pi/agent/settings.json"
hard "Hunk review skill installed" \
	test -f "$HOME/.local/share/npm/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md"
hard "generated no-mistakes skills synchronized" \
	bash -c 'test -f "$HOME/.agents/skills/no-mistakes/SKILL.md" && cmp -s "$HOME/.agents/skills/no-mistakes/SKILL.md" "$HOME/.claude/skills/no-mistakes/SKILL.md"'

echo "== home ownership (root-elevated installers must not write here) =="
# Guards the class behind the run-28558929981 failure: a root-run installer
# step (nix's fish self-test) creating root-owned dirs in the user's home.
ROOT_OWNED="$(find "$HOME/.config" "$HOME/.local" "$HOME/.cache" -user root 2>/dev/null || true)"
if [[ -z "$ROOT_OWNED" ]]; then
	echo "PASS: no root-owned files under ~/.config ~/.local ~/.cache"
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
for b in chezmoi fish starship atuin eza gh op fnm node python rustup go bun pi hunk; do
	p="$(fish -l -i -c "command -v $b" 2>/dev/null | sed -e $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | tail -1 || true)"
	if [[ -n "$p" && -x "$p" ]]; then
		echo "VERSION: $b = $("$p" --version 2>/dev/null | head -1)"
	else
		echo "VERSION: $b = absent"
	fi
done

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
