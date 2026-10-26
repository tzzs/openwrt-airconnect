# 初始化验证记录

本轮验证了独立项目结构和上游依赖来源。归档下载与 SDK 编译的后续结果见下文
“SDK 构建验证（S1）”：两者都已完成，本节保留的是当时的状态。

- 独立 Git 根目录为 openwrt-airconnect，不含原 fork 的历史和远端。
- 本地 Markdown 相对链接检查通过。
- 发布源检查未发现现场音箱 IP、UDN 或登录凭据。
- 官方 GitHub Releases API 返回 1.12.4 的 AirConnect-1.12.4.zip，大小 95,060,625 字节，digest 为 sha256:ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903，与新包配方一致。
- 官方 ZIP 下载当时超时、未完成，未把残缺文件作为有效源或构建产物。**该结论已过时**：
  归档后来完整下载（95,060,625 字节），本地自算 SHA256 与 `PKG_HASH` 一致，详见
  “SDK 构建验证（S1）”。
- 许可证原文取自官方 1.12.4 标签，仅去除行尾空格；声明 AirConnect 为 MIT，第三方组件各自遵循原作者条件。依赖许可证审计仍属于发布前任务。

来源：

- https://api.github.com/repos/philippe44/AirConnect/releases/tags/1.12.4
- https://github.com/philippe44/AirConnect/releases/tag/1.12.4
- https://github.com/philippe44/AirConnect/blob/1.12.4/LICENSE

未部署新服务，路由器继续使用之前已安装的版本。独立管理层与新界面已写入仓库并在主机测试下运行，
三个包后来也已用 SDK 成功编译出 APK（见“SDK 构建验证（S1）”），但**仍未安装到任何真实设备**；
设备验收依然未做，具体状态见下一节。

## 主机验证现状（2026-10-21）

本节记录一次完整的主机运行结果，与上文的初始化记录和下文的分项记录并存，不互相替代。

### 证据来源

- 机器：macOS 27.0（Darwin 27.0.0，arm64）。
- ucode：`~/.local/opt/ucode-host/bin/ucode`（主机自建，含 `fs`/`socket`/`math` 等
  模块，`-L ~/.local/opt/ucode-host/lib/ucode`）；node v24.13.0；bash 3.2.57；`/bin/dash`。
- 这一轮主机测试未使用 OpenWrt SDK、未联网、未安装任何路由器组件。
  （SDK 构建是后来单独做的一轮，见“SDK 构建验证（S1）”。）

### 已在这台主机上验证

统一入口：`bash scripts/run-tests.sh`（15 个套件全部通过）。分套件结果：

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| config | `ucode tests/config/run.uc` | 661 通过，0 失败 |
| discovery | `ucode tests/discovery/run.uc` | 103 项检查通过 |
| broadcast | `ucode tests/broadcast/run.uc` | 37 项检查通过 |
| parity（后端） | `ucode tests/parity/run.uc` | 1388 通过，0 失败 |
| parity（前端） | `node tests/parity/check-frontend.mjs` | 930 通过，0 失败 |
| luci 视图 | `node tests/luci/run.mjs` | 43 通过，0 失败 |
| runtime | `ucode tests/runtime/run.uc` | 38 通过，0 失败 |
| state | `ucode tests/state/run.uc` | 79 通过，0 失败 |
| state 插件 | `bash tests/state/check-plugin.sh` | 43 通过，0 失败（其中插件 I/O 42 项） |
| package 静态 | `bash tests/package/check-package.sh` | 69 通过，0 失败 |
| init 脚本 | `bash tests/package/run-init-script.sh` | 148 项检查，0 失败 |
| engine 配方 | `bash tests/engine/check-recipe.sh` | 30 通过，0 失败 |
| migration | `bash tests/migration/run.sh` | 122 通过，0 失败 |
| 性能：静态资源 | `bash tests/performance/measure-payload.sh` | 5 个文件，47,775 B / gzip 14,646 B，预算全部成立 |
| 性能：回复大小 | `bash tests/performance/measure-status.sh` | 10 通过，0 失败 |
| 性能：轮询契约 | `node tests/performance/poll-contract.mjs` | 29 通过，0 失败 |
| luci 四态渲染 | `node tests/luci/diagnostics.mjs` | 26 通过，0 失败 |

由此可以确认的具体事实：

- **校验与渲染**：`config.uc` 的 `normalizeConfig` / `renderXml` 对两种引擎的默认值、
  继承、非法输入、控制字节和尾随换行均有覆盖（`tests/config/`）。
- **前后端校验一致**：`rules.js` 与 `config.uc` 对 `tests/parity/cases.json` 的每一行
  给出一致结论，边界值包含 0/1/100/101、`1.5`、`0999:1`、63/64 字节名称。
- **原子写入与保留最后有效文件**：`runtime.uc` 在验证失败、渲染失败和单引擎失败时都不
  覆盖上一份有效 XML，权限为 0750/0640（`tests/runtime/`）。
- **rpcd 后端形状**：插件编译通过，签名只注册 `airconnect.manager` 的五个方法；
  在没有 uci、没有 ubus 时仍返回普通对象；冲突检测只报告，不终止或删除
  （`tests/state/check-plugin.sh`）。
- **init 脚本**：`-Z -x`、不使用 `-z`/`-b`、拒绝非法接口值、配置被拒时不发布任何实例；
  仅启用 aircast 时只启动 aircast（`tests/package/run-init-script.sh`）。
- **引擎配方静态内容**：版本、摘要、源路径、ARCH 归一化与提取脚本自诊断
  （`tests/engine/check-recipe.sh`，合成归档，非真实 ZIP）。
- **迁移脚本逻辑**：`scripts/migrate-legacy.sh` 的 dry-run、备份、写入原子性、拒绝非法参数与
  幂等性由 `tests/migration/run.sh` 覆盖（沙箱根目录，未接触真实设备配置）。

