#!/usr/bin/env bash
# Exercise the dedicated-profile lifecycle in a temporary directory only.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
profile_template="$repo_root/.chezmoiscripts/run_onchange_before_15-install-nix-profile.sh.tmpl"
if grep -Fq 'chezmoi source-path' "$profile_template"; then
	echo "Profile installer must not start nested chezmoi during apply" >&2
	exit 1
fi
if ! grep -Fq 'joinPath .chezmoi.sourceDir "nix"' "$profile_template"; then
	echo "Profile installer must render its source path from .chezmoi.sourceDir" >&2
	exit 1
fi

# A fresh installer cannot update its parent shell, and this test also runs in a
# later GitHub Actions step. Initialize an installed Nix before using it.
if ! command -v nix >/dev/null 2>&1; then
	unset __ETC_PROFILE_NIX_SOURCED
	for nix_init in \
		/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
		"$HOME/.nix-profile/etc/profile.d/nix.sh"; do
		if [[ -r "$nix_init" ]]; then
			# shellcheck source=/dev/null
			source "$nix_init"
			break
		fi
	done
fi
if ! command -v nix >/dev/null 2>&1; then
	echo "Nix is required by the dedicated profile lifecycle test" >&2
	exit 1
fi

tmp="$(mktemp -d)"
# macOS exposes /var as a symlink to /private/var. Canonicalize before direnv
# records its allow key so the later process cwd resolves to the same path.
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
# Mirror a chezmoi source directory so the real profile installer can be
# rendered against this fixture instead of against the live source tree.
source_dir="$tmp/source"
mkdir -p "$source_dir"
cp -a "$repo_root/nix" "$source_dir/nix"
cp -a "$repo_root/.chezmoitemplates" "$source_dir/.chezmoitemplates"

profile="$tmp/state/nix/profiles/dotfiles"
flake="path:$source_dir/nix"
mkdir -p "$(dirname "$profile")"

out="$(nix build "$flake#workstation" --no-link --print-out-paths)"
for bin in eza bat fd rg fzf gum starship atuin zoxide direnv tmux nvim go gopls pyright pyright-langserver tsc tsserver typescript-language-server fnm uv; do
	case "$bin" in
	direnv | go | gopls) "$out/bin/$bin" version >/dev/null ;;
	pyright-langserver | tsserver) ;;
	tmux) "$out/bin/$bin" -V >/dev/null ;;
	*) "$out/bin/$bin" --version >/dev/null ;;
	esac
done
if [[ -e "$out/bin/pi" ]]; then
	echo "Pi must stay outside the Nix bundle (native npm prefix owns it)" >&2
	exit 1
fi
python3 "$repo_root/nix/lsp-smoke.py" \
	"$out/bin/pyright-langserver" \
	"$out/bin/typescript-language-server"
test -r "$out/share/nix-direnv/direnvrc"

nix profile add --profile "$profile" "$flake#workstation"
profile_json="$(nix profile list --profile "$profile" --json)"
PROFILE_JSON="$profile_json" python3 - "$out" <<'PY'
import json
import os
import sys

profile = json.loads(os.environ["PROFILE_JSON"])
elements = profile["elements"]
store_paths = [path for element in elements.values() for path in element["storePaths"]]
if len(elements) != 1 or sys.argv[1] not in store_paths:
    raise SystemExit("profile does not contain exactly the built workstation bundle")
PY

initial_link="$(readlink "$profile")"

# The managed direnvrc must load nix-direnv from this temporary profile and
# provide `use flake` without downloading a second independently pinned copy.
mkdir -p "$tmp/config/direnv" "$tmp/data"
cp "$repo_root/dot_config/direnv/direnvrc" "$tmp/config/direnv/direnvrc"
fixture="$tmp/direnv-fixture"
mkdir -p "$fixture"
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
bash "$repo_root/.github/scripts/create-direnv-flake-fixture.sh" \
	"$fixture/flake.nix" "$source_dir/nix" "$system"
printf 'use flake\n' >"$fixture/.envrc"
direnv_env=(
	"XDG_CONFIG_HOME=$tmp/config"
	"XDG_DATA_HOME=$tmp/data"
	"XDG_STATE_HOME=$tmp/state"
)
env "${direnv_env[@]}" "$out/bin/direnv" allow "$fixture"
# Expand the fixture variable inside direnv's child shell, not this test process.
# shellcheck disable=SC2016
env "${direnv_env[@]}" "$out/bin/direnv" exec "$fixture" \
	bash -c 'test "$DOTFILES_DIRENV_FIXTURE" = 1'

