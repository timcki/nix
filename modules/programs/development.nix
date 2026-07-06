{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  # per-machine ssh signing keys: bigboi vs server
  signingKey =
    if isDarwin then
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3zNKM+CpNS5isd8MkCbPy6qTYbPlbVeyqm3hG5FYww"
    else
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICBhciZJdPz1Kq8li2Hs5JLgD4lnhlAtu+0mX65swXpN";
in
{
  programs = {
    zoxide.enable = true;

    # linux only: darwin's ssh config is hand-managed with the strongbox agent
    ssh = lib.mkIf isLinux {
      enable = true;
      enableDefaultConfig = false;
      settings."*".AddKeysToAgent = "yes";
    };

    jujutsu = {
      enable = true;
      settings = {
        user = {
          name = "Tim Chmielecki";
          email = "me@timcki.com";
        };
        "template-aliases" = {
          "format_timestamp(timestamp)" = "timestamp.ago()";
        };
        templates = {
          draft_commit_description = ''
            concat(
              coalesce(description, default_commit_description, "\n"),
              surround(
                "\nJJ: This commit contains the following changes:\n", "",
                indent("JJ:     ", diff.stat(72)),
              ),
              "\nJJ: ignore-rest\n",
              diff.git(),
            )
          '';
        };
        ui = {
          default-command = "log";
          log-synthetic-elided-nodes = true;
          show-cryptographic-signatures = true;
          pager = "less -RFX";
          merge-editor = ":builtin";
        };
        revsets = {
          log = "(trunk()..@):: | (trunk()..@)-";
        };
        signing = {
          behavior = "own";
          backend = "ssh";
          key = signingKey;
          backends.ssh.allowed-signers = "${config.home.homeDirectory}/.ssh/git_allowed_signers";
          backends.ssh.program = "ssh-keygen";
        };
        aliases = {
          "log-recent" = [
            "log"
            "-r"
            "default() & recent()"
          ];
          ll = [
            "log"
            "-r"
            "present(@) | ancestors(immutable_heads().., 2) | present(trunk())"
          ];
          diff-trunk = [
            "diff"
            "--from"
            "trunk()"
            "--to"
            "@"
          ];
          tug = [
            "bookmark"
            "move"
            "--from"
            "closest_bookmark(@-)"
            "--to"
            "@-"
          ];
          c = [ "commit" ];
          ci = [
            "commit"
            "--interactive"
          ];
          e = [ "edit" ];
          i = [
            "git"
            "init"
            "--colocate"
          ];
          nb = [
            "bookmark"
            "create"
            "-r"
            "@-"
          ];
          pull = [
            "git"
            "fetch"
          ];
          push = [
            "git"
            "push"
          ];
          r = [ "rebase" ];
          s = [ "squash" ];
          si = [
            "squash"
            "--interactive"
          ];
          sdiff = [ "diff" "--tool" "difft" ];
          sshow = [ "show" "--tool" "difft" ];
          slog = [ "log" "-p" "--tool" "difft" ];
          sdiff-trunk = [ "diff" "--from" "trunk()" "--to" "@" "--tool" "difft" ];
        }
        // lib.optionalAttrs isDarwin {
          # diffnav and ksdiff are installed outside nix on macos only
          gdiff = [ "diff" "--config" "ui.pager='diffnav'" ];
          gresolve = [ "resolve" "--tool" "ksdiff" ];
        };
        "revset-aliases" = {
          "closest_bookmark(to)" = "heads(::to & bookmarks())";
          "immutable_heads()" = "builtin_immutable_heads() & remote_bookmarks()";
          "recent()" = "committer_date(after:\"3 months ago\")";
        };
        remotes.origin = {
          auto-track-bookmarks = "glob:*";
        };
        merge-tools = {
          difft = {
            diff-args = [ "--color=always" "$left" "$right" ];
          };
        }
        // lib.optionalAttrs isDarwin {
          ksdiff = {
            program = "ksdiff";
            edit-args = [ "--merge" "$left" "$right" ];
            merge-args = [ "--merge" "$left" "$right" "--base" "$base" "-o" "$output" ];
          };
        };
        snapshot = {
          max-new-file-size = "10MiB";
        };
        diff.git.context = 7;
        diff.color-words.context = 7;
        "--scope" = [
          {
            when.commands = [
              "diff"
              "show"
            ];
            ui = {
              pager = "delta";
              diff-formatter = ":git";
            };
          }
        ];
      };
    };

    git = {
      enable = true;
      ignores = [
        ".DS_Store"
        ".jj"
        ".nova"
        ".zed"
      ];

      settings = {
        user = {
          name = "Tim Chmielecki";
          email = "me@timcki.com";
          signingkey = signingKey;
        };
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        commit.gpgsign = true;
        gpg.format = "ssh";
        merge.conflictstyle = "diff3";
        diff.colormoved = "default";
        delta = {
          "side-by-side" = true;
          "line-numbers" = true;
          navigate = true;
          light = false;
          "syntax-theme" = "base16-256";
          hyperlinks = true;
          "wrap-max-lines" = "unlimited";

          # Better visual separation
          "file-style" = "bold yellow";
          "file-decoration-style" = "yellow box";
          "hunk-header-style" = "file line-number syntax";

          # Improved highlighting
          "minus-style" = "syntax \"#3f0001\"";
          "minus-emph-style" = "syntax \"#900009\"";
          "plus-style" = "syntax \"#002800\"";
          "plus-emph-style" = "syntax \"#007800\"";
        };
      }
      // lib.optionalAttrs isDarwin {
        credential.helper = "osxkeychain";
      };
    };
  };
}