### 仍未验证

- **SDK 构建**：本节记录的那一轮主机测试没有构建任何包。**后续已补做**：三个功能包都已用
  OpenWrt SDK 编译出 APK，产物内容已逐项核对，详见“SDK 构建验证（S1）”与
  “SDK 构建与设备安装验证（S2）”。当前构建链已增加由 `luci.mk` 生成的
  `luci-i18n-airconnect-manager-zh-cn`，四包本地构建与 GitHub Pages `packages.adb` 仓库发布尚未完成首次真实验证。
  仓库内仍不存放大体积构建产物（`.gitignore` 排除了 `*.apk`/`*.ipk`）。
- **CI 执行**：`.github/workflows/test.yml` 的主机测试工作流已实现，但从未执行过；
  没有任何一次 CI 运行结果可查。本节表格中的全部数字来自上面的本地运行。
- **真实设备**：本节记录时没有任何东西在真实路由器上运行过。**后续已补做**：
  三个包已用 `apk add` 装进设备，真实 rpcd 注册与 RPC 调用已核对，详见 S2。
  仍未核对的是 procd/netifd 的 ubus 返回形状、设备上的 `/etc/init.d/airconnect-manager`
  启动路径与迁移/回退流程。
- **真实音箱**：没有接入任何音箱，因此播放、发现真实设备、以及“AirPlay 满音量映射”
  都未验证。音量上限只验证了数值边界与 XML 渲染，没有验证音箱端的实际响度。
- **LuCI 集成**：`overview.js` 只在 `dev/` 的模拟后端（`dev/luci-preview.js`）下检查过，
  从未在真实 LuCI 中加载，也没有经过真实的 rpcd/UCI 保存与回滚。`rules.js` 有主机测试，
  页面本身没有自动化浏览器测试。
- **迁移与回退**：迁移脚本已实现且只有主机测试，从未在路由器上运行过；启动新实例与验证
  发现/广播/播放的步骤由人执行，流程见 `docs/MIGRATION.zh-CN.md`，整条流程从未演练。
- **升级保留设置**：`conffiles` 已在配方中声明并由静态检查覆盖，但“升级后设置保留”需要
  一次真实的软件包升级才能确认。
- **性能测量**：主机侧可测的部分已在 `tests/performance/` 落实为断言——本包静态资源
  字节与预算、`status`/`logs` 回复字节与上限执行、轮询间隔/隐藏暂停/退避/表单零写入。
  路由器 CPU、RSS/VSZ、网络流量、播放中断、浏览器长任务仍**未测量**，需要真实设备；
  数字、命令与逐项理由见 [性能测量结果](PERFORMANCE-RESULTS.zh-CN.md)。

## 引擎包配方验证状态（T6，2026）

本节如实记录 `packages/airconnect-engine/Makefile` 与提取脚本的验证情况，与
`docs/ARCHITECTURE.zh-CN.md` 中的架构限制保持一致。

### 已验证

- **发布元数据与摘要**：`PKG_VERSION:=1.12.4`、`PKG_SOURCE_URL` 指向
  `philippe44/AirConnect` 的 releases 路径、`PKG_HASH` 取自 GitHub Releases
  API 元数据（sha256:ae59d595...），与配方一致。摘要字符串本身未被本任务改动。
- **ARCH 归一化表**：`AIRCONNECT_ARCH` 映射块已在主机上用 `make -f` 逐项验证。
  `x86_64`、`aarch64` 保持原值；`aarch64_generic`、`aarch64_cortex-a53` 归一为
  `aarch64`；`arm_cortex-a7_neon-vfpv4`、`arm` 归一为 `arm`；`armv7`、`mips`、
  `mipsel` 作为上游自身使用的文件名片段保留原值；`riscv64` 触发 `
  $(error ...)`，构建明确失败，不会产出错误二进制。
- **提取脚本自诊断**：`files/extract-engines.sh` 用合成的 ZIP（含
  `airupnp-linux-aarch64-static`、`aircast-linux-aarch64-static` 及无关文件）
  验证——能正确落地两个目标二进制、排除无关文件；在架构名缺失或归档文件不存在时
  干净失败，并把归档真实清单打印到 stderr。
- **配方静态检查**：`bash tests/engine/check-recipe.sh` 共 30 项全部通过
  （版本/摘要/源路径/架构限制/Prepare 引用 `AIRCONNECT_ARCH`/`unzip -l` 诊断/
  POSIX 脚本/shebang/无 init 脚本或配置/`PKG_LICENSE:=MIT`）。

### `airconnect.manager` rpcd 后端（T3，2026）

#### 已验证（主机 ucode）

- **签名契约**：`ucode -c` 编译通过且无输出；顶层 `return` 是签名对象，只注册
  `airconnect.manager` 与 `status`/`logs`/`scan`/`validate`/`action` 五个方法；
  `validate` 参数为 `{ config: {} }`，`action` 为 `{ action: "start" }`，其余三个无参数。
- **永不 NO_DATA**：在没有 uci、没有 ubus 的最坏情况下，五个方法都返回普通对象，
  形状符合 LuCI 视图的预期。
- **校验复用**：`validate` 调用 `config.uc` 的 `normalizeConfig`，并对启用的引擎执行
  `renderXml`，因此 Cast 的 PCM 限制在保存前就作为校验错误返回，而不是应用时 500。
- **纯逻辑与有界 I/O**：`state.uc`（合并、去重、64 条上限、24 小时缓存过期、
  `ps` 解析、日志裁剪、错误钳制）与 `files.uc`（原子写、seek 到文件尾、
  丢弃半行、体积上限）由 `tests/state/run.uc` 覆盖。
- **插件 I/O 路径**：`tests/state/plugin.uc` 用沙箱根目录与假 uci/ubus 模块运行真实插件，
  覆盖 status、缓存过期、VERSION、冲突检测、action 拒绝与 procd 结果核对、
  scan 拒绝、`scan-worker` 分支以及日志裁剪。
