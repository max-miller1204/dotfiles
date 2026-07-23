#!/usr/bin/env python3
"""Check fresh-machine Nix bootstrap ownership, routing, and ordering."""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / ".chezmoiscripts"
NATIVE = SCRIPTS / "run_once_before_10-install-packages.sh.tmpl"
NIX = SCRIPTS / "run_once_before_12-install-nix.sh.tmpl"
PROFILE = SCRIPTS / "run_onchange_before_15-install-nix-profile.sh.tmpl"
RUNTIMES = SCRIPTS / "run_onchange_before_16-install-language-runtimes.sh.tmpl"
HUNK = SCRIPTS / "run_onchange_before_17-install-hunk.sh.tmpl"
PI = SCRIPTS / "run_onchange_before_18-install-pi.sh.tmpl"
LSP = SCRIPTS / "run_onchange_after_50-install-lsp-servers.sh.tmpl"
PACKAGES = REPO_ROOT / ".chezmoidata/packages.yaml"

ORDERED_SCRIPTS = (NATIVE, NIX, PROFILE, RUNTIMES, HUNK, PI, LSP)
# Native prerequisites, Nix, the dedicated profile, mutable runtimes, Hunk, Pi,
# and the language servers, in the order each stage's dependencies require.
ROLE_ORDER = (
    "install-packages",
    "install-nix",
    "install-nix-profile",
    "install-language-runtimes",
    "install-hunk",
    "install-pi",
    "install-lsp-servers",
)
STAGE_PATTERN = re.compile(
    r"^run_(?:once|onchange)_(?P<phase>before|after)_"
    r"(?P<name>\d+-(?P<role>[a-z-]+)\.sh)\.tmpl$"
)
# chezmoi runs every `before` script ahead of every `after` script, and within a
# phase sorts by the target NAME as a byte string - so `10-` sorts before `9-`,
# and a numeric stage key would mis-model that. Key on (phase, target name).
PHASE_ORDER = {"before": 0, "after": 1}


def require(text: str, needle: str, source: Path) -> None:
    if needle not in text:
        raise SystemExit(f"{source.relative_to(REPO_ROOT)} is missing: {needle}")


def forbid(text: str, needle: str, source: Path) -> None:
    if needle in text:
        raise SystemExit(f"{source.relative_to(REPO_ROOT)} must not contain: {needle}")


def assert_before(text: str, first: str, second: str, source: Path) -> None:
    first_index = text.find(first)
    second_index = text.find(second)
    if first_index < 0 or second_index < 0 or first_index >= second_index:
        raise SystemExit(
            f"{source.relative_to(REPO_ROOT)} must place {first!r} before {second!r}"
        )


def check_stage_order() -> None:
    """Read the real chezmoi execution order off disk, not off these constants."""
    discovered: dict[str, list[tuple[tuple[int, int], Path]]] = {}
    for path in sorted(SCRIPTS.iterdir()):
        match = STAGE_PATTERN.match(path.name)
        if not match or match.group("role") not in ROLE_ORDER:
            continue
        key = (PHASE_ORDER[match.group("phase")], match.group("name"))
        discovered.setdefault(match.group("role"), []).append((key, path))

    duplicated = {
        role: [path.name for _, path in found]
        for role, found in discovered.items()
        if len(found) > 1
    }
    if duplicated:
        raise SystemExit(f"bootstrap stages are declared more than once: {duplicated}")
    missing = [role for role in ROLE_ORDER if role not in discovered]
    if missing:
        raise SystemExit(f"missing bootstrap stages: {missing}")

    renamed = [
        discovered[role][0][1].name
        for role, expected in zip(ROLE_ORDER, ORDERED_SCRIPTS, strict=True)
        if discovered[role][0][1] != expected
    ]
    if renamed:
        raise SystemExit(
            "bootstrap stages were renamed, so the ownership checks below still "
            f"read the old file names: {renamed}"
        )

    keys = [discovered[role][0][0] for role in ROLE_ORDER]
    if keys != sorted(keys):
        raise SystemExit(
            "bootstrap scripts no longer run in their required order: "
            f"{[discovered[role][0][1].name for role in ROLE_ORDER]}"
        )


def main() -> None:
    check_stage_order()

    native = NATIVE.read_text()
    nix = NIX.read_text()
    profile = PROFILE.read_text()
    packages = PACKAGES.read_text()

    for installer_url in (
        "install.determinate.systems/nix",
        "determinate-pkg/stable/Universal",
    ):
        forbid(native, installer_url, NATIVE)
        require(nix, installer_url, NIX)

    # Intel macOS is unsupported: the upstream installer must not reappear in
    # any bootstrap stage now that the flake no longer targets x86_64-darwin.
    forbid(native, "nixos.org/nix/install", NATIVE)
    forbid(nix, "nixos.org/nix/install", NIX)

    for invariant in (
        'sudo HOME=/root XDG_CONFIG_HOME=/root/.config',
        'case "$(uname -m)"',
        'arm64)',
        'X3JQ4VPJZ6',
        'Unsupported macOS architecture for Nix bootstrap',
        'Refusing to modify existing Nix state automatically.',
    ):
        require(nix, invariant, NIX)

    for destructive_recovery in (
        "rm -rf /nix",
        "diskutil apfs deleteVolume",
        "/nix/nix-installer uninstall",
    ):
        forbid(nix, destructive_recovery, NIX)

    forbid(profile, "install Nix manually", PROFILE)
    require(profile, "Nix bootstrap did not complete", PROFILE)
    require(profile, "for brew_bin in /opt/homebrew/bin /usr/local/bin; do", PROFILE)
    require(profile, "jq is required for dedicated profile activation.", PROFILE)
    assert_before(
        profile,
        "jq is required for dedicated profile activation.",
        "nix profile list",
        PROFILE,
    )

    prerequisite_pairs = (
        ("- name: curl", "- name: pfetch"),
        ("- name: ca-certificates", "- name: treehouse"),
        ("- name: gnupg", "- name: gh"),
        ("- name: gnupg", "- name: 1password-cli"),
        ("- name: jq", "- name: obsidian"),
        ("- name: software-properties-common", "- name: ghostty"),
    )
    for prerequisite, consumer in prerequisite_pairs:
        assert_before(packages, prerequisite, consumer, PACKAGES)

    print(
        "Nix bootstrap is isolated, non-destructive, architecture-aware, and ordered"
    )


if __name__ == "__main__":
    main()
