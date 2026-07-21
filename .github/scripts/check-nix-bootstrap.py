#!/usr/bin/env python3
"""Check fresh-machine Nix bootstrap ownership, routing, and ordering."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / ".chezmoiscripts"
NATIVE = SCRIPTS / "run_once_before_10-install-packages.sh.tmpl"
NIX = SCRIPTS / "run_once_before_12-install-nix.sh.tmpl"
PROFILE = SCRIPTS / "run_onchange_before_15-install-nix-profile.sh.tmpl"
RUNTIMES = SCRIPTS / "run_onchange_before_16-install-language-runtimes.sh.tmpl"
HUNK = SCRIPTS / "run_onchange_before_17-install-hunk.sh.tmpl"
LSP = SCRIPTS / "run_onchange_after_50-install-lsp-servers.sh.tmpl"
PACKAGES = REPO_ROOT / ".chezmoidata/packages.yaml"


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


def main() -> None:
    ordered_scripts = [NATIVE, NIX, PROFILE, RUNTIMES, HUNK, LSP]
    missing = [path for path in ordered_scripts if not path.is_file()]
    if missing:
        raise SystemExit(f"missing bootstrap scripts: {missing}")
    expected_stages = ("_10-", "_12-", "_15-", "_16-", "_17-", "_50-")
    for path, stage in zip(ordered_scripts, expected_stages, strict=True):
        if stage not in path.name:
            raise SystemExit(
                f"{path.name} no longer enforces its required bootstrap stage {stage}"
            )

    native = NATIVE.read_text()
    nix = NIX.read_text()
    profile = PROFILE.read_text()
    packages = PACKAGES.read_text()

    for installer_url in (
        "install.determinate.systems/nix",
        "determinate-pkg/stable/Universal",
        "nixos.org/nix/install",
    ):
        forbid(native, installer_url, NATIVE)
        require(nix, installer_url, NIX)

    for invariant in (
        'sudo HOME=/root XDG_CONFIG_HOME=/root/.config',
        'case "$(uname -m)"',
        'arm64)',
        'x86_64)',
        'X3JQ4VPJZ6',
        '--daemon',
        '--yes',
        '--no-channel-add',
        '--no-modify-profile',
        'extra-experimental-features = nix-command flakes',
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
