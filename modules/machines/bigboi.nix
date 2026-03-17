{ config, pkgs, lib, ... }:

{
  homebrew = {
    taps = [ "nikitabobko/tap" ];
    casks = [ "google-cloud-sdk" "steam" ];
    brews = [
      "graphviz"
    ];
  };
}
