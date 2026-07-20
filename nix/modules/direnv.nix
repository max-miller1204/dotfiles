{ pkgs, ... }:
let
  ownedPackages = [
    "direnv"
    "nix-direnv"
  ];
  packageByName = {
    inherit (pkgs) direnv nix-direnv;
  };
in
{
  dotfiles.homeManager.packageClaims = ownedPackages;
  dotfiles.homeManager.commandClaims = [ "direnv" ];

  home.packages = map (name: packageByName.${name}) ownedPackages;
}