- **静态安全**：请求值不进入 shell；`action` 从固定表取命令；插件内没有
  `killall`/`rm -rf`/`uci delete` 等破坏性命令；`uci`/`ubus` 不是静态 import。

#### 未验证

- **真实 rpcd 注册**：本节记录时只在主机上校验了签名对象的结构。**后续已补做**：
  在真实设备上 `airconnect.manager` 注册成功，五个方法齐全，详见 S2。
- **procd / netifd**：`service list`、`network.device status`、`network.interface dump`
  的返回形状来自文档与源码，未在真实 ubusd 上核对。
- **SSDP 与设备发现**：只覆盖了工作进程的失败路径，未在真实接口上完成发现。
- **init 脚本调用**：`/etc/init.d/airconnect-manager <action>` 在设备上的实际行为未验证
  （只有 `action` RPC 的冲突拒绝路径在设备上跑过）。

### 未验证

- **设备端执行**：本节记录时未在真实 aarch64/x86_64 路由器上安装或运行二进制。
  后续已补做，见“SDK 构建与设备安装验证（S2）”。

## SDK 构建验证（S1，2026-10-22）

本节记录一次真实的 OpenWrt SDK 构建结果，取代上文“未执行 SDK 构建”与“归档未能下载”两条
已过时的结论。**本节只证明“能编译、产物内容已核对”，不证明包能运行。**

### 证据来源

- 构建机：macOS arm64 宿主上的 colima/QEMU **x86_64** Linux 虚拟机
  （`Linux 6.8.0 x86_64`，4 vCPU，8 GB RAM，60 GB 磁盘）。SDK 只有 Linux-x86_64 版本，
  在 arm64 虚拟机上会段错误，故必须用 x86_64 虚拟机。
- SDK：`openwrt-sdk-25.12.6-armsr-armv8_gcc-14.3.0_musl.Linux-x86_64`，
  `REVISION:=r33311-981c978eff`，目标 `armsr/armv8`，`CONFIG_TARGET_ARCH_PACKAGES="aarch64_generic"`。
- 工具链：`aarch64-openwrt-linux-musl-gcc (OpenWrt GCC 14.3.0 r33311-981c978eff) 14.3.0`，musl libc。
- 产物格式：**APK**（`CONFIG_USE_APK`，OpenWrt 25.12 默认），不是 IPK。
- feeds：`packages`、`luci`、`base`（另有 routing/telephony）。luci feed 的 `video` 源在本网络下
  TLS 握手失败，故从 `feeds.conf` 移除后重建索引；这是 feed 侧网络问题，与本仓库无关，
  且三个包都不依赖它。

### 上游归档

- `dl/AirConnect-1.12.4.zip` 已完整下载，大小 **95,060,625 字节**。
- 本地自算 SHA256：`ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903`，
  与 `packages/airconnect-engine/Makefile` 的 `PKG_HASH` **逐字符相同**，因此 `Build/Prepare`
  的摘要校验通过，不是“仅凭 API 元数据声明”。
- `unzip -l` 确认归档内存在 `airupnp-linux-aarch64-static` 与 `aircast-linux-aarch64-static`
  （另有 x86_64 等架构），共 64 个条目。

### 逐包结果

| 包 | 编译 | APK 路径（相对 SDK 根） | 大小 |
| --- | --- | --- | --- |
| `airconnect-engine` | 是 | `bin/packages/aarch64_generic/base/airconnect-engine-1.12.4-r1.apk` | 6,047,428 字节 |
| `airconnect-manager` | 是 | `bin/packages/aarch64_generic/base/airconnect-manager-0.1.0-r1.apk` | 32,090 字节 |
| `luci-app-airconnect-manager` | 是 | `bin/packages/aarch64_generic/base/luci-app-airconnect-manager-0.261022.81988.apk` | 11,533 字节 |

三个包均用 `$SDK/staging_dir/host/bin/apk extract --allow-untrusted` 解开核对过内容。

**airconnect-engine 文件清单**（`file` 输出附后）：

```
/usr/libexec/airconnect/airupnp           -rwxr-xr-x  6,659,893 字节
/usr/libexec/airconnect/aircast           -rwxr-xr-x  7,729,021 字节
/usr/share/airconnect/UPSTREAM-LICENSE
/usr/share/airconnect/THIRD-PARTY-NOTICES
```

两个二进制均为 `ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), for GNU/Linux 4.4.255,
statically linked, no section header`，即上游静态构建，不依赖路由器 musl。

**airconnect-manager 文件清单**：

```
/etc/config/airconnect-manager               (conffiles 已声明)
/etc/init.d/airconnect-manager               -rwxr-xr-x
/etc/uci-defaults/90-airconnect-manager
/usr/share/airconnect-manager/VERSION
/usr/share/airconnect-manager/config.uc
/usr/share/airconnect-manager/discovery.uc
/usr/share/airconnect-manager/files.uc
/usr/share/airconnect-manager/runtime.uc     -rwxr-xr-x
/usr/share/airconnect-manager/state.uc
/usr/share/rpcd/ucode/airconnect-manager     -rwxr-xr-x
```

**luci-app-airconnect-manager 文件清单**：

```
/usr/share/luci/menu.d/luci-app-airconnect-manager.json
/usr/share/rpcd/acl.d/luci-app-airconnect-manager.json
/www/luci-static/resources/airconnect-manager/manager.css
/www/luci-static/resources/airconnect-manager/rules.js
/www/luci-static/resources/view/airconnect-manager/overview.js
```

`rules.js` 落在 `/www/luci-static/resources/airconnect-manager/rules.js`，正是视图里
`'require airconnect-manager.rules'` 需要的路径（luci.mk 整体安装 `htdocs/`，未逐文件列举，
故没有被漏掉）。

