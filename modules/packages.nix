{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Terminals and shells
    fish
    starship

    # Editors
    helix
    neovim

    # Language servers and development tools
    nixd
    nil

    # Core utilities
    bat
    eza
    fzf
    git
    ripgrep
    tmux
    zoxide
    carapace
    jq

    # Additional useful tools
    dust # better du
    procs # better ps
    bottom # better top

    # Programming languages and tools
    go
    gopls
    (python3.withPackages (ps: [
      ps.pip
      ps.uv
      ps.pipx
    ]))
    poetry
    rustup
    dbmate
    nodejs

    # Version control
    jujutsu
    gh

    # Media
    ffmpeg
  ];
}
