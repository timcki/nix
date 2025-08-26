{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./packages.nix
    ./programs/fish.nix
    ./programs/starship.nix
    ./programs/development.nix
    ./programs/gh.nix
  ];

  # Home Manager configuration
  home.stateVersion = "23.05";
  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    BAT_PAGER = "less -XRF";
    BAT_THEME = "base16-256";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse";
    TERM = "xterm-256color";
    USERNAME = "tim";
    PAGER = "less -RFX";
    HOMEBREW_NO_AUTO_UPDATE = "";

    NPM_CONFIG_PREFIX = "$HOME/.local/state/npm";
    PATH = "$HOME/.local/state/npm/bin:$PATH";
  };

  home.file = {
    ".config/ghostty/config".source = ./programs/ghostty/config;
    # ".config/zed/settings.json".source = ./programs/zed/settings.json;
    # ".config/zed/keymap.json".source = ./programs/zed/keymap.json;
    ".local/state/npm/.keep".text = "";
  };
}
