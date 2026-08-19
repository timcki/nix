#!/usr/bin/env bash
# macOS major-upgrade recovery for this Nix / nix-darwin setup.
# Run AFTER upgrading (e.g. to macOS 27 Golden Gate) if `nix` disappears.
# Safe to run repeatedly; it diagnoses first, then repairs only what's broken.
#
#   bash ~/.config/nix/macos-upgrade-recovery.sh
#
# Written for host `bigboi` (darwinConfigurations.bigboi). Determinate
# nix-installer lives at /nix/nix-installer.

set -uo pipefail

INSTALLER=/nix/nix-installer
FLAKE="$HOME/.config/nix#bigboi"
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }

bold "== 1. Diagnostics =="

# is the /nix APFS volume actually mounted?
if mount | grep -q ' /nix '; then
  ok "/nix volume is mounted"
  NIX_MOUNTED=1
else
  bad "/nix volume is NOT mounted (data is safe, just not attached)"
  NIX_MOUNTED=0
fi

# can we reach the nix binary?
if [ -x /nix/var/nix/profiles/default/bin/nix ] && \
   /nix/var/nix/profiles/default/bin/nix --version >/dev/null 2>&1; then
  ok "nix binary reachable: $(/nix/var/nix/profiles/default/bin/nix --version)"
else
  bad "nix binary not reachable"
fi

# are the launch daemons loaded?
for d in org.nixos.nix-daemon org.nixos.darwin-store org.nixos.activate-system; do
  if sudo launchctl print system/"$d" >/dev/null 2>&1; then
    ok "$d loaded"
  else
    bad "$d NOT loaded"
  fi
done

# BTM: the #1 post-upgrade culprit. This only REPORTS; enabling is a GUI step.
bold "== 2. Background Task Management (BTM) check =="
BTM=$(sudo sfltool dumpbtm 2>/dev/null | grep -iA6 -E "nixos|darwin-store")
if echo "$BTM" | grep -qi "disallowed"; then
  bad "BTM has DISABLED the Nix daemons. This survives reboots and must be"
  echo "     re-enabled by hand (Apple offers no CLI for it):"
  echo
  echo "       System Settings → General → Login Items & Extensions"
  echo "         → 'Allow in the Background'"
  echo "         → toggle the two 'sh' / 'unidentified developer' items ON"
  echo "       then reboot and re-run this script."
  echo
  echo "$BTM" | sed 's/^/     /'
elif [ -n "$BTM" ]; then
  ok "BTM entries present and not disallowed"
else
  warn "no BTM entries found for nix (may be fine, or daemons not yet registered)"
fi

bold "== 3. Repairs =="

# remount the volume if the upgrade left it detached
if [ "$NIX_MOUNTED" -eq 0 ]; then
  warn "attempting to mount /nix and (re)bootstrap darwin-store…"
  sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.darwin-store.plist 2>/dev/null
  sudo launchctl kickstart -k system/org.nixos.darwin-store 2>/dev/null
  mount | grep -q ' /nix ' && ok "/nix mounted" || bad "/nix still not mounted — see BTM step above, then reboot"
fi

# re-add shell hooks the OS upgrade wiped from /etc/{zshenv,bashrc,…}
if [ -x "$INSTALLER" ]; then
  bold "  restoring shell hooks (nix-installer repair hooks)…"
  sudo -i "$INSTALLER" repair hooks --no-confirm
  ok "shell hooks repaired"
else
  bad "installer missing at $INSTALLER — cannot auto-repair hooks"
fi

# only offered, not auto-run: fixes _nixbld users if the upgrade reclaimed them.
# harmless if not needed, but it moves users, so make it explicit.
if ! id _nixbld1 >/dev/null 2>&1; then
  bad "_nixbld build users are gone — run this, then re-run the script:"
  echo "     sudo -i $INSTALLER repair sequoia --move-existing-users --no-confirm"
else
  ok "_nixbld build users present"
fi

# (re)bootstrap the core daemons in case they were only unloaded
for d in org.nixos.nix-daemon org.nixos.activate-system; do
  sudo launchctl bootstrap system /Library/LaunchDaemons/"$d".plist 2>/dev/null
done

bold "== 4. Rebuild the system =="
if command -v darwin-rebuild >/dev/null 2>&1 || \
   [ -x /run/current-system/sw/bin/darwin-rebuild ]; then
  echo "  running: darwin-rebuild switch --flake $FLAKE"
  sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "$FLAKE"
  ok "rebuild complete"
else
  warn "darwin-rebuild not on PATH yet. Open a NEW shell (so the restored"
  echo "     hooks load), then run:"
  echo "       sudo darwin-rebuild switch --flake $FLAKE"
fi

bold "== Done. If anything above is still red, open a new shell and re-run. =="
