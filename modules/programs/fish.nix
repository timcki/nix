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

      # Improved tmux logic with error handling
      if test -n "$ZED_TERM"
          if test "$ZED_TERM" != "true"
              if not set -q TMUX
                  if command -v tmux >/dev/null 2>&1
                      tmux attach -t default 2>/dev/null; or tmux new -s default
                  end
              end
          end
      else
          if not set -q TMUX
              if command -v tmux >/dev/null 2>&1
                  tmux attach -t default 2>/dev/null; or tmux new -s default
              end
          end
      end

      if command -v fish_ssh_agent >/dev/null 2>&1
          fish_ssh_agent
      end
    '';

    shellAliases = {
      switchd = "darwin-rebuild switch --flake ~/.config/nix";
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
