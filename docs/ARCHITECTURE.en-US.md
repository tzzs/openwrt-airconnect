# Architecture Decisions / 架构决策

<div align="center">

[中文版本](ARCHITECTURE.zh-CN.md) | English Version

</div>

---

## Overview

This document describes the architectural decisions for the OpenWrt AirConnect project, focusing on the packaging approach that separates concerns between native binary distribution, service management, and user interface.

## Core Principles

### 1. Independent Git History

The project maintains its own Git history rather than forking from `sbwml/luci-app-airconnect`. This provides:
- Clean separation of concerns
- Ability to reference upstream without dependency
- Freedom to choose different implementation approaches

### 2. Three-Layer Separation

```
┌─────────────────────────────────────────┐
│         User Interface Layer            │
│  luci-app-airconnect-manager (LuCI)    │
│  - Static pages with shadcn styling    │
│  - Device management                    │
│  - Settings configuration               │
│  - Diagnostic tools                     │
└─────────────────────────────────────────┘
              ↓ communicates via RPC
┌─────────────────────────────────────────┐
│      Service Management Layer           │
│  airconnect-manager (ucode + rpcd)     │
│  - UCI configuration validation         │
│  - XML generation (atomic updates)      │
│  - Service lifecycle management         │
│  - Status reporting                     │
└─────────────────────────────────────────┘
              ↓ controls
┌─────────────────────────────────────────┐
│       Engine Distribution Layer         │
│     airconnect-engine (static binary)  │
│  - Official binaries only (no build)   │
│  - Version pinning & verification      │
│  - Installation to libexec path        │
└─────────────────────────────────────────┘
```

### 3. Native Binary Integration

The approach treats AirConnect as a black-box binary:
- **No compilation**: Official binaries are downloaded and distributed as-is
- **Version pinning**: Fixed version (1.12.4) with SHA256 verification
- **Independent installation**: Installed to `/usr/libexec/airconnect`
- **Service management**: External control via procd/UCI

## Component Details

### airconnect-engine

**Purpose**: Distribute official AirConnect binaries without modification.

**Key Characteristics**:
- Purely declarative package recipe
- No compile step in OpenWrt build system
- Downloads upstream tarball with hash verification
- Extracts to independent libexec path
- Does not register init scripts or services

**Package Structure**:
```
packages/airconnect-engine/files/
├── Makefile                 # Build recipe (fixed version)
├── UPSTREAM-LICENSE         # Original license text
└── LIBEXEC/                 # Extracted binaries
    ├── airupnp              # Apple AirPlay receiver
    └── aircast              # Chromecast receiver
```

**Benefits**:
- Guarantees binary integrity
- Simplifies version tracking
- Avoids build environment complexity
- Reduces attack surface

### airconnect-manager

**Purpose**: Bridge between LuCI UI and engine binaries through UCI configuration.

**Key Components**:
1. **Configuration Validation** (`config.uc`)
   - Schema validation for all UCI options
   - Default value management
   - Cross-device consistency checks

2. **XML Generation** (`renderXml.uc`)
   - Atomic file writes (write → rename pattern)
   - XML templates for UPnP and Chromecast
   - Dynamic device-specific configuration

3. **RPC Backend** (`airconnect.manager`)
   - ucode-based RPC daemon plugin
   - Five public methods: `status`, `logs`, `scan`, `validate`, `action`
   - Real-time device discovery cache
   - Broadcast monitoring via mDNS socket API

4. **Init Scripts** (`procd`)
   - Service lifecycle management
   - Netifd integration for network state
   - Automatic restart on failures

**Design Decisions**:
- Uses `ucode` instead of Lua for JavaScript familiarity
- Atomic XML writes prevent partial configuration corruption
- Restricts diagnostic operations to read-only status queries
- Implements four-state model (running, discovered, broadcasting, playing)

### luci-app-airconnect-manager

**Purpose**: Provide intuitive web interface for device and configuration management.

**UI Architecture**:
```
Static LuCI Pages
├── View Layer (HTML/CSS/JS)
│   ├── overview.js         # Main view component
│   ├── rules.js            # Field validation rules
│   └── manager.css         # Scoped styling
├── Shared Contract (tests/parity/cases.json)
└── Mock Backend (dev/)
```

