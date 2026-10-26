# OpenWrt AirConnect

<div align="center">

English Version | [中文版本](README.zh-CN.md)

</div>

---

A standalone OpenWrt/iStoreOS adaptation project directly targeting [philippe44/AirConnect](https://github.com/philippe44/AirConnect). The native engine handles audio bridging, while this project maintains packaging, service management, configuration conversion, and the LuCI interface.

This project uses an independent Git history and is not developed as a fork of `sbwml/luci-app-airconnect`. It serves as a reference for OpenWrt packaging approaches. See [Architecture Decisions](docs/ARCHITECTURE.en-US.md).

## Current Status

- ✅ Migrated UI, device management, native capability auditing, and performance requirements.
- ✅ The three functional packages are implemented in the repository:
  - `airconnect-engine`: Engine package recipe (fixed official release 1.12.4 with SHA256, installed to independent libexec path, no service registration)
  - `airconnect-manager`: Contains UCI validation, atomic XML generation, procd startup scripts, and `airconnect.manager` rpcd backend
  - `luci-app-airconnect-manager`: Static LuCI pages with three tabs: speakers, settings, and diagnostics
- ✅ Host verification: all 20 test suites pass via `bash scripts/run-tests.sh`. Command and results are recorded in [Verification Record](docs/VERIFICATION.zh-CN.md), with details in [Testing & CI](docs/TESTING.zh-CN.md).
- ⚙️ SDK build path: the three functional packages plus the generated `luci-i18n-airconnect-manager-zh-cn` translation package are configured to build with OpenWrt SDK 25.12.6 (`armsr-armv8` / `aarch64_generic`). The upstream archive's SHA256 is verified against the recipe's `PKG_HASH` before the build, and the release workflow is configured to generate the OpenWrt 25.12 `packages.adb` index for all four APKs on GitHub Pages. The Pages repository is currently unsigned and intended for testing; the first local four-package build is still in progress.
- ✅ Device install: the three functional APKs were installed on a real iStoreOS 25.12.5 / aarch64 router with `apk add --allow-untrusted`. The `airconnect.manager` object registers on the real rpcd with all five methods, and `status`, `validate`, `logs` and `action` were exercised on the device. The engine binaries run there and report `v1.12.4`. The new Chinese translation package has not yet been installed on the device.
- ⚠️ CI workflows (`.github/workflows/test.yml` and `.github/workflows/release.yml`) are implemented but have not yet produced a recorded run. The repository is connected to GitHub, but Pages has not yet been enabled and the release workflow has not yet published an APK repository.
- ✅ Service switchover done (2026-10-26, first real device): the legacy `airconnect`,
  `luci-app-airconnect` and `luci-i18n-airconnect-zh-cn` packages were removed together with their
  dependency chain, the configuration was mapped into UCI, and `airconnect-manager` runs and is set
  to start at boot. `status.conflicts` is empty and the RPC start/restart actions work again.
- ❌ Not yet completed:
  - Not connected to actual speakers: a scan completes and the mDNS observation records a timestamp,
    but the segment has no UPnP/DLNA renderer AirConnect can discover, so AirPlay volume mapping and
    playback remain unverified
  - The LuCI page itself was not opened in a logged-in browser session; only its static assets were fetched over HTTP
  - Device-side performance (CPU, RSS, network, playback interruption) not measured
  - `--rollback` has never been rehearsed on a router, and upgrade-preserves-settings is unverified
- Local development does not replace existing router services. The first switchover has now been
  done end to end: backup, disable the old instance, migrate the configuration, remove the old
  packages, start the new service, verify. **Measured corrections:** the conflict check only guards
  the RPC path (the init script does not check it), and removing the old packages also stops the new
  service, which then has to be started again.
- See [Old Instance Migration Guide (Chinese)](docs/MIGRATION.zh-CN.md) for detection,
  configuration mapping, disabling, removal and rollback. The full record of the first on-device run,
  including four places where the documentation did not match reality, is in its "首次执行记录" section.

## Three-Layer Architecture

| Layer | Responsibility | Status | Pending |
|-------|----------------|--------|---------|
| `airconnect-engine` | Official airupnp/aircast binaries, version & source tracking | Implemented, SDK-built and installed on a device | Only `aarch64` is built; `x86_64` not built or run |
| `airconnect-manager` | UCI validation, atomic XML generation, procd, restricted diagnostic RPC | Implemented, SDK-built, installed on a device, switchover complete | The procd instance shape, the init script's start path and the RPC recovery after removing the old packages are all verified on real hardware; a scan completes but the segment holds no discoverable speaker, so real speaker discovery and playback are not |
| `luci-app-airconnect-manager` | shadcn-style static LuCI pages, devices & common settings priority | Implemented, SDK-built and installed on a device | Static assets are served and the menu/ACL JSON is valid; the page has not been opened in a logged-in browser session |
| `tests/` | Host tests & static checks | Implemented with host tests | Never run on CI: workflow written but never triggered |

Status determined by files in repository: layers without corresponding code or tests marked as not implemented. Build and device acceptance results in [Verification Record (Chinese)](docs/VERIFICATION.zh-CN.md).

**Initial verification targets:** OpenWrt/iStoreOS 25.12, aarch64_generic; followed by x86_64. 24.10/IPK builds separately. SNAPSHOT installability cannot substitute stable SDK build and device acceptance.

## Getting Started

### Development Setup

Use the OpenWrt SDK matching your target version. Link `packages/airconnect-engine` to SDK's `package/` directory, then run:

```bash
make defconfig
make package/airconnect-engine/compile V=s
```

Future CI must fix SDK and Action versions, documenting actually verified architectures. Currently no published successful build claims exist.

### Run Tests Locally

```bash
bash scripts/run-tests.sh
```

All 20 test suites should pass.

## Documentation

| Document | Description |
|----------|-------------|
| [Product Positioning](PRODUCT.md) | Core product goals and positioning |
| [Implementation Plan](ROADMAP.en-US.md) | Development roadmap and milestones |
| [Architecture Decisions](docs/ARCHITECTURE.en-US.md) | Independent architecture reference |
| [UI & Device Requirements (Chinese)](docs/UI-REQUIREMENTS.zh-CN.md) | User interface and device information needs |
| [Native Capabilities Mapping (Chinese)](docs/AIRCONNECT-CAPABILITIES.zh-CN.md) | Upstream native feature mapping |
| [Performance Constraints (Chinese)](docs/PERFORMANCE.zh-CN.md) | Performance requirements and constraints |
| [Verification Record (Chinese)](docs/VERIFICATION.zh-CN.md) | Test verification results |
| [Testing & CI (Chinese)](docs/TESTING.zh-CN.md) | Test execution and CI setup |
| [Old Instance Migration (Chinese)](docs/MIGRATION.zh-CN.md) | Migration guide from previous versions |

## License

The independent packaging uses MIT license at root directory. AirConnect root LICENSE states MIT and requires third-party components to comply with their own conditions; original text preserved in `packages/airconnect-engine/files/UPSTREAM-LICENSE`. Dependencies and distribution obligations in native release packages must be verified before official release, not replaced by package metadata.

---

<div align="center">

[中文文档](README.zh-CN.md) | English Version

</div>
