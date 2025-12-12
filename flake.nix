{
  description = "tim's system config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  let
    # Helper function to create a darwin system configuration
    mkDarwinSystem = { system ? "aarch64-darwin", machineModule }:
      nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          ./modules/darwin.nix
          machineModule
          home-manager.darwinModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.verbose = false;
            home-manager.backupFileExtension = "bak";
            home-manager.users.tim = ./modules/home.nix;
          }
        ];
      };

    # Helper function to create a nixos system configuration
    mkNixosSystem = { system ? "x86_64-linux", machineModule }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/nixos.nix
          machineModule
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.verbose = false;
            home-manager.backupFileExtension = "bak";
            home-manager.users.tim = ./modules/home.nix;
          }
        ];
      };
  in {
    darwinConfigurations = {
      bigboi = mkDarwinSystem {
        machineModule = ./modules/machines/bigboi.nix;
      };

      small = mkDarwinSystem {
        machineModule = ./modules/machines/small.nix;
      };
    };

    nixosConfigurations = {
      bigchungus = mkNixosSystem {
        machineModule = ./modules/machines/bigchungus.nix;
      };
    };
  };
}