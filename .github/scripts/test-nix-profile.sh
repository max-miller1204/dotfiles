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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -a "$repo_root/nix" "$tmp/nix"

profile="$tmp/state/nix/profiles/dotfiles"
flake="path:$tmp/nix"
mkdir -p "$(dirname "$profile")"

out="$(nix build "$flake#workstation" --no-link --print-out-paths)"
for bin in eza bat fd rg fzf gum starship atuin zoxide direnv tmux nvim go gopls fnm uv; do
	case "$bin" in
	direnv | go | gopls) "$out/bin/$bin" version >/dev/null ;;
	tmux) "$out/bin/$bin" -V >/dev/null ;;
	*) "$out/bin/$bin" --version >/dev/null ;;
	esac
done
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
	"$fixture/flake.nix" "$tmp/nix" "$system"
printf 'use flake\n' >"$fixture/.envrc"
direnv_env=(
	"XDG_CONFIG_HOME=$tmp/config"
	"XDG_DATA_HOME=$tmp/data"
	"XDG_STATE_HOME=$tmp/state"
)
env "${direnv_env[@]}" "$out/bin/direnv" allow "$fixture"
env "${direnv_env[@]}" "$out/bin/direnv" exec "$fixture" \
	bash -c 'test "$DOTFILES_DIRENV_FIXTURE" = 1'

# A failed build must not reach profile activation.
cp "$tmp/nix/flake.nix" "$tmp/flake.nix.valid"
printf '\nnot valid Nix\n' >>"$tmp/nix/flake.nix"
if nix build "$flake#workstation" --no-link >/dev/null 2>&1; then
	echo "Intentionally invalid flake unexpectedly built" >&2
	exit 1
fi
[[ "$(readlink "$profile")" == "$initial_link" ]]
mv "$tmp/flake.nix.valid" "$tmp/nix/flake.nix"

# An unchanged upgrade must not create a generation.
nix profile upgrade --profile "$profile" --all
unchanged_link="$(readlink "$profile")"
[[ "$unchanged_link" == "$initial_link" ]]

# Change only the aggregate derivation name to force a safe test generation.
python3 - "$tmp/nix/bundles.nix" <<'PY'
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

if find "$tmp" -user 0 -print -quit | grep -q .; then
	echo "Temporary profile test created root-owned files" >&2
	exit 1
fi

echo "Temporary profile add, idempotent upgrade, and rollback passed"
