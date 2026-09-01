# migration: rocketpool smartnode -> lido csm

status: planned, not started. written 2026-08-28, reworked 2026-09-02 after
researching how the nix community runs reth + nimbus natively.

## premise

bigchungus has a complete, synced ethereum staking box that was never funded.
the rocketpool node is not registered, there are no minipools, the validator
client reports `validators=0`, and the keystore dir holds nothing but an empty
slashing-protection db. so this is not a migration of a live validator. there is
nothing to exit, no rpl to unstake, no capital to unwind.

what actually moves is the management layer. `reth` and `nimbus-eth2` are plain
ethereum clients; nothing in them or in their 1.6 tb of chaindata is
rocketpool-specific. all the rocketpool-ness lives in four smartnode wrapper
containers. delete the wrapper, keep the node.

## what is on the box today (verified 2026-09-02)

| | |
|---|---|
| reth | `ghcr.io/paradigmxyz/reth:v1.11.1`, **storage v1** (static files hold only headers, transactions, receipts), synced at head |
| nimbus bn | `statusim/nimbus-eth2:multiarch-v26.2.1`, synced, `--history=prune` |
| nimbus vc | `statusim/nimbus-validator-client:multiarch-v26.2.1`, `validators=0` |
| mev-boost | `flashbots/mev-boost:1.12.0`, rocketpool "all mev" relay set, no min-bid |
| chaindata | `/data/docker/volumes/rocketpool_eth1clientdata/_data/reth` (1.5 tb: db 796 g, static_files 646 g) and `.../rocketpool_eth2clientdata/_data/nimbus` (131 g), all owned by root, on the ext4 nvme at `/data` (1.8 tb, 234 g free) |
| jwt | `~/.rocketpool/data/secrets/jwtsecret`, bind-mounted into both containers |
| network | box is on 192.168.100.0/24 behind nat, `--nat=extip:84.40.152.248`; router forwards 30303 tcp+udp and 9001 tcp+udp. rpc ports are only reachable on the docker network `rocketpool_net`; docker-proxy publishes 30303, 9001 and 3100 (grafana) on the host |
| containers | all four clients run as uid 0 inside the containers |
| fee recipient | `0xae78736Cd615f374D3085123A210448E74Fc6393` (rocketpool, wrong for csm) |

exact running command lines are in `docker inspect` on the box; the reth prune
flags in particular need to carry over unchanged (see the config sketch).

## decision: native systemd services via ethereum.nix

**add `github:nix-community/ethereum.nix` as a flake input and use its
`services.ethereum.{reth,nimbus-beacon,nimbus-validator,mev-boost}` modules,
with the chaindata bind-mounted from `/data` into each unit's state directory.
docker leaves the staking path entirely.**

this replaces the earlier decision to declare the stack as
`virtualisation.oci-containers`. that decision rested on the claim that "nixpkgs
has no modules for reth or nimbus and nimbus-eth2 is not packaged, so native
services would mean writing those modules". the first half is true, the
conclusion is not: the community already maintains the modules.

### what the research found

**nixpkgs alone is not viable.** `pkgs.reth` is 1.9.3 (last bumped 2025-11-24,
pre-2.0, storage v1 only), there is no nimbus package (the init pr has been
open since 2022), and `nixos/modules/services/blockchain/ethereum/` has only
erigon, geth and lighthouse. `pkgs.mev-boost` 1.12 is fine.

**nix-community/ethereum.nix is alive and current.** last push 2026-09-02
(reth 2.5.1 -> 2.5.2), renovate-style bumps most days, tracks nixpkgs-unstable.
packages today: reth 2.5.2, nimbus 26.7.0 (one behind upstream 26.8.0, built
from source), mev-boost 1.12.0, ethstaker-deposit-cli. all four x86_64-linux
store paths are present in `nix-community.cachix.org` (checked from bigchungus
on 2026-09-02), so the box never compiles reth.

two recent breaking changes mean every blog post and the published docs site
(gh-pages, last built 2025-08-26) are stale. read `modules/nixos/*/options.nix`
on `main` instead:

