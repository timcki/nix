{ config, pkgs, lib, ... }:

let
  # Mullvad Warsaw server
  mullvadEndpoint = "45.134.212.66:51820";
  mullvadPublicKey = "fO4beJGkKZxosCZz1qunktieuPyzPnEVKVQNhzanjnA=";
  mullvadAddress = "10.67.105.24/32";
  mullvadAddressV6 = "fc00:bbbb:bbbb:bb01::4:6917/128";
  mullvadDNS = "10.64.0.1";

  # veth pair for bridging WebUI ports back to host
  vethHost = "veth-arr";
  vethNS = "veth-arr-ns";
  vethHostAddr = "10.200.0.1/24";
  vethNSAddr = "10.200.0.2/24";
  nsName = "arr-vpn";

  # Ports to forward from host into the namespace
  webuiPorts = {
    qbittorrent = 8085;
    radarr = 7878;
    prowlarr = 9696;
  };
  allPorts = lib.attrValues webuiPorts;

  # iptables rules for forwarding ports into the namespace
  # PREROUTING handles external traffic (Tailscale, LAN)
  # OUTPUT handles localhost access from the host itself
  forwardRules = lib.concatMapStringsSep "\n" (port: ''
    iptables -t nat -A PREROUTING -p tcp --dport ${toString port} -j DNAT --to-destination 10.200.0.2:${toString port}
    iptables -t nat -A OUTPUT -p tcp --dport ${toString port} -j DNAT --to-destination 10.200.0.2:${toString port}
  '') allPorts;

  cleanupForwardRules = lib.concatMapStringsSep "\n" (port: ''
    iptables -t nat -D PREROUTING -p tcp --dport ${toString port} -j DNAT --to-destination 10.200.0.2:${toString port} 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport ${toString port} -j DNAT --to-destination 10.200.0.2:${toString port} 2>/dev/null || true
  '') allPorts;

  # Namespace-side iptables: mark response packets to exit via veth (not VPN)
  nsMarkRules = lib.concatMapStringsSep "\n" (port: ''
    ip netns exec ${nsName} iptables -t mangle -A PREROUTING -i ${vethNS} -p tcp --dport ${toString port} -j MARK --set-mark 0x1
  '') allPorts;

  nsCleanupMarkRules = lib.concatMapStringsSep "\n" (port: ''
    ip netns exec ${nsName} iptables -t mangle -D PREROUTING -i ${vethNS} -p tcp --dport ${toString port} -j MARK --set-mark 0x1 2>/dev/null || true
  '') allPorts;
