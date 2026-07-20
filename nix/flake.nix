{
  description = "Pinned command-line bundles for Max's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin-intel.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-darwin-intel,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      nixpkgsFor = system: if system == "x86_64-darwin" then nixpkgs-darwin-intel else nixpkgs;

      pkgsFor =
        system:
        import (nixpkgsFor system) {
          inherit system;
        };

      bundlesFor =
        system:
        let
          pkgs = pkgsFor system;
          packageGroups = import ./packages.nix { inherit pkgs; };
        in
        import ./bundles.nix { inherit pkgs packageGroups; };
    in
    {
      packages = forAllSystems bundlesFor;

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          bundles = bundlesFor system;
        in
        {
          core-smoke =
            pkgs.runCommand "dotfiles-core-smoke"
              {
                nativeBuildInputs = [ bundles.core ];
              }
              ''
                eza --version
                bat --version
                fd --version
                rg --version
                fzf --version
                touch "$out"
              '';

          headless-smoke =
            pkgs.runCommand "dotfiles-headless-smoke"
              {
                nativeBuildInputs = [ bundles.headless ];
              }
              ''
                gum --version
                starship --version
                atuin --version
                zoxide --version
                direnv version
                tmux -V
                nvim --version
                test -r ${bundles.headless}/share/nix-direnv/direnvrc
                touch "$out"
              '';

          lsp-smoke =
            pkgs.runCommand "dotfiles-lsp-smoke"
              {
                nativeBuildInputs = [ bundles.lsp ];
              }
              ''
                go version
                gopls version
                touch "$out"
              '';

          workstation-smoke =
            pkgs.runCommand "dotfiles-workstation-smoke"
              {
                nativeBuildInputs = [ bundles.workstation ];
              }
              ''
                fnm --version
                uv --version
                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
