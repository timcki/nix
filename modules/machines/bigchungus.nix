{ config, lib, pkgs, slurp, ... }:

{
  imports = [
    ./bigchungus-hardware.nix
    ../services/slurp.nix
    ../services/arr-stack.nix
  ];

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS configuration
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";

  # Cap ZFS ARC to 5 GiB — preserve RAM for EL/CL clients + media stack
  boot.kernelParams = [ "zfs.zfs_arc_max=5368709120" ];

  # Swap: 16 GiB swapfile on /data for memory safety under chain sync
  swapDevices = [{
    device = "/data/swapfile";
    size = 16384; # MiB
  }];
  boot.kernel.sysctl."vm.swappiness" = 10;

  # Docker for Rocket Pool Smartnode (locally managed mode)
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/data/docker";
      log-driver = "journald";
    };
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

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
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/tailscale/caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac" ];
        hash = "sha256-1BAY6oZ1qJCKlh0Y2KKqw87A45EUPVtwS2Su+LfXtCc=";
      };
      virtualHosts."http://0.0.0.0:8080" = {
        extraConfig = ''
          root * /var/www/tymek.me/public
          file_server
        '';
      };
      # Tailscale HTTPS reverse proxies for arr stack
      virtualHosts."bigchungus.tailb9dbd5.ts.net:9443" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy localhost:9696
        '';
      };
      virtualHosts."bigchungus.tailb9dbd5.ts.net:8443" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy localhost:7878
        '';
      };
      virtualHosts."bigchungus.tailb9dbd5.ts.net:8444" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy 10.200.0.2:8085
        '';
      };
      virtualHosts."bigchungus.tailb9dbd5.ts.net:8445" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy localhost:8096
        '';
      };
    };

    tailscale = {
      enable = true;
      permitCertUid = "caddy";
    };

    slurp = {
      enable = true;
      configFile = ../../config/slurp/slurp.toml;
    };
  };
  # Firewall: Rocket Pool EL/CL P2P ports (public)
  networking.firewall.allowedTCPPorts = [ 30303 9001 ];
  networking.firewall.allowedUDPPorts = [ 30303 9001 ];

  # Firewall: Tailscale-only ports (arr stack + Grafana)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 3100 9443 8443 8444 8445 ];

  system.stateVersion = "25.11";
}
