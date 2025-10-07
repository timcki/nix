{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs = {
    zoxide.enable = true;

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
          pager = "less -RFX";
          merge-editor = ":builtin";
        };
        revsets = {
          log = "(trunk()..@):: | (trunk()..@)-";
        };
        signing = {
          behavior = "own";
          backend = "ssh";
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3zNKM+CpNS5isd8MkCbPy6qTYbPlbVeyqm3hG5FYww";
          backends.ssh.allowed-signers = "/Users/tim/.ssh/git_allowed_signers";
          backends.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
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
            "--allow-new"
          ];
          r = [ "rebase" ];
          s = [ "squash" ];
          si = [
            "squash"
            "--interactive"
          ];
        };
        "revset-aliases" = {
          "closest_bookmark(to)" = "heads(::to & bookmarks())";
          "immutable_heads()" = "builtin_immutable_heads() & remote_bookmarks()";
          "recent()" = "committer_date(after:\"3 months ago\")";
        };
        git = {
          push-new-bookmarks = true;
        };
        snapshot = {
          max-new-file-size = "10MiB";
        };
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
          signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3zNKM+CpNS5isd8MkCbPy6qTYbPlbVeyqm3hG5FYww";
        };
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        credential.helper = "osxkeychain";
        commit.gpgsign = true;
        gpg.format = "ssh";
        merge.conflictstyle = "diff3";
        diff.colormoved = "default";
      };
    };
  };
}
