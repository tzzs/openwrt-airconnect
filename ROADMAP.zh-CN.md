# AirConnect LuCI 增强版计划

直接使用 philippe44/AirConnect 原生引擎，建立独立的 OpenWrt/iStoreOS 适配封装；sbwml/luci-app-airconnect 只作为封装方式参考。独立维护引擎包、管理适配层和 LuCI 页面，详见 [架构决策](docs/ARCHITECTURE.zh-CN.md)。

## 第一版：新版界面、设备管理与配置持久化

- [x] 重做整个 AirConnect 管理界面，采用用户确认的 shadcn 风格、系统设置式布局；继续嵌入 LuCI，不改其他管理页面。（`overview.js`、`manager.css`）
- [x] 建立“音箱 / 设置 / 诊断”的信息结构，常用操作优先，高级参数渐进展开；适配手机与明暗模式。（`overview.js` 的三个 tabpanel，`manager.css` 的 600px 断点与深色 token）
- [x] 支持配置每台设备的 AirPlay 显示名称，并展示设备原名称、型号、厂商、地址、协议、最后发现时间和可验证的桥接状态。AirPlay 名称与原厂设备名称明确区分。（`overview.js` 的 `updateDevice`，`config.uc` 的名称校验）
- [x] 将原生 AirConnect 能力逐项映射到增强版，按适用引擎、继承关系和优先级呈现，不把 Chromecast 参数误套到 UPnP。（`config.uc` 覆盖 `codec`/`latency`/`max_volume`/`media_volume`/`log_level` 及高级项 `metadata`/`artwork`/`flush`/`drift`（两引擎）、`http_length`/`upnp_max`（仅 UPnP）、`stop_receiver`（仅 Chromecast），全部按上游默认值接入并逐设备继承；`upnp_max` 仅全局，因为上游只读 `glMRConfig.UPnPMax`。XML 渲染按引擎隔离并有测试（`tests/config`、`tests/runtime`），界面按引擎给出控件（`tests/luci`），前后端契约在 `tests/parity`。`stream_type`（Sonos 专用）、型号/名称筛选 CLI 选项、`max_players`/`ports`/`log_limit` 全局项与延迟格式第三段尚未接入，理由见[能力审计](docs/AIRCONNECT-CAPABILITIES.zh-CN.md)。上游未验证 `metadata`/`artwork` 在真实音箱上的显示效果，这属于设备验收）
- [ ] 把性能作为实现验收：静态页面、低频状态轮询、隐藏暂停、缓存发现、日志限量，不新增 Node 常驻服务。（主机侧测量已完成：本包静态资源 5 个文件、未压缩 47,775 B / `gzip -9` 14,646 B 且预算已断言；`status` 回复 1 / 8 / 32 / 64 台设备为 792 / 4,607 / 17,707 / 35,167 B，64 条上限对 128 个候选成立；`logs` 的 200 行 / 512 B 每行 / 64 KiB 文本上限被执行（全反斜杠时报文 130,590 B，故预算按 JSON 转义翻倍定在 160 KiB）；轮询间隔正好 10,000 ms、隐藏时暂停、单请求在途、失败退避到 60,000 ms、状态刷新对表单零写入，均由 `tests/performance/` 断言。**仍未测**：路由器 CPU、RSS/VSZ、网络、播放中断、浏览器长任务，即“以重构前后同条件对比证明不会明显影响播放”这条，故不能关闭。数字、命令与逐项理由见[性能测量结果](docs/PERFORMANCE-RESULTS.zh-CN.md)）

- [x] 在 LuCI 按音箱展示 AirPlay 最大音量，范围 1–100，默认 100 保持上游行为；允许用户自行选择 30 等上限。（`rules.js` 与 `config.uc` 共用同一边界，`tests/parity/`）
- [x] 用 UPnP UDN 标识音箱，避免依赖 DHCP 地址，不内置任何个人设备名称、IP 或 UDN。（`discovery.uc`、`state.uc`；测试与 `dev/` 只用合成 UDN 与 RFC 5737 地址）
- [x] 将每台音箱配置保存为 UCI 段；从 UCI 生成运行时 XML，网页、服务和开机启动使用同一份配置。（`runtime.uc`、`init.d/airconnect-manager`）
- [x] 打包正式启动脚本和界面，不依赖安装后修改文件。把持久配置列入包的 conffiles。（`tests/package/check-package.sh` 校验安装清单与 conffiles）
- [ ] 验证升级时保留设置。（需要真实升级一个已安装的旧版本，尚未执行）
- [x] 前后端校验整数范围；生成配置失败时保留最后的有效配置，避免半写入文件。（`tests/runtime/run.uc`、`tests/parity/`）
- [x] 明确说明：音量上限约束 AirPlay 发出的音量指令，不能限制音箱实体键、语音和原厂 App。（`overview.js` 的字段说明，[能力审计](docs/AIRCONNECT-CAPABILITIES.zh-CN.md)）

