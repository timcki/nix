{ config, pkgs, lib, ... }:

{
  # Samba file shares — Tailscale-only access for Infuse (Apple TV)
  services.samba = {
    enable = true;
    openFirewall = false; # We control the firewall manually (Tailscale only)

    settings = {
      global = {
        "server string" = "bigchungus";
        "server role" = "standalone";

        # Security: Tailscale-only, user-level auth
        "interfaces" = "tailscale0";
        "bind interfaces only" = "yes";
        "hosts allow" = "100.64.0.0/10 fd7a:115c:a1e0::/48";
        "hosts deny" = "0.0.0.0/0";

        # Performance tuning for media streaming
        "use sendfile" = "yes";
        "min receivefile size" = "16384";
        "aio read size" = "16384";
        "aio write size" = "16384";

        # Disable printing
        "load printers" = "no";
        "printing" = "bsd";
        "printcap name" = "/dev/null";

        # Apple/macOS compatibility (helps Infuse)
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "MacSamba";
        "fruit:nfs_aces" = "no";

        # Guest access (simpler for Infuse on local Tailscale network)
        "map to guest" = "Bad User";
      };

      movies = {
        path = "/media/movies";
        "read only" = "yes";
        "guest ok" = "yes";
        browseable = "yes";
        comment = "Movies";
      };

      tv = {
        path = "/media/tv";
        "read only" = "yes";
        "guest ok" = "yes";
        browseable = "yes";
        comment = "TV Shows";
      };

      books = {
        path = "/media/books";
        "read only" = "yes";
        "guest ok" = "yes";
        browseable = "yes";
        comment = "Books";
      };
    };
  };

  # Samba discovery (optional but helps Infuse auto-detect)
  services.samba-wsdd = {
    enable = true;
    openFirewall = false;
    interface = "tailscale0";
  };

  # Firewall: SMB + WSDD only on Tailscale
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    445   # SMB
    5357  # WSDD
  ];
  networking.firewall.interfaces."tailscale0".allowedUDPPorts = [
    3702  # WSDD
  ];
}
