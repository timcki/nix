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
}