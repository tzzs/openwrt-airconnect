# Migration tests

Host tests for `scripts/migrate-legacy.sh`, the router-side script that detects a
legacy AirConnect installation and maps its settings into
`/etc/config/airconnect-manager`. The operator procedure is
[docs/MIGRATION.zh-CN.md](../../docs/MIGRATION.zh-CN.md).

```sh
bash tests/migration/run.sh
```

The script under test is POSIX sh because the router only has BusyBox ash, so it
is invoked here with `sh` and additionally parsed with `dash -n` (and
`busybox ash -n` when BusyBox is installed). The suite itself is bash, like the
other host suites.

## How the sandbox works

Every absolute path the script uses is prefixed by `AIRCONNECT_MIGRATE_ROOT`,
which the tests point at a throwaway directory tree:

```
<work>/<case>/
  etc/config/airconnect                 synthetic legacy configuration
  etc/config/airconnect-manager         copy of the packaged conffile
  etc/init.d/airconnect                 shim: enabled/running/start/stop/enable/disable
  etc/init.d/airconnect-manager         shim: running/start/stop
  bin/uci                               shim: -q get / -q show over the file above
  bin/docker                            shim: ps / stop / start over a container list
  var/state/                            shim state (running/enabled markers, containers)
```

The shims record the calls they receive under `<work>/logs/<case>/`, outside the
sandbox, so "the tree did not change" assertions are not confused by the test's
own instrumentation. All fixture values are synthetic: `uuid:demo-*` UDNs,
RFC 5737 addresses (`192.0.2.x`), and a `demo/airconnect` image.

## What is covered

1. **Default invocation modifies nothing.** A recursive listing of path, mode
   and content digest is compared before and after; the default mode is
   `--dry-run`.
2. **`--dry-run` prints the mapping and modifies nothing.** Every mapped and
   skipped value is asserted by its exact `old-key=value -> ...` line, including
   the alternate legacy spellings (`iface`, `binding`, `upnp`, `cast`) and the
   `(absent)` defaults.
3. **`--apply`.** The generated main section is compared key by key, the device
   section must be keyed by the UDN with the legacy volume limit and must
   contain no speaker name or address, exactly one backup directory must exist
   with a `manifest.txt` listing both originals and their modes, the legacy
   configuration must be byte-identical, and the legacy service must be stopped
   and disabled. The new service must never be started, and no destructive
   docker subcommand may appear.
4. **`--rollback`.** Both files must be restored byte for byte, the legacy
   service enabled and started again, the backup marked `rolled-back` and kept.
   A second `--rollback` must be a no-op that exits 0.
5. **A second `--apply` refuses** (the implemented behaviour, documented in the
   runbook), leaves the migrated file alone, creates no second backup, and does
   not restart the legacy service.
6. **An existing backup directory is never overwritten.** A fixed `date` shim
   makes two runs collide on the same timestamp; the second `--apply` must
   refuse and leave the existing directory untouched.
7. **`--force-stop-new`.** A running `airconnect-manager` is a hard stop for
   `--apply` (two broadcasters would be live), and the flag lets the script stop
   it first.
8. **Detection-only cases.** A Docker-only installation, an old `/usr/bin`
   layout without a UCI file, a volume limit with no UDN (global fallback plus
   the "needs a scan" note), a disabled legacy service (must stay disabled), and
   a legacy file with almost every key absent.
9. **Guards.** A non-root run without a sandbox exits nonzero, two conflicting
   modes exit 2, an unknown flag exits 2, and `--help` exits 0.
10. **The generated file is accepted by the real validator.** `validate.uc`
    reads the written `/etc/config/airconnect-manager` with a minimal
    UCI-shaped reader, runs the shipped `normalizeConfig` on it and renders
    both enabled engines with the shipped `renderXml`. A migrated file that
    the manager would reject fails the suite instead of being found on the
    router. Skipped, with a message, when no ucode interpreter is available.
11. **Static properties.** `sh -n`, `dash -n`, `#!/bin/sh`, `set -u`, and the
    absence of `eval`, `rm -rf`, `docker rm`, `opkg remove`, `apk del`, `[[ ]]`
    and `sed -i`.

## What a host cannot verify

- **No real router.** `uci`, `procd`, `docker`, the real init scripts and the
  `date` command are shims or the host's own. Whether BusyBox `uci -q get`
  returns the same exit status on a real device is assumed, not proven.
- **No real speakers.** The suite cannot show that discovery, the iOS AirPlay
  menu or playback work after a migration; those stay manual steps in the
  runbook.
- **No real Docker.** The shim keeps a stopped container, but a real
  `--restart always` container will come back after a reboot; the runbook
  documents that as a manual follow-up.
- **Never executed on hardware.** The whole procedure is an untested procedure;
  `docs/MIGRATION.zh-CN.md` says so at the top and has a section for the first
  real run.
