{
  config,
  pkgs,
  lib,
  self,
  pushed,
  ...
}:

{
  # what `nixos-version --configuration-revision` answers. "dirty" is the case
  # worth having: it means this system came from a working copy rather than
  # from what is pushed, so the nightly upgrade will replace it with something
  # else, and the login greeting says so.
  #
  # deploys pass --override-input, and nix then strips rev and dirtyRev from
  # self because the lock no longer matches the commit. narHash survives, so
  # the rev comes from `pushed` (the pushed tip, fetched in the same run) and
  # only when its tree is byte for byte the one being built
  system.configurationRevision =
    self.rev or (
      if pushed.narHash == self.narHash then pushed.rev
      else self.dirtyRev or "dirty"
    );

  # the eight eMudhra intermediates whose keys leaked in october 2026 chain to
  # both roots (AAA through a Sectigo cross-sign). drop once cacert >= 3.131.1
  # reaches the channel; until then this is what keeps the nightly https
  # fetch of this flake, run as root, from accepting a forged certificate
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
  ];

  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nixpkgs.config.allowUnfree = true;

  # User configuration
  users.users.tim = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHcfFNAGdwjYbVyiWqPU0kVaPoHZbHxypW+BInZA1gUQ"
    ];
  };

  # Environment
  environment.variables.EDITOR = "nvim";

  # Programs
  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
        fish_vi_key_bindings
      '';
    };
    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
    };
    mosh.enable = true;
    ssh.startAgent = true;

    # Allow generic Linux binaries (like npm-installed CLIs from mise)
    # to run on NixOS by providing the expected dynamic linker.
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        curl
        icu
        nss
        nspr
        expat
      ];
    };
  };

  # Networking firewall rules for mosh
  networking.firewall.allowedUDPPortRanges = [{
    from = 60000;
    to = 61000;
  }];

  # Minimal system packages (most should come from home-manager)
  environment.systemPackages = with pkgs; [
    git
    curl
  ];

  security.sudo.wheelNeedsPassword = false;
}
