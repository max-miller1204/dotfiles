{
  home-manager,
  nixpkgs,
  toolOwnership,
}:
{
  configurationName,
  host,
  profile,
  profileName,
  system,
}:
let
  platform = if nixpkgs.lib.hasSuffix "-darwin" system then "darwin" else "linux";
  identity = host.${platform};
in
home-manager.lib.homeManagerConfiguration {
  pkgs = import nixpkgs { inherit system; };

  extraSpecialArgs = {
    inherit configurationName profileName toolOwnership;
  };

  modules = [
    ../modules/base.nix
    profile
    {
      home.username = identity.username;
      home.homeDirectory = identity.homeDirectory;
    }
  ];
}