验收：[x] 两台模拟音箱独立设置（`tests/config/run.uc`、`tests/state/run.uc`）；[x] 无效值不能提交
（`tests/parity/`）；[ ] 保存、重启服务和升级后数值保持（重启与升级未执行）；[ ] 真实设备验证
AirPlay 满音量映射及反馈；[ ] 界面状态与服务一致（仅在 `dev/` 模拟后端下检查）。

## 诊断与后续扩展

- [x] 展示发现的音箱、型号、UDN、地址、桥接状态和 AirPlay 名称。（`state.uc` 的 `buildStatus`，`discovery.uc` 的 `parseDescription`）
- [x] 提供受限的重新扫描、日志查看与服务重启功能，按最小权限设计 RPC。（`rpcd/ucode/airconnect-manager` 与 `acl.d` 的读写分权）
- [x] 区分服务运行、发现 DLNA 音箱、AirPlay 广播和实际播放四种状态。（前两种来自 UCI/procd/发现缓存；广播由 `broadcast.uc` 观测 mDNS `_raop._tcp` 实例得到，按引擎用 TXT 的 `am=` 标记判定、按设备用 UDN 推出的 MAC 前缀判定，仅在接口使 `SendARP()` 必然失败（Linux 上即非 `eth0`）时可信，否则未知；播放仍为未知，上游没有文档化状态接口。观测缓存 5 分钟，`status` 只读缓存不发起 mDNS，未测量的状态一律显示未知。证据与逐条边界见[验证记录](docs/VERIFICATION.zh-CN.md)）
- [x] 避免通过关闭防火墙、改 DNS 或自动更改网络来解决发现问题。（后端没有防火墙或 DNS 操作）
- [x] 修复现有状态检查：仅启用 aircast 时也能正确显示运行状态。（`tests/package/run-init-script.sh` 的 cast only 用例，`tests/state/run.uc` 的服务状态合并）

## 构建与发布

