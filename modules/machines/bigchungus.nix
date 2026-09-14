{ config, lib, pkgs, slurp, ... }:

let
  # One definition for the nightly upgrade and for switchn. They used to be two:
  # switchn built ~/.config/nix while the upgrade built what was pushed, so a
  # `nix flake update` that never left the working copy was a deploy with a
  # twelve-hour life, and film night ran a fortnight-old commit while the lock
  # on disk insisted otherwise.
  configFlake = "git+https://tangled.org/tymek.me/nix";

  # Film night is deliberately not pinned here: it follows its own main. What
  # makes that safe is that its build runs its own acceptance suite and type
  # check (doCheck in its nix/package.nix), so a revision that fails either
  # produces no store path and cannot become the running system. A red main is
  # a deploy that does not happen, which this box then reports.
  deployFlags = [
    "--override-input"
    "filmnight"
    "git+https://knot1.tangled.sh/did:plc:l3eogiay43j3momps2d52bol"
  ];

  # a script rather than a shell alias, so there is nowhere for the two to drift
  switchn = pkgs.writeShellScriptBin "switchn" ''
    exec sudo nixos-rebuild switch --flake ${configFlake} \
      ${lib.escapeShellArgs deployFlags} --refresh "$@"
  '';

  switchnLocal = pkgs.writeShellScriptBin "switchn-local" ''
    echo "building the working copy, not ${configFlake}." >&2
    echo "04:30 builds what is pushed, so anything unpushed goes then." >&2
    exec sudo nixos-rebuild switch --flake "$HOME/.config/nix" \
      ${lib.escapeShellArgs deployFlags} "$@"
  '';

  linearCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "linear-cli";
    version = "2.6.0";
    src = pkgs.fetchurl {
      url = "https://github.com/schpet/linear-cli/releases/download/v2.6.0/linear-x86_64-unknown-linux-gnu.tar.xz";
      hash = "sha256-u8udNlMIvDcooeyZE60YgPiMDOaHZzgyl+NIwFfzW40=";
    };
    dontPatchELF = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 linear $out/libexec/linear
      mkdir -p $out/bin
      cat > $out/bin/linear <<EOF
      #!${pkgs.runtimeShell}
      export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
      export NIX_LD_LIBRARY_PATH=${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}
      exec $out/libexec/linear "\$@"
      EOF
      chmod 0755 $out/bin/linear
      runHook postInstall
    '';
    meta = {
      description = "CLI for Linear with Git and Jujutsu integration";
      homepage = "https://github.com/schpet/linear-cli";
      license = lib.licenses.mit;
      mainProgram = "linear";
      platforms = [ "x86_64-linux" ];
    };
  };

  ampRunnerPackages = with pkgs; [
    amp-cli
    bashInteractive
    corepack
    datadog-pup
    fd
    git
    gh
    gnumake
    google-cloud-sdk
    jq
    jujutsu
    linearCli
    nodejs_24
    openssh
    pkg-config
    pnpm
    python3
    railway
    ripgrep
    stdenv.cc
  ];

  ampStageServer = pkgs.writeShellApplication {
    name = "amp-stage-server";
    runtimeInputs = with pkgs; [ coreutils git jujutsu systemd util-linux ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "amp-stage-server: must run as root" >&2
        exit 1
      fi
      if [ "$#" -ne 2 ]; then
        echo "usage: amp-stage-server <name> <commit>" >&2
        exit 2
      fi

      name="$1"
      commit="$2"
      if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; then
        echo "amp-stage-server: invalid name" >&2
        exit 2
      fi
      if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
        echo "amp-stage-server: invalid commit" >&2
        exit 2
      fi

      bare=/home/amp/Sync/exchange-service-2.git
      source=/home/amp/Repos/tokentax/exchange-service-2
      workspace_id="$name-''${commit:0:12}"
      workspace_root="/home/amp/Workspaces/$workspace_id"
      workspace="$workspace_root/exchange-service-2"

      if ! runuser -u amp -- git --git-dir="$bare" cat-file -e "$commit^{commit}"; then
        echo "amp-stage-server: commit was not received by the sync repository" >&2
        exit 1
      fi

      if [ ! -e "$workspace/.jj" ]; then
        install -d -o amp -g amp -m 0700 "$workspace_root"
        runuser -u amp -- git -C "$source" fetch --no-write-fetch-head "$bare" \
          "refs/heads/snapshots/$commit:refs/heads/amp-stage/$commit"
        runuser -u amp -- jj -R "$source" --ignore-working-copy workspace add \
          --name "amp-$workspace_id" --revision "$commit" "$workspace"
        runuser -u amp -- ln -s /home/amp/Repos/tokentax/token-compose "$workspace_root/token-compose"
      fi

      systemctl start "amp-runner-exchange@$workspace_id.service"
      echo "runner: bigchungus-x-$workspace_id"
      echo "path:   $workspace"
      echo "next:   select that runner when creating the Amp thread"
    '';
  };

  # identifies a caddy.withPlugins build: the fixed-output hash covers caddy's
  # source, the plugin and the go toolchain, so both halves belong in the key.
  caddyPluginKey = "${pkgs.caddy.version}-go${pkgs.caddy.passthru.go.version}";
in
{
  imports = [
    ./bigchungus-hardware.nix
    ../services/slurp.nix
    ../services/arr-stack.nix
    ../services/samba.nix
    ../services/filmnight.nix
    ../services/unit-failure.nix
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
    flake = configFlake;
    # the module already passes --refresh and --flake itself; these are the
    # only flags, and switchn passes the same ones
    flags = deployFlags;
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
        # withPlugins hashes caddy's source, the plugin and the go toolchain
        # together, so it moves when nixpkgs bumps caddy *or* go: 2.11.4 alone
        # has two hashes. keyed by both so rolling the lock back still resolves;
        # for a new pair, add the "got:" hash from the build error.
        hash =
          {
            "2.11.3-go1.26.3" = "sha256-iUQXsmUJEdOpv6uXte73RXFOhxfzwb/r9vdCTVXjP4Y=";
            "2.11.4-go1.26.5" = "sha256-tP/ZQjZvfb+e3322dzd3I89Y9QwujcyqV1fbNWyw08g=";
            "2.11.4-go1.26.7" = "sha256-o0oG/9hROjDl69AeuxUhhFVTsdluHJ8VyENVk1KHCOI=";
          }
          .${caddyPluginKey}
            or (throw "caddy ${caddyPluginKey}: add its caddy.withPlugins hash");
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

    filmnight = {
      enable = true;
      demo.enable = true;
    };
  };
  # cli for site creation, exports and sqlite maintenance
  environment.systemPackages = [ pkgs.goatcounter ampStageServer switchn switchnLocal ];

  environment.etc."amp-runner/AGENTS.md".text = ''
    # bigchungus Amp runners

    This session runs as the isolated `amp` user on bigchungus.

    - The working directory is a dedicated jj workspace created by `amp-stage`.
    - The selected local revision and its complete ancestor stack retain their
      original commit and change IDs.
    - Run `corepack pnpm install --frozen-lockfile` when `node_modules` is absent.
      All workspaces share the amp user's pnpm content store.
    - `../token-compose` links to the persistent checkout containing
      `.env.compose`; `pnpm cli-sync` loads it automatically.
    - Do not edit another workspace under `/home/amp/Workspaces` or the legacy
      checkout under `/home/amp/Repos/tokentax/exchange-service-2`.
    - The runner and workspace persist across client disconnects and reboots.
  '';

  # isolate the remotely controlled runner from personal files and host
  # administration. project credentials live only in this user's home.
  users.groups.amp = { };
  users.users.amp = {
    isNormalUser = true;
    description = "Amp remote runner";
    home = "/home/amp";
    createHome = true;
    homeMode = "0700";
    group = "amp";
    shell = pkgs.bashInteractive;
    packages = ampRunnerPackages;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDI2dfsVzngdYLmJ3T0StS3eI3IzLMlAi7XOfqt1uVBe tim@macbook-pro"
    ];
  };

  systemd.services.amp-stage-init = {
    description = "Initialize Amp revision staging";
    wantedBy = [ "multi-user.target" ];
    before = [ "amp-runner-exchange.service" ];
    path = [ pkgs.coreutils pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      User = "amp";
      Group = "amp";
      UMask = "0077";
    };
    script = ''
      mkdir -p /home/amp/Sync /home/amp/Workspaces /home/amp/.config/amp
      if [ ! -d /home/amp/Sync/exchange-service-2.git ]; then
        git init --bare /home/amp/Sync/exchange-service-2.git
      fi
      ln -sfn /etc/amp-runner/AGENTS.md /home/amp/.config/amp/AGENTS.md
    '';
  };

  systemd.services.amp-stage-resume = {
    description = "Resume staged Amp runners";
    wantedBy = [ "multi-user.target" ];
    after = [ "amp-stage-init.service" ];
    requires = [ "amp-stage-init.service" ];
    path = [ pkgs.coreutils pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      for workspace in /home/amp/Workspaces/*/exchange-service-2/.jj; do
        if [ ! -e "$workspace" ]; then
          continue
        fi
        instance="$(basename "$(dirname "$(dirname "$workspace")")")"
        systemctl start "amp-runner-exchange@$instance.service"
      done
    '';
  };

  systemd.slices.amp-runners.sliceConfig = {
    CPUWeight = 20;
    IOWeight = 20;
    MemoryHigh = "8G";
    MemoryMax = "10G";
  };

  systemd.services.amp-runner-exchange = {
    description = "Amp runner for exchange-service-2";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathIsDirectory = "/home/amp/Repos/tokentax/exchange-service-2/.jj";
    path = ampRunnerPackages;
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
      AMP_SKIP_UPDATE_CHECK = "1";
    };
    serviceConfig = {
      User = "amp";
      Group = "amp";
      WorkingDirectory = "/home/amp/Repos/tokentax/exchange-service-2";
      ExecStart = "${pkgs.amp-cli}/bin/amp --no-tui --runner-id bigchungus-exchange --remote-control-terminal";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
      Nice = 10;
      CPUWeight = 20;
      IOWeight = 20;
      MemoryHigh = "6G";
      MemoryMax = "8G";
      OOMScoreAdjust = 500;
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectSystem = "full";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.services."amp-runner-exchange@" = {
    description = "Amp runner for staged exchange-service-2 revision %i";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "amp-stage-init.service" ];
    unitConfig.ConditionPathIsDirectory = "/home/amp/Workspaces/%i/exchange-service-2/.jj";
    path = ampRunnerPackages;
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
      AMP_SKIP_UPDATE_CHECK = "1";
    };
    serviceConfig = {
      User = "amp";
      Group = "amp";
      WorkingDirectory = "/home/amp/Workspaces/%i/exchange-service-2";
      ExecStart = "${pkgs.amp-cli}/bin/amp --no-tui --runner-id bigchungus-x-%i --remote-control-terminal";
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
      Nice = 10;
      CPUWeight = 20;
      IOWeight = 20;
      MemoryHigh = "6G";
      MemoryMax = "8G";
      OOMScoreAdjust = 500;
      Slice = "amp-runners.slice";
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectSystem = "full";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  };

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

  # Firewall: Tailscale-only ports (arr stack + Grafana + film night and its
  # public demo, which chungus-1 reverse proxies for film.tymek.me and
  # demo.film.tymek.me, + goatcounter on 8447)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 3010 3011 3100 9443 8443 8444 8445 8446 8447 ];

  system.stateVersion = "25.11";
}
