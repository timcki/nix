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

    # send an exact local jj revision to an isolated Amp runner on bigchungus
    (writeShellApplication {
      name = "amp-stage";
      runtimeInputs = [ coreutils gawk git jujutsu openssh ];
      text = ''
        set -euo pipefail

        if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
          echo "usage: amp-stage <name> [revision]" >&2
          exit 2
        fi

        name="$1"
        revision="''${2:-@}"

        if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; then
          echo "amp-stage: name must match [a-z0-9][a-z0-9-]{0,31}" >&2
          exit 2
        fi

        root="$(jj root)"
        origin="$(jj -R "$root" git remote list | awk '$1 == "origin" { print $2 }')"
        case "$origin" in
          git@github.com:TokenTax/exchange-service-2.git|ssh://git@github.com/TokenTax/exchange-service-2.git|https://github.com/TokenTax/exchange-service-2.git)
            ;;
          *)
            echo "amp-stage: only exchange-service-2 is supported, found origin: $origin" >&2
            exit 1
            ;;
        esac

        # jj snapshots the working copy before resolving the selected revision.
        commit="$(jj -R "$root" log --no-graph -r "$revision" -T 'commit_id ++ "\n"')"
        if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
          echo "amp-stage: revision must resolve to exactly one Git commit" >&2
          exit 1
        fi

        echo "sending $revision ($commit) to bigchungus"
        git -C "$root" push \
          ssh://amp@bigchungus/home/amp/Sync/exchange-service-2.git \
          "$commit:refs/heads/snapshots/$commit"

        # shellcheck disable=SC2029
        ssh bigchungus sudo amp-stage-server "$name" "$commit"
      '';
    })

    # Media
    ffmpeg
    exiftool

    # capture local dotfile drift into chezmoi and push it; the fish hook in
    # programs/fish.nix runs this daily on the mac, and it can be run by hand
    (writeShellScriptBin "chezmoi-sync" ''
      set -eu
      # templates and encrypted files must never be captured back from the
      # live filesystem: re-add would flatten them to plaintext, and the
      # repo is public on tangled
      chezmoi re-add --exclude templates,encrypted
      cd ~/.local/share/chezmoi
      # belt and suspenders: refuse to push if anything resembling a secret
      # shows up outside the age blob
      if grep -rElq "ctx7sk-|BSAU1|sk-ant-|AKIA[0-9A-Z]{16}|BEGIN.*PRIVATE KEY|ghp_[A-Za-z0-9]{30}" \
          --exclude-dir=.git --exclude-dir=.jj --exclude="*.age" .; then
        echo "chezmoi-sync: possible plaintext secret in source, refusing to push" >&2
        exit 1
      fi
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
