{ lib, pkgs, ... }:

let
  dir = "/var/lib/unit-failure";
  spool = "${dir}/failures";

  # The one place that knows how a failure is delivered. Today that is a file
  # and a line at login, which is already the difference between noticing and
  # not: filmnight-demo-refresh died every hour for four days and nothing on
  # this box said a word. Adding a push notification is a curl in here and no
  # change anywhere else, which is why every unit points at this template rather
  # than at whatever the delivery happens to be.
  record = pkgs.writeShellScript "unit-failure-record" ''
    set -uo pipefail
    unit="''${1:?which unit}"
    {
      echo "=== $unit  $(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      ${pkgs.systemd}/bin/journalctl -u "$unit" -n 12 --no-pager -o cat 2>/dev/null || true
      echo
    } >> ${spool}
    ${pkgs.coreutils}/bin/chmod 0664 ${spool} || true

    # delivery goes here
  '';

  # `systemctl --failed` only knows about units that are failed *now*, which an
  # hourly oneshot stops being the moment one run happens to succeed. The spool
  # is what survives that, so the two are reported together and mean different
  # things: one is broken, the other has been.
  report = pkgs.writeShellScriptBin "unit-failures" ''
    set -uo pipefail
    mode="''${1:-}"

    if [ "$mode" = "--clear" ]; then
      ${pkgs.coreutils}/bin/rm -f ${spool} && echo "cleared"
      exit $?
    fi

    failed=$(${pkgs.systemd}/bin/systemctl list-units --state=failed --no-legend --plain 2>/dev/null \
      | ${pkgs.gawk}/bin/awk '{print $1}')
    seen=$(${pkgs.gnugrep}/bin/grep -c '^=== ' ${spool} 2>/dev/null || echo 0)
    # self.dirtyRev is "<rev>-dirty", and an unset revision reads "unknown";
    # only the first of those is worth saying anything about
    rev=$(/run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null || echo "")
    case "$rev" in
      *-dirty | dirty) dirty=1 ;;
      *) dirty="" ;;
    esac

    # at login there is no news in "everything is fine", and a greeting that
    # prints every time is one that stops being read
    if [ "$mode" = "--login" ] && [ -z "$failed" ] && [ "$seen" = "0" ] && [ -z "$dirty" ]; then
      exit 0
    fi

    if [ -n "$failed" ]; then
      echo "failed units:"
      echo "$failed" | ${pkgs.gnused}/bin/sed 's/^/  /'
    fi

    if [ "$seen" != "0" ]; then
      echo "$seen recorded failure(s) since last cleared: ${spool}"
      echo "  latest: $(${pkgs.gnugrep}/bin/grep '^=== ' ${spool} | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.coreutils}/bin/cut -c5-)"
      echo "  unit-failures --clear once dealt with"
    fi

    # a system built from a working copy is one the next nightly upgrade will
    # throw away, which is worth knowing before wondering where the change went
    if [ -n "$dirty" ]; then
      echo "built from a working copy ($rev); the 04:30 upgrade will replace it"
    fi

    if [ -z "$failed" ] && [ "$seen" = "0" ] && [ -z "$dirty" ]; then
      echo "no failures recorded"
    fi
  '';
in
{
  systemd.services."unit-failure@" = {
    description = "Record that %i failed";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${record} %i";
      # writes one file and reads the journal; nothing else
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ dir ];
      NoNewPrivileges = true;
    };
  };

  # group writable so clearing it does not need root, and so the template can
  # append before any unit has ever had a StateDirectory made for it
  systemd.tmpfiles.rules = [ "d ${dir} 0775 root wheel -" ];

  environment.systemPackages = [ report ];
}