### 构建过程中修复的两个真实配方缺陷

两者都不是“为了让包编译而删功能”，而是配方本身写错：

1. **`packages/luci-app-airconnect-manager/Makefile` 的 include 路径**。原来写
   `include $(TOPDIR)/feeds/luci/luci.mk`。SDK 的包扫描器会以**未设置 `TOPDIR`** 的方式
   读取每个 Makefile 来建索引，此时该路径解析成 `/feeds/luci/luci.mk`，dump 直接失败，
   包因此不在 `tmp/.packageinfo` 里。改为相对路径 `include ../../feeds/luci/luci.mk`
   （与 feed 内 `luci-app-acl` 等包一致），扫描与真实构建都能解析。
2. **同一文件缺少 `$(eval $(call BuildPackage,luci-app-airconnect-manager))`**。
   扫描器（`include/scan.mk`）是靠 `find | grep 'call BuildPackage'` 发现包的；
   `luci.mk` 只提供宏定义、不负责调用，所以本包对扫描器完全不可见，
   `make defconfig` 会**静默丢弃** `CONFIG_PACKAGE_luci-app-airconnect-manager`，
   最终表现为“没有产出 APK”而无任何有用报错。补上这一行后正常注册。

（`airconnect-engine` 的两个缺陷——无条件 `$(error)` 破坏包扫描、`$(file ...)` 被 make
当作内建函数——已在更早的提交中修复，本轮构建验证了修复有效。）

### 可复现构建脚本

新增 `scripts/build-sdk.sh`（主机/Linux 工具，不在路由器上运行）。它把本轮的步骤固化下来：
校验 SDK 目录、缺 feed 时用本地 `feeds/` 离线安装、检测同目录并发构建、用
`bsdtar --exclude '._*'` 拷贝包（避开 macOS AppleDouble 头导致 GNU tar 解包错位）、
写入并复核 `CONFIG_*`、`make defconfig`、逐包 `make package/<name>/compile V=s`、
打印 APK 路径与大小，任一包没有 APK 则非零退出。它**从不**下载 AirConnect 归档，
只检查 `$SDK/dl/` 是否已有并在缺失时打印获取命令与期望 SHA256。

默认关闭 `libopenssl-afalg` / `libopenssl-devcrypto`（`--keep-openssl-engines` 可保留）：
这两个可选引擎会让 `libopenssl` 依赖 `kernel/linux/compile`，在 SDK 自带的
`CONFIG_ALL_KMODS=y` 下会连带交叉编译目标平台**全部一千多个内核模块**。本项目只用
libopenssl 的 TLS，不用这两个引擎，关掉它们把构建范围收敛到实际发布的包。

一次完整运行的结果：`build-sdk.sh: all 3 package(s) built`，退出码 0。

### 仍未验证（本轮明确不做）

- **路由器安装**：没有任何 APK 被安装到真实设备，`apk add` 的实际解析、依赖满足、
  conffiles 升级保留都未验证。
- **开机与服务启动**：没有开机，没有 `service airconnect-manager start`，
  procd 实例注册、`/var/etc/airconnect-manager/` 的生成、init 脚本在设备上的行为均未验证。
- **音频**：没有接入音箱，没有播放，AirPlay 广播与满音量映射都未验证。
- **24.10 / IPK**：没有为 OpenWrt 24.10 构建，也没有产出任何 IPK。
- **x86_64**：只构建了 `aarch64_generic`；`x86_64` 目标未构建。
- **LuCI 运行时**：`luci-app-airconnect-manager` 只验证了文件落位，没有在真实 LuCI 里加载，
  没有经过真实 rpcd/UCI 的保存与回滚。
- **rpcd 注册**：`/usr/share/rpcd/ucode/airconnect-manager` 的权限与位置已核对，
  但没有在运行中的 rpcd 上确认 `airconnect.manager` 对象真的注册成功。

## 四态区分：广播可测量性的证据（S4，2026-10-22）

本节记录“AirPlay 广播”从固定文案变成实测值时，究竟测的是什么、证据在哪里，以及
哪些情况下必须继续显示未知。**结论：广播可以测量，但只在合成 MAC 路径成立；
播放仍然不可测量，保持未知。**

### 上游对外暴露了什么（逐项证据）

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 引擎注册哪些 mDNS 服务类型 | 只有 `_raop._tcp.local`。**没有** `_airplay._tcp`。 | `common/libraop/src/raop_server.c:155` 与 `:186` 都是 `mdnsd_register_svc(..., "_raop._tcp.local", ...)`；两个已发布静态二进制里 `strings` 只出现 `_raop._tcp.local`，`_airplay` 出现 0 次。 |
| 实例名（instance name）的构成 | `"<MAC 6 字节大写十六进制>@<AirPlay 名称>"`，并截断到 63 字节 | `raop_server.c:146`：`for (i = 0; i < 6; i++) sprintf(id + i*2, "%02X", mac[i]);`，`:149` `sprintf(id + 12, "@%s", name);`，`:152` `if (strlen(id) > 63) id[63] = '\0';` |
| TXT 记录里有什么 | 第一条是 `am=<model>`，`model` 由调用方传入：`"airupnp"` 或 `"aircast"` | `raop_server.c:138` `char *txt[] = { NULL, "tp=UDP", ... }`，`:141` `(void)!asprintf(&(txt[0]), "am=%s", model)`；调用点 `airupnp/src/airupnp.c:784,840` 传 `"airupnp"`，`aircast/src/aircast.c:550` 传 `"aircast"`。 |
| MAC 从哪来 | 先用 `SendARP()` 读音箱真实 MAC；失败才用 `hash32(UDN)` 合成，并把前两字节置为 `0xbb`（airupnp）或 `0xcc`（aircast） | `airupnp.c:1014-1024`、`aircast.c:663-671`。`hash32` 是 djb2-33，见 `crosstools/src/cross_util.c:425`。 |
| Linux 上 `SendARP()` 真能成功吗 | 不能，除非接口正好叫 `eth0`：它把 `areq.arp_dev` 硬编码成 `"eth0"` | `crosstools/src/cross_net.c:139-168`，其中 `:158` 是 `strncpy(areq.arp_dev, "eth0", 15);`，随后 `:160` `ioctl(s, SIOCGARP, ...)`；设备名不符时返回 `-1`，调用方就走 `hash32(UDN)` 分支。 |
| 有没有状态 API | **没有**。CLI 只有日志等级、日志文件、PID 文件；内部有设备/播放状态但不对外 | 能力审计已记录（`docs/AIRCONNECT-CAPABILITIES.zh-CN.md`）；`-d all=debug` 只能读日志，日志匹配属于推断，设计禁止。 |

