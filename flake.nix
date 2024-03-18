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
    shared-configuration = { pkgs, ... }: {
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

            shell = pkgs.nushell;
        };

        programs = {
            fish.enable = true;
        };

        environment.systemPackages = [ pkgs.alacritty pkgs.nushell ];

        homebrew = {
            enable = true;
            onActivation.cleanup = "uninstall";

            casks = [ "rectangle" "zed" "discord" ];
        };
    };

    bigboi-configuration = { pkgs, ... }: {
        homebrew = {
            taps = [ ];
            brews = [ "hyper-focus" ];
        };
    };

    small-configuration = { pkgs, ... }: {
        homebrew = {
            taps = [ ];
            brews = [ ];
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
            nushell
            helix
            bat
            eza
            fzf
            git
            go
            jq
            ripgrep
            starship
            tmux
            zoxide
            carapace
            jujutsu
        ];

        home.sessionVariables = { editor = "hx"; };

        programs = {
            nushell = {
                enable = true;
                configFile.source = ./config.nu;
                extraConfig = ''
                    $env.PATH = (
                        $env.PATH |
                        split row (char esep) |
                        prepend /usr/local/bin |
                        append /usr/bin/env
                    )
                '';
                envFile.text = nixpkgs.lib.optionalString (osConfig ? environment) ''
                    $env.PATH = ${builtins.replaceStrings
                    [ "$USER" "$HOME" ]
                    [ config.home.username config.home.homeDirectory ]
                    osConfig.environment.systemPath}
                '';
                
                shellAliases = {
                    vi = "hx";
                    vim = "hx";
                    nano = "hx";

                    switch = "darwin-rebuild switch --flake ~/.config/nix";

                    cat = "bat";

                    gs = "git status";
                };

            };

            carapace = {
                enable = true;
                enableNushellIntegration = true;
            };

            starship = {
                enable = true;
                settings = {
                    add_newline = false;
                    format = "$directory $jj_status $sudo";

                    line_break.disabled = true;
                    jj_status.symbol = "";
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
