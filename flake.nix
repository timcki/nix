{
  description = "tim's system config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      # Track master to stay compatible with nixpkgs-unstable.
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    filmnight = {
      # Public read over https, so root needs no key to evaluate this.
      url = "git+https://knot1.tangled.sh/did:plc:l3eogiay43j3momps2d52bol";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }:
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
    # slurp is fetched locally on the NixOS server where the repo exists,
    # rather than as a flake input, so macOS machines don't need it.
    slurp = builtins.getFlake "git+file:///home/tim/slurp";

    mkNixosSystem = { system ? "x86_64-linux", machineModule }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit slurp; inherit (inputs) filmnight; };
        modules = [
          ./modules/nixos.nix
          inputs.agenix.nixosModules.default
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