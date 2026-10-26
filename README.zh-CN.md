# OpenWrt AirConnect

<div align="center">

[English Version](README.md) | 中文版本

</div>

---

直接面向 [philippe44/AirConnect](https://github.com/philippe44/AirConnect) 的独立 OpenWrt/iStoreOS 适配项目。原生引擎负责音频桥接，本项目维护软件包、服务管理、配置转换和 LuCI 界面。

本项目使用独立 Git 历史，不基于 `sbwml/luci-app-airconnect` 的 fork 继续开发。该项目仅作为 OpenWrt 封装方式的参考，见 [架构决策](docs/ARCHITECTURE.zh-CN.md)。

## 当前状态

- ✅ 已迁入界面、设备管理、原生能力审计和性能需求。
- ✅ 仓库中已实现三个功能包：
  - `airconnect-engine`：引擎包配方（固定官方 1.12.4 发布包及 SHA256，安装到独立的 libexec 路径，不注册服务）
  - `airconnect-manager`：包含 UCI 校验、原子生成 XML、procd 启动脚本和 `airconnect.manager` rpcd 后端
  - `luci-app-airconnect-manager`：音箱、设置、诊断三个页签的静态 LuCI 页面
- ✅ 主机验证：`bash scripts/run-tests.sh` 的 20 个套件全部通过，命令与结果记录在 [验证记录](docs/VERIFICATION.zh-CN.md)，说明见 [测试运行与 CI](docs/TESTING.zh-CN.md)。
- ✅ SDK 发布链：已配置三个功能包加上自动生成的 `luci-i18n-airconnect-manager-zh-cn` 中文翻译包，使用 OpenWrt SDK 25.12.6（`armsr-armv8` / `aarch64_generic`）构建。上游归档的 SHA256 与配方 `PKG_HASH` 校验一致后才进入构建，发布工作流会生成包含全部四个 APK 的 OpenWrt 25.12 `packages.adb` 索引并发布到 GitHub Pages。当前 Pages 仓库尚未签名，仅用于测试；仍需记录一次成功的远程发布运行。
- ✅ 设备安装：三个功能 APK 已用 `apk add --allow-untrusted` 装到真实的 iStoreOS 25.12.5 / aarch64 路由器。`airconnect.manager` 在真实 rpcd 上注册成功，五个方法齐全，`status`、`validate`、`logs`、`action` 均在设备上跑过。引擎二进制在设备上可执行并报 `v1.12.4`。新的中文翻译 APK 尚未在设备上安装验证。
- ⚙️ CI 工作流：`test.yml` 在每次 push 和 pull request 上运行主机测试。`release.yml` 在 `main` 上由 release-please 管理；发布 PR 合并后，它会构建四个 APK、上传到 GitHub Release，并发布 Pages APK 仓库。当前本地工作流改动仍需一次成功的远程运行；首次启用时还要在仓库设置中把 Pages Source 设为 GitHub Actions。
- ✅ 服务切换已完成（2026-10-26，第一台真实设备）：旧 `airconnect`、`luci-app-airconnect`、
  `luci-i18n-airconnect-zh-cn` 连同依赖已卸载，配置按 UCI 映射迁移，`airconnect-manager` 在运行
  且已设为开机自启，`status.conflicts` 为空，RPC 的启动/重启恢复正常。
- ❌ 以下事情都还没有发生：
  - 没有接入真实音箱：扫描能跑完，mDNS 观测也写入了时间戳，但该网段没有 AirConnect 能发现的
    UPnP/DLNA 渲染器，AirPlay 满音量映射与播放仍未验证
  - LuCI 页面没有在登录后的浏览器会话里打开过，只验证了静态资源能被 HTTP 取到
  - 设备侧性能（CPU、RSS、网络、播放中断）未测量
  - 回退（`--rollback`）从未在路由器上演练过；升级保留设置也还没验证
- 本地开发不会替换路由器现有服务。首次切换已经走完一遍：备份 → 停用旧实例 → 迁移配置 → 卸载
  旧包 → 启动新服务 → 验证。**实测纠正**：冲突拦截只在 RPC 路径生效（init 脚本不检查），且
  卸载旧包会把新服务一起停掉、需要重新启动。
- 旧实例的检测、配置映射、停用、卸载与回退步骤见 [旧实例迁移手册](docs/MIGRATION.zh-CN.md)，
  首次现场执行的完整记录（含四处与文档不符的偏差）在该文件的“首次执行记录”一节。

## 三层结构

| 层 | 职责 | 状态 | 未完成 |
| --- | --- | --- | --- |
| `airconnect-engine` | 官方 airupnp/aircast 二进制、版本与来源追踪 | 已实现，已用 SDK 构建并装到设备 | 只构建了 `aarch64`；`x86_64` 既没构建也没运行过 |
| `airconnect-manager` | UCI 校验、原子生成 XML、procd、受限诊断 RPC | 已实现，已用 SDK 构建、装到设备并完成服务切换 | procd 实例形状、init 脚本启动路径与卸载旧包后的 RPC 恢复都已在真机验证；扫描能跑完但网段内没有可发现的音箱，真实音箱的发现与播放仍未验证 |
| `luci-app-airconnect-manager` | shadcn 风格静态 LuCI 页面，设备和常用设置优先 | 已实现，已用 SDK 构建并装到设备 | 静态资源可访问、menu/ACL JSON 有效；页面本身未在登录会话中打开过 |
| `tests/` | 主机测试与静态检查 | 已实现并有主机测试 | 没有在 CI 上跑过：工作流已写好但从未触发 |

状态只按仓库里的文件判定：没有对应代码或没有对应测试的层不写成已实现；构建与设备验收的结果见 [验证记录](docs/VERIFICATION.zh-CN.md)。

**首版验证目标：** OpenWrt/iStoreOS 25.12、aarch64_generic；随后验证 x86_64。24.10/IPK 单独构建。不能将 SNAPSHOT 的可安装性替代稳定版 SDK 构建与设备验收。

## 安装

对于 OpenWrt/iStoreOS 25.12 的 `aarch64_generic` 设备，添加项目测试仓库后只安装一个面向用户的 LuCI 主包即可：

```sh
cat >> /etc/apk/repositories <<'EOF'
https://tzzs.github.io/openwrt-airconnect/aarch64_generic/base
EOF

apk --allow-untrusted update
apk add --allow-untrusted luci-app-airconnect-manager
```

`luci-app-airconnect-manager` 会自动拉取 `airconnect-manager`、`airconnect-engine` 以及所需运行时依赖。需要简体中文 LuCI 翻译时，再安装可选包：

```sh
apk add --allow-untrusted luci-i18n-airconnect-manager-zh-cn
```

当前 Pages 仓库尚未签名，仅用于测试。在完成 APK 和仓库签名前，请保留 `--allow-untrusted`。如果 Pages 尚未启用，也可以从 GitHub Release 下载四个 APK 后，用 `apk add --allow-untrusted` 一起安装；普通用户不需要自行构建 SDK。

## 开发入口

### 本地开发构建

开发软件包时使用匹配目标版本的 OpenWrt SDK，并运行仓库提供的可复现四包构建脚本：

```bash
bash scripts/build-local.sh
```

产物写入 `packages/output/`。发布工作流只会在 release-please 发布 PR 合并并创建 tag 后，自动执行同一套 SDK 构建。

### 本地运行测试

```bash
bash scripts/run-tests.sh
```

所有 20 个测试套件应该通过。

## 文档索引

| 文档 | 说明 |
|------|------|
| [产品定位](PRODUCT.md) | 核心产品目标和定位 |
| [实施计划](ROADMAP.zh-CN.md) | 开发路线图和里程碑 |
| [架构决策](docs/ARCHITECTURE.zh-CN.md) | 独立架构参考 |
| [UI 与设备信息需求](docs/UI-REQUIREMENTS.zh-CN.md) | 用户界面和设备信息需求 |
| [上游原生能力映射](docs/AIRCONNECT-CAPABILITIES.zh-CN.md) | 上游原生功能映射 |
| [性能约束](docs/PERFORMANCE.zh-CN.md) | 性能需求和约束 |
| [验证记录](docs/VERIFICATION.zh-CN.md) | 测试验证结果 |
| [测试运行与 CI](docs/TESTING.zh-CN.md) | 测试执行和 CI 设置 |
| [旧实例迁移](docs/MIGRATION.zh-CN.md) | 从旧版本的迁移指南 |

## 来源与许可

独立编写的封装使用根目录 MIT 许可证。AirConnect 根 LICENSE 声明 MIT，并要求第三方组件遵守各自条件；保留的原文见 `packages/airconnect-engine/files/UPSTREAM-LICENSE`。原生发布包包含的依赖许可及分发义务须在正式发布前完成核对，不以包元数据代替依赖许可审计。

---

<div align="center">

[English Version](README.md) | 中文版本

</div>
