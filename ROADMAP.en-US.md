# OpenWrt AirConnect Implementation Roadmap / 实施计划

<div align="center">

English Version | [中文版本](ROADMAP.zh-CN.md)

</div>

---

## Overview

This project provides standalone OpenWrt/iStoreOS adaptation for [philippe44/AirConnect](https://github.com/philippe44/AirConnect). It maintains engine packages, management layer, and LuCI interface independently. See [Architecture Decisions](docs/ARCHITECTURE.en-US.md) for details.

## Version 1: New UI, Device Management & Configuration Persistence

### Completed ✅

- [x] Complete UI redesign with shadcn-style system settings layout integrated into LuCI
- [x] Information architecture with "Speakers / Settings / Diagnostics" tabs; mobile-responsive with dark mode support
- [x] Per-device AirPlay name overrides with display of original device info (model, manufacturer, address, protocol, discovery time, bridging state)
- [x] Native AirConnect capabilities mapped to enhanced version, properly separated by engine type (UPnP vs Chromecast)
- [x] Performance as implementation criteria: static payload budgets verified, status polling optimized, log limits enforced
- [x] Per-speaker volume control (1-100, default 100 to maintain upstream behavior)
- [x] Device identification via UPnP UDN rather than DHCP addresses
- [x] UCI-based persistent configuration generation at runtime
- [x] Self-contained installation scripts with conffiles for package integrity
- [x] Frontend/backend validation parity for integer ranges
- [x] Clear documentation that volume limit only constrains AirPlay commands, not physical speaker controls

**Verification Status**: Code and host tests completed. Pending: real device verification, upgrade retention testing, full integration validation.

### In Progress 🚧

- [ ] Real hardware audio verification (AirPlay full-volume mapping playback)
- [ ] Interface status synchronization with actual service state
- [ ] Long-term stability testing under production conditions

## Diagnostics & Extended Features

### Implemented ✅

- [x] Speaker discovery display with model, UDN, address, bridging state, and AirPlay name
- [x] Limited diagnostic controls (rescan, logs, restart) with minimal RPC permissions
- [x] Four-state distinction (running, discovered, broadcasting, playing) with proper source attribution
- [x] No network manipulation for discovery issues (firewall/DNS changes)
- [x] Fixed status checking for partial engine configurations

### Future Considerations 🔮

- [ ] Enhanced broadcast monitoring reliability across different kernel versions
- [ ] Real-time performance metrics collection (CPU, RSS, network)
- [ ] Advanced troubleshooting workflows
- [ ] Multi-language UI support beyond EN/ZH-CN

## Build & Release Pipeline

### Infrastructure Ready ✅

- [x] CI workflow implemented but never executed
- [x] Package build automation with release-please integration
- [x] Version pinning for SDK and build actions
- [x] License compliance checks in release pipeline
- [x] Checksum verification for all artifacts

### Deployment Strategy 🚀

- [ ] Initial deployment to aarch64_generic / OpenWrt 25.12 APK
- [ ] Extension to x86_64 after primary validation
- [ ] Separate maintenance for 24.10 IPK builds
- [ ] Staged rollout with rollback capability
- [ ] Real device acceptance testing before public releases

**Important**: The release workflow is configured but has never been successfully executed. No published builds have been installed on actual devices yet.

## Migration from Existing Customizations

Legacy single-speaker volume limit implementations should be converted to UDN-based UCI configuration:

### Completed ✅

- [x] UDN-based universal UCI device sections with inheritance rules
- [x] Read-only conflict detection with existing services
- [x] Migration script with backup and atomic rename operations

### Remaining ⏳

- [ ] Full migration execution on routers with legacy installations
- [ ] Rollback procedure validation
- [ ] User documentation for migration process

See [Old Instance Migration Guide (Chinese)](docs/MIGRATION.zh-CN.md) for detailed procedures.

## Requirements & Audit Documentation

Core documents defining project scope and constraints:

- [Product Positioning](PRODUCT.md) - Core goals and vision
- [UI & Device Requirements (Chinese)](docs/UI-REQUIREMENTS.zh-CN.md) - Interface specifications
- [Native Capabilities Audit (Chinese)](docs/AIRCONNECT-CAPABILITIES.zh-CN.md) - Feature coverage matrix
- [Performance Constraints (Chinese)](docs/PERFORMANCE.zh-CN.md) - Resource budgets

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Code implemented with host tests completed |
| 🚧 | In progress or requires real device validation |
| 🔮 | Future consideration, not planned yet |
| ⏳ | Deferred pending requirements clarification |

---

## Notes

The items marked `[x]` indicate that corresponding code and host tests exist, **not** that they have been validated on actual routers or speakers. Real device verification remains the critical next step before production release.

For detailed development plans and milestone tracking, see [Implementation Plan (Chinese)](ROADMAP.zh-CN.md).

---

<div align="center">

English Version | [中文版本](ROADMAP.zh-CN.md)

</div>
