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
  the exact default XML for both engines.

## parity

Frontend/backend validation parity. `cases.json` is the hand-maintained
contract; both runners must agree with it.

- Backend: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/parity/run.uc`
- Frontend: `node tests/parity/check-frontend.mjs`
- Covers: every row of the interface/latency/max_volume/media_volume/name/log_level
  mismatch table plus its boundary values (0/1/100/101, `1.5`, `0999:1`,
  `10000:10000`, 63/64-byte names, whitespace-only names, `.` and `..`), in both
  the `main` section and a device override. The backend runner decides each case
  with the real `normalizeConfig`; the node runner loads
  `airconnect-manager/rules.js` in a shim, asks the ucode runner for the backend
  verdicts and fails when the two disagree. It also proves `rules.js` loads
  without LuCI's `_()` and returns message strings, not `false`.

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
  codes for `apply`, `validate` and `show`.

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
  `--apply` refusing, backup-directory collisions, `--force-stop-new`, and the
  Docker-only / old-binary-only / no-UDN / disabled-legacy cases. The script is
  additionally parsed with `dash -n`.
- See `tests/migration/README.md` for the sandbox layout and what a host cannot
  verify (real uci, procd, docker, init scripts, speakers).
