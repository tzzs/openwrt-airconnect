# Engine recipe tests

Host-side checks for `packages/airconnect-engine` (the upstream binary package).
They run with no network, no OpenWrt SDK and no router: `bash`, `make`, `zip`,
`unzip` and a POSIX `sh` are all that is needed.

```sh
bash tests/engine/check-recipe.sh
```

Exit status is non-zero on the first failing check.

## Coverage

- **Recipe content** — `PKG_VERSION` stays `1.12.4`, `PKG_HASH` matches the
  GitHub-API digest, `PKG_SOURCE_URL` points at the `philippe44/AirConnect`
  releases path, `DEPENDS` restricts the build to `aarch64`/`x86_64`,
  `Build/Prepare` references `AIRCONNECT_ARCH`, `unzip -l` diagnostics are
  present, the extract helper is POSIX `sh`, `PKG_LICENSE` stays `MIT`, and the
  package adds no init script or config.
- **ARCH normalization** — the recipe's `AIRCONNECT_ARCH` mapping block is
  extracted verbatim and exercised with `make -f` for each of
  `x86_64 aarch64 aarch64_generic aarch64_cortex-a53 arm_cortex-a7_neon-vfpv4
  arm armv7 mips mipsel riscv64`. Subtarget names normalize to their short
  token (e.g. `aarch64_generic` → `aarch64`), known tokens pass through, and an
  unmapped arch (`riscv64`) triggers a build error.
- **Extraction** — `files/extract-engines.sh` is driven against a synthetic zip
  that mirrors the upstream layout. It must place exactly the two expected
  binaries, fail cleanly (and print the real archive listing) when the arch
  binary is missing, and fail on a missing archive.

## What is deliberately not checked

The 95 MB upstream archive is never downloaded in this environment, so the test
exercises the recipe logic with a synthetic archive. Archive contents, SDK
compile and on-device execution remain unverified; see
`docs/VERIFICATION.zh-CN.md`.
