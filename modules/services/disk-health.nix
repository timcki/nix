{ config, lib, pkgs, ... }:

let
  # percent full at which a mount counts as a failure. /data holds reth's
  # database, and running it out of space stops the execution client and with
  # it the validator; it sat at 90% when this was written
  mountLimits = {
    "/data" = 95;
    "/boot" = 90;
  };
  # zfs slows down well before it fills, so the pool gets a lower bar than ext4
  poolLimit = 85;

  # smartd logs the warning itself before running this, so recording the unit
  # through the usual template carries the message into the spool
  smartdHook = pkgs.writeShellScript "smartd-record" ''
    ${pkgs.systemd}/bin/systemctl start --no-block unit-failure@smartd.service.service
  '';
in
{
  systemd.services.disk-usage-check = {
    description = "Check filesystem and zpool usage";
    onFailure = [ "unit-failure@%n.service" ];
    path = [ pkgs.coreutils pkgs.gawk config.boot.zfs.package ];
    serviceConfig.Type = "oneshot";
    script = ''
      status=0

      check() {
        local what="$1" pct="$2" limit="$3"
        if [ "$pct" -ge "$limit" ]; then
          echo "$what is ''${pct}% full (limit ''${limit}%)"
          status=1
        fi
      }

      ${lib.concatLines (lib.mapAttrsToList (mount: limit: ''
        check ${mount} "$(df --output=pcent ${mount} | awk 'NR == 2 { print $1 + 0 }')" ${toString limit}''
      ) mountLimits)}

      while read -r pool cap; do
        check "zpool $pool" "$cap" ${toString poolLimit}
      done < <(zpool list -H -p -o name,capacity)

      exit "$status"
    '';
  };

  systemd.timers.disk-usage-check = {
    description = "Periodically check filesystem and zpool usage";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "0/6:00";
      Persistent = true;
    };
  };

  services.smartd = {
    enable = true;
    # headless, so nobody would see a wall message; the hook below replaces it
    notifications.wall.enable = false;
    # a short self-test every night at 02:00, and a warning at 65°C (critical
    # at 75°C) on top of the health and error log checks that -a covers
    defaults.autodetected = "-a -s S/../.././02 -W 0,65,75 -m <nomailer> -M exec ${smartdHook}";
  };

  environment.systemPackages = [ pkgs.smartmontools ];
}
