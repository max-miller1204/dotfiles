{ pkgs, ... }:
let
  ownedPackages = [
    "clang-tools"
    "gopls"
    "pyright"
    "rust-analyzer"
    "typescript"
    "typescript-language-server"
  ];
  ownedCommands = [
    "clangd"
    "gopls"
    "pyright"
    "pyright-langserver"
    "rust-analyzer"
    "tsc"
    "tsserver"
    "typescript-language-server"
  ];
  # clang-tools contains many unrelated global commands. Expose only clangd so
  # Home Manager does not silently take ownership of clang-format, clang-tidy,
  # and the rest of the LLVM tooling bundle.
  clangdOnly = pkgs.runCommand "clangd-${pkgs.clang-tools.version}" { } ''
    mkdir -p "$out/bin"
    ln -s "${pkgs.clang-tools}/bin/clangd" "$out/bin/clangd"
  '';
  packageByName = {
    "clang-tools" = clangdOnly;
    inherit (pkgs)
      gopls
      pyright
      rust-analyzer
      typescript
      typescript-language-server
      ;
  };
in
{
  dotfiles.homeManager.packageClaims = ownedPackages;
  dotfiles.homeManager.commandClaims = ownedCommands;

  home.packages = map (name: packageByName.${name}) ownedPackages;
}
