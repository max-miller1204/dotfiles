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
  # gopls invokes Go from PATH, and typescript-language-server loads the
  # TypeScript module at runtime, so each server stays pinned with its runtime.
  lsp = with pkgs; [
    go
    gopls
    pyright
    typescript
    typescript-language-server
  ];

  # Nix owns the manager executables; their mutable runtimes stay outside the
  # store under fnm and uv.
  workstation = with pkgs; [
    fnm
    uv
  ];
}