### 在真实二进制上做的实测（不是读源码的推断）

在 Linux x86_64 上运行**官方 1.12.4 静态二进制**
`airupnp-linux-x86_64-static`（来自 `AirConnect-1.12.4.zip`，SHA256 已核对），
配一个合成的 UPnP MediaRenderer（UDN `uuid:demo-synthetic-renderer`），用 `tcpdump`
抓 `udp port 5353`：

```
_raop._tcp.local. PTR BBBBA7A5DB92@Demo Speaker+._raop._tcp.local.,
_services._dns-sd._udp.local. PTR _raop._tcp.local.
  BBBBA7A5DB92@Demo Speaker+._raop._tcp.local. TXT "am=airupnp" "tp=UDP" ... "txtvers=1"
  BBBBA7A5DB92@Demo Speaker+._raop._tcp.local. SRV port=38609 target=colima.local
  colima.local. A 192.168.5.1
```

引擎自己的日志同时打印 `adding renderer (Demo Speaker) with mac BBBB92DBA5A7`，
即 `hash32("uuid:demo-synthetic-renderer") = 0x92dba5a7` 小端写入 MAC 第 2..5 字节、
前两字节 `0xbb 0xbb`。**这条抓包就是 `tests/broadcast/run.uc` 里的
`CAPTURED_UPNP` 夹具**，解析器因此是对着真实报文而不是自己造的报文测试的。

### 因此“广播”能测到什么，不能测到什么

- **能测到**：某个 `_raop._tcp` 实例正在被通告，且它的 MAC 前缀与本设备 UDN 推出的
  前缀一致 → 这个设备的 AirPlay 接收端**已注册**。这就是“广播中”。
- **测不到**：是否有人在推流、是否在出声。上游没有接口，日志匹配是推断，不做。
- **只在合成 MAC 路径可靠**：接口名不是 `eth0` 时，Linux `SendARP()` 必定失败，
  引擎必定走 `hash32(UDN)`，前缀可以从 UCI 里的 UDN 精确算出。接口名**正好是 `eth0`**
  时前缀可能是音箱真实 MAC 的第 2..5 字节，管理器无法推出，此时
  **按设备的状态一律报未知**（`broadcast.uc:prefixIsDerivable`）。
- **服务级状态（`services.<engine>.broadcasting`）不依赖 MAC**：它只用 TXT 里的
  `am=` 标记，因此在任何接口上都成立。

### 三态规则（`false` 什么时候才允许）

| 情况 | 结果 | 理由 |
| --- | --- | --- |
| 扫描完成，找到匹配实例 | `true` | 直接观测到通告 |
| 扫描完成，没有匹配实例 | `false` | 真的测了，确实没有 |
| 没有 socket / 没有回复 / 超时 | `unknown` | 没测到，不是“没有” |
| 报文无法解析（截断、超限、指针环、记录数超限） | `unknown` | 同上 |
| 观测超过 300 秒 | `unknown` | 进程可能已经停了，旧数据不是现状 |
| 接口是 `eth0`（前缀不可推导） | `unknown` | 前缀算不出来，不能猜 |
| 同一前缀下有两个不同实例名 | `unknown` | 无法归属到具体设备 |
| 服务从未运行过 | `unknown` | 从未测量 |

### 边界与不新增常驻进程

- `broadcast.uc` 只做一次有界查询：一个 `_raop._tcp` 问题（QU 位置位，请对方单播回复，
  避免把整个 LAN 的 mDNS 都惊动）、3 秒预算、4096 字节报文上限、64 条记录上限、
  指针只允许向后跳且最多 64 跳。
- 观测由**已有的** `scan` 工作进程在 SSDP 之后执行，写入独立的
  `/var/lib/airconnect-manager/broadcast.json`（0640，原子替换）。`status` 只读这个文件，
  **从不打开 socket**，所以 10 秒轮询不会产生任何 mDNS 流量。
- 没有新增软件包依赖：只用 `ucode-mod-socket`，它已经在 `DEPENDS` 里。
  `umdns` **不在** OpenWrt 25.12 的 `DEFAULT_PACKAGES`（`include/target.mk` 里没有），
  所以没有采用 `ubus call umdns browse` 这条路，也没有把它加进依赖。

### 仍未验证

- **真实路由器上的 mDNS**：设备已验证 `broadcast.uc` 能编译并导入（见下一节），但
  `scan()` 本身（唯一的 I/O 函数）没有在设备上执行过。`SO_BINDTODEVICE` +
  `IP_MULTICAST_IF` 在 musl/内核上的行为、防火墙对 5353 的影响、真实音箱是否真的
  出现 `_raop._tcp` 通告均未实测。主机测试只覆盖纯决策层。
- **真实音箱**：没有接入任何音箱，因此“广播 true 与手机真的能看到接收端一致”未验证。
- **`am=` 与真实固件的交互**：只验证了引擎写出的值，没有验证其他 mDNS 实现是否会
  改写或丢弃该 TXT 记录。

## 真实设备验证（iStoreOS 25.12.5 / aarch64，2026-10-23）

