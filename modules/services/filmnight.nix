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
  };

  config = lib.mkIf cfg.enable {
    systemd.services.filmnight = {
      description = "Film Night";
      documentation = [ "https://film.tymek.me" ];
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

    # handing out links is still a hand-run job:
    #   sudo -u filmnight filmnight-seed
    environment.systemPackages = [
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
  };
}
