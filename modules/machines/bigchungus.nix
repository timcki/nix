{ config, lib, pkgs, slurp, ... }:

{
  imports = [
    ./bigchungus-hardware.nix
    ../services/slurp.nix
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

    caddy = {
      enable = true;
      virtualHosts."http://0.0.0.0:8080" = {
        extraConfig = ''
          root * /var/www/tymek.me/public
          file_server
        '';
      };
    };

    tailscale.enable = true;

    slurp = {
      enable = true;
      configFile = ../../config/slurp/slurp.toml;
    };
  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 ];

  system.stateVersion = "25.11";
}
