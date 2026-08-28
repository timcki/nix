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

    # capture local dotfile drift into chezmoi and push it; the fish hook in
    # programs/fish.nix runs this daily on the mac, and it can be run by hand
    (writeShellScriptBin "chezmoi-sync" ''
      set -eu
      chezmoi re-add
      cd ~/.local/share/chezmoi
      jj git fetch --remote origin
      # refuse to push over changes made elsewhere; resolve by hand instead
      if [ -n "$(jj log --no-graph -r 'main@origin ~ ::main' -T 'commit_id')" ]; then
        echo "chezmoi-sync: origin/main has commits not in local main, resolve manually" >&2
        exit 1
      fi
      if [ -z "$(jj diff --from main --to @ --summary)" ]; then
        echo "chezmoi-sync: nothing to sync"
        exit 0
      fi
      jj describe -m "auto-sync from $(hostname -s)"
      jj bookmark move main --to @
      jj git push --remote origin --bookmark main
      jj new
    '')
  ];
}
