{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./packages.nix
    ./programs/starship.nix
    ./programs/gh.nix
    ./programs/darwin/fish.nix
    ./programs/darwin/development.nix
    ./programs/nixos/fish.nix
    ./programs/nixos/development.nix
  ];

  # Home Manager configuration
  home.stateVersion = "23.05";
  # Home Manager master is intentionally paired with nixpkgs-unstable here;
  # disable the release-number check because unstable can move ahead first.
  home.enableNixpkgsReleaseCheck = false;
  programs.home-manager.enable = true;

  # Keep mise installed and shell-integrated on macOS.
  # Tool versions are managed outside Nix (e.g. via chezmoi-managed
  # ~/.config/mise/config.toml), so tools can be changed without rebuilds.
  programs.mise = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    enableFishIntegration = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    BAT_PAGER = "less -XRF";
    BAT_THEME = "base16";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse";
    TERM = "xterm-256color";
    USERNAME = "tim";
    PAGER = "less -RFX";

    NPM_CONFIG_PREFIX = "$HOME/.local/state/npm";
    PATH = "$HOME/.local/state/npm/bin:$PATH";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    HOMEBREW_NO_AUTO_UPDATE = "";
  };

  home.file = {
    ".local/state/npm/.keep".text = "";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    ".config/ghostty/config".source = ./programs/ghostty/config;
    # ".config/zed/settings.json".source = ./programs/zed/settings.json;
    # ".config/zed/keymap.json".source = ./programs/zed/keymap.json;
  };
}
