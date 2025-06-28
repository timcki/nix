{ config, pkgs, lib, ... }:

{
  nix.enable = true;
  
  # Enable sudo with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Nix configuration
  ids.gids.nixbld = 350;
  nix.settings.experimental-features = "nix-command flakes";

  nix.gc = {
    automatic = true;
    interval = {
      Day = 3;
    };
    options = "--delete-older-than 3d";
  };

  # macOS system defaults
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "bottom";
      show-recents = false;
    };
    
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv"; # Column view
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3; # Full keyboard access
      AppleShowScrollBars = "WhenScrolling";
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
    };
    
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };
  };

  system.configurationRevision = null;
  system.stateVersion = 4;
  system.primaryUser = "tim";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # User configuration
  users.users.tim = {
    name = "tim";
    home = "/users/tim";
    shell = pkgs.fish;
  };

  environment.systemPackages = with pkgs; [ pam-reattach ];
  
  # Hack to make pam-reattach work
  environment.etc."pam.d/sudo_local".text = ''
    # Written by nix-darwin
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
  '';

  programs = {
    fish.enable = true;
    zsh.enable = true;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "uninstall";
    };
    
    # Shared homebrew packages for all machines
    casks = [
      "zed@preview"
      "discord"
      "vimr"
      "1password@nightly"
      "1password-cli@beta"
      "jordanbaird-ice"
      "rectangle"
      "ghostty"
    ];

    brews = [
      "cargo-binstall"
      "llm"
    ];
  };
}