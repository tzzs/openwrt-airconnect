# rpcd backend tests

Host-side checks for the `airconnect.manager` ubus object and the two modules it
delegates to. They need neither OpenWrt nor a router, and they never contact the
network.

```sh
~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/state/run.uc
bash tests/state/check-plugin.sh
```

`run.uc` covers the pure logic. `check-plugin.sh` compiles the plugin, asserts
its rpcd signature, drives every method, and then runs `plugin.uc`, which loads
the real plugin against a sandbox root with fake `uci`/`ubus` modules.

## What the plugin cannot be tested for here

The plugin needs ubus, uci, netifd, procd and a real LAN. None of those exist on
a host, so the following are **not** verified by this suite and must be checked
on a device before release:

- registration with a real rpcd (the signature shape is checked, not rpcd's
  acceptance of it);
- `service list` against a real procd, and the pid/instance shapes it returns;
- `network.device status` / `network.interface dump` against a real netifd;
- SSDP discovery on a real interface (only the worker's failure path is covered);
- that `/etc/init.d/airconnect-manager <action>` behaves as expected on procd.

## `run.uc` — pure logic

`state.uc` is the reply-shaping half of the backend, and `files.uc` the bounded
file access. Both are imported directly; neither has a runtime module dependency
(`files.uc` uses only `fs`, which exists on the host).

- **`mergeConfigured`** — a configured speaker that was not discovered stays in
  the list with `online:false`; a configured name overrides a discovered one and
  an empty one becomes `null`; dedupe is by engine *and* UDN; facts are never
  invented; the list is bounded to 64 entries; control bytes are rejected.
- **`freshCache` / `buildStatus`** — a snapshot older than 24 hours (or stamped
  too far in the future) yields no devices and no `last_scan`; `running` stays
  `null` when procd cannot be asked and is `false` when procd says so; the whole
  documented reply shape is asserted, including `conflicts` and `scan.error`.
- **`parsePsOutput`** — our own pids are ignored, unrelated processes and
  look-alike arguments (`grep airupnp`, `logread -e airupnp`, the init script)
  are not mistaken for engines, the BusyBox and procps column layouts both work,
  and the 64 KiB cap is enforced.
- **`tailLines`** — keeps the newest lines, strips control bytes while keeping
  tabs, caps each line at 512 bytes, honours both the line and byte caps, and
  reports truncation only when something was dropped.
- **`clampErrors`** — 20 entries at most, 512 bytes per message, empty entries
  dropped, input not mutated.
- **`actionSatisfied`** — compares procd's reported state with the state the
  action was supposed to reach, and returns `null` (not `true`) when the answer
  is unknowable.
- **`stripControl`** — the cleaning used for a value shown in the page.
- **`files.uc`** — real temporary directories: atomic writes keep the exact
  bytes and mode and leave no temporary behind, a failed write never touches the
  destination, `readTail` seeks and drops a partial first line, `readText` and
  `readJson` refuse oversized input, `ensureDir` creates 0750 ancestors.

## `check-plugin.sh` — the plugin itself

- `ucode -c <plugin>` exits 0 **and prints nothing**;
- the top-level return is a signature object registering exactly
  `airconnect.manager` with `status`, `logs`, `scan`, `validate`, `action`;
  `validate` takes `{ config: {} }`, `action` takes `{ action: "start" }`, and
  the three read methods take no arguments;
- every method returns a plain object even with **no uci and no ubus at all**,
  which is the requirement that keeps the page from showing `NO_DATA`;
- `validate` reuses `config.uc` and reports path-prefixed errors, including the
  Cast `pcm` rejection;
- static checks: the action command comes from a fixed table, no request or
  discovery value reaches `popen`/`system`, no destructive command (`killall`,
  `rm -rf`, `uci delete`, …) exists anywhere in the file, `uci`/`ubus` are
  loaded with `require()` rather than a static `import`, and `state.uc`/`files.uc`
  import no runtime modules.

## `plugin.uc` — the plugin's I/O paths

`check-plugin.sh` creates a temporary root and stub directory, sets
`AIRCONNECT_MANAGER_ROOT`, and runs this file with the stubs on the module
search path. The stubs read `<stubs>/config.json` on every call, because the
ucode module cache is process-wide.

The fake `uci` and `ubus` modules themselves live in `stubs.uc`, not in this
file: `tests/performance/measure-status.uc` drives the same plugin and imports
the same fakes, so there is exactly one definition of what a router's `uci` and
`ubus` look like to this backend. A suite that re-implemented them could pass
against a fake more forgiving than the other suite's.

- **status** — reads UCI, procd, `VERSION` and the cache; a cache older than 24
  hours is ignored while configured devices stay visible and offline; a corrupt
  cache and a malformed `VERSION` degrade to empty/`null`; status never creates
  a lock or a cache file.
- **conflicts** — a running legacy init script, legacy binaries in `/usr/bin`,
  a foreign engine process (with a fake `ps`, so our own pids, a pidfile-marked
  pid and a `grep airupnp` look-alike are all distinguished), and nothing at all
  when none is present; detection never deletes or modifies what it finds.
- **action** — an unknown name dies without running anything; `start` and
  `restart` are refused while a legacy instance is present, `stop` is not; a
  failing command's output is reported; success is claimed only when procd
  agrees, and a stop that leaves an engine running is a failure.
- **scan** — refused with no engine enabled, with an invalid interface token
  (from `config.uc`), and while a live lock exists; a worker that cannot be
  started is reported as a failure and leaves no lock.
- **the worker branch** — run directly with the fixed `scan-worker` argument, it
  records the failure, keeps the previous snapshot and scan time, releases the
  lock, exits nonzero, and prints nothing (so it can never register an object).
- **logs** — 200 newest lines, CR and control bytes stripped, 512-byte line cap,
  truncation reported, the three sources merged in order, and no path or config
  value in the reply.