- pr #866 (2026-07-21): the nested `args = { authrpc.jwtsecret = ...; }` api
  became a freeform `settings` attrset keyed by flat cli flag names
  (`"authrpc.jwtsecret"`, `"http.addr"`), rendered with `lib.cli.toCommandLine`.
- pr #1239 (2026-08-28): a `user` option; setting it turns `DynamicUser` off.

module facts that shape the config below:

- units are `reth-<name>`, `nimbus-beacon-<name>`, `nimbus-validator-<name>`,
  `mev-boost-<name>`, each with `StateDirectory = <unit>`, `Restart=on-failure`
  and a full hardening block. nimbus gets `MemoryDenyWriteExecute=false` (jit)
  and `RestartPreventExitStatus=129` (doppelganger exit).
- the jwt path goes in `settings."authrpc.jwtsecret"` (reth) and
  `settings.jwt-secret` (nimbus bn); the module turns it into `LoadCredential`
  and passes `%d/jwtsecret`, so the agenix file can stay root-owned 0400.
- package defaults are `pkgs.reth`, `pkgs.nimbus`, `pkgs.mev-boost` and the
  modules do not inject an overlay. with plain nixpkgs that silently picks reth
  1.9.3 and fails on nimbus. **always set `package` explicitly from
  `ethereum-nix.packages.x86_64-linux`.**
- reth's `openFirewall` opens tcp 30303 and the engine port 8551 to the world,
  and misses udp 30303. nimbus's opens 9000 and knows nothing about the quic
  port added in 26.8.0. keep both `false` and open ports by hand.
- setting nimbus `settings.trusted-node-url` adds an `ExecStartPre` that runs
  `trustedNodeSync` on every start. the db already exists; do not set it.
- the nimbus bn module also writes `<data-dir>/api-token.txt` on every start.
  harmless.

**how other people do it.** the handful of public nixos staking configs found
(scottbot95, lucemans, codyps, openmesh) all use ethereum.nix; one status
engineer (jakubgs) uses nimbus-eth2's own upstream flake modules with agenix.
nobody found runs reth + nimbus together, and nobody runs csm on nixos, so this
setup is undocumented territory on both the lido and the nix side. the
consistent patterns worth copying: jwt from a secret manager handed to the
module as a path, and chaindata on another disk **bind-mounted onto the unit's
state directory** rather than pointing `datadir` elsewhere and fighting
`ProtectSystem=strict`.

### two consequences that are easy to get wrong

**do not `follows` nixpkgs for the ethereum.nix input.** the cachix store paths
were built against ethereum.nix's own nixpkgs pin. re-basing them on this
flake's nixpkgs changes every hash and turns each nightly autoupgrade into a
from-source reth build (rust, hours, and it would compete with attestations for
ram on a box that has 5 g free). the cost of not following is a second nixpkgs
evaluation and some closure duplication. accept it.

**add the cache to `nix.settings`.** the flake's `nixConfig` is ignored without
`--accept-flake-config`, and root's `system.autoUpgrade` will not pass it. put
`https://nix-community.cachix.org` and its key
`nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=` into
`nix.settings.substituters` / `trusted-public-keys` on bigchungus. before any
`nix flake update` that moves ethereum.nix, check the new paths are cached:

```
nix path-info --store https://nix-community.cachix.org \
  $(nix eval --raw 'github:nix-community/ethereum.nix#packages.x86_64-linux.reth.outPath')
```

(that eval only works on a linux machine; run it on the box.)

### alternatives rejected

**oci-containers (the previous plan).** works, and reuses upstream images with
zero compile risk, but it keeps docker as a hard dependency of the staking
path, keeps the clients as root inside their containers, needs a hand-made
docker network for `http://eth1:8551` style names, and gives nothing in
return that a systemd unit with `LoadCredential` does not. it is the fallback
if ethereum.nix ever stops being maintained: the same datadirs and flags drop
straight back into containers.

**own module + upstream release binaries (fetchurl + autoPatchelf).** cleanest
in the sense of owning every line and never compiling, but it re-implements
what ethereum.nix already maintains (flag renames such as `--web3-url` ->
`--el`, the new quic port, hardening), and the cachix hits remove the compile
argument. keep this as the escape hatch if a cache miss ever blocks an upgrade:
override `package` with a binary derivation for that one version.

