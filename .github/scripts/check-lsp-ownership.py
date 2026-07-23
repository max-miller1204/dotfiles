#!/usr/bin/env python3
"""Check that each global LSP tool has exactly one declared owner."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[2]


def read(relative: str) -> str:
    return (ROOT / relative).read_text()


def fail(message: str) -> NoReturn:
    print(f"LSP ownership error: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    config = read(".chezmoi.toml.tmpl")
    entries = {}
    for block in config.split("[[data.lspLanguages]]")[1:]:
        plugin_match = re.search(r'^\s*plugin = "([^"]+)"', block, re.MULTILINE)
        method_match = re.search(r'^\s*method = "([^"]+)"', block, re.MULTILINE)
        if not plugin_match or not method_match:
            fail("an lspLanguages entry lacks plugin or method")
        entries[plugin_match.group(1)] = method_match.group(1)
    expected_entries = {
        "rust-analyzer-lsp": "rustup",
        "pyright-lsp": "nix",
        "typescript-lsp": "nix",
        "gopls-lsp": "nix",
        "clangd-lsp": "os",
    }
    if entries != expected_entries:
        fail(f"lspLanguages ownership is {entries!r}, expected {expected_entries!r}")

    packages = read("nix/packages.nix")
    lsp_match = re.search(r"lsp = with pkgs; \[(.*?)\n  \];", packages, re.DOTALL)
    if not lsp_match:
        fail("could not find the Nix lsp package group")
    nix_lsp = {
        line.strip()
        for line in lsp_match.group(1).splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    expected_nix_lsp = {
        "go",
        "gopls",
        "pyright",
        "typescript-go",
        "typescript-language-server",
    }
    if nix_lsp != expected_nix_lsp:
        fail(f"Nix lsp group is {nix_lsp!r}, expected {expected_nix_lsp!r}")

    print("LSP ownership is exact: Nix owns Pyright and TypeScript tooling")


if __name__ == "__main__":
    main()
