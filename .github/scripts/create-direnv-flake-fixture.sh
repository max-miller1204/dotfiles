#!/usr/bin/env bash
# Write the shared nix-direnv smoke-test flake used by focused and E2E checks.
set -euo pipefail

output="${1:?usage: create-direnv-flake-fixture.sh OUTPUT DOTFILES_SOURCE SYSTEM}"
dotfiles_source="${2:?missing dotfiles source path}"
system="${3:?missing Nix system}"
nixpkgs_input="nixpkgs"
if [[ "$system" == "x86_64-darwin" ]]; then
    nixpkgs_input="nixpkgs-darwin-intel"
fi

cat >"$output" <<EOF
{
  inputs.dotfiles.url = "path:$dotfiles_source";
  inputs.nixpkgs.follows = "dotfiles/$nixpkgs_input";
  outputs = { nixpkgs, ... }:
    let
      system = "$system";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.\${system}.default = pkgs.mkShell {
        shellHook = "export DOTFILES_DIRENV_FIXTURE=1";
      };
    };
}
EOF