in
{
  # Enable IP forwarding (required for DNAT from tailscale0 → veth namespace bridge)
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Shared media group for arr stack services
  users.groups.media = {};

  # Mullvad private key - store securely
  # TODO: move to agenix/sops-nix for proper secret management
  environment.etc."mullvad/wg-key" = {
    text = "qPwJmg7F90oBYNpBRQP6M+34rIFQ5y+mP5SqszzxLWc=";
    mode = "0600";
  };

  # 1. Create the network namespace
  systemd.services."netns-${nsName}" = {
    description = "Network namespace for arr stack VPN";
    before = [ "wg-${nsName}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      ip netns add ${nsName} || true
      ip -n ${nsName} link set lo up
    '';
    preStop = ''
      ip netns del ${nsName} || true
    '';
  };

  # 2. Set up WireGuard inside the namespace + veth bridge
  systemd.services."wg-${nsName}" = {
    description = "WireGuard VPN in ${nsName} namespace";
    after = [ "netns-${nsName}.service" "network-online.target" ];
    requires = [ "netns-${nsName}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ iproute2 wireguard-tools iptables ];
    script = ''
      # Create WireGuard interface in default namespace, then move to arr-vpn
      ip link add wg-mullvad type wireguard
      wg set wg-mullvad private-key /etc/mullvad/wg-key \
        peer ${mullvadPublicKey} \
        endpoint ${mullvadEndpoint} \
        allowed-ips 0.0.0.0/0,::0/0
      ip link set wg-mullvad netns ${nsName}

      # Configure WireGuard inside the namespace
      ip -n ${nsName} addr add ${mullvadAddress} dev wg-mullvad
      ip -n ${nsName} link set wg-mullvad up

      # Default route through WireGuard (in routing table 2468)
      ip -n ${nsName} route add default dev wg-mullvad table 2468

      # Unmarked traffic uses the WireGuard table
      ip -n ${nsName} rule add not fwmark 0x1 table 2468

      # Create veth pair bridging host <-> namespace
      ip link add ${vethHost} type veth peer name ${vethNS}
      ip link set ${vethNS} netns ${nsName}

      # Configure host side
      ip addr add ${vethHostAddr} dev ${vethHost}
      ip link set ${vethHost} up

      # Configure namespace side
      ip -n ${nsName} addr add ${vethNSAddr} dev ${vethNS}
      ip -n ${nsName} link set ${vethNS} up

      # Marked traffic (responses to WebUI requests) exits via veth
      ip -n ${nsName} rule add fwmark 0x1 table 3000
      ip -n ${nsName} route add default via 10.200.0.1 dev ${vethNS} table 3000

      # NAT on host: forward WebUI ports into namespace
      iptables -t nat -A POSTROUTING -s 10.200.0.0/24 -j MASQUERADE
      ${forwardRules}

      # Mark incoming WebUI traffic inside namespace so responses go back via veth
      ${nsMarkRules}
      ip netns exec ${nsName} iptables -t mangle -A PREROUTING -i ${vethNS} -j CONNMARK --save-mark
      ip netns exec ${nsName} iptables -t mangle -A OUTPUT -j CONNMARK --restore-mark

      # DNS inside namespace
      mkdir -p /etc/netns/${nsName}
      echo "nameserver ${mullvadDNS}" > /etc/netns/${nsName}/resolv.conf
    '';
    preStop = ''
      ${cleanupForwardRules}
      iptables -t nat -D POSTROUTING -s 10.200.0.0/24 -j MASQUERADE 2>/dev/null || true
      ${nsCleanupMarkRules}
      ip link del ${vethHost} 2>/dev/null || true
      ip -n ${nsName} link del wg-mullvad 2>/dev/null || true
      rm -rf /etc/netns/${nsName}
    '';
  };

  # 3. Services running inside the VPN namespace

  services.qbittorrent = {
    enable = true;
    webuiPort = webuiPorts.qbittorrent;
    group = "media";
    openFirewall = false;
  };
  systemd.services.qbittorrent.serviceConfig.NetworkNamespacePath = "/var/run/netns/${nsName}";
  systemd.services.qbittorrent.after = [ "wg-${nsName}.service" ];
  systemd.services.qbittorrent.requires = [ "wg-${nsName}.service" ];

  services.radarr = {
    enable = true;
    openFirewall = false;
    group = "media";
  };
  systemd.services.radarr.serviceConfig.NetworkNamespacePath = "/var/run/netns/${nsName}";
  systemd.services.radarr.after = [ "wg-${nsName}.service" ];
  systemd.services.radarr.requires = [ "wg-${nsName}.service" ];

  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };
  systemd.services.prowlarr.serviceConfig.NetworkNamespacePath = "/var/run/netns/${nsName}";
  systemd.services.prowlarr.after = [ "wg-${nsName}.service" ];
  systemd.services.prowlarr.requires = [ "wg-${nsName}.service" ];

  # FlareSolverr - Cloudflare bypass proxy for Prowlarr
  # Runs in the same namespace so Prowlarr reaches it at http://localhost:8191
  services.flaresolverr = {
    enable = true;
    port = 8191;
    openFirewall = false;
  };
  systemd.services.flaresolverr.serviceConfig.NetworkNamespacePath = "/var/run/netns/${nsName}";
  systemd.services.flaresolverr.after = [ "wg-${nsName}.service" ];
  systemd.services.flaresolverr.requires = [ "wg-${nsName}.service" ];

  # 4. Jellyfin media server (runs on host, not in VPN namespace)
  #    VAAPI hardware acceleration via AMD 780M iGPU
  hardware.graphics.enable = true;
  users.users.jellyfin.extraGroups = [ "render" "video" ];

  services.jellyfin = {
    enable = true;
    group = "media";
    openFirewall = false;
  };

  # 5. Directory structure on rpool/media (mounted at /media)
  systemd.tmpfiles.rules = [
    "d /media/torrents 0775 qbittorrent media -"
    "d /media/torrents/movies 0775 qbittorrent media -"
    "d /media/movies 0775 radarr media -"
  ];

  # 6. Expose WebUIs and Jellyfin only on Tailscale
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    webuiPorts.qbittorrent
    webuiPorts.radarr
    webuiPorts.prowlarr
    8096  # Jellyfin
  ];
}
