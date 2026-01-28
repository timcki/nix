{ config, lib, pkgs, slurp, ... }:

let
  cfg = config.services.slurp;
  slurpPackage = slurp.packages.${pkgs.system}.default;
in
{
  options.services.slurp = {
    enable = lib.mkEnableOption "Slurp RSS reader";
    configFile = lib.mkOption {
      type = lib.types.path;
      default = /home/tim/slurp/slurp.toml;
      description = "Path to slurp config file";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.slurp = {
      description = "Slurp RSS Reader";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      preStart = ''
        if [ ! -f /var/lib/slurp/slurp.toml ]; then
          install -m 640 -o slurp -g slurp \
            ${cfg.configFile} /var/lib/slurp/slurp.toml
        fi
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = "${slurpPackage}/bin/slurp serve --config /var/lib/slurp/slurp.toml";
        Restart = "on-failure";
        RestartSec = "5s";

        User = "slurp";
        Group = "slurp";
        WorkingDirectory = "/var/lib/slurp";
        StateDirectory = "slurp";

        # security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/slurp" ];
      };
    };

    users.users.slurp = {
      isSystemUser = true;
      group = "slurp";
      home = "/var/lib/slurp";
      createHome = true;
    };

    users.groups.slurp = {};
  };
}