**Feature Scope**:
- **Speakers Tab**: Device list with override capabilities
- **Settings Tab**: Global audio format and buffer preferences
- **Diagnostics Tab**: Logs, status, and manual scan triggers

**Validation Strategy**:
- Client-side validation mirrors server-side rules
- Single source of truth in `rules.js`
- Test suite ensures parity between client and server

## Configuration Model

### UCI Structure

```
config airconnect-manager 'main'
    option max_volume '100'
    option audio_format 'flac'
    option buffer_size '2048'
    
config airconnect-manager 'device_001122334455'
    option name 'Living Room Speaker'
    option airplay_name 'Living Room'
    option override_max_volume '30'
```

**Key Design Points**:
- Single "main" config section for global settings
- Per-device sections identified by MAC address
- Empty override values inherit from global config
- All changes validated before applying

### State Model

The system tracks four distinct states independently:

| State | Source | Measurement Method |
|-------|--------|-------------------|
| **Running** | procd | ubus service status |
| **Discovered** | SSDP cache | Recent SSDP response |
| **Broadcasting** | mDNS observation | `_raop._tcp` TXT record |
| **Playing** | Unknown | Not exposed by upstream |

**Important**: Playing state is explicitly `unknown` because upstream binaries provide no documented status API. This avoids speculating about playback state.

## Security Considerations

### Binary Integrity
- SHA256 hash verification for all upstream downloads
- No compilation means no build-time vulnerabilities
- Static binaries reduce dynamic link dependencies

### Configuration Security
- UCI validation prevents injection attacks
- RPC methods restricted to read-only diagnostics
- No direct shell access from UI layer

### Isolation
- Engines run with minimal privileges
- Separate installation paths prevent conflicts
- Clear boundaries between layers

## Performance Targets

### Resource Budget
| Metric | Target | Actual |
|--------|--------|--------|
| Static payload (compressed) | 32 KiB | 12,313 B |
| Status response (1 device) | 64 KiB | 792 B |
| Status response (64 devices) | 64 KiB | 35,167 B |
| Poll interval | 10s | 10s |
| Poll backoff on failure | 60s | 60s |

### Optimization Strategies
- Minimized JavaScript footprint
- Scoped CSS to prevent leaks
- Lazy loading of diagnostic data
- Debounced status refresh

---

# 架构决策

## 概述

本文档描述 OpenWrt AirConnect 项目的架构决策，重点在于包装方法，在原生二进制分发、服务管理和用户界面之间分离关注点。

## 核心原则

### 1. 独立 Git 历史

项目维护自己的 Git 历史，而不是从 `sbwml/luci-app-airconnect` fork。这提供了：
- 清晰的关注点分离
- 能够引用上游而不依赖
- 自由选择不同的实现方法

### 2. 三层分离

（同上架构图）

### 3. 原生二进制集成

该方法将 AirConnect 视为黑盒二进制文件：
- **无编译**：下载官方二进制文件并原样分发
- **版本锁定**：固定版本（1.12.4）带 SHA256 验证
- **独立安装**：安装到独立的 libexec 路径
- **服务管理**：通过 procd/UCI 外部控制

## 组件详情

（与英文版相同，翻译见中文版）

## 配置模型

（同上文）

## 安全考虑

### 二进制完整性
- 所有上游下载的 SHA256 哈希验证
- 无编译意味着无构建时漏洞
- 静态二进制减少动态链接依赖

### 配置安全
- UCI 验证防止注入攻击
- RPC 方法限制为只读诊断
- UI 层无直接 shell 访问

### 隔离
- 引擎以最小权限运行
- 独立安装路径防止冲突
- 各层之间有清晰边界

## 性能目标

（同上文）

## 优化策略

### 资源预算
- 最小化 JavaScript 文件大小
-  scoped CSS 防止污染
- 诊断数据懒加载
- 状态刷新防抖动

---

<div align="center">

[中文版本](ARCHITECTURE.zh-CN.md) | English Version

</div>
