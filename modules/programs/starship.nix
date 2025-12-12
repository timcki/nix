{ config, pkgs, lib, ... }:

{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$hostname$sudo$directory$character";

      hostname = {
        ssh_only = true;
        format = "\\([$hostname](bold blue)\\) ";
        trim_at = ".";
        disabled = false;
        aliases = { bigchungus = "bigc"; };
      };

      sudo = {
        disabled = false;
        format = "[$symbol]($style)";
        symbol = "as # ";
        style = "bold red";
      };

      character.success_symbol = "[→](bold green)";
      character.error_symbol = "[→](bold red)";
      character.vimcmd_symbol = "[←](bold yellow)";
      character.vimcmd_visual_symbol = "[←](bold purple)";

      line_break.disabled = true;

      custom = {
        jj_branch = {
          when = "jj workspace root --ignore-working-copy";
          command = ''
            jj log -r "(immutable_heads()..@):: & bookmarks()" -T 'local_bookmarks.join("\n") ++ "\n"' --no-graph --ignore-working-copy | head -n 1
          '';
          style = "yellow";
        };
        jj_changeid = {
          when = "jj workspace root --ignore-working-copy";
          command = ''
            jj log -T "change_id.short()" --no-graph --ignore-working-copy -r @'';
          style = "bright-purple";
        };
      };
    };
  };
}

