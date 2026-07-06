{ config, pkgs, lib, ... }:

{
  homebrew = {
    taps = [ "nikitabobko/tap" "schpet/tap" ];
    casks = [ "gcloud-cli" "steam" ];
    brews = [
      "graphviz"
      "schpet/tap/linear"
    ];
  };
}
