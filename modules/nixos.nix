{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Nix configuration
  nix.settings.experimental-features = "nix-command flakes";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nixpkgs.config.allowUnfree = true;

  # User configuration
  users.users.tim = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
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
