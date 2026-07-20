{
  description = "Standalone Home Manager configurations for the dotfiles repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      home-manager,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs supportedSystems;
      toolOwnership = builtins.fromJSON (builtins.readFile ./data/tool-ownership.json);
      maxHost = import ./hosts/max.nix;
      ciHost = import ./hosts/ci.nix;
      mkHome = import ./lib/mk-home.nix {
        inherit home-manager nixpkgs toolOwnership;
      };

      homeConfigurations = {
        "max@linux-desktop" = mkHome {
          configurationName = "max@linux-desktop";
          system = "x86_64-linux";
          host = maxHost;
          profile = ./profiles/linux-desktop.nix;
          profileName = "linux-desktop";
        };
        "max@linux-headless" = mkHome {
          configurationName = "max@linux-headless";
          system = "x86_64-linux";
          host = maxHost;
          profile = ./profiles/linux-headless.nix;
          profileName = "linux-headless";
        };
        "max@wsl" = mkHome {
          configurationName = "max@wsl";
          system = "x86_64-linux";
          host = maxHost;
          profile = ./profiles/wsl.nix;
          profileName = "wsl";
        };
        "max@macos-aarch64" = mkHome {
          configurationName = "max@macos-aarch64";
          system = "aarch64-darwin";
          host = maxHost;
          profile = ./profiles/macos.nix;
          profileName = "macos";
        };
        "max@macos-x86_64" = mkHome {
          configurationName = "max@macos-x86_64";
          system = "x86_64-darwin";
          host = maxHost;
          profile = ./profiles/macos.nix;
          profileName = "macos";
        };
        "ci@linux-desktop" = mkHome {
          configurationName = "ci@linux-desktop";
          system = "x86_64-linux";
          host = ciHost;
          profile = ./profiles/linux-desktop.nix;
          profileName = "linux-desktop";
        };
        "ci@linux-headless" = mkHome {
          configurationName = "ci@linux-headless";
          system = "x86_64-linux";
          host = ciHost;
          profile = ./profiles/linux-headless.nix;
          profileName = "linux-headless";
        };
        "ci@wsl" = mkHome {
          configurationName = "ci@wsl";
          system = "x86_64-linux";
          host = ciHost;
          profile = ./profiles/wsl.nix;
          profileName = "wsl";
        };
        "ci@macos-aarch64" = mkHome {
          configurationName = "ci@macos-aarch64";
          system = "aarch64-darwin";
          host = ciHost;
          profile = ./profiles/macos.nix;
          profileName = "macos";
        };
        "ci@macos-x86_64" = mkHome {
          configurationName = "ci@macos-x86_64";
          system = "x86_64-darwin";
          host = ciHost;
          profile = ./profiles/macos.nix;
          profileName = "macos";
        };
      };

      nativeConfigurationNames = {
        x86_64-linux = [
          "max@linux-desktop"
          "max@linux-headless"
          "max@wsl"
          "ci@linux-desktop"
          "ci@linux-headless"
          "ci@wsl"
        ];
        aarch64-linux = [ ];
        x86_64-darwin = [
          "max@macos-x86_64"
          "ci@macos-x86_64"
        ];
        aarch64-darwin = [
          "max@macos-aarch64"
          "ci@macos-aarch64"
        ];
      };

      mkOwnershipPolicyCheck =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          active = toolOwnership.active.homeManager;
          target = toolOwnership.target.homeManager;
        in
        assert toolOwnership.migrationPhase == 3;
        assert lib.subtractLists target.packages active.packages == [ ];
        assert lib.subtractLists target.commands active.commands == [ ];
        assert active.writableConfigs == [ ];
        assert active.services == [ ];
        pkgs.runCommand "home-manager-ownership-policy" { } ''
          touch "$out"
        '';
    in
    {
      inherit homeConfigurations;

      packages = forAllSystems (system: {
        default = home-manager.packages.${system}.default;
        home-manager = home-manager.packages.${system}.default;
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      checks = forAllSystems (
        system:
        lib.genAttrs nativeConfigurationNames.${system} (name: homeConfigurations.${name}.activationPackage)
        // {
          ownership-policy = mkOwnershipPolicyCheck system;
        }
      );
    };
}
