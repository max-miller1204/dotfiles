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

# The fnm mock emits its multishell path, which must be the final global runtime
# layer above the profile. It does not download or mutate any runtime.
cat >"$profile/bin/fnm" <<'EOF'
#!/bin/sh
if [ "${1:-}" = env ]; then
    printf 'set -gx PATH "%s" $PATH\n' "$XDG_RUNTIME_DIR/fnm_multishells/test/bin"
fi
EOF
chmod +x "$profile/bin/fnm"

for bin in eza shellcheck go gopls pyright pyright-langserver tsc tsgo typescript-language-server uv node python rustup rustc cargo bun; do
	make_command "$profile/bin/$bin"
done
make_command "$home/.local/bin/go"
make_command "$home/.local/bin/pi"
make_command "$home/.local/bin/hunk"
for bin in node npm; do make_command "$runtime/fnm_multishells/test/bin/$bin"; done
for bin in python python3; do make_command "$data/uv/python-bin/$bin"; done
for bin in rustup rustc cargo; do make_command "$home/.cargo/bin/$bin"; done
make_command "$home/.bun/bin/bun"
# A command present only in the inherited system PATH must still resolve there,
# below every managed layer.
make_command "$tmp/system/bin/legacy-only"

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

for bin in eza shellcheck go gopls pyright pyright-langserver tsc tsgo typescript-language-server fnm uv; do
	assert_path "$bin" "$profile/bin/$bin"
done
for bin in node npm; do assert_path "$bin" "$runtime/fnm_multishells/test/bin/$bin"; done
for bin in python python3; do assert_path "$bin" "$data/uv/python-bin/$bin"; done
for bin in rustup rustc cargo; do assert_path "$bin" "$home/.cargo/bin/$bin"; done
assert_path bun "$home/.bun/bin/bun"
assert_path pi "$home/.local/bin/pi"
assert_path hunk "$home/.local/bin/hunk"
assert_path legacy-only "$tmp/system/bin/legacy-only"

echo "Fish runtime and package ownership precedence passed"
