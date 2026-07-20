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
      assertion = toolOwnership.migrationPhase == 2;
      message = "The active Home Manager module requires migration phase 2 ownership data";
    }
    {
      assertion = activeOwnership.writableConfigs == [ ];
      message = "Phase 2 Home Manager must not claim writable configuration files";
    }
    {
      assertion = config.home.file == { };
      message = "Phase 2 Home Manager must not generate files in the home directory";
    }
    {
      assertion = lib.attrByPath [ "xdg" "configFile" ] { } config == { };
      message = "Phase 2 Home Manager must not generate XDG configuration files";
    }
    {
      assertion = configurationName != "" && profileName != "";
      message = "Every Home Manager output must declare its configuration and profile names";
    }
  ];

  home.stateVersion = "26.05";

  # Home Manager 26.05 otherwise creates .cache/.keep and
  # .local/state/.keep through its XDG module even when no file module is used.
  # Force the merged file set empty so chezmoi remains the sole file owner.
  home.file = lib.mkForce { };

  manual.manpages.enable = false;
  news.display = "silent";
  programs.man.enable = false;
  systemd.user.enable = false;
  xdg.mime.enable = false;
}
