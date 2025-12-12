{ config, lib, pkgs, ... }:

{
  imports = [
    ./bigchungus-hardware.nix
  ];

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS configuration
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  # Networking
  networking.hostName = "bigchungus";
  networking.hostId = "5914a708"; # required for ZFS
  networking.networkmanager.enable = true;

  # Time zone
  time.timeZone = "Europe/Amsterdam";

  # Services
  services = {
    # ZFS maintenance
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    tailscale.enable = true;
  };

  system.stateVersion = "25.11";
}
