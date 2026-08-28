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
    ./programs/fish.nix
    ./programs/development.nix
  ];

  # Home Manager configuration
  home.stateVersion = "23.05";
  # Home Manager master is intentionally paired with nixpkgs-unstable here;
  # disable the release-number check because unstable can move ahead first.
  home.enableNixpkgsReleaseCheck = false;
  programs.home-manager.enable = true;

  # mise owns fast-moving toolchains on both platforms; versions live in the
  # chezmoi-managed ~/.config/mise/config.toml so bumps need no nix rebuild
  programs.mise = {
    enable = true;
    enableFishIntegration = true;
  };

  # bigchungus is the consume side of dotfiles: pull and apply on a timer so
  # it can never drift behind. the mac captures and pushes via chezmoi-sync.
  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.chezmoi-update = {
      Unit.Description = "pull and apply dotfiles";
      Service = {
        Type = "oneshot";
        Environment = "PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh ]}";
        # force: no TTY here, and the mac is the source of truth for dotfiles;
        # local edits on this box are expected to lose
        ExecStart = "${pkgs.chezmoi}/bin/chezmoi update --force";
      };
    };
    timers.chezmoi-update = {
      Unit.Description = "periodic chezmoi update";
      Timer = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
      Install.WantedBy = [ "timers.target" ];
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
