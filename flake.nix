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

            shell = pkgs.fish;
        };

        environment.systemPackages = with pkgs; [
          alacritty
          nushell

          # jankyborders

          yabai
          skhd

        ];

        programs = {
            fish.enable = true;
            zsh.enable = true;
        };

        services = {
          yabai = {
            enable = true;
            package = pkgs.yabai;
            enableScriptingAddition = true;
            config = {
              focus_follows_mouse          = "autoraise";
              mouse_follows_focus          = "off";
              window_placement             = "second_child";
              window_opacity               = "off";
              window_opacity_duration      = "0.0";
              window_topmost               = "on";
              window_shadow                = "float";
              active_window_opacity        = "1.0";
              normal_window_opacity        = "0.99";
              split_ratio                  = "0.61805";
              auto_balance                 = "on";
              mouse_modifier               = "fn";
              mouse_action1                = "move";
              mouse_action2                = "resize";
              layout                       = "bsp";
              top_padding                  = 8;
              bottom_padding               = 8;
              left_padding                 = 8;
              right_padding                = 8;
              window_gap                   = 8;
            };

            extraConfig = ''
                # rules
                yabai -m rule --add label="Finder" app="^Finder$" title="(Co(py|nnect)|Move|Info|Pref)" manage=off
                yabai -m rule --add label="Safari" app="^Safari$" title="^(General|(Tab|Password|Website|Extension)s|AutoFill|Se(arch|curity)|Privacy|Advance)$" manage=off
                yabai -m rule --add label="macfeh" app="^macfeh$" manage=off
                yabai -m rule --add label="System Preferences" app="^System Preferences$" title=".*" manage=off
                yabai -m rule --add label="App Store" app="^App Store$" manage=off
                yabai -m rule --add label="Activity Monitor" app="^Activity Monitor$" manage=off
                yabai -m rule --add label="Strongbox Pro" app="^Strongbox Pro$" manage=off
                yabai -m rule --add label="Calculator" app="^Calculator$" manage=off
                yabai -m rule --add label="Dictionary" app="^Dictionary$" manage=off
                yabai -m rule --add label="Software Update" title="Software Update" manage=off
                yabai -m rule --add label="About This Mac" app="System Information" title="About This Mac" manage=off

                # Any other arbitrary config here
                # borders active_color=0xe0808080 inactive_color=0x00010101 width=4.0 &
              '';
          };

          skhd = {
            enable = true;
            package = pkgs.skhd;
          };
        };


        homebrew = {
            enable = true;
            onActivation.cleanup = "uninstall";

            casks = [ "rectangle" "zed" "discord" "bruno" "vscodium" "neovide" "vimr" ];
        };
    };

    bigboi-configuration = { pkgs, ... }: {
        homebrew = {
            taps = [ "FelixKratz/formulae" ];
            brews = [ "hyper-focus" "pam-reattach" "borders" ];
        };
    };

    small-configuration = { pkgs, ... }: {
        homebrew = {
            taps = [ "FelixKratz/formulae" ];
            brews = [ "pam-reattach" "borders" ];
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
            starship

            helix
            neovim

            yabai
            skhd

            bat
            eza
            fzf
            git

            go
            gopls
            python3
            rustup

            nodejs-slim

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

        programs = {
            nushell = {
                enable = true;

                configFile.source = ./config.nu;

                envFile.source = ./env.nu;
                extraEnv = nixpkgs.lib.optionalString (osConfig ? environment) ''
                    $env.PATH = ${
                      builtins.replaceStrings
                      [ "$USER" "$HOME" ]
                      [ config.home.username config.home.homeDirectory ]
                      osConfig.environment.systemPath
                    }

                    $env.PATH = ($env.PATH |
                        split row (char esep) |
                        prepend "/usr/local/bin" |
                        prepend "/opt/homebrew/bin" |
                        append ($env.CARGO_HOME | path join "bin") |
                        append ($env.HOME | path join ".local" "bin") |
                        append ($env.HOME | path join "go" "bin")
                    )
                    $env.PATH = ($env.PATH | uniq)

                    zoxide init nushell | save -f ~/.zoxide.nu
                '';

                shellAliases = {
                    switch = "darwin-rebuild switch --flake ~/.config/nix";

                    vi = "hx";
                    vim = "hx";
                    nano = "hx";

                    vm = "vimr --cur-env";

                    cat = "bat";

                    # git
                    gs = "git status";

                    # jujutsu
                    je = "jj edit";
                    jd = "jj desc";
                    jn = "jj next";
                    jp = "jj prev";

                    # misc
                    dc = "docker compose";
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
                    format = "$directory$sudo$jj_status$character";

                    character.success_symbol = "[➜](bold green)";
                    character.error_symbol = "[➜](bold red)";
                    character.vimcmd_symbol = "[←](bold green)";
                    character.vimcmd_visual_symbol = "[←](bold green)";

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
