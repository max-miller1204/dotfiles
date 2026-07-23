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
    shellcheck
    nix-direnv
  ];
  # gopls invokes Go from PATH, so Go stays pinned beside it. typescript-go
  # owns the tsc/tsgo CLIs; the nixpkgs typescript attribute would collide on
  # bin/tsc and trails the native TS 7 compiler. typescript-language-server
  # resolves its own pinned TypeScript module internally.
  lsp = with pkgs; [
    go
    gopls
    pyright
    typescript-go
    typescript-language-server
  ];

  # Nix owns the manager executables. Mutable runtimes stay outside the store
  # under fnm and uv. Pi stays outside Nix with Hunk so npm releases land
  # immediately instead of trailing the nixpkgs package bump.
  workstation = with pkgs; [
    fnm
    uv
  ];
}
