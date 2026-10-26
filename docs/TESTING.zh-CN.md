# 测试运行与 CI

本文件说明如何在主机上运行全部测试、每个套件证明什么、明确不证明什么，以及 CI
今天覆盖到哪里、哪些环节仍然只能人工验收。所有测试都只在主机（macOS 或 Linux）
上运行，路由器不执行它们，也不依赖路由器。

## 一条命令

```sh
bash scripts/run-tests.sh
```

脚本从自身位置解析仓库根目录，因此可以在任意工作目录调用：

```sh
cd /tmp && bash /path/to/openwrt-airconnect/scripts/run-tests.sh
```

输出是每个套件一行 `PASS`/`FAIL` 加耗时，最后一行是 `N passed, M failed`；
任一失败则退出码为 1，脚本本身有问题（没有套件、没有 ucode、参数错误）为 2。
某个套件失败不会中断整轮，剩下的套件照常运行，避免一处红掩盖其他问题。

- `--verbose`（或 `-v`）：直接流出每个套件的完整输出，而不是只在失败时打印末尾。
- 判定只看退出码，不要求统一输出格式：有的套件打印 TAP（`1..N` / `ok` / `not ok`），
  有的打印自己的 `N checks passed` 汇总。失败时打印最后 20 行，通常已经包含真正的
  断言错误。

套件按约定发现，不维护列表：

| 路径 | 解释器 | 说明 |
| --- | --- | --- |
| `tests/<套件>/run.uc` | ucode | 直接执行该文件 |
| `tests/<套件>/*.mjs` | node | 直接执行该文件 |
| `tests/<套件>/**/*.sh` | bash | 递归包含子目录，如 `tests/package/run-init-script.sh` |

`tests/` 下的其他文件（`fixtures.uc`、`plugin.uc`、`cases.json`、`README.md`）是
夹具与辅助文件，不会被当作套件执行。新增套件只要遵守上表命名即可，无需修改脚本。

## ucode 解释器

ucode 套件需要**真实的** ucode 解释器。查找顺序：

1. `$UCODE` 环境变量（可以是绝对路径，也可以是 PATH 上的命令名）；
2. `~/.local/opt/ucode-host/bin/ucode`；
3. `command -v ucode`。

三者都没有时脚本**直接报错并给出构建方法**，退出码 2，而不是跳过 ucode 套件。
这是刻意的：`$` 在 ucode 正则中会匹配结尾换行，`/^x$/` 因此接受 `"x\n"`；这个
缺陷当初正是因为相关套件没有在 CI 里真正执行才存活下来。跳过等于把已知会漏的
测试当作通过。

若解释器旁边存在 `<bin>/../lib/ucode`，脚本自动加上 `-L <该目录>`，并把
`UCODE`/`UCODE_LIB` 导出给 node 与 shell 套件（`tests/parity/check-frontend.mjs`
与 `tests/state/check-plugin.sh` 自己也会找解释器），保证整轮用的是同一个构建，
不会出现 ucode 套件用 A、parity 后端用 B 的情况。

为什么不能用 stub 或“假装”的 ucode：套件导入的是真实模块并调用真实函数——
`normalizeConfig`/`renderXml` 的完整校验路径、`parseSsdp`/`parseDescription` 的有界
解析、`runtime.uc` 的原子写、`state.uc` 的回复整形，以及 `ucode -c` 的编译结果。
这些行为只有解释器本身能给；一个返回固定值的 stub 只能证明测试脚本会调用 stub。
`tests/parity/check-frontend.mjs` 更进一步：它 shell 出 `run.uc --verdicts`，让后端
判定只存在于一处实现，前端规则必须与真实后端一致。

## 各套件证明什么

| 套件 | 命令 | 证明 |
| --- | --- | --- |
| `tests/config` | `run.uc` | `config.uc` 的校验与 XML 渲染：默认值、继承、数值边界、控制字节、结尾换行、UTF-8 字节上限、XML 转义、确定性输出；高级引擎参数的枚举、继承、按引擎分离（`http_length`/`upnp_max` 不进 `<aircast>`，`stop_receiver` 不进 `<airupnp>`） |
| `tests/discovery` | `run.uc` | `discovery.uc` 的 SSDP/XML 有界解析、URL 与地址校验、去重、深度与体积上限 |
| `tests/broadcast` | `run.uc` | `broadcast.uc` 的 mDNS 决策层：`hash32`/`macPrefixes` 与引擎合成的 MAC 一致、`parseResponse` 解析真实抓包、三态区分（匹配为 `true`、扫描完成无匹配为 `false`、失败/超时/无法解析/过期/前缀不可推导为 `unknown`）、垃圾与超限报文无法翻转状态 |
| `tests/runtime` | `run.uc` | `runtime.uc` 的 UCI 读取、渲染、原子写、失败保留上一份有效 XML、`dry_run`、权限位、`status.json`、CLI 退出码；缺少高级选项的旧配置与当前默认配置渲染结果逐字节相同 |
| `tests/state` | `run.uc` + `check-plugin.sh` | `state.uc`/`files.uc` 的纯逻辑与有界 I/O；rpcd 插件能编译、签名正确、五个方法永不返回 NO_DATA；插件在沙箱根目录 + 假 uci/ubus 下的真实 I/O 路径；`validate` 能报告新高级字段的错误路径；四态分离（服务在跑与音箱被发现都不推出广播、广播为真不推出播放）；广播观测的读取路径（按引擎、按设备、失败、过期、损坏、超限）经由真实插件驱动 |
| `tests/parity` | `run.uc` + `check-frontend.mjs` | `cases.json` 这张手写契约同时约束 `config.uc` 与 LuCI 的 `rules.js`，两边判定必须一致 |
| `tests/luci` | `run.mjs` + `diagnostics.mjs` | 真实视图为两台引擎各建一份表单：Chromecast 设备不出现 `http_length`/`upnp_max`，UPnP 设备不出现 `stop_receiver`；每台设备的覆盖项都能留空继承；下拉项与 `config.uc` 接受的值一致。`diagnostics.mjs` 覆盖四态渲染：未测量显示未知、已测量显示值与观测时间、已测定的否定与未知不同、广播为真不改变播放行 |
| `tests/package` | `check-package.sh` + `run-init-script.sh` | 包清单与文件布局；init 脚本在 procd 替身下的实例注册、`-Z`/`-x`、先校验后发布、接口清洗 |
| `tests/performance` | `measure-payload.sh` + `measure-status.sh` + `poll-contract.mjs` | 本包静态资源字节与 `gzip` 字节及其预算；`status`/`logs` 回复字节与文档化的条数/字节上限是否真的在执行；轮询间隔、隐藏暂停、单请求在途、失败退避、状态刷新不写表单 |
| `tests/engine` | `check-recipe.sh` | 引擎配方的版本/摘要/架构归一化/提取脚本逻辑，用合成 ZIP 驱动 |

