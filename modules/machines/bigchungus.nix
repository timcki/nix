{ config, lib, pkgs, slurp, tobi, ... }:

let
  # One definition for the nightly upgrade and for switchn. They used to be two:
  # switchn built ~/.config/nix while the upgrade built what was pushed, so a
  # `nix flake update` that never left the working copy was a deploy with a
  # twelve-hour life, and film night ran a fortnight-old commit while the lock
  # on disk insisted otherwise.
  configFlake = "git+https://knot1.tangled.sh/did:plc:vhk4g55hbzwg6eha6r42wacw";

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
    bashInteractive
    clang
    cmake
    corepack
    curl
    datadog-pup
    fd
    git
    gh
    gnumake
    google-cloud-sdk
    jq
    jujutsu
    linearCli
    mise
    minisign
    ninja
    openssh
    pipx
    pkg-config
    python3
    railway
    ripgrep
    rsync
    shellcheck
    stdenv.cc
    unzip
    uv
    xz
  ];

  ampRunnerPath = lib.makeBinPath ampRunnerPackages;

  tobiPackage = tobi.packages.${pkgs.stdenv.hostPlatform.system}.default;

  ampClaude = lib.recursiveUpdate {
    after = [ "network-online.target" "amp-mise-sync.service" "amp-runner-init.service" ];
    wants = [ "network-online.target" "amp-mise-sync.service" ];
    requires = [ "amp-runner-init.service" ];
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
      XDG_RUNTIME_DIR = "/run/user/1001";
      DOCKER_HOST = "unix:///run/user/1001/docker.sock";
      PATH = lib.mkForce "/home/amp/.local/share/mise/shims:/home/amp/.local/bin:${ampRunnerPath}";
    };
    serviceConfig = {
      User = "amp";
      Group = "amp";
      Slice = "amp-claude.slice";
      Restart = "always";
      RestartSec = "30s";
      UMask = "0077";
      Nice = 10;
      CPUWeight = 20;
      IOWeight = 20;
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

  # marks directories as trusted in ~/.claude.json, so remote-control starts
  # without a terminal to answer the prompt. trust in Repos doesn't carry into
  # git repos below it. takes claude's own proper-lockfile lock (a directory
  # whose mtime a live holder keeps fresh) so neither side loses a write.
  ampClaudeTrust = pkgs.writeShellApplication {
    name = "amp-claude-trust";
    runtimeInputs = with pkgs; [ coreutils jq ];
    text = ''
      config=/home/amp/.claude.json
      lock="$config.lock"
      trusted="reduce \$ARGS.positional[] as \$d (.; .projects[\$d].hasTrustDialogAccepted = true)"

      if [ -s "$config" ] && jq -e --args "($trusted) == ." "$@" < "$config" > /dev/null; then
        exit 0
      fi

      held=
      for _ in $(seq 50); do
        if mkdir "$lock" 2> /dev/null; then
          held=1
          break
        fi
        mtime="$(stat -c %Y "$lock" 2> /dev/null)" || continue
        if [ $(($(date +%s) - mtime)) -gt 60 ]; then
          rmdir "$lock" 2> /dev/null || true
          continue
        fi
        sleep 0.2
      done
      if [ -z "$held" ]; then
        echo "amp-claude-trust: $lock still held, leaving $config alone" >&2
        exit 1
      fi
      trap 'rmdir "$lock"' EXIT

      [ -s "$config" ] || echo '{}' > "$config"
      jq --args "$trusted" "$@" < "$config" > "$config.tmp"
      mv "$config.tmp" "$config"
    '';
  };

  # mise's shim execs the current claude-code, so the service's main process is claude itself
  ampClaudeBin = "/home/amp/.local/share/mise/shims/claude";

  ampStageServer = pkgs.writeShellApplication {
    name = "amp-stage-server";
    runtimeInputs = with pkgs; [ coreutils git jujutsu systemd util-linux ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "amp-stage-server: must run as root" >&2
        exit 1
      fi

      validate_repo() {
        local namespace="$1"
        local repo="$2"
        if ! [[ "$namespace" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] ||
           ! [[ "$repo" =~ ^[A-Za-z0-9._-]+$ ]] ||
           [[ "/$namespace/" == *"/./"* ]] ||
           [[ "/$namespace/" == *"/../"* ]] ||
           [ "$repo" = . ] || [ "$repo" = .. ]; then
          echo "amp-stage-server: invalid repository path" >&2
          exit 2
        fi
      }

      case "''${1:-}" in
        prepare)
          if [ "$#" -ne 3 ]; then
            echo "usage: amp-stage-server prepare <namespace> <repo>" >&2
            exit 2
          fi
          namespace="$2"
          repo="$3"
          validate_repo "$namespace" "$repo"
          bare="/home/amp/Sync/$namespace/$repo.git"
          install -d -o amp -g amp -m 0700 "$(dirname "$bare")"
          if [ ! -d "$bare" ]; then
            runuser -u amp -- git init --bare "$bare"
          fi
          ;;
        create)
          if [ "$#" -ne 5 ]; then
            echo "usage: amp-stage-server create <name> <commit> <namespace> <repo>" >&2
            exit 2
          fi
          name="$2"
          commit="$3"
          namespace="$4"
          repo="$5"
          validate_repo "$namespace" "$repo"
          if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; then
            echo "amp-stage-server: invalid name" >&2
            exit 2
          fi
          if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
            echo "amp-stage-server: invalid commit" >&2
            exit 2
          fi

          bare="/home/amp/Sync/$namespace/$repo.git"
          source="/home/amp/Sources/$namespace/$repo"
          namespace_slug="''${namespace//\//-}"
          workspace_id="$namespace_slug-$repo-$name-''${commit:0:12}"
          workspace_root="/home/amp/Workspaces/$workspace_id"
          workspace="$workspace_root/$repo"

          if ! runuser -u amp -- git --git-dir="$bare" cat-file -e "$commit^{commit}"; then
            echo "amp-stage-server: commit was not received by the sync repository" >&2
            exit 1
          fi

          if [ ! -d "$source/.jj" ]; then
            install -d -o amp -g amp -m 0700 "$(dirname "$source")"
            runuser -u amp -- git clone --no-checkout "$bare" "$source"
            runuser -u amp -- jj git init --colocate "$source"
          fi

          if [ ! -e "$workspace/.jj" ]; then
            install -d -o amp -g amp -m 0700 "$workspace_root"
            runuser -u amp -- git -C "$source" fetch --no-write-fetch-head "$bare" \
              "refs/heads/snapshots/$commit:refs/heads/amp-stage/$commit"
            # colocated so git-aware tools work in the workspace; orphan worktrees skip the post-checkout hook
            runuser -u amp -- jj -R "$source" workspace add --colocate \
              --name "amp-$workspace_id" --revision "$commit" "$workspace"
          fi
          if [ "''${namespace,,}" = tokentax ]; then
            runuser -u amp -- ln -sfn /home/amp/Repos/tokentax/token-compose \
              "$workspace_root/token-compose"
          fi

          echo "runner: bigchungus"
          echo "path:   $workspace"
          echo "next:   select this path under the bigchungus runner"
          ;;
        *)
          echo "usage: amp-stage-server <prepare|create> ..." >&2
          exit 2
          ;;
      esac
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
    ../services/things-cloud-mcp.nix
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
    rootless = {
      enable = true;
      setSocketVariable = false;
      extraPackages = with pkgs; [ fuse-overlayfs slirp4netns ];
      daemon.settings = {
        data-root = "/home/amp/.local/share/docker";
        storage-driver = "fuse-overlayfs";
      };
    };
  };

  # the rootless Docker user unit is installed system-wide, but only the amp
  # user should run it; tim continues to administer the host Docker daemon.
  systemd.user.services.docker = {
    unitConfig.ConditionUser = lib.mkForce "amp";
    serviceConfig = {
      CPUWeight = 20;
      IOWeight = 20;
      MemoryHigh = "4G";
      MemoryMax = "6G";
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
            "2.11.7-go1.26.8" = "sha256-3Dzgarb1nhPEA8Bxfxk7L3cn4OsIIWshYUosWf3fhqM=";
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

    things-cloud-mcp.enable = true;
  };
  # cli for site creation, exports and sqlite maintenance
  environment.systemPackages = [ pkgs.goatcounter ampStageServer switchn switchnLocal ];

  environment.etc."amp-runner/AGENTS.md".text = ''
    # bigchungus Amp runner

    This session runs as the isolated `amp` user on bigchungus.

    - Persistent repositories live under `/home/amp/Repos` and revisions sent
      by `amp-stage` live under `/home/amp/Workspaces`.
    - Clone with an SSH URL using `jj git clone`, never an HTTPS URL. Use jj,
      not Git, for version control. If a clone has no `.jj` directory, run
      `jj git init --colocate` in it before making changes.
    - Use the mise-managed toolchain. pnpm comes from each repository's
      `packageManager` through Corepack.
    - Every TokenTax checkout has `token-compose` as a sibling. Its mode-0600
      `.env.compose` is the shared source used by `pnpm cli-sync`.
    - Docker uses the amp user's rootless daemon, never the host daemon that
      runs system services.
    - Do not edit another checkout or workspace unless the user asks.
    - Repositories and workspaces persist across disconnects and reboots.
  '';

  environment.etc."amp-runner/tangled-known-hosts".text = ''
    tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2UShEm/FFPmYZUizaPnIqOJuynoCQpcLhl5PPHd02n
  '';

  environment.etc."amp-runner/git-template/hooks/post-checkout" = {
    mode = "0755";
    text = ''
      #!${pkgs.runtimeShell}
      set -eu

      worktree="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null)" || exit 0
      [ -d "$worktree/.jj" ] || ${pkgs.jujutsu}/bin/jj git init --colocate "$worktree"
    '';
  };

  # isolate the remotely controlled runner from personal files and host
  # administration. project credentials live only in this user's home.
  users.groups.amp = { };
  users.users.amp = {
    isNormalUser = true;
    description = "Amp remote runner";
    uid = 1001;
    home = "/home/amp";
    createHome = true;
    homeMode = "0700";
    group = "amp";
    shell = pkgs.bashInteractive;
    linger = true;
    packages = ampRunnerPackages ++ [ tobiPackage ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDI2dfsVzngdYLmJ3T0StS3eI3IzLMlAi7XOfqt1uVBe tim@macbook-pro"
    ];
  };

  systemd.services.amp-runner-init = {
    description = "Initialize the Amp runner home";
    wantedBy = [ "multi-user.target" ];
    before = [ "amp-bootstrap.service" "amp-claude.service" "amp-mise-sync.service" "amp-runner.service" ];
    path = with pkgs; [ coreutils findutils gh git gnugrep jq jujutsu ];
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "amp";
      Group = "amp";
      UMask = "0077";
    };
    script = ''
      mkdir -p \
        /home/amp/Repos \
        /home/amp/Sources \
        /home/amp/Sync \
        /home/amp/Workspaces \
        /home/amp/.config/amp \
        /home/amp/.config/mise
      ln -sfn /etc/amp-runner/AGENTS.md /home/amp/.config/amp/AGENTS.md

      # match the runner's PATH in ssh sessions; the amp installer owns the rest of .bashrc
      shims='export PATH="$HOME/.local/share/mise/shims:$PATH"'
      grep -qxF "$shims" /home/amp/.bashrc 2>/dev/null || echo "$shims" >> /home/amp/.bashrc
      [ -e /home/amp/.bash_profile ] || echo '. ~/.bashrc' > /home/amp/.bash_profile

      ${ampClaudeTrust}/bin/amp-claude-trust /home/amp/Repos

      git config --global init.templateDir /etc/amp-runner/git-template
      git config --global url."git@github.com:".insteadOf https://github.com/
      git config --global url."git@gitlab.com:".insteadOf https://gitlab.com/
      git config --global url."git@bitbucket.org:".insteadOf https://bitbucket.org/
      git config --global url."git@codeberg.org:".insteadOf https://codeberg.org/
      git config --global url."git@tangled.org:".insteadOf https://tangled.org/
      gh config set git_protocol ssh --host github.com

      while IFS= read -r -d "" git_dir; do
        repo="$(dirname "$git_dir")"
        if [ ! -d "$repo/.jj" ]; then
          jj git init --colocate "$repo"
        fi
      done < <(find /home/amp/Repos -name .git -prune -print0)
    '';
  };

  systemd.services.amp-bootstrap = {
    description = "Install the self-updating Amp CLI";
    after = [ "network-online.target" "amp-runner-init.service" ];
    wants = [ "network-online.target" ];
    requires = [ "amp-runner-init.service" ];
    unitConfig.ConditionPathExists = "!/home/amp/.amp/bin/amp";
    path = [ pkgs.bash pkgs.coreutils pkgs.curl pkgs.gzip pkgs.minisign ];
    environment = {
      HOME = "/home/amp";
      AMP_HOME = "/home/amp/.amp";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "amp";
      Group = "amp";
      UMask = "0077";
    };
    script = ''
      installer="$(mktemp)"
      trap 'rm -f "$installer"' EXIT
      curl -fsSL https://ampcode.com/install.sh -o "$installer"
      bash "$installer"
    '';
  };

  systemd.services.amp-mise-sync = {
    description = "Sync and install the Amp runner toolchain";
    after = [ "network-online.target" "amp-runner-init.service" ];
    wants = [ "network-online.target" ];
    requires = [ "amp-runner-init.service" ];
    path = ampRunnerPackages;
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
      GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o UserKnownHostsFile=/etc/amp-runner/tangled-known-hosts";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "amp";
      Group = "amp";
      UMask = "0077";
    };
    script = ''
      source=/home/amp/.local/share/chezmoi
      if [ ! -d "$source/.git" ]; then
        git clone git@tangled.org:did:plc:276qn75nkn4upl3oapzf6utp "$source"
      else
        git -C "$source" pull --ff-only
      fi
      install -Dm644 "$source/dot_config/mise/config.toml" \
        /home/amp/.config/mise/config.toml
      mise install --yes
      mise upgrade --yes
    '';
  };

  systemd.timers.amp-mise-sync = {
    description = "Periodically sync the Amp runner toolchain";
    wantedBy = [ "multi-user.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  systemd.services.amp-runner = {
    description = "General Amp runner";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "amp-bootstrap.service"
      "amp-mise-sync.service"
      "amp-runner-init.service"
    ];
    wants = [ "network-online.target" "amp-mise-sync.service" ];
    requires = [ "amp-bootstrap.service" "amp-runner-init.service" ];
    environment = {
      HOME = "/home/amp";
      XDG_CONFIG_HOME = "/home/amp/.config";
      DOCKER_HOST = "unix:///run/user/1001/docker.sock";
      PATH = lib.mkForce "/home/amp/.local/share/mise/shims:/home/amp/.local/bin:${ampRunnerPath}";
    };
    serviceConfig = {
      User = "amp";
      Group = "amp";
      WorkingDirectory = "/home/amp/Repos";
      ExecStart = lib.concatStringsSep " " [
        "/home/amp/.amp/bin/amp"
        "--no-tui"
        "--runner-id bigchungus"
        "--remote-control-terminal"
        "--discover-dirs=/home/amp/Repos"
        "--discover-dirs=/home/amp/Workspaces"
        "--discover-depth=3"
      ];
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

  # claude remote-control servers driven from claude.ai. one serves Repos, for
  # cloning and cross-repo work; each repo directory gets its own so sessions
  # start with that repo's CLAUDE.md and project settings. output goes to the
  # journal: `journalctl -u amp-claude@tokentax`.
  systemd.services.amp-claude = ampClaude {
    description = "Claude Code remote control for the Amp runner";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      WorkingDirectory = "/home/amp/Repos";
      ExecStart = "${ampClaudeBin} remote-control --name bigchungus";
    };
  };

  # started and stopped by amp-claude-repos, not enabled directly
  systemd.services."amp-claude@" = ampClaude {
    description = "Claude Code remote control for /home/amp/Repos/%I";
    unitConfig.ConditionPathIsDirectory = "/home/amp/Repos/%I";
    serviceConfig = {
      WorkingDirectory = "/home/amp/Repos/%I";
      ExecStartPre = "${ampClaudeTrust}/bin/amp-claude-trust /home/amp/Repos/%I";
      ExecStart = "${ampClaudeBin} remote-control --name bigchungus/%I";
    };
  };

  # keep one amp-claude@ instance per directory directly under Repos
  systemd.services.amp-claude-repos = {
    description = "Match amp-claude@ instances to the directories in Repos";
    wantedBy = [ "multi-user.target" ];
    after = [ "amp-runner-init.service" ];
    onFailure = [ "unit-failure@%n.service" ];
    path = with pkgs; [ coreutils systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      shopt -s nullglob
      declare -A want
      for dir in /home/amp/Repos/*/; do
        dir="''${dir%/}"
        [ -L "$dir" ] && continue
        want["amp-claude@$(systemd-escape -- "$(basename "$dir")").service"]=1
      done

      for unit in $(systemctl list-units --all --plain --no-legend 'amp-claude@*.service' | cut -d' ' -f1); do
        [ -n "''${want[$unit]:-}" ] || systemctl stop "$unit"
      done
      [ "''${#want[@]}" -eq 0 ] || systemctl start --no-block "''${!want[@]}"
    '';
  };

  # amp-mise-sync upgrades claude-code and deletes the old version, leaving
  # remote-control on a binary it can no longer re-exec to spawn sessions.
  # restart each server onto the new one once its sessions have sat idle a while.
  systemd.services.amp-claude-follow-upgrade = {
    description = "Restart amp-claude servers onto an upgraded claude-code";
    onFailure = [ "unit-failure@%n.service" ];
    path = with pkgs; [ coreutils jq procps systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      installs=/home/amp/.local/share/mise/installs/claude-code
      latest="$(readlink -f "$installs/latest/claude")" || exit 0

      # each spawned session is a child process with a status file; null, busy
      # and waiting (on a permission prompt) all mean someone is mid-turn
      sessions_idle() {
        local now pid
        now="$(date +%s%3N)"
        for pid in $(pgrep -P "$1"); do
          jq -e --argjson now "$now" \
            '.status == "idle" and $now - .statusUpdatedAt > 600000' \
            "/home/amp/.claude/sessions/$pid.json" > /dev/null 2>&1 || return 1
        done
      }

      for rc in $(pgrep -u amp -f "^$installs/[^/]+/claude remote-control"); do
        running="$(readlink "/proc/$rc/exe")"
        [ "$running" != "$latest" ] || continue
        unit="$(basename "$(cut -d: -f3- "/proc/$rc/cgroup")")"
        [[ "$unit" == amp-claude*.service ]] || continue
        if ! sessions_idle "$rc"; then
          echo "$unit: sessions not idle for 10 minutes, retrying later"
          continue
        fi
        echo "$unit: restarting, running $running, latest $latest"
        systemctl try-restart "$unit"
      done
    '';
  };

  # shared by every remote-control server and the sessions they spawn
  systemd.slices.amp-claude = {
    description = "Claude Code remote control for the Amp runner";
    sliceConfig = {
      MemoryHigh = "6G";
      MemoryMax = "8G";
    };
  };

  systemd.paths.amp-claude-repos = {
    description = "Watch Repos for added or removed directories";
    wantedBy = [ "paths.target" ];
    pathConfig.PathChanged = "/home/amp/Repos";
  };

  systemd.timers.amp-claude-follow-upgrade = {
    description = "Periodically move amp-claude servers onto an upgraded claude-code";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
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
  # demo.film.tymek.me, + goatcounter on 8447, + things cloud mcp on 3020,
  # which chungus-1 reverse proxies for things.tymek.me)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8080 3000 3010 3011 3020 3100 9443 8443 8444 8445 8446 8447 ];

  system.stateVersion = "25.11";
}