**nimbus-eth2's upstream flake modules.** credible (used in production at
status), but a second flake input with `?submodules=1`, its own nixpkgs pin and
a from-source nim build, for one client. ethereum.nix already covers it.

**eth-docker / sedge / stereum / dappnode.** as before: a third config surface
with its own update channel, on a box whose whole point is converging from one
flake.

### client choice: keep reth + nimbus, keep bn and vc split

no change on clients. reth and nimbus are minority clients on both layers,
which is what csm's performance oracle rewards and what avoids correlated
failures. the 1.5 tb resync cost is a bonus, not the reason.

nimbus can host validators inside the beacon node, and its own guide notes most
known slashings came from split setups. the split is still the right call
here, for one reason: doppelganger detection costs two epochs of missed
attestations on every restart of the process that holds the keys. reth bumps
and beacon-node flag changes restart the bn; with a separate vc those do not
touch the keys. a nimbus package bump restarts both regardless.

## what stays, goes, changes

| | |
|---|---|
| **stays** | both chaindata trees (moved, not copied, within `/data`), p2p ports 30303 + 9001 and the router forwards behind them, `--nat=extip`, the reth prune profile |
| **goes** | docker, `rocketpool_*` containers and volumes, `~/.rocketpool`, the smartnode hot wallet, grafana/prometheus/alertmanager in docker (see monitoring below) |
| **changes** | reth 1.11.1 -> 2.5.x, nimbus 26.2.1 -> 26.7+, all four clients become systemd units under their own users, jwt becomes an agenix secret, fee recipient, relay set + min-bid, `--local-block-value-boost`, validator keys |

## the addresses that matter

| what | value |
|---|---|
| lido withdrawal vault (withdrawal address) | `0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f` |
| resulting withdrawal credentials | `0x010000000000000000000000b9d7934878b5fb9610b3fe8a5e441e8fad7e293f` |
| lido el rewards vault (fee recipient) | `0x388C818CA8B9251b393131C08a736A67ccB19297` |
| mev-boost relay allowed list contract | `0xF95f069F9AD107938F6ba802a3da87892298610E` |
| current fee recipient on the box (wrong) | `0xae78736Cd615f374D3085123A210448E74Fc6393` |

get the withdrawal address wrong and the keys are unusable at best, and the
32 eth lands somewhere you do not control at worst. this is the one step to be
slow on.

**0x01 credentials only.** the lido key-gen guide says outright not to generate
0x02 keys for csm. a separate 0x02 csm module went live on hoodi on 2026-09-01
and targets mainnet in q4 2026, and existing 0x01 operators should not expect
consolidation support into it. irrelevant for now; noted so nobody "helpfully"
picks 0x02 in the deposit cli.

## security improvement worth taking

smartnode needed a hot wallet on the box to send transactions. csm does not. the
node operator manager address and reward address are yours to choose and never
need to touch the machine; the box only ever holds validator keystores.

use a hardware wallet for both. retire `0xdceb0e79...5D02` and delete
`~/.rocketpool` once the cutover is done.

## csm state as of 2026-09-02

csm is on **v3** on mainnet (core upgrade enacted 2026-07-27). the numbers the
earlier draft used are unchanged; the new operator type (identified dvt
cluster) does not apply here.

| type | first key bond | next keys | operator reward share |
|---|---|---|---|
| permissionless | 2.4 eth | 1.3 eth | 3.5% |
| ics | 1.5 eth | 1.3 eth | 6% on the first 16 keys, then 3.5% |

performance oracle: 28-day frames, threshold is network average attestation
effectiveness minus 3% leeway (5% for ics on the first 150 keys). a frame below
threshold pays no operator rewards and adds a strike; 3 strikes in 6 frames
ejects (4 for ics). mev stealing or a wrong fee recipient locks the stolen
amount plus 0.1 eth of bond.

**ics timing.** assessment is now quarterly. round 6 closes 2026-09-07, which
this plan cannot make. round 7 closes **2026-12-07**. the 6-point "csm mainnet
participation" proof needs 30+ days active and above threshold in the latest
oracle report, so the validator should be attesting by mid october to have a
full frame reported before the cutoff; earlier is safer. testnet (hoodi) is
worth 4 points after 60+ days but needs disk this box does not have.