## 各套件不证明什么

这是本文件最重要的部分。**主机测试全绿不等于可以在路由器上发布**。

- **没有路由器，也没有真实的 ucode `uci`/`ubus`**：`uci`、`ubus` 在主机上不存在，
  相关代码路径用注入的假游标或 stub 模块驱动。真实 rpcd 是否接受该签名、procd 的
  `service list` 返回形状、netifd 的 `network.device status` 字段，都只按文档和源码
  编写，未在真实 ubusd 上核对。
- **没有音频**：不播放、不转码、不验证 AirPlay 广播名称是否真的出现在设备上，
  也不验证音量上限对实体键/语音/原厂 App 无效这一产品事实。播放与广播状态在界面上
  一律显示为未知，测试也不能把它变成已知。
- **没有 SSDP 网络**：发现逻辑只验证解析与边界；真实网卡上的组播、绑定接口、
  防火墙行为未覆盖。
- **没有 SDK 构建**：不下载 OpenWrt SDK，不编译任何软件包，不产出 APK/IPK。
  配方的 `PKG_HASH` 与上游 95 MB 归档也从未在本环境完成下载与本地摘要校验。
- **没有设备端执行**：二进制未在 aarch64/x86_64 路由器上运行过。
- **没有浏览器**：`dev/` 预览与 `rules.js` 的加载是模块级验证，不替代真实 LuCI、
  真实浏览器渲染、无障碍与移动端布局验收。
- **不验证并发与性能**：`tests/performance` 已把**主机可测**的部分变为了断言（静态资源
  字节、`status`/`logs` 回复字节、轮询决策），数字与命令见
  [性能测量结果](PERFORMANCE-RESULTS.zh-CN.md)。但路由器 CPU、RSS/VSZ、网络、播放中断、
  浏览器长任务仍需真实设备，这些主机无法产生任何数字。

人工验收项汇总见 [验证记录](VERIFICATION.zh-CN.md)。

## CI：今天覆盖什么

`.github/workflows/test.yml` 的 `Host tests` 工作流在 `push`（任意分支）与
`pull_request` 上运行一个 `ubuntu-latest` 任务 `host-tests`：

1. `actions/checkout@v4` 检出代码；
2. `actions/setup-node@v4` 安装 **Node 20**（固定主版本；仓库没有任何 npm 依赖，
   node 只用于执行普通 `.mjs` 文件）；
3. `apt-get install libjson-c-dev`，ucode 本身的硬性构建依赖；
4. 从 `jow-/ucode` 的**固定标签** `v0.0.20250529` 下载源码并 `cmake` 构建安装到
   `.ucode/`，用 `actions/cache@v4` 缓存；缓存命中时只校验解释器可执行；
5. `bash scripts/run-tests.sh`，也就是上面那条命令。

因此 CI 覆盖的正是“主机可证明”的部分：ucode 模块的校验/渲染/解析/原子写、rpcd
插件的编译与沙箱 I/O、包与 init 脚本的静态及行为检查、前后端校验一致性。

`workflow_dispatch` 只会重新运行 `host-tests`。SDK 构建不属于这个工作流；它由
`.github/workflows/release.yml` 的 `build` job 负责，并且只在 release-please 创建发布后运行。
该 job 会使用固定的 OpenWrt SDK 编译三个功能包和自动生成的中文翻译包，校验四个 APK，
生成 `packages.adb`，再交给 Release 上传和 Pages 发布任务。

## CI 不覆盖、仍需人工的门槛

- **SDK 构建的远程成功记录**：发布工作流已经实现自动构建，但当前修改仍需一次真实的
  GitHub Actions 运行来确认 SDK 下载、四包编译、Release 上传和 Pages artifact 聚合。
  这不是 `host-tests` 的 push/PR 阶段工作。
- **真实设备验收**：安装、启动、两台音箱独立设置、保存/重启/升级后配置保留、
  AirPlay 满音量映射与反馈、回退方案。
- **真实 LuCI 集成**：页面在目标 LuCI 版本中的渲染、保存回滚、服务触发器。
- **音频与网络**：实际播放、多流并发、发现成功率、防火墙与 DNS 环境差异。
- **性能测量**：主机侧部分已完成（静态资源量、`status`/`logs` 回复大小与上限执行、轮询契约），
  见 [性能测量结果](PERFORMANCE-RESULTS.zh-CN.md)；设备侧的 CPU、RSS、网络与播放中断仍未测。

在这些门槛通过之前，本仓库不声称“可在路由器上直接部署的增强版发行包”。
