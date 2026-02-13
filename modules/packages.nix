{
  pkgs,
  lib,
  ...
}:

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
    fd
    fzf
    git
    ripgrep
    tmux
    zellij
    zoxide
    carapace
    jq
    mosh
    just

    # Additional useful tools
    dust # better du
    procs # better ps
    bottom # better top
    zola
    typst

    # Programming languages and tools
    gopls
    (python3.withPackages (ps: [ ps.pip ps.uv ps.pipx ]))
    dbmate

    # Version control
    jujutsu
    gh
    delta

    # dotfiles
    chezmoi

    # Media
    ffmpeg
  ];
}
