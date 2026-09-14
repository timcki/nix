# AGENTS.md

Tim's Nix configuration for all personal systems: two macOS machines via
nix-darwin and one NixOS server, all sharing a single home-manager config.

The canonical remote is **tangled** (`origin`); GitHub is a push mirror. The
repo is **public**: never commit plaintext secrets (see [Secrets](#secrets)).

## Repository Structure

```
.
├── flake.nix              # entry point - defines all system configurations
├── flake.lock
├── mise.toml              # repo-local mise tools
├── modules/
│   ├── darwin.nix         # shared macOS system config (incl. shared homebrew)
│   ├── nixos.nix          # shared NixOS system config
│   ├── home.nix           # shared home-manager config (both platforms)
│   ├── packages.nix       # common home packages + chezmoi-sync script
│   ├── machines/
│   │   ├── bigboi.nix     # macOS workstation (aarch64-darwin)
│   │   ├── small.nix      # macOS laptop (aarch64-darwin)
│   │   ├── bigchungus.nix # NixOS server (x86_64-linux)
│   │   └── bigchungus-hardware.nix
│   ├── programs/          # per-program config, shared across platforms
│   │   ├── fish.nix       # fish shell, abbreviations, platform blocks inline
│   │   ├── starship.nix   # starship prompt
│   │   ├── development.nix # jj, git, delta, zoxide
│   │   ├── gh.nix         # GitHub CLI
│   │   ├── ghostty/config # ghostty config, linked on darwin only
│   │   └── zed/           # zed settings/keymap (currently not linked)
│   └── services/          # NixOS service modules, bigchungus only
│       ├── slurp.nix      # RSS reader (flake input)
│       ├── filmnight.nix  # film night app (flake input)
│       ├── arr-stack.nix  # media stack behind a Mullvad wireguard netns
│       └── samba.nix      # tailscale-only file shares
├── secrets/               # agenix-encrypted secrets + recipients
├── config/slurp/          # non-secret app config checked into the repo
└── docs/                  # long-form notes
```

## Machines

| Machine     | OS     | Architecture   | Description |
|-------------|--------|----------------|-------------|
| bigboi      | macOS  | aarch64-darwin | Primary workstation; extra homebrew (gcloud-cli, steam, graphviz, linear) |
| small       | macOS  | aarch64-darwin | Laptop; shared config only, no machine-specific packages |
| bigchungus  | NixOS  | x86_64-linux   | Headless server: ZFS, Tailscale, Caddy, Docker (Rocket Pool), goatcounter, slurp, filmnight, arr-stack, samba |

## Flake Inputs

- `nixpkgs`: nixos/nixpkgs `nixpkgs-unstable`
- `nix-darwin`, `home-manager` (master, to track unstable), both `follows` nixpkgs
- `filmnight`, `slurp`: own apps, fetched over anonymous https from tangled
  knots so root can evaluate them unattended
- `agenix`: secret management

**The tree must stay pure-evaluable.** bigchungus evaluates this flake as root
on a timer, so nothing may depend on a path in `/home/tim` or on `--impure`.

## Toolchain Split

- **nix** owns the stable base: shells, editors, CLI utilities, language servers.
- **mise** owns fast-moving toolchains (including `claude-code`). Versions live
  in the chezmoi-managed `~/.config/mise/config.toml`, so bumps need no rebuild.
- **homebrew** (macOS only) owns GUI apps and anything not in nixpkgs.
- Note `fish`, `starship`, `gh`, `git`, `jujutsu`, and `zoxide` are installed by
  their `programs.*` modules, not by `packages.nix`.

## Dotfiles

Dotfiles live in a separate chezmoi repo, not here.

- The macs are the **source of truth**: the fish hook in `programs/fish.nix`
  runs `chezmoi-sync` (defined in `packages.nix`) daily to capture drift and push.
- bigchungus is the **consume side**: a user timer in `home.nix` runs
  `chezmoi update --force` hourly, so it can never drift behind.

## Auto-Upgrade

bigchungus runs `system.autoUpgrade` nightly at 04:30 (+ up to 10 min jitter),
building `git+https://tangled.org/tymek.me/nix`, so **pushing to `main` deploys
the server**. `allowReboot = false` because the box runs a staking node; kernel
changes need a manual reboot. Don't set `autoUpgrade.flags` for `--refresh` or
`--flake`; the NixOS module already passes both.

`flags` does carry `--override-input filmnight`, and `switchn` on bigchungus
passes the same list from the same `let` binding in
`modules/machines/bigchungus.nix`. Keep it that way. They were two things once:
`switchn` built `~/.config/nix` while the upgrade built what was pushed, so a
`nix flake update filmnight` that stayed in the working copy deployed until
04:30 and then silently reverted, and film night served a fortnight-old commit.
Anything that makes the two invocations differ again brings that back.

Film night is therefore not pinned in `flake.lock`; it follows its own `main`,
gated by its own build, which runs its acceptance suite and type check. To pin
it deliberately for a rollback, drop the flag and bump the lock as usual.

## Failures

Units that matter carry `onFailure = [ "unit-failure@%n.service" ]`.
`modules/services/unit-failure.nix` is the only place that knows how a failure
is delivered: it records one to a spool and the fish greeting prints anything
outstanding at login. Add a push notification there and nowhere else.
`unit-failures` reports, `unit-failures --clear` empties the spool.

`system.configurationRevision` is `self.rev`, or `"dirty"` when the system came
from a working copy, which is what `nixos-version --configuration-revision`
reports and what the login greeting warns about.

## Usage

```bash
# rebuild macOS (abbreviation: switchd)
sudo darwin-rebuild switch --flake ~/.config/nix

# rebuild NixOS, on bigchungus: builds the pushed config, same flags as 04:30
switchn

# the same, from the working copy; reverted at 04:30, and it says so
switchn-local

# validate before committing
nix flake check

# update flake inputs
nix flake update
```

### Remote Amp runner

Use `amp-stage <name> [revision]` from an exchange-service-2 jj workspace to
transfer that exact revision and its ancestor stack to a new isolated runner on
bigchungus. See [docs/amp-runner.md](docs/amp-runner.md) for the workflow and
server environment.

## Secrets

Encrypted with agenix; recipients are tim's SSH key and the bigchungus host key
so the box can decrypt at activation.

```bash
cd secrets
nix run github:ryantm/agenix -- -e mullvad-wg-key.age
```

## Guidelines for AI Agents

1. **Version control**: this repo uses **jujutsu (jj)**, not git. `origin` is
   tangled; GitHub is a mirror. Pushing `main` deploys bigchungus.

2. **Validate before committing**: `nix flake check`. Never reach for `--impure`
   to make an evaluation succeed; fix the impurity instead.

3. **Adding packages**: common home packages go in `modules/packages.nix`.
   Machine-specific additions go in the relevant `modules/machines/*.nix`.
   Fast-moving toolchains belong in mise, not here.

4. **Platform-specific config**: there are no `programs/darwin/` or
   `programs/nixos/` directories. Shared modules branch inline on
   `pkgs.stdenv.isDarwin` / `isLinux`, usually via `lib.optionalAttrs`.

5. **Home-manager vs system**: user-level config goes in `home.nix` or
   `programs/`. System-level goes in `darwin.nix` / `nixos.nix`, or in
   `services/` for bigchungus services.

6. **Homebrew (macOS only)**: shared taps/casks/brews live in `darwin.nix`;
   per-machine ones in the machine file. Use it for apps not in nixpkgs.

7. **The repo is public**: no plaintext secrets, tokens, or keys. Anything
   sensitive goes through agenix.
