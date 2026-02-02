{ config, pkgs, lib, ... }:

{
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      
      aliases = {
        co = "pr checkout";
        pv = "pr view";
        pc = "pr create";
        pm = "pr merge";
        pl = "pr list";
        rc = "repo clone";
        rv = "repo view";
        rl = "repo list";
      };
    };
  };

  # Install gh extensions via activation script
  home.activation.installGhExtensions = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.gh}/bin/gh extension install silouanwright/gh-comment 2>/dev/null || true
  '';
}
