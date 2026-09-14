{ config, lib, pkgs, filmnight, ... }:

let
  cfg = config.services.filmnight;
  app = "${filmnight.packages.${pkgs.stdenv.hostPlatform.system}.default}/lib/filmnight";
  node = lib.getExe pkgs.nodejs_24;
in
{
  options.services.filmnight = {
    enable = lib.mkEnableOption "Film Night";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Reached over Tailscale only; chungus-1 terminates TLS.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/filmnight.env";
      description = ''
        Holds ORIGIN, RULES, TZ and the TMDB token, so none of them reach the
        store. Anything set here must stay out of the unit's environment
        block, since EnvironmentFile wins over Environment.
      '';
    };

    backupDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/backups/filmnight";
    };

    demo = {
      enable = lib.mkEnableOption "the public demo: this same code, a second service, a database with nobody real in it";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3011;
        description = "Reached over Tailscale only; chungus-1 terminates TLS.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.path;
        default = "/etc/filmnight-demo.env";
        description = ''
          Holds ORIGIN, RULES, TZ, DEMO_HOME and the TMDB token. ADMINS must
          appear neither here nor in the unit: the anonymiser preserves
          is_admin, so the demo already has an admin to switch to, and the ids
          in the real ADMINS do not exist in that database anyway.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      systemd.services.filmnight = {
        description = "Film Night";
        documentation = [ "https://film.tymek.me" ];
        onFailure = [ "unit-failure@%n.service" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        environment = {
          DATABASE_PATH = "/var/lib/filmnight/filmnight.db";
          PORT = toString cfg.port;
          HOST = "0.0.0.0";
          # a phone photo blows through adapter-node's 512K default before the
          # browser has had a chance to shrink it; setAvatar still refuses 2 MB
          BODY_SIZE_LIMIT = "3M";
          # seeds /admin access at boot; grants only, so revoking in the UI
          # sticks and a rebuild can never hand the flag back
          ADMINS = "tymek-chmielecki,piotr-cenda";

          # the commit this store path was built from, handed on so /healthz can
          # answer what is running without anybody grepping the store. rev is
          # absent only when the input is a dirty working copy
          FILMNIGHT_REV = filmnight.rev or "dirty";
        };

        serviceConfig = {
          Type = "simple";
          ExecStart = "${node} ${app}/build/index.js";
          WorkingDirectory = app;
          EnvironmentFile = cfg.environmentFile;
          Restart = "always";
          RestartSec = 3;

          User = "filmnight";
          Group = "filmnight";
          StateDirectory = "filmnight";

          # the database and its WAL sidecars are the only state worth protecting
          ReadWritePaths = [ "/var/lib/filmnight" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          MemoryMax = "512M";
        };
      };

      # sqlite3 .backup is safe against a live WAL writer, so this needs no stop
      systemd.services.filmnight-backup = {
        description = "Film Night nightly database backup";
        onFailure = [ "unit-failure@%n.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "filmnight";
          Group = "filmnight";
          ExecStart = pkgs.writeShellScript "filmnight-backup" ''
            set -euo pipefail
            ${pkgs.sqlite}/bin/sqlite3 /var/lib/filmnight/filmnight.db \
              ".backup '${cfg.backupDir}/filmnight-$(${pkgs.coreutils}/bin/date +%F).db'"
            ${pkgs.findutils}/bin/find ${cfg.backupDir} \
              -name 'filmnight-*.db' -mtime +30 -delete
          '';
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ cfg.backupDir "/var/lib/filmnight" ];
        };
      };

      systemd.timers.filmnight-backup = {
        description = "Run the Film Night backup nightly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 04:17:00";
          Persistent = true;
        };
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.backupDir} 0750 filmnight filmnight -"
      ];

      # sqlite3 for snapshots and restores by hand; handing out links is still a
      # hand-run job: sudo -u filmnight filmnight-seed
      environment.systemPackages = [
        pkgs.sqlite
        (pkgs.writeShellScriptBin "filmnight-seed" ''
          set -a
          . ${cfg.environmentFile}
          set +a
          export DATABASE_PATH=''${DATABASE_PATH:-/var/lib/filmnight/filmnight.db}
          exec ${node} ${app}/seed.mjs "$@"
        '')
      ];

      users.users.filmnight = {
        isSystemUser = true;
        group = "filmnight";
        home = "/var/lib/filmnight";
      };

      users.groups.filmnight = { };
    })

    (lib.mkIf (cfg.enable && cfg.demo.enable) {
      # the same store path as the app above, opening a different file. the
      # privacy is in that file rather than in this unit: nothing here masks
      # anything, the database simply never had anybody real in it
      systemd.services.filmnight-demo = {
        description = "Film Night demo";
        documentation = [ "https://demo.film.tymek.me" ];
        onFailure = [ "unit-failure@%n.service" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        environment = {
          DATABASE_PATH = "/var/lib/filmnight-demo/demo.db";
          PORT = toString cfg.demo.port;
          HOST = "0.0.0.0";
          DEMO = "1";
          # without these adapter-node reports the socket peer, which behind
          # chungus-1 is caddy: every visitor would share one rate limit bucket
          # and one person clicking would lock out the next. caddy sets
          # X-Forwarded-For itself and is the only hop in front, hence depth 1
          ADDRESS_HEADER = "X-Forwarded-For";
          XFF_DEPTH = "1";

          # the commit this store path was built from, handed on so /healthz can
          # answer what is running without anybody grepping the store. rev is
          # absent only when the input is a dirty working copy
          FILMNIGHT_REV = filmnight.rev or "dirty";
        };

        serviceConfig = {
          Type = "simple";
          ExecStart = "${node} ${app}/build/index.js";
          WorkingDirectory = app;
          EnvironmentFile = cfg.demo.environmentFile;
          Restart = "always";
          RestartSec = 3;

          User = "filmnight-demo";
          Group = "filmnight-demo";
          StateDirectory = "filmnight-demo";

          # nothing in here is worth keeping: the refresh below overwrites it
          # every hour, and there is no backup timer for the same reason
          ReadWritePaths = [ "/var/lib/filmnight-demo" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          MemoryMax = "512M";
        };
      };

      # snapshot the real database, rewrite the copy into made-up people, swap
      # it in. set -e is the whole failure contract: the anonymiser writes no
      # output at all unless its verification passed, so a bad run installs
      # nothing and the demo keeps serving what it already has. a stale demo is
      # fine, a leaking one is not
      systemd.services.filmnight-demo-refresh = {
        description = "Rebuild the Film Night demo database";
        # a stale demo is fine and a silently stale one is not; see unit-failure.nix
        onFailure = [ "unit-failure@%n.service" ];

        serviceConfig = {
          Type = "oneshot";

          # runs as root because it reads the real database and installs the
          # result as another user. the snapshot of the real thing spends its
          # short life in /run at 0700, never anywhere the demo user can read
          RuntimeDirectory = "filmnight-demo-refresh";
          RuntimeDirectoryMode = "0700";

          ExecStart = pkgs.writeShellScript "filmnight-demo-refresh" ''
            set -euo pipefail
            work=/run/filmnight-demo-refresh
            trap 'rm -f "$work"/*' EXIT

            # .backup is safe against the live WAL writer and never writes to
            # the database it is reading
            ${pkgs.sqlite}/bin/sqlite3 /var/lib/filmnight/filmnight.db \
              ".backup '$work/snapshot.db'"
            ${node} ${app}/anonymise.mjs "$work/snapshot.db" "$work/next.db"

            ${pkgs.coreutils}/bin/install -o filmnight-demo -g filmnight-demo \
              -m 0640 "$work/next.db" /var/lib/filmnight-demo/demo.db
            # a journal left beside the new file belongs to the database it
            # replaced, and sqlite would replay it over the fresh copy
            ${pkgs.coreutils}/bin/rm -f /var/lib/filmnight-demo/demo.db-wal \
              /var/lib/filmnight-demo/demo.db-shm
            ${pkgs.systemd}/bin/systemctl restart filmnight-demo
          '';

          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/var/lib/filmnight-demo" ];
        };
      };

      systemd.timers.filmnight-demo-refresh = {
        description = "Rebuild the Film Night demo database hourly";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };

      # the refresh can run before the demo has ever started, and StateDirectory
      # would not have made this yet
      systemd.tmpfiles.rules = [
        "d /var/lib/filmnight-demo 0750 filmnight-demo filmnight-demo -"
      ];

      users.users.filmnight-demo = {
        isSystemUser = true;
        group = "filmnight-demo";
        home = "/var/lib/filmnight-demo";
      };

      users.groups.filmnight-demo = { };
    })
  ];
}
