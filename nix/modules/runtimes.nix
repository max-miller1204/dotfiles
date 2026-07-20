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
  commandOnly =
    name: package: commands:
    pkgs.runCommand "${name}-${package.version}-commands" { } ''
      mkdir -p "$out/bin"
      ${lib.concatMapStringsSep "\n" (command: ''
        test -x "${package}/bin/${command}"
        ln -s "${package}/bin/${command}" "$out/bin/${command}"
      '') commands}
    '';
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
