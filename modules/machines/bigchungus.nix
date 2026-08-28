{ config, lib, pkgs, slurp, ... }:

{
  imports = [
    ./bigchungus-hardware.nix
    ../services/slurp.nix
    ../services/arr-stack.nix
    ../services/samba.nix
    ../services/filmnight.nix
  ];

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS configuration
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";
  # Preserve the previous NixOS default for this single-host root pool.
  # This avoids surprises after hard resets on the headless box while making
  # the choice explicit for newer nixpkgs.
  boot.zfs.forceImportRoot = true;

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
    # Disable readahead for zram swap — compressed pages have no locality
    "vm.page-cluster" = 0;
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

  # follow the nix config repo on tangled so this box converges on its own;
  # push to main and it picks the change up here at night (or run switchn).
  # public read over https, so root needs no key; tangled.org redirects to
  # the knot url, which git follows
  system.autoUpgrade = {
    enable = true;
    flake = "git+https://tangled.org/tymek.me/nix";
    # impure: slurp is an unlocked local flake resolved via builtins.getFlake
    flags = [ "--impure" "--refresh" ];
    dates = "04:30";
    randomizedDelaySec = "10min";
    # never reboot on its own; this box runs a staking node
    allowReboot = false;
  };

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
        plugins = [ "github.com/tailscale/caddy-tailscale@v0.0.0-20260106222316-bb080c4414ac" ];
        # withPlugins hashes caddy's own source together with the plugin, so the
        # value changes on every caddy bump, and changes back when the lock
        # rolls back. keyed by version so moving between known ones just works;
        # for a new caddy, add the "got:" hash from the build error.
        hash =
          {
            "2.11.3" = "sha256-iUQXsmUJEdOpv6uXte73RXFOhxfzwb/r9vdCTVXjP4Y=";
            "2.11.4" = "sha256-tP/ZQjZvfb+e3322dzd3I89Y9QwujcyqV1fbNWyw08g=";
          }
          .${pkgs.caddy.version}
            or (throw "caddy ${pkgs.caddy.version}: add its caddy.withPlugins hash");
      };
      # chungus-1 fronts tymek.me over tailscale; trusting it makes {client_ip}
      # the real visitor instead of the proxy, which analytics needs
      globalConfig = ''
        servers {
          trusted_proxies static 100.113.99.69/32
        }
      '';
      virtualHosts."http://:8080" = {
        extraConfig = ''
          # first-party analytics beacon (/count and /count.js). goatcounter
          # picks the site by Host, and the site is registered under the
          # tailnet name where its dashboard lives, so rewrite Host here
          handle /count* {
            reverse_proxy 127.0.0.1:8081 {
              header_up Host bigchungus.tailb9dbd5.ts.net
              header_up X-Real-Ip {client_ip}
              header_up X-Forwarded-Proto https
            }
          }
          handle {
            root * /var/www/tymek.me/public
            file_server
          }
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
      # goatcounter dashboard, tailnet only; the public site only ever reaches
      # /count* through the :8080 vhost above
      virtualHosts."bigchungus.tailb9dbd5.ts.net:8447" = {
        extraConfig = ''
          tls {
            get_certificate tailscale
          }
          reverse_proxy localhost:8081
        '';
      };
    };

    goatcounter = {
      enable = true;
      address = "127.0.0.1";
      port = 8081;
      extraArgs = [
        "-automigrate"
        "-db"
        "sqlite+/var/lib/goatcounter/db.sqlite3"
        # so dashboard links and the websocket carry the non-standard port
        "-public-port"
        "8447"
      ];
    };

    tailscale = {
      enable = true;
      permitCertUid = "caddy";
    };

    slurp = {
      enable = true;
      configFile = ../../config/slurp/slurp.toml;
    };

    filmnight.enable = true;
  };
  # cli for site creation, exports and sqlite maintenance
  environment.systemPackages = [ pkgs.goatcounter ];

  # The goatcounter module runs under DynamicUser, which makes the one-off
  # "goatcounter db create site" runs awkward; a fixed user keeps
  # /var/lib/goatcounter reachable for site creation and sqlite backups
  users.users.goatcounter = {
    isSystemUser = true;
    group = "goatcounter";
  };
  users.groups.goatcounter = { };
  systemd.services.goatcounter.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "goatcounter";
    Group = "goatcounter";
  };

  # Firewall: Rocket Pool EL/CL P2P ports (public)
  networking.firewall.allowedTCPPorts = [ 30303 9001 ];
  networking.firewall.allowedUDPPorts = [ 30303 9001 ];

  # Firewall: Tailscale-only ports (arr stack + Grafana + film night, which
  # chungus-1 reverse proxies for film.tymek.me, + goatcounter on 8447)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 3010 3100 9443 8443 8444 8445 8446 8447 ];

  system.stateVersion = "25.11";
}
