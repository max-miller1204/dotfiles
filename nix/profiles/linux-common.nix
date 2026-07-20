{ pkgs, ... }:
{
  imports = [ ./common.nix ];

  assertions = [
    {
      assertion = pkgs.stdenv.isLinux;
      message = "A Linux Home Manager profile must use a Linux package set";
    }
  ];
}
