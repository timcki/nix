{ ... }:

let
  # bigchungus on the tailnet; the tailscale admin console points global DNS here
  tailnetAddrs = [
    "100.86.94.29"
    "[fd7a:115c:a1e0::8801:5e34]"
  ];
in
{
  # blocky binds the tailnet addresses directly, and tailscaled assigns them
  # asynchronously, so starting before tailscale0 is up must not fail the bind
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv6.ip_nonlocal_bind" = 1;
  };

  services.blocky = {
    enable = true;
    settings = {
      ports = {
        dns = map (addr: "${addr}:53") tailnetAddrs;
        # api (`blocky blocking disable`) and prometheus metrics
        http = "127.0.0.1:4000";
      };

      upstreams = {
        # every device on the tailnet resolves through this, so answer queries
        # immediately on restart instead of waiting for upstreams to check out
        init.strategy = "fast";
        groups.default = [
          "https://dns.quad9.net/dns-query"
          "https://dns.mullvad.net/dns-query"
        ];
      };

      # resolves the upstream and list hostnames without going through the
      # system resolver, which on this box is MagicDNS and so, eventually, blocky
      bootstrapDns = [
        {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [ "9.9.9.9" "149.112.112.112" ];
        }
      ];

      blocking = {
        denylists.ads = [
          "https://big.oisd.nl/domainswild"
          "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        ];
        # domains a list wrongly blocks; allowlists win over denylists
        allowlists.ads = [ ];
        clientGroupsBlock.default = [ "ads" ];
        loading = {
          refreshPeriod = "24h";
          # serve unfiltered while lists download rather than not at all
          strategy = "fast";
          downloads.timeout = "60s";
        };
      };

      caching = {
        minTime = "5m";
        prefetching = true;
      };

      prometheus.enable = true;

      # one log line per tailnet query is noise in the journal
      queryLog.type = "none";
    };
  };

  systemd.services.blocky = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    onFailure = [ "unit-failure@%n.service" ];
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