- [ ] 优先验证 aarch64_generic / OpenWrt 25.12 APK；再扩展 x86_64，单独维护 24.10 IPK。（构建链已就位：`.github/workflows/release.yml` 目前只启用 armsr-armv8 一条 matrix，x86_64 与 24.10 IPK 是注释掉的占位。**已验证**：2026-10-26 在本地用 SDK 25.12.6 把三个包编译成 APK 并用 `apk add` 装进 iStoreOS 25.12.5 设备，rpcd 注册与五个 RPC 方法都在真机上跑过；证据见 [验证记录](docs/VERIFICATION.zh-CN.md) 的 S2 一节。**仍未验证**：CI 工作流从未执行过，x86_64 未构建。服务切换已于 2026-10-26 完成：旧包及依赖卸载、配置迁移、新服务运行并设为开机自启，真实音箱的发现与播放仍未验证）
- [ ] 当前上游工作流只有 openwrt-24.10 与 SNAPSHOT。稳定版构建应使用对应 SDK，不能把 SNAPSHOT 自动等同于稳定版兼容。（`release.yml` 固定 `sdk_version: 25.12.6` + `gcc 14.3.0` + `musl`，与目标版本号显式对应；SDK 按完整版本串做缓存键，避免陈旧 SDK 悄悄为错误版本出包）
- [x] 添加配置生成及校验测试。（`tests/config/`、`tests/runtime/`、`tests/parity/`）
- [x] 主机测试的 CI 工作流与统一入口。（`.github/workflows/test.yml`、`scripts/run-tests.sh`；工作流已实现但从未执行过）
- [x] 固定构建 Action 版本，发布校验和与明确的兼容列表。（`release.yml` 用 `googleapis/release-please-action@v4` 与 `actions/checkout@v4`、`actions/cache@v4` 固定大版本；上游 AirConnect 归档按 `PKG_HASH` 的 SHA256 校验后解包，不匹配即失败；构建目标与 SDK 组合在 `docs/RELEASE.zh-CN.md` 第 3 节列出。2026-10-26 修掉了两处会让构建静默出错的问题：包拷贝改用 `cp -r` 以刷新 mtime（否则 `cp -a` 会让扫描器跳过新包、defconfig 静默丢掉它的 `CONFIG_PACKAGE_*`），并关闭 `libopenssl-afalg`/`libopenssl-devcrypto`（这两个引擎会把全部内核模块拉进编译，正是此前 OOM 的根因）；`tests/release/check-release.sh` 已加断言防止再次漂移。**仍未发布过任何构建产物**）
- [x] 接入 release-please 与自动发版。（`release-please-config.json` + `.release-please-manifest.json` + `release.yml`：提交信息决定版本号，release PR 合并后自动打 tag、编译并上传 APK 到 GitHub Release。`package.json` 仅为 release-please 存在，无 npm 依赖。流程、版本号写入位置与人工确认清单见 [docs/RELEASE.zh-CN.md](docs/RELEASE.zh-CN.md)）
- [ ] 在本地验证及真实设备验证后发布测试版；实际升级路由器前保留可回退的软件包与配置。（`docs/RELEASE.zh-CN.md` 第 4 节列出了发版前必须人工确认的六项，其中升级保留设置、迁移演练两项尚未执行）
- [x] 发布前核对各文件及 AirConnect 分发内容的许可证，保留原版权声明；不把混合组件武断地统一声明为一种许可证。（`docs/LICENSES.zh-CN.md` 的逐组件证据表；`PKG_LICENSE` 已改为正确的 SPDX 表达式；`THIRD-PARTY-NOTICES` 随包分发并由 `release.yml` 的 `Check the package contents` 步骤断言存在）

## 现有本机定制如何迁移

已有的单音箱音量上限页面可作为原型参考，但其中的个人音箱信息和硬编码逻辑不进入公开仓库。将其改造成按 UDN 的通用 UCI 配置后再提交实现。

- [x] 按 UDN 的通用 UCI 设备段与继承规则（`config.uc` 的 `inherited`、`tests/config/fixtures.uc`）。
- [x] 旧服务与外来引擎进程的只读冲突检测（`rpcd/ucode/airconnect-manager` 的 `detectConflicts`；只报告，不终止、不删除）。
- [x] 迁移脚本本身：把旧单音箱配置映射为 UCI 设备段（`scripts/migrate-legacy.sh`，先备份再写临时文件再改名）。**已于 2026-10-26 在真实设备上执行**（iStoreOS 25.12.5 / aarch64 / APK）：`--dry-run` 与 `--apply` 跑通，旧包及依赖卸载，新服务启动并设为开机自启；完整记录见[旧实例迁移手册](docs/MIGRATION.zh-CN.md)的“首次执行记录”。这次执行纠正了两处文档偏差：冲突拦截只在 RPC 路径生效（init 脚本不检查），以及卸载旧包会把新服务一起停掉、需要重新启动；脚本对没有对应项的旧键（本机是 `stream_type`）也改为明确报告 `skipped`，不再静默丢弃。
- [ ] 回退流程的实际执行。步骤见 [旧实例迁移手册](docs/MIGRATION.zh-CN.md)，但整条流程从未演练。

本文件是开发计划；`[x]` 只表示对应代码与主机测试已存在，不代表已在路由器或真实音箱上验收。


## 需求与审计文档

- [产品定位](PRODUCT.md)
- [新版界面与设备信息需求](docs/UI-REQUIREMENTS.zh-CN.md)
- [原生 AirConnect 能力审计](docs/AIRCONNECT-CAPABILITIES.zh-CN.md)
- [性能与资源约束](docs/PERFORMANCE.zh-CN.md)
- [性能测量结果](docs/PERFORMANCE-RESULTS.zh-CN.md)

界面重构、名称配置、信息展示及上游能力接入属于本轮新增的正式范围；文档本身不代表增强版功能已经实现或部署。
