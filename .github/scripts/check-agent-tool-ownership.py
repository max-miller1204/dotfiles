#!/usr/bin/env python3
"""Check exact agent-tool ownership for Pi and Hunk."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parents[2]
HUNK_PREFIX = "~/.local/share/npm-hunkdiff"
HUNK_SKILL = f"{HUNK_PREFIX}/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md"
PI_PREFIX = "~/.local/share/npm-pi"
PI_PREFIX_SHELL = PI_PREFIX.replace("~", "$HOME", 1)


def read(relative: str) -> str:
    return (ROOT / relative).read_text()


def fail(message: str) -> NoReturn:
    print(f"Agent-tool ownership error: {message}", file=sys.stderr)
    raise SystemExit(1)


def package_group(name: str, packages: str) -> set[str]:
    match = re.search(rf"{name} = with pkgs; \[(.*?)\n  \];", packages, re.DOTALL)
    if not match:
        fail(f"could not find the Nix {name} package group")
    return {
        line.strip()
        for line in match.group(1).splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }


def main() -> None:
    packages = read("nix/packages.nix")
    workstation = package_group("workstation", packages)
    expected_workstation = {"fnm", "uv"}
    if workstation != expected_workstation:
        fail(
            f"Nix workstation group is {workstation!r}, "
            f"expected {expected_workstation!r}"
        )
    # The nixpkgs attribute would carry the npm package's name, hunkdiff.
    if re.search(r"^\s+hunk(?:diff)?\s*$", packages, re.MULTILINE):
        fail("Hunk must remain outside the universal Nix bundle")
    if re.search(r"^\s+pi-coding-agent\s*$", packages, re.MULTILINE):
        fail("Pi must remain outside the universal Nix bundle")

    hunk_installer = read(".chezmoiscripts/run_onchange_before_17-install-hunk.sh.tmpl")
    required_hunk_installer = (
        'hunk_prefix="$HOME/.local/share/npm-hunkdiff"',
        'npm install --global --prefix "$hunk_prefix" hunkdiff@latest',
        '"$npm_bin" != "$FNM_MULTISHELL_PATH/bin/npm"',
        'ln -sfn "$hunk_prefix/bin/hunk" "$HOME/.local/bin/hunk"',
    )
    missing = [
        value for value in required_hunk_installer if value not in hunk_installer
    ]
    if missing:
        fail(f"native Hunk installer lacks required declarations: {missing!r}")

    pi_installer = read(".chezmoiscripts/run_onchange_before_18-install-pi.sh.tmpl")
    required_pi_installer = (
        f'pi_prefix="{PI_PREFIX_SHELL}"',
        'npm install --global --prefix "$pi_prefix" @earendil-works/pi-coding-agent@latest',
        '"$npm_bin" != "$FNM_MULTISHELL_PATH/bin/npm"',
        'ln -sfn "$pi_prefix/bin/pi" "$HOME/.local/bin/pi"',
    )
    missing = [value for value in required_pi_installer if value not in pi_installer]
    if missing:
        fail(f"native Pi installer lacks required declarations: {missing!r}")

    try:
        settings = json.loads(read("dot_pi/agent/settings.json"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not parse Pi settings: {error}")
    if settings.get("skills") != [HUNK_SKILL]:
        fail(
            f"Pi Hunk skill path is {settings.get('skills')!r}, expected {HUNK_SKILL!r}"
        )
    if "npmCommand" in settings:
        fail("Pi must use the fnm-managed npm resolved from Fish PATH")

    profile_installer = read(
        ".chezmoiscripts/run_onchange_before_15-install-nix-profile.sh.tmpl"
    )
    if re.search(r"for bin in .*\bpi\b.*; do", profile_installer):
        fail("the profile activation smoke still includes Pi")

    update_all = read("dot_config/fish/functions/update-all.fish.tmpl")
    required_update = (
        'set -l hunk_prefix "$HOME/.local/share/npm-hunkdiff"',
        'npm install --global --prefix "$hunk_prefix" hunkdiff@latest',
        'set -l pi_prefix "$HOME/.local/share/npm-pi"',
        'npm install --global --prefix "$pi_prefix" @earendil-works/pi-coding-agent@latest',
    )
    missing = [value for value in required_update if value not in update_all]
    if missing:
        fail(f"update-all lacks native Hunk and Pi updates: {missing!r}")

    print("Agent-tool ownership is exact: native npm owns Pi and Hunk")


if __name__ == "__main__":
    main()
