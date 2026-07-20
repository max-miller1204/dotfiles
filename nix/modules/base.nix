{
  config,
  configurationName,
  lib,
  profileName,
  toolOwnership,
  ...
}:
let
  activeOwnership = toolOwnership.active.homeManager;
in
{
  assertions = [
    {
      assertion = toolOwnership.schemaVersion == 1;
      message = "Unsupported tool ownership schema version";
    }
    {
      assertion = toolOwnership.migrationPhase == 1;
      message = "The inactive Home Manager module requires migration phase 1 ownership data";
    }
    {
      assertion = activeOwnership.writableConfigs == [ ];
      message = "Phase 1 Home Manager must not claim writable configuration files";
    }
    {
      assertion = lib.attrByPath [ "xdg" "configFile" ] { } config == { };
      message = "Phase 1 Home Manager must not generate XDG configuration files";
    }
    {
      assertion = configurationName != "" && profileName != "";
      message = "Every Home Manager output must declare its configuration and profile names";
    }
  ];

  home.stateVersion = "26.05";
  home.packages = [ ];

  manual.manpages.enable = false;
  news.display = "silent";
  programs.man.enable = false;
  systemd.user.enable = false;
  xdg.mime.enable = false;
}