# A failed build must not reach profile activation. Exercise the installer
# itself: a standalone `nix build` never writes to the dedicated profile, so it
# cannot detect the installer falling through to `nix profile upgrade`.
render_installer() {
	chezmoi --source "$source_dir" execute-template \
		<"$profile_template" >"$tmp/install-profile.sh"
	grep -Fq "flake=\"path:$source_dir/nix\"" "$tmp/install-profile.sh"
}

cp "$source_dir/nix/flake.nix" "$tmp/flake.nix.valid"
printf '\nnot valid Nix\n' >>"$source_dir/nix/flake.nix"
render_installer
if XDG_STATE_HOME="$tmp/state" bash "$tmp/install-profile.sh" \
	>"$tmp/failed-build.log" 2>&1; then
	echo "The installer accepted an intentionally invalid flake" >&2
	cat "$tmp/failed-build.log" >&2
	exit 1
fi
[[ "$(readlink "$profile")" == "$initial_link" ]]

# The same installer must succeed once the flake is valid again, proving the
# failure above came from the build and not from the fixture itself.
cp "$tmp/flake.nix.valid" "$source_dir/nix/flake.nix"
render_installer
XDG_STATE_HOME="$tmp/state" bash "$tmp/install-profile.sh"
[[ "$(readlink "$profile")" == "$initial_link" ]]

# An unchanged upgrade must not create a generation.
nix profile upgrade --profile "$profile" --all
unchanged_link="$(readlink "$profile")"
[[ "$unchanged_link" == "$initial_link" ]]

# Change only the aggregate derivation name to force a safe test generation.
python3 - "$source_dir/nix/bundles.nix" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = 'mkBundle "workstation" workstationPackages'
new = 'mkBundle "workstation-upgrade" workstationPackages'
if text.count(old) != 1:
    raise SystemExit("expected one workstation bundle definition")
path.write_text(text.replace(old, new))
PY
nix profile upgrade --profile "$profile" --all
upgraded_link="$(readlink "$profile")"
[[ "$upgraded_link" != "$initial_link" ]]

nix profile rollback --profile "$profile"
rolled_back_link="$(readlink "$profile")"
[[ "$rolled_back_link" == "$initial_link" ]]

# Applying from a relocated source dir makes the recorded originalUrl differ from
# the rendered flake ref, driving the installer's re-point branch. It must
# replace the managed element (never strand a zero-element profile) and record
# the new flake ref while keeping the same built store path.
relocated_source="$tmp/relocated-source"
mkdir -p "$relocated_source"
cp -a "$repo_root/nix" "$relocated_source/nix"
cp -a "$repo_root/.chezmoitemplates" "$relocated_source/.chezmoitemplates"
relocated_flake="path:$relocated_source/nix"
chezmoi --source "$relocated_source" execute-template \
	<"$profile_template" >"$tmp/relocated-install.sh"
grep -Fq "flake=\"$relocated_flake\"" "$tmp/relocated-install.sh"
XDG_STATE_HOME="$tmp/state" bash "$tmp/relocated-install.sh"
repoint_json="$(nix profile list --profile "$profile" --json)"
REPOINT_JSON="$repoint_json" RELOCATED_FLAKE="$relocated_flake" OUT="$out" python3 <<'PY'
import json
import os

profile = json.loads(os.environ["REPOINT_JSON"])
elements = profile["elements"]
if len(elements) != 1:
    raise SystemExit(f"re-point left {len(elements)} element(s), expected exactly 1")
element = next(iter(elements.values()))
if not element.get("attrPath", "").endswith(".workstation"):
    raise SystemExit(f"re-point lost the workstation attrPath: {element.get('attrPath')!r}")
if element.get("originalUrl") != os.environ["RELOCATED_FLAKE"]:
    raise SystemExit(f"re-point did not record the new flake ref: {element.get('originalUrl')!r}")
if os.environ["OUT"] not in element.get("storePaths", []):
    raise SystemExit("re-point changed the built store path")
print("re-point branch replaced the managed element from a relocated source")
PY

if find "$tmp" -user 0 -print -quit | grep -q .; then
	echo "Temporary profile test created root-owned files" >&2
	exit 1
fi

echo "Temporary profile add, idempotent upgrade, and rollback passed"
