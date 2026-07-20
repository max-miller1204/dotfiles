{ pkgs, ... }:
{
  imports = [ ./common.nix ];

  assertions = [
    {
      assertion = pkgs.stdenv.isDarwin;
      message = "The macOS Home Manager profile must use a Darwin package set";
    }
  ];
}
