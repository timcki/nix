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

        # auto-attach to zellij only from a real terminal emulator. OrbStack probes
        # the login shell at startup without TERM_PROGRAM; without this guard that
        # probe creates the session with cwd / and macOS charges every pane's energy
        # use to OrbStack. zed and the claude desktop app (TERM_PROGRAM=claude-desktop,
        # incl. its hidden command shells) embed their own terminals, and attaching
        # there resizes the shared session for every other client
        if set -q TERM_PROGRAM; and test "$ZED_TERM" != "true"; and test "$TERM_PROGRAM" != "claude-desktop"; and not set -q CLAUDECODE; and not set -q ZELLIJ; and command -v zellij >/dev/null 2>&1
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

        # a unit that failed, or a system built from an unpushed working copy,
        # said once at login. prints nothing when there is nothing to say
        if status is-interactive; and command -v unit-failures >/dev/null 2>&1
            unit-failures --login
        end
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
    };
    # switchn is not here: on bigchungus it is a script the machine module
    # installs, sharing one definition with the nightly upgrade so that what it
    # builds and what converges at 04:30 cannot be two different things
  };
}
