{
  pkgs,
  lib,
  ...
}:

{
  # note: fish, starship, gh, git, jujutsu, and zoxide are installed by
  # their programs.* modules in home.nix / programs/
  home.packages = with pkgs; [
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
    ripgrep
    tmux
    zellij
    carapace
    jq
    mosh
    just

    # Security
    gnupg

    # Additional useful tools
    dust # better du
    procs # better ps
    bottom # better top
    zola
    typst

    # Programming languages and tools
    gopls
    (python3.withPackages (ps: [ ps.pip ps.uv ]))
    # Work around an upstream pipx test failure on nixpkgs-unstable/Python 3.13.
    (python3Packages.pipx.overridePythonAttrs (_: { doCheck = false; }))
    dbmate

    # Version control
    delta
    difftastic

    # dotfiles
    chezmoi

    # Media
    ffmpeg
    exiftool
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # On NixOS these are managed by Nix instead of mise
    nodejs
    rustup
    go
    yarn
    k9s
    cargo-binstall
    poetry
  ];
}
