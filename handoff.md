# handoff: env sync + tangled migration (2026-08-28)

state after this session: dotfiles live on tangled (public, history scrubbed,
api keys age-encrypted), nix repo lives on tangled with a github mirror,
bigchungus self-converges (hourly `chezmoi update --force` user timer, nightly
`system.autoUpgrade` from `git+https://tangled.org/tymek.me/nix`). toolchain
is unified on mise for both boxes (node 24 + corepack pnpm verified on
bigchungus).

## todo

- [ ] codeberg still has the pre-scrub dotfiles history (contains the old
      context7/brave keys; repo is private). either leave it frozen as a
      backup or align it:
      `git -C ~/.local/share/chezmoi push --force codeberg main`
- [ ] optionally rotate the context7 and brave api keys. they never hit a
      public host, but they sat in a private repo, local backups, and one
      claude session transcript.
- [ ] delete the local pre-scrub backups once confident:
      `~/dotfiles-pre-scrub.bundle` and `~/.local/share/chezmoi.pre-scrub`
- [ ] run `switchd` on bigboi when on real wifi. this activates: mise via
      home-manager (was already active), the `chezmoi-sync` script, and the
      daily fish hook that auto-captures and pushes dotfile drift. until
      then, sync dotfiles manually:
      `chezmoi re-add --exclude templates,encrypted`, then jj commit + push
      in `~/.local/share/chezmoi`.
- [ ] decide the `.pi/agent/CLAUDE.md` merge. the bigchungus copy had a
      better "ask before rebuild/switch" section than the mac copy, and the
      hourly timer clobbers bigchungus with the mac version. to merge, swap
      the mac file's "Never Run System Rebuilds" section for this and re-add:

      ## CRITICAL: Never Run System-Rebuild/Switch Commands Without Explicit Approval

      **NEVER** run privileged or disruptive system configuration commands
      without explicit user approval first, including but not limited to:

      1. `sudo nixos-rebuild switch ...`
      2. `sudo nixos-rebuild boot ...`
      3. `sudo nixos-rebuild test ...`
      4. `sudo darwin-rebuild switch ...`
      5. Any command that can restart services/networking or change the live
         system state

      Before running such commands, show the exact command and explicitly
      ask: "Should I proceed with this command?"

## later / nice to have

- [ ] make slurp a proper flake input (it can live on tangled) so evals stop
      needing `--impure`; this also unblocks a spindle ci workflow that
      eval-gates main before bigchungus's nightly auto-upgrade pulls it
- [ ] pin more mise majors (go, rust) so both boxes resolve identical
      versions instead of "latest" at install time
- [ ] exchange-service-2 on bigchungus: clone under `~/Repos/tokentax` to
      mirror the mac layout, `pnpm install`, run long tests in zellij; pnpm
      resolves itself via corepack from the repo's `packageManager` pin
