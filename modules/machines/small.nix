{ config, pkgs, lib, ... }:

{
  # Small machine - minimal additional packages
  homebrew = {
    # Only essential tools for smaller machines
    brews = [ ];
    casks = [ ];
  };
}