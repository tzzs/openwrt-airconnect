# OpenWrt AirBridge

<div align="center">

English Version | [中文版本](README.zh-CN.md)

</div>

---

AirBridge is a standalone OpenWrt/iStoreOS adaptation project directly targeting [philippe44/AirConnect](https://github.com/philippe44/AirConnect). The native engine handles audio bridging, while AirBridge maintains packaging, service management, configuration conversion, and the LuCI interface.

AirBridge uses an independent Git history and is not developed as a fork of `sbwml/luci-app-airconnect`. The upstream project is used as a packaging reference.

## Naming

The product is **AirBridge** (隔空音箱 in Chinese). The internal identifiers intentionally keep their historical `airconnect` spelling: the UCI configuration is still named `airconnect-manager` and the rpcd object is still `airconnect.manager`. This lets devices that already have the previous packages installed upgrade in place without losing settings; those names are compatibility identifiers, not a missed rename.

## Current Status

The first supported target is OpenWrt/iStoreOS 25.12 on `aarch64_generic`.

- The engine, manager, and LuCI packages are implemented; local SDK builds and installation of all four APKs (including Chinese translation) have been verified on iStoreOS 25.12.5 / aarch64.
- The legacy service was migrated and replaced on the reference router. The new service starts at boot; rpcd methods, scanning, and logged-in LuCI page rendering were verified. S4 also confirmed Chinese translations and the three LuCI tabs.
- Host tests and PR CI have passed. The release workflow is configured, but a successful remote Release/Pages publication and signed repository have not been verified.
- Still pending: real speaker discovery/playback and volume behavior, router performance measurements, upgrade configuration retention, migration rollback rehearsal, and save/apply/reset behavior in LuCI. The tested network had no discoverable UPnP/DLNA renderer.
- Only `aarch64_generic` has been built and device-tested. `x86_64` and OpenWrt 24.10/IPK remain out of scope for the current build.

See the [Migration Guide](docs/MIGRATION.zh-CN.md) before replacing a legacy installation. Release steps and remaining checks are in the [Release and Installation Guide](docs/RELEASE.zh-CN.md).

## Installation

For OpenWrt/iStoreOS 25.12 on `aarch64_generic`, add the project's test repository and install the single user-facing LuCI package:

```sh
cat >> /etc/apk/repositories <<'EOF'
https://tzzs.github.io/openwrt-airconnect/aarch64_generic/base
EOF

apk --allow-untrusted update
apk add --allow-untrusted luci-app-airconnect-manager
```

`luci-app-airconnect-manager` pulls `airconnect-manager`, `airconnect-engine`, and the required runtime dependencies automatically. To install the optional Simplified Chinese LuCI translation:

```sh
apk add --allow-untrusted luci-i18n-airconnect-manager-zh-cn
```

This Pages repository is currently unsigned and is for testing only. Keep `--allow-untrusted` until APK and repository signing is configured. If Pages is not enabled yet, download the four APKs from the GitHub Release and install them together with `apk add --allow-untrusted`; users do not need to build the SDK.

### Developer Build

For local package development, use the matching OpenWrt SDK and run the repository's reproducible four-package script:

```bash
bash scripts/build-local.sh
```

The output is written to `packages/output/`. The release workflow performs the same SDK build automatically only after a release-please PR is merged and its tag is created.

### Run Tests Locally

```bash
bash scripts/run-tests.sh
```

All host test suites should pass.

## Documentation

- [Migration Guide (Chinese)](docs/MIGRATION.zh-CN.md): migrate, verify, or roll back a legacy installation.
- [Release and Installation Guide (Chinese)](docs/RELEASE.zh-CN.md): supported targets, release flow, and pre-release checks.

## License

The independent packaging uses MIT license at root directory. AirConnect root LICENSE states MIT and requires third-party components to comply with their own conditions; original text preserved in `packages/airconnect-engine/files/UPSTREAM-LICENSE`. Dependencies and distribution obligations in native release packages must be verified before official release, not replaced by package metadata.

---

<div align="center">

[中文文档](README.zh-CN.md) | English Version

</div>
