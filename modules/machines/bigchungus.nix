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

  # Swap: zram only — no disk swap to avoid I/O contention with reth sync
  # and ZFS zvol deadlocks under memory pressure
  swapDevices = lib.mkForce [];
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
    priority = 100;
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    # Auto-reboot on kernel hangs (critical for headless/remote box)
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "kernel.hung_task_panic" = 1;
    "kernel.hung_task_timeout_secs" = 300;
    "kernel.softlockup_panic" = 1;
  };

  # Hardware watchdog: SP5100 TCO — force reboot if kernel/systemd hangs
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "2min";
    WatchdogDevice = "/dev/watchdog0";
  };

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
        # No tagged releases; pinned to latest main (bb080c4, 2026-01-06).
        # Hash must be updated when nixpkgs bumps Caddy/Go — use the hash from the build error.
        plugins = [ "github.com/tailscale/caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac" ];
        hash = "sha256-9CYQSdGAQwd1cmFuKT2RNzeiJ4DZoyrxvsLS4JDCFCY=";
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
      virtualHosts."bigchungus.tailb9dbd5.ts.net:8446" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy localhost:8787
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
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 3100 9443 8443 8444 8445 8446 ];

  system.stateVersion = "25.11";
}
