#!/usr/bin/env bash
# Verify Fish ownership precedence with isolated fake commands only.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
state="$tmp/state"
data="$tmp/data"
runtime="$tmp/runtime"
profile="$state/nix/profiles/dotfiles"
mkdir -p \
	"$home/.config/fish" \
	"$home/.local/bin" \
	"$home/.local/share/mise/shims" \
	"$home/.cargo/bin" \
	"$home/.bun/bin" \
	"$data/uv/python-bin" \
	"$runtime/fnm_multishells/test/bin" \
	"$profile/bin" \
	"$tmp/system/bin" \
	"$tmp/default/bin"

make_command() {
	local path="$1"
	printf '#!/bin/sh\nexit 0\n' >"$path"
	chmod +x "$path"
}

# The mise mock prepends stale shims exactly as activation does. The managed
# config must move this directory behind every other ownership layer afterward.
cat >"$home/.local/bin/mise" <<'EOF'
#!/bin/sh
if [ "${1:-}" = activate ]; then
    printf 'fish_add_path --global --move --path "%s"\n' "$HOME/.local/share/mise/shims"
fi
EOF
chmod +x "$home/.local/bin/mise"

# The fnm mock emits its multishell path, which must be the final global runtime
# layer above the profile. It does not download or mutate any runtime.
cat >"$profile/bin/fnm" <<'EOF'
#!/bin/sh
if [ "${1:-}" = env ]; then
    printf 'set -gx PATH "%s" $PATH\n' "$XDG_RUNTIME_DIR/fnm_multishells/test/bin"
fi
EOF
chmod +x "$profile/bin/fnm"

for bin in eza go gopls pyright pyright-langserver tsc tsserver typescript-language-server uv node python rustup rustc cargo bun; do
	make_command "$profile/bin/$bin"
	make_command "$home/.local/share/mise/shims/$bin"
done
make_command "$home/.local/bin/go"
for bin in node npm; do make_command "$runtime/fnm_multishells/test/bin/$bin"; done
for bin in python python3; do make_command "$data/uv/python-bin/$bin"; done
for bin in rustup rustc cargo; do make_command "$home/.cargo/bin/$bin"; done
make_command "$home/.bun/bin/bun"
make_command "$home/.local/share/mise/shims/legacy-only"
make_command "$tmp/system/bin/legacy-only"
make_command "$home/.local/share/mise/shims/mise-only"

chezmoi --source "$repo_root" execute-template \
	<"$repo_root/dot_config/fish/config.fish.tmpl" \
	>"$home/.config/fish/config.fish"

fish_path() {
	env \
		HOME="$home" \
		XDG_CONFIG_HOME="$home/.config" \
		XDG_DATA_HOME="$data" \
		XDG_STATE_HOME="$state" \
		XDG_RUNTIME_DIR="$runtime" \
		CARGO_HOME="$home/.cargo" \
		BUN_INSTALL="$home/.bun" \
		RUSTUP_TOOLCHAIN=stale-mise-toolchain \
		NODE_PATH="$tmp/existing-node-modules" \
		PATH="$tmp/system/bin:$tmp/default/bin:/usr/bin:/bin" \
		fish -l -i -c "command -v $1" 2>/dev/null | tail -1
}

assert_path() {
	local bin="$1" expected="$2" actual
	actual="$(fish_path "$bin")"
	if [[ "$actual" != "$expected" ]]; then
		printf '%s resolved to %s, expected %s\n' "$bin" "$actual" "$expected" >&2
		exit 1
	fi
}

for bin in eza go gopls pyright pyright-langserver tsc tsserver typescript-language-server fnm uv; do
	assert_path "$bin" "$profile/bin/$bin"
done
for bin in node npm; do assert_path "$bin" "$runtime/fnm_multishells/test/bin/$bin"; done
for bin in python python3; do assert_path "$bin" "$data/uv/python-bin/$bin"; done
for bin in rustup rustc cargo; do assert_path "$bin" "$home/.cargo/bin/$bin"; done
assert_path bun "$home/.bun/bin/bun"
assert_path legacy-only "$tmp/system/bin/legacy-only"
assert_path mise-only "$home/.local/share/mise/shims/mise-only"

node_path="$(
	env \
		HOME="$home" \
		XDG_CONFIG_HOME="$home/.config" \
		XDG_DATA_HOME="$data" \
		XDG_STATE_HOME="$state" \
		XDG_RUNTIME_DIR="$runtime" \
		NODE_PATH="$tmp/existing-node-modules" \
		PATH="$tmp/system/bin:$tmp/default/bin:/usr/bin:/bin" \
		fish -l -i -c 'printf "%s\n" "$NODE_PATH"' 2>/dev/null | tail -1
)"
[[ "$node_path" == "$tmp/existing-node-modules" ]]

echo "Fish runtime and package ownership precedence passed"
