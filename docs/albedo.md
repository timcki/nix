# Albedo agent on bigchungus

[Albedo](https://tangled.sh/@okami.mom/albedo) runs as the isolated `albedo`
user (uid 1002) and is woken by iMessage through Photon. The module is
`modules/services/albedo.nix`.

## Boundary

Albedo has no sandbox or approval flow; the agent can do anything its user can.
So the user is the boundary: no wheel, no docker group, home mode 0700, and
`user@1002` is capped (`MemoryMax=6G`, low CPU/IO weight) so detached kernels
cannot starve the validator. Inside `/home/albedo` it has free reign.

## What Nix owns and what it does not

Nix declares the user, the daemon (`albedo.service`, a user unit), the web
gateway (`albedo-web.service`, tailnet only on port 4317), the tool PATH, and
`~/work/AGENTS.md` (a store symlink; edit it in the module).

Provider, model, credentials and the Photon pairing are runtime state in
`~/.albedo`, set once by hand below. They are kept out of
`services.albedo.settings` on purpose: activation merges those files while the
daemon may be writing them, and the nightly upgrade activates with the daemon
running. Anything in `settings` also lands in the world-readable store.

## One-time setup

As tim on bigchungus, after the config is deployed:

```bash
sudo machinectl shell albedo@
```

Then, as albedo:

```bash
cd ~/work
albedo login          # Claude -> Console API key; never the subscription sign-in
albedo                # TUI: set default model to Opus 5.5, medium effort, fast mode off
albedo photon setup --phone +<E.164 number>
albedo photon status  # should say Ready
```

Do not use Claude subscription OAuth: Albedo's `claude` extension presents it
as Claude Code, which Anthropic's terms don't allow in third-party harnesses.

In the Claude Console, put a monthly spend limit on the key.

If Photon asks for an opt-in, text the assigned number once from the phone.
The first pairing skips older messages.

## Operating

```bash
systemctl --user status albedo albedo-web   # as albedo
tail -f ~/.albedo/daemon.log
albedo photon status
```

Web UI: `https://bigchungus.tailb9dbd5.ts.net:4317` (run `albedo web` as albedo
for the sign-in link).

Kernels survive daemon restarts (`KillMode=process`) but not a reboot.

## Cost

About 6 cents per step at ~80k context. A text after more than 5 idle minutes
pays a full cache write (about 50 cents at 100k), since `warm` only keeps the
cache warm while awaited work runs. Keep sessions small; let compaction run.

## Bumping

`flake.lock` pins the input, so it moves with `nix flake update`. Albedo is
pre-alpha: when it moves, reread its `docs/home-manager.md` and `docs/photon.md`
at the new rev.
