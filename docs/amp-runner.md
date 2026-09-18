# Amp runner on bigchungus

`bigchungus` is one persistent Amp runner serving repositories under
`/home/amp/Repos` and staged revisions under `/home/amp/Workspaces`. Amp scans
both trees every minute, so new checkouts appear without another runner process
or a service restart.

## Persistent repositories

Clone repositories as the `amp` user under an owner directory:

```text
/home/amp/Repos/tokentax/api-v2
/home/amp/Repos/tokentax/exchange-service-2
/home/amp/Repos/tymek/slurp
```

Select the checkout beneath the `bigchungus` runner when creating a thread.

The persistent TokenTax checkout `/home/amp/Repos/tokentax/token-compose` is a
sibling of every other TokenTax repository. Its mode-0600 `.env.compose` is
therefore available at `../token-compose/.env.compose`.

## Staging a local revision

`amp-stage` sends an exact local Git-backed jj revision to bigchungus. It
transfers the selected Git commit and every missing ancestor, then creates a
dedicated jj workspace without publishing anything to the canonical remote.

Run it from any supported jj workspace:

```bash
amp-stage vitest @
amp-stage robinhood zslpnzoo
```

The first argument is a short lowercase name. The optional second argument is
any jj revision expression resolving to one commit and defaults to `@`. Running
the command snapshots the local working copy as part of resolving the revision.

The command prints a path such as:

```text
/home/amp/Workspaces/TokenTax-exchange-service-2-vitest-ca0a4f396585/exchange-service-2
```

Select that path beneath the `bigchungus` runner. The runner discovers it within
one minute. Repeating the same command is idempotent and returns the same path.

Staged TokenTax workspaces receive a sibling `token-compose` link matching the
persistent repository layout. Other namespaces do not.

## Toolchain

The runner uses the same chezmoi-managed mise configuration as the macs and the
`tim` user on bigchungus. An hourly service pulls the dotfiles repository over
SSH, applies only the mise configuration, and upgrades the configured tools.
Nix supplies the stable bootstrap tools and build environment. pnpm comes from
Corepack and the repository's `packageManager` field.

Docker commands use the `amp` user's rootless daemon. They cannot reach the host
daemon that runs system services.

Repositories, workspaces, package caches, and runner state persist across
disconnects and reboots. There is no automatic workspace cleanup because it
could destroy unpublished work.
