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
  packageClaims = lib.sort builtins.lessThan config.dotfiles.homeManager.packageClaims;
  commandClaims = lib.sort builtins.lessThan config.dotfiles.homeManager.commandClaims;
in
{
  options.dotfiles.homeManager = {
    packageClaims = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
    };
    commandClaims = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
    };
  };

  config = {
    assertions = [
      {
        assertion = toolOwnership.schemaVersion == 1;
        message = "Unsupported tool ownership schema version";
      }
      {
        assertion = toolOwnership.migrationPhase == 3;
        message = "The active Home Manager modules require migration phase 3 ownership data";
      }
      {
        assertion = packageClaims == activeOwnership.packages;
        message = "Home Manager package claims must exactly match active ownership data";
      }
      {
        assertion = commandClaims == activeOwnership.commands;
        message = "Home Manager command claims must exactly match active ownership data";
      }
      {
        assertion = activeOwnership.writableConfigs == [ ];
        message = "Phase 3 Home Manager must not claim writable configuration files";
      }
      {
        assertion = config.home.file == { };
        message = "Phase 3 Home Manager must not generate files in the home directory";
      }
      {
        assertion = lib.attrByPath [ "xdg" "configFile" ] { } config == { };
        message = "Phase 3 Home Manager must not generate XDG configuration files";
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
  };
}
