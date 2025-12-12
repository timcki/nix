{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting ""
      fish_vi_key_bindings

      # enable truecolor support for nvim/helix in zellij
      set -gx COLORTERM truecolor

      # API key management with error handling
      if test -z "$ANTHROPIC_API_KEY"
          if command -v op >/dev/null 2>&1
              set -gx ANTHROPIC_API_KEY (op item get orqobbytrs3q5kgjrh7kk5caca --fields=credential --reveal 2>/dev/null || echo "")
          end
      end

      if test -z "$OPENAI_API_KEY"
          if command -v op >/dev/null 2>&1
              set -gx OPENAI_API_KEY (op item get cfjnlwmstlkg5rc36yadjtgiiy --fields=credential --reveal 2>/dev/null || echo "")
          end
      end

      if test -z "$OPEN_ROUTER_API_KEY"
          if command -v op >/dev/null 2>&1
              set -gx OPEN_ROUTER_API_KEY (op item get ras7stvjo4kzxesjetl5nip6gm --fields=credential --reveal 2>/dev/null || echo "")
          end
      end

      # No auto-start zellij on NixOS (prevents nested sessions when SSH from mac)

      if command -v fish_ssh_agent >/dev/null 2>&1
          fish_ssh_agent
      end
    '';

    shellAliases = {
      switch = "sudo nixos-rebuild switch --flake ~/.config/nix";
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
