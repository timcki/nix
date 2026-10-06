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
    slurp = {
      # Public read over https, so root needs no key to evaluate this.
      url = "git+https://knot1.tangled.sh/did:plc:lvc6qlu5xd6poflokxox6pxv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tobi = {
      url = "git+https://tangled.org/ptr.pet/tobi";
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
    mkNixosSystem = { system ? "x86_64-linux", machineModule }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; inherit (inputs) slurp filmnight tobi; };
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