前几节反复写着"没有在真实路由器上运行过"。这一节记录第一次在真实目标设备上跑起来的结果，
它同时推翻了其中两条结论。

### 设备

| 项 | 值 |
| --- | --- |
| 设备 | EasePi R1（`board.json` 的 `model.id` = `easepi,r1`，RK3588 / ARMv8） |
| 发行版 | iStoreOS 25.12.5（`DISTRIB_REVISION=2026092410`） |
| 目标 | `rockchip/armv8`，`aarch64_generic` |
| 内存 / 存储 | 4 GB / 1.9 GB overlay（可用约 1.1 GB） |
| 包格式 | `apk`（`/usr/bin/apk`，apk-tools 3.0.5） |
| ucode | 包版本 `ucode-2026.01.16~85922056-r2`，但实际运行时是 `libucode.so.20230711` |
| 已有旧包 | `/etc/config/airconnect` + `/etc/init.d/airconnect`（旧 UCI 服务，正在运行） |

### 在这台设备上真正验证过的

- **五个后端模块都能编译并 import**：`config.uc`、`discovery.uc`、`files.uc`、`state.uc`、
  `broadcast.uc`，导出数量分别为 2 / 6 / 7 / 9 / 8。
- **XML 渲染在设备上正确**：`renderXml(normalizeConfig({...}), 'upnp')` 产出以 `<airupnp>` 为根的
  文档，`<binding>`、`<main_log>`、`<common>` 等元素按预期出现。
- **rpcd 插件在设备上成功注册**：`airconnect.manager` 对象的
  `status`、`logs`、`scan`、`validate`、`action` 五个方法全部存在且形状为 `{ call: fn }`。
- **`status` 返回真实回复**（设备上的实际输出，节选）：
  `{"enabled":false,"interface":null,...,"playback":{"known":false,"reason":"no documented engine
  status API"},"broadcast":{"observed_at":null,"error":null},"conflicts":[],"devices":[]}`。
  `broadcasting` 为 `null` 而不是 `false`，与"未测量即 unknown"的规则一致。

### 设备验证推翻的两个结论

1. **`export function` 在目标运行时上不可用。** 之前所有模块都用 `export function`，
   在 `libucode.so.20230711` 上直接报
   `Syntax error: Unexpected token / Expecting ';'`，**整个后端在设备上根本无法加载**。
   已改为 `const f = function () {}` + 末尾 `export { }`，设备上验证可编译、可调用。
   主机测试用的是较新的 ucode，两种写法都接受，所以这个缺陷在主机上完全看不出来。
2. **迁移脚本硬编码了错误的 section 名。** 旧包用 `config_foreach` 遍历所有 `airconnect`
   类型的 section，出厂文件里它叫 `config`；迁移脚本却固定读 `airconnect.main.*`。
   在真机上表现为**每一次查找都落空**，然后把内置默认值写回配置——`max_volume` 从 30
   变成 100，`interface`/引擎选择也被默认值覆盖。已改为从 `uci show` 解析 section 名，
   找不到 section 时直接失败而不是"迁移一份没东西可迁的文件"。

### 仍未验证（这一节不改变这些）

- 包**没有**用 `apk add` 安装进设备（只在 `/tmp` 里按安装后的目录布局加载）。
  因此 procd 启动、`/etc/init.d/airconnect-manager` 的真实行为、conffiles 处理仍未核对。
- 没有接入真实音箱：SSDP 发现、`_raop._tcp` 观测、音量映射的实际效果都未验证。
- 性能项（CPU、RSS、网络、播放中断）仍未测量。
- `airconnect-manager` 与 `luci-app-airconnect-manager` 仍未编译出 APK
  （构建 VM 在编译 curl/openssl 依赖链时 OOM，与代码无关）。

> 上面四条已由下一节（S2，2026-10-26）取代。保留原文是因为它记录了当时的状态；
> 下面两节记录了实际的构建、安装与验证结果。

## SDK 构建与设备安装验证（S2，2026-10-26）

本节记录一次完整的“本地 SDK 构建 → 装机 → 真机调用”验证。它取代 S1 之后那些关于
“没有用 SDK 构建过 APK”“包没有用 `apk add` 装进设备”“真实 rpcd 注册未验证”的结论。

### 构建机

- 宿主：macOS arm64（Darwin 27.0.0）。
- 构建环境：colima 的 **x86_64** QEMU 虚拟机里的 Ubuntu 24.04 容器，限制为 2 vCPU / 4 GB。
  SDK 只有 `Linux-x86_64` 版本，arm64 上会段错误，所以必须是 x86_64。
- SDK：`openwrt-sdk-25.12.6-armsr-armv8_gcc-14.3.0_musl.Linux-x86_64`，
  `REVISION:=r33311-981c978eff`，目标 `armsr/armv8`，`CONFIG_TARGET_ARCH_PACKAGES="aarch64_generic"`，
  产物格式为 APK（`CONFIG_USE_APK`）。
- 上游归档：`dl/AirConnect-1.12.4.zip`，95,060,625 字节；本地自算 SHA256 与
  `packages/airconnect-engine/Makefile` 的 `PKG_HASH` **逐字符相同**（`ae59d595…cd1903`），
  构建前用 `sha256sum -c` 校验通过。

### 三个包都编译成功

| 包 | APK | 大小 |
| --- | --- | --- |
| `airconnect-engine` | `airconnect-engine-1.12.4-r1.apk` | 6,047,428 字节 |
| `airconnect-manager` | `airconnect-manager-0.1.0-r1.apk` | 39,572 字节 |
| `luci-app-airconnect-manager` | `luci-app-airconnect-manager-0.1.0-r1.apk` | 12,004 字节 |

产物用 `apk extract` 解开逐个核对：

