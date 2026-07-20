{ pkgs }:
{
  core = with pkgs; [
    eza
    bat
    fd
    ripgrep
    fzf
  ];

  # The bundles remain cumulative, so the dedicated profile always installs
  # only workstation rather than overlapping bundle elements.
  headless = with pkgs; [
    gum
    starship
    atuin
    zoxide
    direnv
    tmux
    neovim
    nix-direnv
  ];
  # gopls invokes Go from PATH, so they are pinned and updated together.
  lsp = with pkgs; [
    go
    gopls
  ];

  # Nix owns the manager executables; their mutable runtimes stay outside the
  # store under fnm and uv.
  workstation = with pkgs; [
    fnm
    uv
  ];
}
