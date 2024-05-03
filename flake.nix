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
       services.nix-daemon.enable = true;
        # enable sudo with touchid
        security.pam.enableSudoTouchIdAuth = true;

        # necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

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
            onActivation.cleanup = "uninstall";

            taps = [ "FelixKratz/formulae" "nikitabobko/tap" "dotenvx/brew"];
            casks = [ "zed@preview" "discord" "vimr" "1password@nightly" "1password-cli@beta" "jordanbaird-ice" "rectangle"];
        };
    };

    bigboi-configuration = { pkgs, nix-darwin, home-manager, ... }: {
        homebrew = {
            brews = [ "hyper-focus" "k9s" "yarn" "dotenvx/brew/dotenvx" "cargo-binstall"];
        };
    };

    small-configuration = { pkgs, nix-darwin, home-manager, ... }: {
        homebrew = {
            brews = [ "k9s" "yarn" "cargo-binstall"];
        };
    };

    homeconfig = { pkgs, osConfig, config, ... }: {
        # this is internal compatibility configuration
        # for home-manager, don't change this!
        home.stateVersion = "23.05";
        # let home-manager install and manage itself.
        programs.home-manager.enable = true;

        home.packages = with pkgs; [
            fish
            starship

            helix
            neovim

            bat
            eza
            fzf
            git

            go
            gopls
            python3
            rustup

            nodejs-slim

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
        };

        home.file = {
            ".config/ghostty/config".source = ./ghostty.config;
        };

        programs = {
            # nushell = {
            #     enable = true;

            #     configFile.source = ./config.nu;

            #     envFile.source = ./env.nu;
            #     extraEnv = nixpkgs.lib.optionalString (osConfig ? environment) ''
            #         $env.PATH = ${
            #           builtins.replaceStrings
            #           [ "$USER" "$HOME" ]
            #           [ config.home.username config.home.homeDirectory ]
            #           osConfig.environment.systemPath
            #         }

            #         $env.PATH = ($env.PATH |
            #             split row (char esep) |
            #             prepend "/usr/local/bin" |
            #             prepend "/opt/homebrew/bin" |
            #             append ($env.CARGO_HOME | path join "bin") |
            #             append ($env.HOME | path join ".local" "bin") |
            #             append ($env.HOME | path join "go" "bin")
            #         )
            #         $env.PATH = ($env.PATH | uniq)

            #         zoxide init nushell | save -f ~/.zoxide.nu
            #     '';

            #     shellAliases = {
            #         switch = "darwin-rebuild switch --flake ~/.config/nix";

            #         vi = "hx";
            #         vim = "hx";
            #         nano = "hx";

            #         vm = "vimr --cur-env";

            #         cat = "bat";

            #         # git
            #         gs = "git status";

            #         # jujutsu
            #         je = "jj edit";
            #         jd = "jj desc";
            #         jn = "jj next";
            #         jp = "jj prev";

            #         # misc
            #         dc = "docker compose";
            #     };

            # };

            carapace = {
                enable = true;
                enableNushellIntegration = true;
            };

            starship = {
                enable = true;
                settings = {
                    add_newline = false;
                    format = "$directory$sudo$jj_status$character";

                    character.success_symbol = "[➜](bold green)";
                    character.error_symbol = "[➜](bold red)";
                    character.vimcmd_symbol = "[←](bold green)";
                    character.vimcmd_visual_symbol = "[←](bold green)";

                    line_break.disabled = true;
                    jj_status.symbol = "";
                    jj_status.no_description_symbol = " ✎";
                };
            };

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
                    home-manager.darwinModules.home-manager {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.verbose = true;
                        home-manager.users.tim = homeconfig;
                    }
                ];
            };

            small = nix-darwin.lib.darwinSystem {
                modules = [
                    shared-configuration
                    small-configuration
                    home-manager.darwinModules.home-manager {
                        home-manager.useGlobalPkgs = true;
                        home-manager.useUserPackages = true;
                        home-manager.verbose = true;
                        home-manager.users.tim = homeconfig;
                    }
                ];
            };
        };
    };

}