- `airconnect-engine`：`/usr/libexec/airconnect/airupnp` 与 `aircast` 均为
  `ELF 64-bit LSB executable, ARM aarch64, statically linked`，另有
  `usr/share/airconnect/UPSTREAM-LICENSE` 与 `THIRD-PARTY-NOTICES`。
- `airconnect-manager`：`etc/config/airconnect-manager`、`etc/init.d/airconnect-manager`、
  `etc/uci-defaults/90-airconnect-manager`、`usr/share/airconnect-manager/` 下 6 个 `.uc`
  与 `VERSION`、`usr/share/rpcd/ucode/airconnect-manager`；`conffiles` 正确声明
  `/etc/config/airconnect-manager`。
- `luci-app-airconnect-manager`：`menu.d` 与 `acl.d` 的 JSON、`manager.css`、`rules.js`、
  `view/airconnect-manager/overview.js`。

### 构建过程中定位并修掉的两个真实缺陷

1. **`cp -a` 的 mtime 会让包对扫描器消失。** `include/scan.mk` 用 Makefile 的 mtime
   与上次扫描留下的戳比较，决定要不要重读这个包。`cp -a` 保留了检出时的旧 mtime，
   而戳更新，于是新包被当作“已扫描过”：`tmp/.packageinfo` 里没有它，`make defconfig`
   **静默丢弃** `CONFIG_PACKAGE_luci-app-airconnect-manager`，最终表现为“没有产出 APK”
   而不指名是哪个包。`scripts/build-local.sh` 与 `.github/workflows/release.yml` 都改用
   `cp -r`，并在 defconfig 之后校验必需符号没被丢弃，丢弃即按名字失败。
   CI 缓存了整个 `~/sdk`（含 `tmp/`），所以缓存命中时同样会中招。
2. **OOM 的根因是 libopenssl 的两个可选引擎。** `CONFIG_PACKAGE_libopenssl-afalg` 与
   `CONFIG_PACKAGE_libopenssl-devcrypto` 各自让 `libopenssl` 依赖 `kernel/linux/compile`，
   在 SDK 默认的 `CONFIG_ALL_KMODS=y` 下连带交叉编译目标平台全部内核模块。
   `scripts/build-sdk.sh` 早就默认关掉它们，但 `scripts/build-local.sh` 与
   `release.yml` 都没有——这正是本节之前记的“编译 curl/openssl 依赖链时 OOM”的原因。
   现在两条路径都关闭它们，`tests/release/check-release.sh` 也加了断言防止再次漂移。

### 设备安装与真机调用

设备：iStoreOS 25.12.5（`DISTRIB_REVISION=2026092410`），aarch64，apk-tools 3.0.5，
overlay 剩余约 1.1 GB。安装前设备上已装并运行着旧包 `airconnect-1.12.4-r1`
（`/etc/config/airconnect` + `/etc/init.d/airconnect`，`/usr/bin/airupnp` 在跑）。

`apk add --allow-untrusted` 装上三个包，退出码 0。随后在设备上验证通过：

- **引擎二进制真实可执行**：`/usr/libexec/airconnect/airupnp -h` 输出 `v1.12.4 (Sep 26 2026 @ 20:05:21)`。
  这是二进制在目标架构上真的跑起来了，不只是静态检查。
- **rpcd 真实注册**：`ubus -v list airconnect.manager` 显示 `status`、`logs`、`scan`、
  `validate`、`action` 五个方法，签名与设计一致（`validate` 收 `{config: Table}`，
  `action` 收 `{action: String}`）。
- **`status` 返回真实回复**：`enabled:false`、`interface:"br-lan"`、`version:"0.1.0"`、
  `services.upnp.running:false`、`services.upnp.broadcasting:null`、
  `playback.known:false`、`broadcast.observed_at:null`、空的 `devices`。
  `broadcasting` 是 `null` 而不是 `false`，与“未测量即未知”一致。
- **冲突检测在真机上生效**：`conflicts` 同时报出
  `Legacy service 'airconnect' is running.`、`Legacy binaries found in /usr/bin.`、
  `AirConnect engine processes are running outside this manager (1).`。
- **`validate` 区分合法与非法**：非法 `codec` 返回
  `main.codec: use wav, pcm (UPnP), flac[:0..9], mp3[:32..320] or aac[:16..320]`，合法输入 `ok:true`。
- **`action` 的安全闸门生效**：`action {"action":"start"}` 返回
  `ok:false`、`error:"Conflicting AirConnect instance detected"`，且 `pgrep` 确认没有新引擎进程。
- **`logs`**：返回空 `lines` 与 `truncated:false`。
- **LuCI 静态资源可访问**：`http://127.0.0.1/luci-static/resources/view/airconnect-manager/overview.js`
  返回 HTTP 200（24900 字节），`rules.js` 同样 200；`menu.d` 与 `acl.d` 的 JSON 经 `jsonfilter` 解析通过。
- **安装没有干扰旧服务**：旧 `airconnect` 仍 enabled 且 running（PID 27874），
  新服务 `enabled=0`、未运行，两套没有同时广播。

### 安装时发现的一处文档与行为不符

包内两处文档写“服务默认禁用，必须显式 enable”。真机事实是：OpenWrt 的 `default_postinst`
（`/lib/functions.sh` 里的 `rc.common ... enable`）在安装时就建好了
`/etc/rc.d/S95airconnect-manager`，所以 `/etc/init.d/airconnect-manager enabled` 一直返回 0。
真正决定是否广播的是 UCI 的 `airconnect-manager.main.enabled`——为 0 时 `start_service`
不注册任何 procd 实例，因此“装完不广播”这个保证仍然成立，只是“开关”不是 init 脚本。
配方描述、配置文件注释、init 脚本注释和迁移手册都已按这个事实改写。

### 这一节仍然没有验证的

