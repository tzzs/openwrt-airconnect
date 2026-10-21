# Tests

This directory holds host-side test suites for `airconnect-manager`. They run
against a real ucode interpreter on the host; the router never runs them.

## Run everything

```sh
bash scripts/run-tests.sh            # one PASS/FAIL line per suite, then a summary
bash scripts/run-tests.sh --verbose  # stream each suite's full output
```

`scripts/run-tests.sh` discovers suites by convention — `tests/<suite>/run.uc`
(ucode), `tests/<suite>/*.mjs` (node) and `tests/<suite>/**/*.sh` (bash) — so a
new suite is picked up without editing the runner. Pass/fail is judged by exit
status only, so a suite may print TAP or its own summary. A failing suite does
not stop the run.

The ucode interpreter comes from `$UCODE`, then
`~/.local/opt/ucode-host/bin/ucode`, then `ucode` on PATH; when none is found
the runner stops with build instructions instead of skipping the ucode suites.
See [docs/TESTING.zh-CN.md](../docs/TESTING.zh-CN.md) for what these suites
prove, what they cannot prove, and what CI covers.

The per-suite `Command:` lines below are the exact invocations the runner uses;
they are handy when debugging one suite in isolation.

## config

Pure validation and XML render checks for `config.uc`.

- Command: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/config/run.uc`
- Covers: `normalizeConfig` and `renderXml` — every accepted value, every
  rejected value (including control-byte and trailing-newline regressions), and
  the exact default XML for both engines. It also covers the advanced engine
  parameters: defaults, per-device overrides, empty-value inheritance, rejection
  of out-of-range values, and the engine separation — a rendered `<airupnp>`
  never contains `stop_receiver`, a rendered `<aircast>` never contains
  `http_length` or `upnp_max`.

## parity

Frontend/backend validation parity. `cases.json` is the hand-maintained
contract; both runners must agree with it.

- Backend: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/parity/run.uc`
- Frontend: `node tests/parity/check-frontend.mjs`
- Covers: every row of the
  interface/latency/max_volume/media_volume/name/log_level/metadata/flush/drift/
  stop_receiver/http_length/upnp_max/artwork mismatch table plus its boundary
  values (0/1/100/101, `1.5`, `0999:1`, `10000:10000`, 63/64-byte names,
  whitespace-only names, `.` and `..`, `-3/-1/0` versus `-2/1/4096`, `1/3/9`
  versus `0/10`, `http://` versus `ftp://`), in both the `main` section and a
  device override. The backend runner decides each case
  with the real `normalizeConfig`; the node runner loads
  `airconnect-manager/rules.js` in a shim, asks the ucode runner for the backend
  verdicts and fails when the two disagree. It also proves `rules.js` loads
  without LuCI's `_()` and returns message strings, not `false`.

## luci

Which controls the production view offers for which engine.

- Command: `node tests/luci/run.mjs`
- Covers: the real, unmodified `overview.js` building both forms for a UPnP and a
  Chromecast device. A Chromecast device never offers `http_length` or `upnp_max`,
  a UPnP device never offers `stop_receiver`, every per-device advanced control
  accepts an empty value (which means "inherit"), the `http_length`/`upnp_max`
  selects offer exactly the values `config.uc` accepts, and the engine-specific
  global fields carry an engine-specific label. **Does not cover** a real LuCI
  render, a real browser or the resulting DOM.

## discovery

Bounded SSDP and XML parser checks for `discovery.uc`.

- Command: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/discovery/run.uc`
- Covers: `parseSsdp`, `parseDescription`, `validateLocation`, `privateAddress`
  and `deduplicate` — strict header/URL parsing, control-byte scanning, comment
  handling and the bounded XML tokenizer.

## runtime

UCI loading, validation and atomic runtime-file writes for `runtime.uc`.

- Command: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/runtime/run.uc`
- Covers: `loadConfig` with an injected fake cursor, `applyConfig` rendering and
  writing both engines, the "keep the last good file" guarantee on validation
  and render failures, per-file atomicity when one engine fails, `dry_run`,
  0750/0640 modes, `status.json` shape and digest stability, and the CLI exit
  codes for `apply`, `validate` and `show`. It also proves a configuration that
  predates the advanced options renders byte-identical XML to the current
  default configuration, which is the backwards-compatibility promise.

