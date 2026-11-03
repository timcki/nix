{
  config,
  pkgs,
  lib,
  ...
}:

let
  refreshTrackpadGestures = pkgs.runCommandCC "refresh-trackpad-gestures" { } ''
    mkdir -p $out/bin
    cat > refresh-trackpad-gestures.m <<'EOF'
    #import <Foundation/Foundation.h>
    #import <dlfcn.h>

    @interface MTTGestureBackEnd : NSObject
    + (instancetype)sharedInstance;
    - (long long)threeFingerVertSwipe;
    - (void)setThreeFingerVertSwipe:(long long)value;
    @end

    int main(void) {
      if (!dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport", RTLD_NOW)) {
        return 1;
      }

      MTTGestureBackEnd *backend = [NSClassFromString(@"MTTGestureBackEnd") sharedInstance];
      if (!backend) {
        return 1;
      }

      long long original = [backend threeFingerVertSwipe];
      [backend setThreeFingerVertSwipe:0];
      [NSThread sleepForTimeInterval:0.25];
      [backend setThreeFingerVertSwipe:original];
      return 0;
    }
    EOF
    $CC -fobjc-arc -framework Foundation refresh-trackpad-gestures.m \
      -o $out/bin/refresh-trackpad-gestures
  '';
in
{
  nix.enable = true;

  # nix-darwin master lags nixpkgs-unstable; its manual builder calls the
  # removed --toc-depth flag, breaking darwin-manual-html. skip the offline docs.
  documentation.enable = false;

  # the uninstaller evaluates its own embedded darwin-system with docs enabled,
  # which hits the same --toc-depth failure; drop it until nix-darwin catches up.
  system.tools.darwin-uninstaller.enable = false;

  # Enable sudo with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Nix configuration
  ids.gids.nixbld = 350;
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    interval = {
      Day = 3;
    };
    options = "--delete-older-than 3d";
  };

  # macOS system defaults
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "bottom";
      showAppExposeGestureEnabled = true;
      showMissionControlGestureEnabled = true;
      show-recents = false;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv"; # Column view
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    NSGlobalDomain = {
      AppleKeyboardUIMode = 3; # Full keyboard access
      AppleShowScrollBars = "WhenScrolling";
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
    };

    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
      TrackpadThreeFingerVertSwipeGesture = 2;
    };
  };

  # toggle the gesture backend after login so it reloads vertical swipes
  launchd.user.agents.refresh-trackpad-gestures = {
    script = ''
      until /usr/bin/pgrep -x Dock >/dev/null; do
        /bin/sleep 1
      done
      /bin/sleep 3
      ${refreshTrackpadGestures}/bin/refresh-trackpad-gestures
    '';
    serviceConfig.RunAtLoad = true;
  };

  system.configurationRevision = null;
  system.stateVersion = 4;
  system.primaryUser = "tim";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # User configuration
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

    # Shared homebrew packages for all machines
    taps = [ "ampcode/tap" ];

    casks = [
      "zed@preview"
      "discord"
      "rectangle"
      "ghostty"
      "codex"
      "tailscale-app"
    ];

    # amp only: every published version carries a `-g<sha>` prerelease suffix,
    # so mise cannot resolve `latest` for it; pup moved to mise
    brews = [ "ampcode/tap/ampcode" ];
  };
}