- ~~**服务切换**：旧实例尚未停用并卸载，新服务尚未启动（`enabled` 仍为 0）~~
  **已完成**，见下面的 S3 一节（2026-10-26）：旧包已卸载、新服务在运行并开机自启。
  `--apply` 已跑过；`--rollback` 仍未演练。
- **真实音箱**：SSDP 发现、`_raop._tcp` 观测、音量映射的实际效果都未验证。
- **LuCI 页面本身**：只验证了静态资源可访问，页面没有在登录后的浏览器会话里打开过，
  真实的 rpcd/UCI 保存与回滚未走通。
- **设备侧性能**：CPU、RSS、网络流量、播放中断仍未测量。
- **升级保留设置**：`conffiles` 已声明，但“升级一个已安装的旧版本后配置保留”需要一次真实升级。
- **CI / Pages**：工作流尚未执行过，GitHub Pages 尚未启用，APK 仓库尚未发布。

## 服务切换与旧包卸载验证（S3，2026-10-26）

第一台真实设备上的完整切换，设备同 S2：iStoreOS 25.12.5、`rockchip/armv8`、`aarch64_generic`、APK。

### 切换前的现场

- 旧包 `airconnect-1.12.4-r1`、`luci-app-airconnect-1.0.3-r1`、
  `luci-i18n-airconnect-zh-cn-26.216.59507~71e1bd6`；
- `/etc/config/airconnect` 与 `/etc/init.d/airconnect` 都在，服务 enabled 且 running；
- 引擎进程 `/usr/bin/airupnp -x /var/etc/airconnect-airupnp.xml -l 1000:2000 -Z -b br-lan
  -S broadcast`（PID 27874）；
- 新包已装，但 `airconnect-manager.main.enabled=0`，新服务未运行。

### 迁移脚本的执行

`--dry-run` 与 `--apply` 都在设备上跑通，映射结果见
[旧实例迁移手册](MIGRATION.zh-CN.md)的“首次执行记录”。关键点：旧配置的 `stream_type=broadcast` 被
报告为 `skipped (no equivalent option in airconnect-manager; not carried over)` —— 这条报告本身是本次
新增的，此前脚本对不认识的键完全沉默，报告读起来像无损迁移。

`--apply` 写出 `/etc/config/airconnect-manager`（mode 600），备份目录
`/etc/airconnect-manager-backup/20261025T173836Z` 含完整 `manifest.txt`；旧服务被 `stop` +
`disable`，`/etc/rc.d` 中的旧链接消失。

### 冲突拦截只在 RPC 路径生效（本次最重要的实测）

旧二进制仍在 `/usr/bin` 时，两条启动路径的行为不同：

| 路径 | 结果 |
| --- | --- |
| `/etc/init.d/airconnect-manager start` | 返回 0，引擎**真的启动了**（PID 26929） |
| `ubus call airconnect.manager action '{"action":"start"}'` | `{"ok":false,"error":"Conflicting AirConnect instance detected"}` |

同时 `status.conflicts` 报 `Legacy binaries found in /usr/bin.`。也就是说：冲突检测是**报告 + RPC
拦截**，init 脚本不受约束。跳过卸载旧包不会报错，只会留下一个“进程在跑、LuCI 点重启必定失败”的
服务。`docs/MIGRATION.zh-CN.md` 第 4 步与 `scripts/migrate-legacy.sh` 的 `next_steps` 已按此改写。

### 卸载旧包

`apk del luci-i18n-airconnect-zh-cn* airconnect luci-app-airconnect` 三个一起删。通配符是必需的：
带 `~` 的全名会被 apk 当成版本运算符而报 `No such package`，而单独删另两个又会被 i18n 包的依赖
拒绝（`not removed due to: luci-i18n-airconnect-zh-cn`）。

卸载后：

- `apk list --installed` 只剩 `airconnect-engine` / `airconnect-manager` /
  `luci-app-airconnect-manager`；
- `/usr/bin/airupnp`、`/usr/bin/aircast` 消失，`/usr/libexec/airconnect` 保留；
- `/etc/rc.d` 只剩 `K10airconnect-manager` 与 `S95airconnect-manager`；
- **`status.conflicts` 变为空**；
- **RPC `start` 恢复为 `{"ok":true}`**，procd 报 `airupnp` 实例 `running: true`（PID 30545）。

两点副作用：`apk del` 会把新服务一起停掉（procd 实例消失、`init status` 变 `inactive`），必须重新
启动；`apk` 保留了 `/etc/config/airconnect` 与 `/etc/init.d/airconnect` 这两个 conffile，但因为
`/etc/rc.d` 里没有旧链接，它们不会开机自启，也不触发 `conflicts`。

### 切换后的运行状态

- `ubus call airconnect.manager status`：`enabled=true`、`interface=br-lan`、
  `upnp {enabled:true, running:true}`、`cast {enabled:false}`、`conflicts` 为空；
- `/var/etc/airconnect-manager/airupnp.xml` 与 `runtime.uc show upnp` 逐字节一致，`binding=br-lan`、
  `max_volume=30`（迁移自旧配置）、`latency=1000:2000`、`codec=flac`；
- 开机自启：`/etc/rc.d/S95airconnect-manager` 存在，`uci get airconnect-manager.main.enabled` 为 1；
- `ubus call airconnect.manager scan` 返回 `{"ok":true,"running":true}`，完成后 `last_scan` 与
  `broadcast.observed_at` 都写入了时间戳 —— `broadcast.uc` 的 mDNS 观测在真机上确实工作。

### 这一节仍然没有验证的

- **真实音箱**：扫描跑完但 `devices` 为空，该网段没有 AirConnect 能发现的 UPnP/DLNA 渲染器；
  AirPlay 菜单与播放无从验证，`broadcasting` 仍为 `null`。
- **`--rollback`**：没有演练过。备份目录按约定保留。
- **升级保留设置**：未做真实升级。
- **LuCI 页面**：仍未在登录会话中打开。
- **设备侧性能**：仍未测量。

