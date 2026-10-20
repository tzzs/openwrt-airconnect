# Tests

This directory holds host-side test suites for `airconnect-manager`. They run
against a real ucode interpreter on the host; the router never runs them.

## config

Pure validation and XML render checks for `config.uc`.

- Command: `~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/config/run.uc`
- Covers: `normalizeConfig` and `renderXml` — every accepted value, every
  rejected value (including control-byte and trailing-newline regressions), and
  the exact default XML for both engines.

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

## package

Static checks for the packaged files (package metadata and the init script).

- Command: `bash tests/package/check-package.sh` and `bash tests/package/run-init-script.sh`
- Covers: package manifest rules, file layout, and procd/init-script behaviour
  on the host, without building the OpenWrt packages.
