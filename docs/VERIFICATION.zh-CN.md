# 初始化验证记录

本轮验证了独立项目结构和上游依赖来源，尚未完成 SDK 编译或设备安装。

- 独立 Git 根目录为 openwrt-airconnect，不含原 fork 的历史和远端。
- 本地 Markdown 相对链接检查通过。
- 发布源检查未发现现场音箱 IP、UDN 或登录凭据。
- 官方 GitHub Releases API 返回 1.12.4 的 AirConnect-1.12.4.zip，大小 95,060,625 字节，digest 为 sha256:ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903，与新包配方一致。
- 官方 ZIP 下载超时、未完成，未把残缺文件作为有效源或构建产物。后续 SDK 下载必须通过 PKG_HASH 验证；本轮没有做完整 ZIP 自计算 SHA256、ELF 检查或可执行性验证。
- 许可证原文取自官方 1.12.4 标签，仅去除行尾空格；声明 AirConnect 为 MIT，第三方组件各自遵循原作者条件。依赖许可证审计仍属于发布前任务。

来源：

- https://api.github.com/repos/philippe44/AirConnect/releases/tags/1.12.4
- https://github.com/philippe44/AirConnect/releases/tag/1.12.4
- https://github.com/philippe44/AirConnect/blob/1.12.4/LICENSE

未部署新服务，路由器继续使用之前已安装的版本。独立管理层与新界面已写入仓库并在主机测试下运行，
但尚未经 SDK 构建与真实设备验收；当时的这项结论对构建与设备仍然成立，具体状态见下一节。

## 主机验证现状（2026-10-21）

本节记录一次完整的主机运行结果，与上文的初始化记录和下文的分项记录并存，不互相替代。

### 证据来源

- 机器：macOS 27.0（Darwin 27.0.0，arm64）。
- ucode：`~/.local/opt/ucode-host/bin/ucode`（主机自建，含 `fs`/`socket`/`math` 等
  模块，`-L ~/.local/opt/ucode-host/lib/ucode`）；node v24.13.0；bash 3.2.57；`/bin/dash`。
- 未使用 OpenWrt SDK、未联网、未安装任何路由器组件。

### 已在这台主机上验证

统一入口：`bash scripts/run-tests.sh`（15 个套件全部通过）。分套件结果：

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| config | `ucode tests/config/run.uc` | 661 通过，0 失败 |
| discovery | `ucode tests/discovery/run.uc` | 103 项检查通过 |
| parity（后端） | `ucode tests/parity/run.uc` | 1388 通过，0 失败 |
| parity（前端） | `node tests/parity/check-frontend.mjs` | 930 通过，0 失败 |
| luci 视图 | `node tests/luci/run.mjs` | 43 通过，0 失败 |
| runtime | `ucode tests/runtime/run.uc` | 38 通过，0 失败 |
| state | `ucode tests/state/run.uc` | 70 通过，0 失败 |
| state 插件 | `bash tests/state/check-plugin.sh` | 43 通过，0 失败 |
| package 静态 | `bash tests/package/check-package.sh` | 67 通过，0 失败 |
| init 脚本 | `bash tests/package/run-init-script.sh` | 148 项检查，0 失败 |
| engine 配方 | `bash tests/engine/check-recipe.sh` | 30 通过，0 失败 |
| migration | `bash tests/migration/run.sh` | 122 通过，0 失败 |
| 性能：静态资源 | `bash tests/performance/measure-payload.sh` | 5 个文件，47,775 B / gzip 14,646 B，预算全部成立 |
| 性能：回复大小 | `bash tests/performance/measure-status.sh` | 10 通过，0 失败 |
| 性能：轮询契约 | `node tests/performance/poll-contract.mjs` | 29 通过，0 失败 |

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

- **SDK 构建**：没有用 OpenWrt SDK 编译过任何一个包，也没有生成或安装过 APK 或 IPK。
  仓库内不存在 `*.apk`、`*.ipk` 或构建产物。CI 中的 `sdk-build` 只是一个明确标注为
  “未实现”的占位 job，不产出任何东西。
- **CI 执行**：`.github/workflows/test.yml` 的主机测试工作流已实现，但从未执行过；
  没有任何一次 CI 运行结果可查。本节表格中的全部数字来自上面的本地运行。
- **真实设备**：没有任何东西在真实路由器上运行过。真实 rpcd 注册、procd/netifd 的 ubus
  返回形状、设备上的 `/etc/init.d/airconnect-manager` 行为均未核对。
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

- **真实 rpcd 注册**：只在主机上校验了签名对象的结构，未在运行中的 rpcd 上确认注册成功。
- **procd / netifd**：`service list`、`network.device status`、`network.interface dump`
  的返回形状来自文档与源码，未在真实 ubusd 上核对。
- **SSDP 与设备发现**：只覆盖了工作进程的失败路径，未在真实接口上完成发现。
- **init 脚本调用**：`/etc/init.d/airconnect-manager <action>` 在设备上的实际行为未验证。

### 未验证

- **归档内容**：95 MB 的 `AirConnect-1.12.4.zip` 在本环境中始终未能完成下载
  （环境层两次超时），因此未对归档内实际文件名、ELF 内容或结构做任何本地核对。
  提取脚本仅以合成归档做了逻辑验证，不代表真实归档已通过 `PKG_HASH` 校验。
- **SDK 编译**：未执行 OpenWrt SDK 构建；`Build/Compile` 中的 ELF 校验
  （`file` 优先，回退到 `od -An -tx1 -N4` 头字节检查）尚未在真实 SDK 容器中运行。
- **设备端执行**：未在真实 aarch64/x86_64 路由器上安装或运行二进制。

> 注意：`PKG_HASH` 与发布元数据来自 GitHub API，但 ZIP 本体从未在本环境完成下载，
> 故不声称“归档已通过本地下载与摘要校验”。完整的 `PKG_HASH` 自计算、ELF 检查与
> 可执行性验证仍属 SDK/设备验收阶段的任务。
