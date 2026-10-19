{ config, lib, pkgs, ... }:

let
  cfg = config.services.things-cloud-mcp;
  stateDir = "/var/lib/things-cloud-mcp";

  # the protocol is reverse-engineered and has one maintainer, so this moves by
  # hand only: read the diff, back up, bump rev and both hashes together
  package = pkgs.buildGoModule {
    pname = "things-cloud-mcp";
    version = "1.4.4-unstable-2026-10-19";
    # the task7 branch of tim's fork: upstream 83135bb plus Task7 reads, which
    # current Things releases write and upstream still rejects. back to
    # wbopan/things-cloud-mcp once a release handles Task7
    src = pkgs.fetchFromGitHub {
      owner = "timcki";
      repo = "things-cloud-mcp";
      rev = "b759e7fd2aa5c9fa383c3b77200c72fefef0ee34";
      hash = "sha256-XlkE6RjksFoXchUAf5KiG9oqQiVz8brIH5fSxbK0EvY=";
    };
    vendorHash = "sha256-KHlGecewRIOOY5+BO4lQjjntzmzpKHJn1QTJKio8YOI=";
    # things-cloud-sdk is a separate module pulled in by a replace directive
    subPackages = [ "." ];
    meta.mainProgram = "things-cloud-mcp";
  };
in
{
  options.services.things-cloud-mcp = {
    enable = lib.mkEnableOption "Things Cloud MCP server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3020;
      description = "Reached over Tailscale only; chungus-1 terminates TLS for things.tymek.me.";
    };

    backupDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/backups/things-cloud-mcp";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.things-cloud-mcp = {
      description = "Things Cloud MCP";
      documentation = [ "https://github.com/wbopan/things-cloud-mcp" ];
      onFailure = [ "unit-failure@%n.service" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # no JWT_SECRET or CREDENTIALS_SECRET: unset, it generates both and keeps
      # them in the state dir (the jwt secret inside oauth.db, the credential key
      # beside it), so the database and the key that decrypts it are always
      # backed up and restored as one. it refuses to start, rather than mint a
      # new key, if the key is gone while encrypted rows remain
      environment = {
        PORT = toString cfg.port;
        DATA_DIR = stateDir;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe package;
        Restart = "always";
        RestartSec = 3;

        User = "things-cloud-mcp";
        Group = "things-cloud-mcp";
        StateDirectory = "things-cloud-mcp";
        StateDirectoryMode = "0700";
        UMask = "0077";

        # holds Things Cloud passwords (encrypted) for anyone who signs in, and
        # shares nothing with the staking node: no docker, no other state
        ReadWritePaths = [ stateDir ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
        MemoryMax = "256M";
        CPUQuota = "100%";
      };
    };

    # .backup is safe against the live writer; the key goes with every copy
    # because a database without its key is unreadable by design
    systemd.services.things-cloud-mcp-backup = {
      description = "Things Cloud MCP nightly state backup";
      onFailure = [ "unit-failure@%n.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "things-cloud-mcp";
        Group = "things-cloud-mcp";
        UMask = "0077";
        ExecStart = pkgs.writeShellScript "things-cloud-mcp-backup" ''
          set -euo pipefail
          dest=${cfg.backupDir}/$(${pkgs.coreutils}/bin/date +%F)
          ${pkgs.coreutils}/bin/mkdir -p "$dest"
          ${pkgs.sqlite}/bin/sqlite3 ${stateDir}/oauth.db ".backup '$dest/oauth.db'"
          ${pkgs.coreutils}/bin/cp ${stateDir}/credentials.key "$dest/"
          ${pkgs.findutils}/bin/find ${cfg.backupDir} -mindepth 1 -maxdepth 1 \
            -type d -mtime +30 -exec ${pkgs.coreutils}/bin/rm -rf {} +
        '';
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.backupDir stateDir ];
      };
    };

    systemd.timers.things-cloud-mcp-backup = {
      description = "Run the Things Cloud MCP backup nightly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:12:00";
        Persistent = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.backupDir} 0700 things-cloud-mcp things-cloud-mcp -"
    ];

    users.users.things-cloud-mcp = {
      isSystemUser = true;
      group = "things-cloud-mcp";
      home = stateDir;
    };

    users.groups.things-cloud-mcp = { };
  };
}
