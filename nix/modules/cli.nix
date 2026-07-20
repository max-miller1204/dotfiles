{ lib, pkgs, ... }:
let
  expectedPackages = [
    "atuin"
    "bat"
    "eza"
    "fd"
    "fzf"
    "gum"
    "neovim"
    "ripgrep"
    "starship"
    "tmux"
    "zoxide"
  ];
  expectedCommands = [
    "atuin"
    "bat"
    "eza"
    "fd"
    "fzf"
    "gum"
    "nvim"
    "rg"
    "starship"
    "tmux"
    "zoxide"
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
  sourcePackages = {
    inherit (pkgs)
      atuin
      bat
      eza
      fd
      fzf
      gum
      neovim
      ripgrep
      starship
      tmux
      zoxide
      ;
  };
  commandsByPackage = {
    atuin = [ "atuin" ];
    bat = [ "bat" ];
    eza = [ "eza" ];
    fd = [ "fd" ];
    fzf = [ "fzf" ];
    gum = [ "gum" ];
    neovim = [ "nvim" ];
    ripgrep = [ "rg" ];
    starship = [ "starship" ];
    tmux = [ "tmux" ];
    zoxide = [ "zoxide" ];
  };
  packageByName = lib.mapAttrs (
    name: package: commandOnly name package commandsByPackage.${name}
  ) sourcePackages;
in
{
  dotfiles.homeManager.packageClaims = expectedPackages;
  dotfiles.homeManager.commandClaims = expectedCommands;

  home.packages = map (name: packageByName.${name}) expectedPackages;
}