## phases

### phase 0: decide the entry route

rocketpool operation earns **zero** ics points. it is not in the framework. the
accepted experience proofs are ethstaker's list, stakecat's solo-stakers-b,
obol techne, ssv verified operators, sdvtm, and csm participation itself.

with no staking history on any address here, experience is the blocked category.
the cheapest unblock is csm mainnet itself: 30+ days active above the
performance threshold is worth 6 points.

**so: enter permissionless now, apply for ics in round 7.** post 2.4 eth, run
one validator cleanly for a month, then apply. bond requirement drops to 1.5
eth on the first key and the excess becomes claimable or reusable toward more
keys, and reward share goes from 3.5% to 6% on the first 16 keys.

second thing to check before applying: **engagement is likely the other weak
category.** snapshot votes need 100+ ldo held and 3+ votes, aragon votes 2+.
the alternatives are a lido galxe score (4-5), a high signal score (2-5), or a
gitpoap from an approved staking project (2; the gitpoap snapshot is frozen as
of 2026-08-17 but still counts). the per-category minimums are not published
anywhere; total must be >= 15. worth planning for during the 30-day wait rather
than discovering at application time.

budget: 2.4 eth bond, plus gas for the bond deposit and key upload.

### phase 1: declarative cutover, no re-sync

the trick is the same as before: the chaindata is in ordinary directories and
the clients keep their databases in known subdirectories. move the directories
out of the docker volumes (a rename within the same ext4 filesystem, instant),
chown them, and bind-mount them where the ethereum.nix units expect their
state.

```
/data/docker/volumes/rocketpool_eth1clientdata/_data/reth    -> /data/ethereum/reth
/data/docker/volumes/rocketpool_eth2clientdata/_data/nimbus  -> /data/ethereum/nimbus-beacon
/var/lib/reth-mainnet           = bind of /data/ethereum/reth            (reth --datadir)
/var/lib/nimbus-beacon-mainnet  = bind of /data/ethereum/nimbus-beacon   (nimbus --data-dir)
/var/lib/nimbus-validator-mainnet   stays on rpool/root; holds keys + slashing db
/var/lib/mev-boost-mainnet          stays on rpool/root; stateless
```

the validator client's data dir (keystores, `secrets/`, and
`validators/slashing_protection.sqlite3`) deliberately lives on the zfs root,
not on the chaindata disk.

steps, in one sitting, with the branch checked out on the box:

1. write `modules/services/ethereum.nix` (sketch below), add the
   `ethereum-nix` input, the cachix settings, and the `eth-jwtsecret` agenix
   secret (a fresh `openssl rand -hex 32`; there is no reason to carry the old
   one over, both clients restart together anyway).
2. `nix flake check` locally; on the box, confirm the four store paths are
   cache hits (command above).
3. `rocketpool service stop`, then `docker rm` the smartnode containers but
   **not** the volumes.
4. `mv` the two datadirs as above, `chown -R` to the new users. leave the empty
   volumes in place.
5. `sudo nixos-rebuild switch --flake ~/.config/nix` with the vc **disabled**
   (`services.ethereum.nimbus-validator.mainnet.enable = false` for now).
6. the checkpoint: `journalctl -fu reth-mainnet` must show reth opening the
   existing db and reporting the current head within a minute, and
   `curl localhost:5052/eth/v1/node/syncing` must say `is_syncing: false`. if
   reth starts at block 0 or complains about the db, stop and fix the mount
   before doing anything else.
7. only then push `main`. until then, autoupgrade at 04:30 would activate the
   new units on top of the running containers and fight over 30303 and 9001.

rollback until phase 3 is done: stop the units, `mv` the directories back,
`chown -R root`, `rocketpool service start`. keep `~/.rocketpool` and the
volumes until a validator is attesting.

**reth 1.11 -> 2.5 on a storage v1 datadir.** reth 2.0 made storage v2 the
default for new nodes and says existing v1 nodes "are unaffected and will
continue to work", with v1 support to be removed at a date "communicated
separately". no removal had happened through 2.5.2. this is the one unverified
compatibility step; the checkpoint above catches it. longer term, either
`reth db migrate-v2` (added in 2.1, in-place) or a resync from
`snapshots.reth.rs` will be needed, and both want free space that 234 g may
not cover. track the deprecation notice and plan the disk before it lands.

