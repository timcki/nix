{ config, pkgs, lib, ... }:

{
  homebrew = {
    taps = [ "nikitabobko/tap" ];
    casks = [ "gcloud-cli" "steam" ];
    brews = [ "graphviz" ]; # linear moved to mise
  };
}
