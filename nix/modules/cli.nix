{ toolOwnership, ... }:
let
  activeOwnership = toolOwnership.active.homeManager;
in
{
  assertions = [
    {
      assertion = activeOwnership.packages == [ ] && activeOwnership.commands == [ ];
      message = "Phase 1 Home Manager must not claim migrated CLI packages or commands";
    }
  ];
}
