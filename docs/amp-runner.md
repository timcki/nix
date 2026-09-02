# Amp runner on bigchungus

`amp-stage` sends an exact local exchange-service-2 jj revision to an isolated,
persistent Amp runner on bigchungus. It transfers the selected Git commit and
every missing ancestor, so linear stacks and non-linear revision graphs retain
their original commit IDs, change IDs, descriptions, and topology.

## Usage

Run this from any exchange-service-2 jj workspace:

```bash
amp-stage vitest @
amp-stage robinhood zslpnzoo
```

The first argument is a short lowercase name. The optional second argument is
any jj revision expression resolving to one commit and defaults to `@`. Running
the command snapshots the local working copy as part of resolving the revision,
but does not create a new change or publish anything to GitHub.

The command prints a runner ID such as:

```text
bigchungus-x-vitest-ca0a4f396585
```

Select that runner when creating an Amp thread. Each unique name and commit gets
its own server workspace, so syncing another revision never overwrites an active
thread. Repeating the same command is idempotent and returns the existing runner.

## Server environment

Staged workspaces live under `/home/amp/Workspaces`. Each workspace shares the
dedicated `amp` user's Amp login, GCloud credentials, GitHub SSH key, and pnpm
content store. Its parent directory links `token-compose` to the persistent
checkout, which provides the mode-0600 `.env.compose` used by `pnpm cli-sync`.

Run this once in a fresh workspace before testing:

```bash
corepack pnpm install --frozen-lockfile
```

Runners and workspaces intentionally persist across disconnects and reboots.
There is no automatic cleanup because deleting a workspace could destroy remote
work. Stop and remove obsolete instances manually only after confirming their
threads are finished.
