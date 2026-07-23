{ pkgs, packageGroups }:
let
  mkBundle =
    name: packageList:
    pkgs.buildEnv {
      name = "dotfiles-${name}";
      paths = packageList;
      pathsToLink = [
        "/bin"
        "/share"
      ];
      ignoreCollisions = false;
    };

  corePackages = packageGroups.core;
  headlessPackages = corePackages ++ packageGroups.headless;
  lspPackages = headlessPackages ++ packageGroups.lsp;
  workstationPackages = lspPackages ++ packageGroups.workstation;

  workstation = mkBundle "workstation" workstationPackages;
in
{
  core = mkBundle "core" corePackages;
  headless = mkBundle "headless" headlessPackages;
  lsp = mkBundle "lsp" lspPackages;
  inherit workstation;
  default = workstation;
}
