{ config, pkgs, lib, ... }:

{
  homebrew = {
    taps = [ "nikitabobko/tap" ];
    casks = [ "google-cloud-sdk" ];
    brews = [
      "k9s"
      "yarn"
      "graphviz"
      "dotenvx/brew/dotenvx"
    ];
  };
}
