{ lib, pkgs, ... }:
let
  ownedPackages = [
    "bun"
    "fnm"
    "go"
    "rustup"
    "uv"
  ];
  ownedCommands = [
    "bun"
    "fnm"
    "go"
    "gofmt"
    "rustup"
    "uv"
  ];
  commandOnly = import ../lib/command-only.nix { inherit lib pkgs; };
  packageByName = {
    bun = commandOnly "bun" pkgs.bun [ "bun" ];
    inherit (pkgs) fnm go;
    rustup = commandOnly "rustup" pkgs.rustup [ "rustup" ];
    uv = commandOnly "uv" pkgs.uv [ "uv" ];
  };
in
{
  dotfiles.homeManager.packageClaims = ownedPackages;
  dotfiles.homeManager.commandClaims = ownedCommands;

  home.packages = map (name: packageByName.${name}) ownedPackages;
}