### phase 2: generate keys, air-gapped

```
./deposit new-mnemonic \
  --num_validators 1 \
  --chain mainnet \
  --eth1_withdrawal_address 0xB9D7934878B5FB9610B3fE8A5e441e8fad7E293f
```

ethstaker-deposit-cli, on a machine with networking off. 0x01 credentials only,
not 0x02. deposit amount 32 eth. the mnemonic is the only recovery path for the
validator keys; back it up offline.

produces keystores plus a `deposit_data-*.json`.

### phase 3: bond and upload

at `csm.lido.fi`, connect the hardware wallet, choose the permissionless type,
submit the bond in eth / steth / wsteth, upload the deposit data. read the live
bond number off the widget rather than trusting any doc, including this one.

then import the keystores into the vc's data dir and enable the vc:

```
sudo -u nimbus nimbus_beacon_node deposits import \
  --data-dir=/var/lib/nimbus-validator-mainnet /path/to/validator_keys
```

(`deposits import` is a beacon-node subcommand but only touches `validators/`
and `secrets/` under whatever `--data-dir` it is given.) nimbus wants those
dirs 0700 and files 0600, owned by the running user. then flip
`nimbus-validator.mainnet.enable = true`, rebuild, and watch doppelganger
detection sit out two epochs before the first attestation.

### phase 4: get the mev config right

mandatory, and penalised if wrong. policy is snop block proposals v4.0
(2026-06-24). current live allowed list, read from the contract on 2026-09-02:

flagged mandatory (`must use some`, pick at least one):

```
agnostic-relay.net                      Agnostic
bloxroute.regulated.blxrbdn.com         bloXroute Regulated
bloxroute.max-profit.blxrbdn.com        bloXroute Max-Profit   (portal says deprecated 2026-08-26, still on-chain; skip it)
aestus.live                             Aestus
boost-relay.flashbots.net               Flashbots
relay.ultrasound.money                  Ultra Sound
relay-filtered.ultrasound.money         Ultra Sound filtering
```

not flagged mandatory (optional):

```
regional.titanrelay.xyz                 Titan Regional
global.titanrelay.xyz                   Titan Global
```

read the full uris (with pubkeys) from the contract at deploy time rather than
from any doc; the sedge defaults in lido's own docs still list a relay that is
no longer on-chain:

```
cast call 0xF95f069F9AD107938F6ba802a3da87892298610E \
  "get_relays()((string,string,bool,string)[])" --rpc-url http://127.0.0.1:8545
```

the current box config is rocketpool's `all-mev` set including `relay.btcs.com`
and the `?id=rocketpool` tags, which is not the lido list. it has to be
replaced.

three settings that are easy to miss:

- **mev-boost `--min-bid 0.07`.** lido caps min-bid at 0.07 eth. the box
  currently has none.
- **nimbus bn `--local-block-value-boost=0`.** lido requires a neutral
  builder-boost-factor of 100%. nimbus defaults this to `10`, meaning it inflates
  local block value by 10% when comparing against builder bids, which biases
  against the relay. `0` is the neutral setting. it is a *beacon node* flag; the
  vc's `--builder-boost-factor` already defaults to 100 and needs nothing.
- **`--payload-builder` on both bn and vc.** nimbus requires it on both sides;
  the bn additionally takes `--payload-builder-url`.

### phase 5: run for 30 days, then apply for ics

apply at `csm.lido.fi/type/ics-apply` before 2026-12-07. main address plus up
to five supporting addresses. minimum in each of experience / engagement /
humanity, total >= 15. the list is updated in waves through easy track
governance, so there is lag between approval and the parameters actually
changing.

### phase 6: monitoring and removing docker

the smartnode grafana/prometheus/alertmanager stack goes with the containers.
replace with native `services.prometheus` scraping `127.0.0.1:9105` (reth),
`9100` (nimbus bn) and `9101` (vc), and `services.grafana` on the existing
tailnet-only port 3100. add a `services.prometheus.alertmanager` rule for
"no attestation in 2 epochs" at minimum; csm withholds a whole 28-day frame of
rewards for a bad frame, so silence is expensive.

