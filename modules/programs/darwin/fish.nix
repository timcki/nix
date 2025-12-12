{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.fish = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting ""
      fish_vi_key_bindings

      # enable truecolor support for nvim/helix in zellij
      set -gx COLORTERM truecolor

      # auto-attach to zellij (skip in Zed terminal)
      if test "$ZED_TERM" != "true"; and not set -q ZELLIJ; and command -v zellij >/dev/null 2>&1
          zellij attach -c default
      end

      if command -v fish_ssh_agent >/dev/null 2>&1
          fish_ssh_agent
      end
    '';

    shellAliases = {
      switchd = "sudo darwin-rebuild switch --flake ~/.config/nix";
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
    };
  };
}
