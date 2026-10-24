# OpenWrt AirConnect

<div align="center">

English Version | [中文版本](README.zh-CN.md)

</div>

---

A standalone OpenWrt/iStoreOS adaptation project directly targeting [philippe44/AirConnect](https://github.com/philippe44/AirConnect). The native engine handles audio bridging, while this project maintains packaging, service management, configuration conversion, and the LuCI interface.

This project uses an independent Git history and is not developed as a fork of `sbwml/luci-app-airconnect`. It serves as a reference for OpenWrt packaging approaches. See [Architecture Decisions](docs/ARCHITECTURE.en-US.md).

## Current Status

- ✅ Migrated UI, device management, native capability auditing, and performance requirements.
- ✅ All three packages are implemented in the repository:
  - `airconnect-engine`: Engine package recipe (fixed official release 1.12.4 with SHA256, installed to independent libexec path, no service registration)
  - `airconnect-manager`: Contains UCI validation, atomic XML generation, procd startup scripts, and `airconnect.manager` rpcd backend
  - `luci-app-airconnect-manager`: Static LuCI pages with three tabs: speakers, settings, and diagnostics
- ✅ Only host verification available: all 11 test suites pass (2465 assertions) via `bash scripts/run-tests.sh`. Command and results recorded in [Verification Record](docs/VERIFICATION.zh-CN.md), with details in [Testing & CI](docs/TESTING.zh-CN.md).
- ⚠️ CI workflow (`.github/workflows/test.yml`) is implemented but never executed: no CI run results available.
- ❌ Not yet completed:
  - No APK or IPK built using SDK
  - Not installed or running on real routers
  - Not connected to actual speakers; AirPlay volume mapping and playback unverified
  - LuCI pages only checked under `dev/` mock backend, not loaded in real LuCI with rpcd/UCI
  - Old instance migration and rollback scripts only have host testing, never executed on routers
- Local development does not replace existing router services. Initial switching requires backup, disabling old instances, migrating configuration, validation, and providing rollback options.
- See [Old Instance Migration Guide (Chinese)](docs/MIGRATION.zh-CN.md) for detection, configuration mapping, disabling, and rollback steps (not yet executed on real hardware).

## Three-Layer Architecture

| Layer | Responsibility | Status | Pending |
|-------|----------------|--------|---------|
| `airconnect-engine` | Official airupnp/aircast binaries, version & source tracking | Implemented with host tests | Only recipe static checks (`tests/engine/check-recipe.sh`); not built via SDK, 95 MB upstream archive not fully downloaded |
| `airconnect-manager` | UCI validation, atomic XML generation, procd, restricted diagnostic RPC | Implemented with host tests | Real rpcd registration, procd/netifd response shapes, real SSDP discovery, init script behavior on device not verified |
| `luci-app-airconnect-manager` | shadcn-style static LuCI pages, devices & common settings priority | Implemented, unverified on real devices | Only `rules.js` has host tests; pages only checked under `dev/` mock backend, not loaded in real LuCI with rpcd/UCI |
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

All 11 test suites should pass with 2465 assertions.

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
