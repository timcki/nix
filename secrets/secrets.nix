# agenix recipients. edit secrets with:
#   nix run github:ryantm/agenix -- -e <name>.age
# run from this directory; agenix reads this file to decide who can decrypt.
# agenix falls back to ~/.ssh/id_ed25519 automatically, so no -i needed.
let
  # tim's ssh key, doubles as the agenix admin identity
  tim = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDI2dfsVzngdYLmJ3T0StS3eI3IzLMlAi7XOfqt1uVBe";

  # bigchungus ssh host key, so the box can decrypt at activation
  bigchungus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBudOtXgq40HcClO+if/ok3mTMsdZWaohFijwizkK6rH";

  all = [ tim bigchungus ];
in
{
  "mullvad-wg-key.age".publicKeys = all;
}
