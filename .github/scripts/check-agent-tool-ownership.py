#!/usr/bin/env python3
"""Check exact Phase 7 ownership for Pi, Hunk, and retired mise state."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parents[2]
HUNK_PREFIX = "~/.local/share/npm-hunkdiff"
HUNK_SKILL = f"{HUNK_PREFIX}/lib/node_modules/hunkdiff/skills/hunk-review/SKILL.md"


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
    expected_workstation = {"fnm", "uv", "pi-coding-agent"}
    if workstation != expected_workstation:
        fail(
            f"Nix workstation group is {workstation!r}, "
            f"expected {expected_workstation!r}"
        )
    if re.search(r"^\s+hunk\s*$", packages, re.MULTILINE):
        fail("Hunk must remain outside the universal Nix bundle")

    manifest = read(".chezmoidata/packages.yaml")
    if re.search(r"^\s*- name: mise\s*$", manifest, re.MULTILINE):
        fail("the native package manifest still installs mise")
    if re.search(r"^\s+mise:\s*", manifest, re.MULTILINE):
        fail("the native package manifest still exposes a mise method")

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
    if not re.search(r"for bin in .*\bpi\b.*; do", profile_installer):
        fail("the profile activation smoke does not include Pi")

    update_all = read("dot_config/fish/functions/update-all.fish.tmpl")
    required_update = (
        'set -l hunk_prefix "$HOME/.local/share/npm-hunkdiff"',
        'npm install --global --prefix "$hunk_prefix" hunkdiff@latest',
    )
    missing = [value for value in required_update if value not in update_all]
    if missing:
        fail(f"update-all lacks native Hunk updates: {missing!r}")

    active_files = {
        ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl": read(
            ".chezmoiscripts/run_once_before_10-install-packages.sh.tmpl"
        ),
        ".chezmoitemplates/lib-install.sh": read(".chezmoitemplates/lib-install.sh"),
        ".chezmoitemplates/lib-resolve.sh": read(".chezmoitemplates/lib-resolve.sh"),
        "dot_config/fish/config.fish.tmpl": read("dot_config/fish/config.fish.tmpl"),
        "dot_config/fish/functions/update-all.fish.tmpl": update_all,
    }
    forbidden_active = (
        "mise activate",
        "mise upgrade",
        "mise use",
        "resolve_mise",
        "install_mise",
        "npm:@earendil-works/pi-coding-agent",
        "npm:hunkdiff",
    )
    for relative, text in active_files.items():
        found = [value for value in forbidden_active if value in text]
        if found:
            fail(f"{relative} retains active mise ownership: {found!r}")

    migration_files = active_files | {
        ".chezmoidata/packages.yaml": manifest,
        ".chezmoiscripts/run_onchange_before_17-install-hunk.sh.tmpl": hunk_installer,
    }
    destructive = ("mise uninstall", "rm -rf $HOME/.local/share/mise")
    for relative, text in migration_files.items():
        found = [value for value in destructive if value in text]
        if found:
            fail(f"{relative} deletes preserved stale mise state: {found!r}")

    print(
        "Agent-tool ownership is exact: Nix owns Pi, native npm owns Hunk, "
        "and mise is inactive"
    )


if __name__ == "__main__":
    main()
