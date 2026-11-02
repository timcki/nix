{ config, pkgs, lib, ... }:

let
  # opens drafts and server files from tailnet servers in the local zed, see
  # https://github.com/timcki/laptop-portal. bigboi only: it joins the
  # tailnet as its own node `edit-agent`, so one machine runs it
  laptopPortalAgent = pkgs.buildGoModule {
    pname = "laptop-portal-agent";
    version = "0-unstable-2026-10-21";
    src = pkgs.fetchFromGitHub {
      owner = "timcki";
      repo = "laptop-portal";
      rev = "de95fe345ca5c4d34c90761a1d1647020a442b73";
      hash = "sha256-DjKSeklgthGHWtts0C3HDGQrdMS14uxDQ+WQrwM5+lM=";
    };
    modRoot = "agent";
    vendorHash = "sha256-+DZ0mMO2TtSiAfthcMCt0xtLatEvOvTNi+OZR9bLAKE=";
    # go names the binary after the module's last path element
    postInstall = "mv $out/bin/agent $out/bin/laptop-portal-agent";
    meta.mainProgram = "laptop-portal-agent";
  };
in
{
  homebrew = {
    taps = [ "nikitabobko/tap" ];
    casks = [ "gcloud-cli" "steam" ];
    brews = [ "graphviz" ]; # linear moved to mise
  };

  # node state stays in ~/Library/Application Support/edit-proposed-text-agent
  # (its pre-rename name), so a rebuild or a new rev needs no tailnet login
  launchd.user.agents.laptop-portal-agent.serviceConfig = {
    ProgramArguments = [ (lib.getExe laptopPortalAgent) ];
    RunAtLoad = true;
    KeepAlive = true;
    ProcessType = "Interactive";
    StandardOutPath = "/Users/tim/Library/Logs/laptop-portal-agent.log";
    StandardErrorPath = "/Users/tim/Library/Logs/laptop-portal-agent.log";
  };
}
