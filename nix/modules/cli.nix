{ pkgs, ... }:
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
  packageByName = {
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
in
{
  dotfiles.homeManager.packageClaims = expectedPackages;
  dotfiles.homeManager.commandClaims = expectedCommands;

  home.packages = map (name: packageByName.${name}) expectedPackages;
}
