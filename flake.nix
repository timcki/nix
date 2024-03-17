
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
configuration = { pkgs, ... }: {

services.nix-daemon.enable = true;
# enable sudo with touchid
security.pam.enablesudotouchidauth = true;

# necessary for using flakes on this system.
nix.settings.experimental-features = "nix-command flakes";

system.configurationrevision = self.rev or self.dirtyrev or null;

# used for backwards compatibility. please read the changelog
# before changing: `darwin-rebuild changelog`.
system.stateversion = 4;

# the platform the configuration will be used on.
nixpkgs.hostplatform = "aarch64-darwin";

# declare the user that will be running `nix-darwin`.
users.users.tim = {
    name = "tim";
    home = "/users/tim";

    shell = pkgs.nushell;
};

programs.fish.enable = true;

environment.systempackages = [
    pkgs.neofetch
    pkgs.alacritty
];

homebrew = {
    enable = true;
    onactivation.cleanup = "uninstall";

    taps = [ ];
    brews = [ "hyper-focus" ];
    casks = [ "rectangle" ];
};

};
homeconfig = { pkgs, ... }: {
# this is internal compatibility configuration
# for home-manager, don't change this!
home.stateversion = "23.05";
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
];

home.sessionvariables = { editor = "hx"; };

programs = {

    nushell = {
    enable = true;
    extraconfig = ''
        let carapace_completer = {|spans|
            carapace $spans.0 nushell $spans | from json
        }
        $env.config = {
            edit_mode: vi,
            show_banner: false,
            completions: {
            case_sensitive: false # case-sensitive completions
            quick: true    # set to false to prevent auto-selecting completions
            partial: true    # set to false to prevent partial filling of the prompt
            algorithm: "fuzzy"    # prefix or fuzzy
            external: {
                # set to false to prevent nushell looking into $env.path to find more suggestions
                enable: true
                # set to lower can improve completion performance at the cost of omitting some options
                max_results: 100
                completer: $carapace_completer # check 'carapace_completer'
                }
            }
        }
        $env.path = (
            $env.path |
            split row (char esep) |
        prepend /usr/local/bin |
        append /usr/bin/env
        )
    '';
    shellaliases = {
        vi = "hx";
        vim = "hx";
        nano = "hx";

        cat = "bat";
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
};
};
in {
darwinconfigurations.bigboi = nix-darwin.lib.darwinsystem {
modules = [
    configuration
    home-manager.darwinmodules.home-manager
    {
    home-manager.useglobalpkgs = true;
    home-manager.useuserpackages = true;
    home-manager.verbose = true;
    home-manager.users.tim = homeconfig;
    }
];
};
};
}
