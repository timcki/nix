# AGENTS.md

This is Tim's Nix configuration for all personal systems, managing both macOS (nix-darwin) and NixOS machines with home-manager.

## Repository Structure

```
.
├── flake.nix              # Main entry point - defines all system configurations
├── modules/
│   ├── darwin.nix         # macOS-specific system configuration
│   ├── nixos.nix          # NixOS-specific system configuration
│   ├── home.nix           # Shared home-manager configuration
│   ├── packages.nix       # Common packages installed on all systems
│   ├── machines/          # Per-machine configurations
│   │   ├── bigboi.nix     # macOS workstation (aarch64-darwin)
│   │   ├── small.nix      # macOS laptop (aarch64-darwin)
│   │   ├── bigchungus.nix # NixOS server (x86_64-linux)
│   │   └── bigchungus-hardware.nix
│   └── programs/          # Program-specific configurations
│       ├── fish.nix       # Fish shell config
│       ├── starship.nix   # Starship prompt
│       ├── development.nix # Dev tools setup
│       ├── gh.nix         # GitHub CLI
│       ├── darwin/        # macOS-only program configs
│       └── nixos/         # NixOS-only program configs
```

## Machines

| Machine     | OS     | Architecture    | Description |
|-------------|--------|-----------------|-------------|
| bigboi      | macOS  | aarch64-darwin  | Primary workstation with extra dev tools (k9s, yarn, gcloud, graphviz) |
| small       | macOS  | aarch64-darwin  | Laptop with minimal config |
| bigchungus  | NixOS  | x86_64-linux    | Linux server with ZFS, Tailscale, SSH |

## Key Tools & Packages

Common across all systems (via `packages.nix`):
- **Shells**: fish, starship, zoxide, carapace
- **Editors**: helix, neovim
- **Dev tools**: claude-code, nixd, nil, rustup, go, python3, nodejs
- **CLI utilities**: bat, eza, fzf, ripgrep, jq, tmux, zellij
- **Version control**: jujutsu (jj), git, gh, delta

## Usage

```bash
# Rebuild macOS system
darwin-rebuild switch --flake .#bigboi
darwin-rebuild switch --flake .#small

# Rebuild NixOS system
sudo nixos-rebuild switch --flake .#bigchungus

# Update flake inputs
nix flake update
```

## Guidelines for AI Agents

1. **Version Control**: This repo uses **jujutsu (jj)** instead of git. Use `jj` commands for commits and history.

2. **Testing changes**: Always validate Nix syntax before committing:
   ```bash
   nix flake check
   ```

3. **Adding packages**: Add common packages to `modules/packages.nix`. For machine-specific additions, use the relevant machine file.

4. **Platform-specific configs**: Use `modules/programs/darwin/` or `modules/programs/nixos/` for OS-specific program configurations.

5. **Home-manager vs system**: User-level configs go in `home.nix` or `programs/`. System-level configs go in `darwin.nix` or `nixos.nix`.

6. **Homebrew (macOS only)**: Managed via nix-darwin in machine-specific files. Use for apps not available in nixpkgs.
