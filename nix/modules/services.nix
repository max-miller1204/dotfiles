{
  config,
  lib,
  toolOwnership,
  ...
}:
{
  assertions = [
    {
      assertion = toolOwnership.active.homeManager.services == [ ];
      message = "Phase 4 Home Manager must not claim user services";
    }
    {
      assertion =
        lib.attrByPath [ "systemd" "user" "services" ] { } config == { }
        && lib.attrByPath [ "launchd" "agents" ] { } config == { };
      message = "Phase 4 Home Manager must not define user services";
    }
  ];
}
