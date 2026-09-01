{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  programs.fish = {
    enable = true;
    interactiveShellInit =
      ''
        set fish_greeting ""
        fish_vi_key_bindings

        # enable truecolor support for nvim/helix in zellij
        set -gx COLORTERM truecolor
      ''
      + lib.optionalString isDarwin ''
        # Source secrets file if it exists (API keys, etc.)
        if test -f ~/.secrets
            source ~/.secrets
        end

        # auto-attach to zellij only from a real terminal emulator (skip Zed).
        # OrbStack probes the login shell at startup without TERM_PROGRAM; without
        # this guard that probe creates the session with cwd / and macOS charges
        # every pane's energy use to OrbStack
        if set -q TERM_PROGRAM; and test "$ZED_TERM" != "true"; and not set -q ZELLIJ; and command -v zellij >/dev/null 2>&1
            zellij attach -c work
        end

        if command -v fish_ssh_agent >/dev/null 2>&1
            fish_ssh_agent
        end

        # capture dotfile drift into chezmoi at most once a day; runs from the
        # interactive session so the ssh agent is available for the push
        if status is-interactive; and command -v chezmoi-sync >/dev/null 2>&1
            set -l stamp ~/.local/state/chezmoi-sync/last-run
            if not test -f $stamp; or test (math (date +%s) - (stat -f %m $stamp)) -gt 86400
                mkdir -p ~/.local/state/chezmoi-sync
                touch $stamp
                chezmoi-sync >~/.local/state/chezmoi-sync/log 2>&1 &
                disown
            end
        end
      ''
      + lib.optionalString isLinux ''
        # No auto-start zellij on NixOS (prevents nested sessions when SSH from mac)
      '';

    shellAliases = {
      vi = "hx";
      vim = "hx";
      nano = "hx";
      cat = "bat";

      # git
      gs = "git status";

      # jujutsu
      je = "jj edit";
      jd = "jj desc";
      jn = "jj next";
      jp = "jj prev";
      jb = "jj bookmark";
      jg = "jj git";

      # misc
      dc = "docker compose";
    }
    // lib.optionalAttrs isDarwin {
      switchd = "sudo darwin-rebuild switch --flake ~/.config/nix";
    }
    // lib.optionalAttrs isLinux {
      switchn = "sudo nixos-rebuild switch --flake ~/.config/nix";
    };
  };
}
