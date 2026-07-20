{ pkgs, toolOwnership, ... }:
let
  activeOwnership = toolOwnership.active.homeManager;
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
  assertions = [
    {
      assertion = activeOwnership.packages == expectedPackages;
      message = "Phase 2 Home Manager package ownership must match the CLI bundle";
    }
    {
      assertion = activeOwnership.commands == expectedCommands;
      message = "Phase 2 Home Manager command ownership must match the CLI bundle";
    }
  ];

  home.packages = map (name: packageByName.${name}) activeOwnership.packages;
}