## state

Pure reply shaping (`state.uc`), bounded file access (`files.uc`) and the rpcd
plugin itself.

- Command: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/state/run.uc`
  and `bash tests/state/check-plugin.sh`
- Covers: the configured-but-offline merge, cache staleness, `ps` parsing,
  log tailing and truncation, error clamping, the plugin's rpcd signature, and
  every RPC method against a sandbox root with fake `uci`/`ubus` modules.
- See `tests/state/README.md` for what a host cannot verify (real rpcd, procd,
  netifd and SSDP).

## performance

Measurement suites: the static payload, the rpcd reply sizes and the polling
contract. They are tests **and** the source of the numbers in
[docs/PERFORMANCE-RESULTS.zh-CN.md](../docs/PERFORMANCE-RESULTS.zh-CN.md), so a
budget cannot drift away from the documentation.

- Command: `bash tests/performance/measure-payload.sh`,
  `bash tests/performance/measure-status.sh`,
  `node tests/performance/poll-contract.mjs`
- `measure-payload.sh` — bytes and `gzip -9` bytes of every static file the LuCI
  package installs (the resources tree plus the menu and ACL JSON), with a total
  and a per-file budget. Measured with no SDK, no router and no network.
- `measure-status.sh` — drives the real rpcd plugin through the shared fake
  `uci`/`ubus` modules (`tests/state/stubs.uc`) and records `status` reply bytes
  at 1/8/32/64 devices, the 64-device cap against 128 candidates, `logs` reply
  bytes at the documented caps, and the subprocess count per call.
- `poll-contract.mjs` — loads the production `overview.js` in the same module
  shim `tests/parity/check-frontend.mjs` uses and asserts the polling contract:
  10000 ms interval, skip while `document.hidden`, one request in flight,
  backoff to 60000 ms, and that `updateStatus` never writes to a form control.
- Covers: byte budgets, reply bounds and the poll decisions. **Does not cover**
  router CPU, RSS/VSZ, network, playback interruption, browser long tasks or a
  real LuCI — see the "未测量" section of the results file.

## package

Static checks for the packaged files (package metadata and the init script).

- Command: `bash tests/package/check-package.sh` and `bash tests/package/run-init-script.sh`
- Covers: package manifest rules, file layout, and procd/init-script behaviour
  on the host, without building the OpenWrt packages.

## engine

Static and behavioural checks for the `airconnect-engine` recipe.

- Command: `bash tests/engine/check-recipe.sh`
- Covers: recipe content (version, upstream digest, arch restriction, POSIX
  extract helper), `AIRCONNECT_ARCH` normalization through `make -f`, and the
  extraction script driven against a synthetic zip. The 95 MB upstream archive
  is never downloaded here.
- See `tests/engine/README.md` for the deliberate limits of a synthetic archive.

## migration

Host tests for `scripts/migrate-legacy.sh`, the legacy-instance migration and
rollback script.

- Command: `bash tests/migration/run.sh`
- Covers: default invocation and `--dry-run` changing nothing (recursive digest
  comparison), every mapping and skip line including the alternate legacy key
  spellings, `--apply` writing the mapped UCI plus one backup with a manifest,
  `--rollback` restoring the original bytes and being idempotent, a second
  `--apply` refusing, backup-directory collisions, `--force-stop-new`, the
  Docker-only / old-binary-only / no-UDN / disabled-legacy cases, and a
  cross-check that the generated file passes the shipped `normalizeConfig` and
  renders both engines. The script is additionally parsed with `dash -n`.
- See `tests/migration/README.md` for the sandbox layout and what a host cannot
  verify (real uci, procd, docker, init scripts, speakers).