once nothing else needs it, drop `virtualisation.docker` from bigchungus,
delete `/data/docker` (it still holds the empty volumes and ~1 g of images) and
`~/.rocketpool`. the docker `data-root` setting and the `docker` group on tim
go with it.

## config sketch

not final. the `settings` keys are the flat cli flag names the modules render;
check them against `modules/nixos/<module>/options.nix` in the locked
ethereum.nix revision before rollout, since the freeform type will not catch a
typo.

flake input:

```nix
ethereum-nix = {
  url = "github:nix-community/ethereum.nix";
  # deliberately no nixpkgs follows: the nix-community cache was built against
  # ethereum.nix's own pin, and following ours would rebuild reth from source
};
```

pass it through `specialArgs` like `slurp` and `filmnight`, and import
`ethereum-nix.nixosModules.default` in `mkNixosSystem`.

`modules/machines/bigchungus.nix` additions:

```nix
nix.settings = {
  substituters = [ "https://nix-community.cachix.org" ];
  trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
};

# chaindata lives on the ext4 nvme; the units expect it under /var/lib
fileSystems."/var/lib/reth-mainnet" = {
  device = "/data/ethereum/reth";
  options = [ "bind" ];
};
fileSystems."/var/lib/nimbus-beacon-mainnet" = {
  device = "/data/ethereum/nimbus-beacon";
  options = [ "bind" ];
};
```

`modules/services/ethereum.nix`:

```nix
{ config, pkgs, lib, ethereum-nix, ... }:

let
  ethPkgs = ethereum-nix.packages.${pkgs.stdenv.hostPlatform.system};
  jwt = config.age.secrets."eth-jwtsecret".path;
  feeRecipient = "0x388C818CA8B9251b393131C08a736A67ccB19297";
  externalIp = "84.40.152.248";

  # full uris from the allowed-list contract, at least one flagged mandatory.
  # bloxroute max-profit is on-chain but marked deprecated by lido; left out
  relays = [
    "https://0xac6e...@boost-relay.flashbots.net"
    "https://0xa155...@relay.ultrasound.money"
    "https://0xa15b...@aestus.live"
    "https://0xa7ab...@agnostic-relay.net"
    "https://0x8c4e...@regional.titanrelay.xyz"
  ];
in
{
  age.secrets."eth-jwtsecret".file = ../../secrets/eth-jwtsecret.age;

  # static users so ownership of 1.6 tb of chaindata and of the keystores is
  # predictable; the module's `user` option turns DynamicUser off
  users.users.reth = { isSystemUser = true; group = "reth"; };
  users.groups.reth = { };
  users.users.nimbus = { isSystemUser = true; group = "nimbus"; };
  users.groups.nimbus = { };

  services.ethereum.reth.mainnet = {
    enable = true;
    package = ethPkgs.reth;
    user = "reth";
    openFirewall = false;
    settings = {
      chain = "mainnet";
      "authrpc.jwtsecret" = jwt;
      "authrpc.addr" = "127.0.0.1";
      "authrpc.port" = 8551;
      http = true;
      "http.addr" = "127.0.0.1";
      "http.api" = "eth,net,web3";
      metrics = "127.0.0.1:9105";
      port = 30303;
      "max-outbound-peers" = 100;
      "max-inbound-peers" = 30;
    };
    # the smartnode "historyExpiry" prune profile the datadir was built with;
    # keep it identical so reth does not reinterpret the prune config
    extraArgs = [
      "--block-interval" "5"
      "--prune.senderrecovery.full"
      "--prune.accounthistory.distance" "10064"
      "--prune.storagehistory.distance" "10064"
      "--prune.bodies.pre-merge"
      "--prune.receipts.pre-merge"
      "--prune.transaction-lookup.distance=10064"
    ];
  };

  services.ethereum.nimbus-beacon.mainnet = {
    enable = true;
    package = ethPkgs.nimbus;
    user = "nimbus";
    openFirewall = false;
    settings = {
      network = "mainnet";
      el = "http://127.0.0.1:8551";
      jwt-secret = jwt;
      rest = true;
      rest-address = "127.0.0.1";
      rest-port = 5052;
      tcp-port = 9001;
      udp-port = 9001;
      # 26.8.0 turns on quic gossip on udp 9001 by default, which collides with
      # discovery above. pin it somewhere explicit and forward it, or disable
      quic-port = 9002;
      nat = "extip:${externalIp}";
      enr-auto-update = true;
      max-peers = 160;
      history = "prune";
      metrics = true;
      metrics-address = "127.0.0.1";
      metrics-port = 9100;
      payload-builder = true;
      payload-builder-url = "http://127.0.0.1:18550";
      # lido wants a neutral builder-boost-factor; nimbus defaults to 10
      local-block-value-boost = 0;
    };
  };

  services.ethereum.nimbus-validator.mainnet = {
    enable = false; # flip after the keys are imported (phase 3)
    package = ethPkgs.nimbus;
    user = "nimbus";
    settings = {
      network = "mainnet";
      beacon-node = [ "http://127.0.0.1:5052" ];
      payload-builder = true;
      suggested-fee-recipient = feeRecipient;
      doppelganger-detection = true;
      block-monitor-type = "event";
      graffiti = "wolny kurdystan";
      metrics = true;
      metrics-address = "127.0.0.1";
      metrics-port = 9101;
    };
  };

  services.ethereum.mev-boost.mainnet = {
    enable = true;
    package = ethPkgs.mev-boost;
    settings = {
      mainnet = true;
      addr = "127.0.0.1:18550";
      relay-check = true;
      # lido caps min-bid at 0.07 eth
      min-bid = "0.07";
      inherit relays;
    };
  };

  # order the chaindata units after their bind mounts, and reth before the bn
  systemd.services.reth-mainnet.unitConfig.RequiresMountsFor = "/var/lib/reth-mainnet";
  systemd.services.nimbus-beacon-mainnet = {
    unitConfig.RequiresMountsFor = "/var/lib/nimbus-beacon-mainnet";
    after = [ "reth-mainnet.service" "mev-boost-mainnet.service" ];
  };
  systemd.services.nimbus-validator-mainnet.after = [ "nimbus-beacon-mainnet.service" ];

  # p2p only; every rpc, engine and metrics port stays on loopback
  networking.firewall.allowedTCPPorts = [ 30303 9001 ];
  networking.firewall.allowedUDPPorts = [ 30303 9001 9002 ];
}
```

