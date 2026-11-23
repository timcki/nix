{ config, lib, pkgs, albedo, ... }:

# albedo agent, woken by iMessage through photon. it has no sandbox of its own,
# so the boundary is the user: its own uid, no wheel/docker, nothing of tim's or
# the validator's readable. inside its home it has free reign.
#
# provider, model and photon pairing are runtime state set once with the CLI
# (see docs/albedo.md), not declared here: activation merges into files the
# daemon also writes, and the nightly upgrade activates with the daemon running.
let
  cfg = config.services.albedo-agent;
  home = "/home/albedo";
  uid = 1002;
in
{
  options.services.albedo-agent = {
    enable = lib.mkEnableOption "albedo agent as the isolated albedo user";
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 4317;
      description = "tailnet-only port of the albedo web gateway";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.albedo = { };
    users.users.albedo = {
      isNormalUser = true;
      description = "Albedo agent";
      inherit uid home;
      createHome = true;
      homeMode = "0700";
      group = "albedo";
      shell = pkgs.bashInteractive;
      # the daemon is a systemd user unit; this starts user@1002 at boot
      linger = true;
      openssh.authorizedKeys.keys = config.users.users.amp.openssh.authorizedKeys.keys;
    };

    # caps everything the user runs, detached python kernels included, so a
    # runaway job cannot starve the staking node
    systemd.services."user@${toString uid}" = {
      overrideStrategy = "asDropin";
      serviceConfig = {
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = "4G";
        MemoryMax = "6G";
        OOMScoreAdjust = 500;
      };
    };

    home-manager.users.albedo = {
      imports = [ albedo.homeModules.default ];

      home = {
        username = "albedo";
        # must equal $HOME exactly or the daemon-home identity check fails
        homeDirectory = home;
        stateVersion = "25.11";
        enableNixpkgsReleaseCheck = false;
        # what the agent reaches for from its python kernel via run()
        packages = with pkgs; [
          bashInteractive
          coreutils
          curl
          diffutils
          fd
          file
          findutils
          gawk
          gh
          git
          gnugrep
          gnused
          gnutar
          gzip
          jq
          jujutsu
          less
          openssh
          procps
          python3
          ripgrep
          rsync
          unzip
          uv
          which
          xz
        ];
      };

      programs.albedo = {
        enable = true;
        # kernel-native port of the shared kagi-search skill; the key is
        # runtime state in ~/.config/kagi/api_key, never the store
        skills.kagi-search = ../../config/albedo/skills/kagi-search;
      };
      services.albedo = {
        enable = true;
        web = {
          enable = true;
          port = cfg.webPort;
          # explicit, so a network saved at runtime cannot widen it
          allowedNetworks = [ "100.64.0.0/10" ];
        };
      };
    };

    systemd.tmpfiles.settings."10-albedo" = {
      "${home}/work".d = { user = "albedo"; group = "albedo"; mode = "0700"; };
      # a store symlink, so it changes here and nowhere else
      "${home}/work/AGENTS.md"."L+" = {
        argument = toString (pkgs.writeText "albedo-AGENTS.md" ''
          # Albedo on bigchungus

          You run as the `albedo` user on bigchungus, Tymek's NixOS home server.
          Tymek talks to you over iMessage.

          - Replies go to a phone. Keep them short and in plain text: no
            markdown, no tables, no headings. Code only when asked.
          - `/home/albedo` is yours. Install, clone and build what you need
            there. You have no sudo and cannot reach other users' files.
          - The box also runs an Ethereum validator. Keep jobs light; never
            run long CPU or disk heavy work without asking first.
          - Every step costs real money from a small API budget. Do the work
            in as few steps as you can and stop when it is done.
          - If you spawn child agents, use Sonnet 5.5 for them.
        '');
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.webPort ];
  };
}
