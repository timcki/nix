{
    description = "tim's system config";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        nix-darwin = {
            url = "github:lnl7/nix-darwin";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
    let
    shared-configuration = { pkgs, nix-darwin, home-manager, ... }: {
        nix.enable = true;
        # enable sudo with touchid
        security.pam.services.sudo_local.touchIdAuth = true;

        # necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

        nix.gc = {
          automatic = true;
          interval = {
              Day = 3;
          };
          options = "--delete-older-than 3d";
        };

        system.configurationRevision = self.rev or self.dirtyrev or null;

        # used for backwards compatibility. please read the changelog
        # before changing: `darwin-rebuild changelog`.
        system.stateVersion = 4;

        # the platform the configuration will be used on.
        nixpkgs.hostPlatform = "aarch64-darwin";

        # declare the user that will be running `nix-darwin`.
        users.users.tim = {
            name = "tim";
            home = "/users/tim";

            shell = pkgs.fish;
        };

        environment.systemPackages = with pkgs; [ pam-reattach ];
        # Hack to make pam-reattach work
        environment.etc."pam.d/sudo_local".text = ''
          # Written by nix-darwin
          auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
          auth       sufficient     pam_tid.so
        '';

        programs = {
            fish.enable = true;
            zsh.enable = true;
        };

        homebrew = {
            enable = true;
            onActivation = {
                autoUpdate = true;
                cleanup = "uninstall";
            };
        };
    };

    bigboi-configuration = { pkgs, nix-darwin, home-manager, ... }: {
        homebrew = {
            taps = [ "nikitabobko/tap" ];
            casks = [ "zed@preview" "discord" "vimr" "1password@nightly" "1password-cli@beta" "jordanbaird-ice" "rectangle" "google-cloud-sdk" "ghostty" ];
            brews = [ "hyper-focus" "k9s" "yarn" "cargo-binstall" "graphviz" "circleci" "dotenvx/brew/dotenvx" "llm" ];
        };
    };

    small-configuration = { pkgs, nix-darwin, home-manager, ... }: {
        homebrew = {
            casks = [ "zed@preview" "discord" "vimr" "1password@nightly" "1password-cli@beta" "jordanbaird-ice" "rectangle" "ghostty" ];
            brews = [ "cargo-binstall" "llm" ];
        };
    };

    homeconfig = { pkgs, osConfig, config, ... }: {
        # this is internal compatibility configuration
        # for home-manager, don't change this!
        home.stateVersion = "23.05";
        # let home-manager install and manage itself.
        programs.home-manager.enable = true;


        home.packages = with pkgs; [
            # ghostty

            fish
            starship
            mods

            helix
            neovim

            nixd
            nil

            bat
            eza
            fzf
            git

            go
            gopls
            (python3.withPackages (ps: [ ps.pip ps.uv ps.pipx ps.duckduckgo-search ]))
            poetry
            rustup
            dbmate

            nodejs

            restish
            jq
            ripgrep
            tmux
            zoxide
            carapace
            jujutsu

            ffmpeg
        ];

        home.sessionVariables = {
            EDITOR = "nvim";
            BAT_PAGER = "less -XRF";
            BAT_THEME = "base16-256";
            FZF_DEFAULT_OPTS = "--height 40% --layout=reverse";
            TERM = "xterm-256color";
            USERNAME = "tim";
            PAGER = "less -RFX";
            HOMEBREW_NO_AUTO_UPDATE = "";

            NPM_CONFIG_PREFIX = "$HOME/.local/state/npm";
            PATH = "$HOME/.local/state/npm/bin:$PATH";
        };

        home.file = {
            ".config/ghostty/config".source = ./ghostty/config;
            ".config/zed/settings.json".source = ./zed/settings.json;
            ".config/zed/keymap.json".source = ./zed/keymap.json;
            ".local/state/npm/.keep".text = "";
        };

        programs = {
            fish = {
                enable = true;
                interactiveShellInit = ''
                      set fish_greeting ""
                      fish_vi_key_bindings

                      bind \cP _fish_ai_codify_or_explain
                      bind -k nul _fish_ai_autocomplete_or_fix


                      if test -z "$ANTHROPIC_API_KEY"
                          set -gx ANTHROPIC_API_KEY (op item get orqobbytrs3q5kgjrh7kk5caca --fields=credential --reveal)
                      end

                      if test -z "$OPENAI_API_KEY"
                          set -gx OPENAI_API_KEY (op item get cfjnlwmstlkg5rc36yadjtgiiy --fields=credential --reveal)
                      end

                      if test -z "$OPEN_ROUTER_API_KEY"
                          set -gx OPEN_ROUTER_API_KEY (op item get ras7stvjo4kzxesjetl5nip6gm --fields=credential --reveal)
                      end


                      if test -n "$ZED_TERM"
                          if test "$ZED_TERM" != "true"
                              if not set -q TMUX
                                  tmux attach -t default; or tmux new -s default
                              end
                          end
                      else
                          if not set -q TMUX
                              tmux attach -t default; or tmux new -s default
                          end
                      end

                      fish_ssh_agent
                    '';
                shellAliases = {
                    switchd = "darwin-rebuild switch --flake ~/.config/nix";
                    vi = "hx";
                    vim = "hx";
                    nano = "hx";
                    cat = "bat";

                    # git
                    gs = "git status";

                    # jujutsu
                    je = "jj edit";
                    jd = "jj desc";
                    jn = "jj next";
                    jp = "jj prev";
                    jb = "jj bookmark";
                    jg = "jj git";

                    # misc
                    dc = "docker compose";
                };
            };
            zoxide.enable = true;
            # carapace = {
            #     enable = true;
            #     enableNushellIntegration = true;
            # };

            starship = {
                enable = true;
                settings = {
                    add_newline = false;
                    format = "$sudo$directory$jj_branch $jj_changeid$character";

                    character.success_symbol = "[→](bold green)";
                    character.error_symbol = "[→](bold red)";
                    character.vimcmd_symbol = "[←](bold yellow)";
                    character.vimcmd_visual_symbol = "[←](bold purple)";


                    line_break.disabled = true;
                    custom = {
                        jj_branch = {
                            when = "jj workspace root --ignore-working-copy";
                            command = ''
                                jj log -r "(immutable_heads()..@):: & bookmarks()" -T 'local_bookmarks.join("\n") ++ "\n"' --no-graph --ignore-working-copy | head -n 1
                            '';
                            style = "yellow";
                        };
                        jj_changeid = {
                          when = "jj workspace root --ignore-working-copy";
                          command = "jj log -T \"change_id.short()\" --no-graph --ignore-working-copy -r @";
                          style = "bright-purple";
                        };
                    };
                };
            };

            # python3 = {
            #     enable = true;
            # };

            git = {
                enable = true;

                userName = "Tim Chmielecki";
                userEmail = "me@timcki.com";
                ignores = [ ".DS_Store" ".jj" ".nova" ".zed" ];

                extraConfig = {
                    init.defaultBranch = "main";
                    push.autoSetupRemote = true;
                    credential.helper = "osxkeychain";
                    user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3zNKM+CpNS5isd8MkCbPy6qTYbPlbVeyqm3hG5FYww";
                    commit.gpgsign = true;
                    gpg.format = "ssh";
                    merge.conflictstyle = "diff3";
                    diff.colormoved = "default";
                };
            };

        };

    };
    in {
        darwinConfigurations = {
            bigboi = nix-darwin.lib.darwinSystem {
                modules = [
                    shared-configuration
                    bigboi-configuration
                    # determinate.darwinModules.default
                    home-manager.darwinModules.home-manager {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.verbose = false;
                        home-manager.backupFileExtension = "bak";
                        home-manager.users.tim = homeconfig;
                    }

                ];
            };

            small = nix-darwin.lib.darwinSystem {
                modules = [
                    shared-configuration
                    small-configuration
                    # determinate.darwinModules.default
                    home-manager.darwinModules.home-manager {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.verbose = false;
                        home-manager.backupFileExtension = "bak";
                        home-manager.users.tim = homeconfig;
                    }
                ];
            };
        };
    };

}
