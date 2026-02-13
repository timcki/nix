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
  programs.home-manager.enable = true;

  # Mise - manage language runtimes and dev tools
  programs.mise = {
    enable = true;
    enableFishIntegration = true;
    globalConfig = {
      tools = {
        "npm:@anthropic-ai/claude-code" = "latest";
        "npm:@mariozechner/pi-coding-agent" = "latest";
      } // lib.optionalAttrs pkgs.stdenv.isDarwin {
        poetry = "latest";
        rust = "latest";
        go = "latest";
        node = "lts";
        yarn = "latest";
        k9s = "latest";
        cargo-binstall = "latest";
      };
    };
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