`secrets/secrets.nix` gains `"eth-jwtsecret.age".publicKeys = all;`.

## risks

- **re-sync.** a wrong bind mount or a missed chown silently costs days on
  1.6 tb, and `/data` has 234 g free. the phase 1 checkpoint exists for this.
- **reth storage v1.** works today on 2.5.x per the release notes, but is on a
  deprecation path with no date yet, and migrating or resyncing needs disk.
- **cache miss on upgrade.** if a future ethereum.nix bump is not in cachix the
  box would try to build reth at 04:30. mitigations: check before moving the
  lock, and the binary-derivation escape hatch above.
- **disk.** 234 g of headroom is fine for the current stack and not enough for
  a parallel csm testnet stack or for a v2 migration. running testnet for ics
  points would need a plan for space.
- **double-signing.** never run the old and new vc against the same keys. since
  the keys are brand new and the old vc has none, the real risk is only during
  a later rebuild. doppelganger detection stays on; the vc data dir is the one
  directory on this box that must never be restored from an old backup.
- **colocation.** this box also serves media, samba, filmnight, goatcounter and
  caddy. csm's oracle withholds operator rewards for a whole 28-day frame if
  attestation effectiveness falls below the network average minus 300 bps. a
  transcode storm competing with attestations is a real, if modest, cost.
- **parameter drift.** bond curves, reward shares and the relay list all move by
  dao vote. re-read them at execution time.

## open questions

- how many validators to start with. the plan assumes one.
- whether to also stand up csm testnet for the extra 4 ics points, given disk.
- whether the engagement category can be met without acquiring ldo.
- quic: forward udp 9002 on the router, or disable quic until the port
  situation is clearer.
