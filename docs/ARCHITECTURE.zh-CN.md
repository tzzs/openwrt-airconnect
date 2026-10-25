# 独立适配封装的架构决策

## 决策

协议与音频实现直接依赖 [philippe44/AirConnect](https://github.com/philippe44/AirConnect)。本项目建立独立 Git 历史，不继承 sbwml fork 的提交或发布流水线。现有 fork 和现场服务保留，避免把项目方向调整变成线上服务切换。

## 现有封装如何工作

核对的参考基线为 `sbwml/luci-app-airconnect` 的 `b0dfd0689356d634191e77a25ff4f8c92763df4a`。

| 参考实现 | 做法 | 独立项目取舍 |
| --- | --- | --- |
| [引擎 Makefile](https://github.com/sbwml/luci-app-airconnect/blob/b0dfd0689356d634191e77a25ff4f8c92763df4a/airconnect/Makefile) | 下载固定版本官方 ZIP，校验 SHA256，按架构安装 static 二进制 | 采用官方固定版本及校验和的方式；首版明确限定 aarch64/x86_64，不沿用未经测试的架构矩阵 |
| [启动脚本](https://github.com/sbwml/luci-app-airconnect/blob/b0dfd0689356d634191e77a25ff4f8c92763df4a/airconnect/files/airconnect.init) | UCI 读取引擎开关和接口，procd 启动并拉起进程 | 采用 procd；新增独立的校验/配置生成层，所有设备配置生成对应引擎 XML |
| [LuCI 页面](https://github.com/sbwml/luci-app-airconnect/blob/b0dfd0689356d634191e77a25ff4f8c92763df4a/luci-app-airconnect/htdocs/luci-static/resources/view/airconnect.js) | LuCI form 和 service.list 轮询 | 使用 LuCI 静态 JS 和受限 RPC；全新设备优先界面，不沿用单张长表 |
| [权限文件](https://github.com/sbwml/luci-app-airconnect/blob/b0dfd0689356d634191e77a25ff4f8c92763df4a/luci-app-airconnect/root/usr/share/rpcd/acl.d/luci-app-airconnect.json) | 授权读取服务列表和读写对应 UCI | 按方法划分状态/配置/操作权限，禁止任意 shell、任意文件读写 |
| [发布流水线](https://github.com/sbwml/luci-app-airconnect/tree/b0dfd0689356d634191e77a25ff4f8c92763df4a/.github/workflows) | 标签触发多个架构与 24.10/SNAPSHOT SDK 构建 | 重新建立稳定版 SDK 构建、测试和发布流程，不把 SNAPSHOT 等同于 25.12 |

以上为技术方式参考，不代表复制整个项目。若后续复用任何代码，需保留该文件适用的版权及许可证声明。

## 三个独立边界

### 引擎包：airconnect-engine

只提供 `/usr/libexec/airconnect/airupnp` 与 `aircast`、来源信息和许可证。固定官方发布版本，初始 1.12.4。使用 static 是针对 OpenWrt/musl 的明确打包选择，不是上游对所有平台的首选建议；动态版需验证 ABI 和依赖后再支持。不运行安装脚本下载 latest，不把未经测试的 HEAD 更新自动送到路由器。

### 适配层：airconnect-manager

计划管理 `/etc/config/airconnect-manager` 和同名 procd 服务。UCI 为唯一持久配置来源；按引擎及设备 ID 保存覆盖项，生成 `/var/etc/airconnect-manager/` 下运行时 XML。快照、日志和运行时文件不得反向覆盖持久配置。

配置先校验，再生成临时文件并原子替换；失败时不停止正在使用的有效实例。名称按 UTF-8 字节数验证及 XML 转义，UPnP `max_volume` 与 Cast `media_volume` 分别处理。尽量使用 OpenWrt 自带 ucode/UCI，不增加 Python 或 Node 常驻服务；最终依赖在实现时显式声明。

procd 使用 `-Z`，不让引擎自行 daemonize；分别管理 UPnP/Cast 实例。扫描、状态和日志通过有界缓存提供，避免每个页面都启动一个发现进程。结构化数据来源不足时展示未知，不伪装为可靠实时播放 API。

### `airconnect.manager` rpcd 后端

`files/usr/share/rpcd/ucode/airconnect-manager` 是 rpcd 的 ucode 插件，顶层 `return` 即签名对象，注册 `airconnect.manager` 的 `status`、`logs`、`scan`、`validate`、`action` 五个方法（ACL 已在 LuCI 包中，不在此重复）。

- **复用而非重写**：`config.uc` 负责校验与渲染，`discovery.uc` 负责 SSDP，`broadcast.uc` 负责 mDNS 广播观测，`runtime.uc` 负责读 UCI（该文件是 script 模式，只能经 `loadfile()` 取到 API），`state.uc` 与 `files.uc` 负责纯逻辑与有界 I/O。
- **降级而不是失联**：`uci`、`ubus` 用 `require()` 在 try/catch 内加载。静态 `import` 一旦缺模块会让整个插件编译失败、所有方法消失，而 `status` 恰恰需要在 procd 读不到时仍能返回。
- **状态与进程分离**：`enabled`/`interface` 来自 UCI，`running` 来自 procd 的 `service list`；ubus 问不到时为 `null`（未知），绝不写成 `false`。
- **扫描显式且限时**：`status` 从不发起扫描。`scan` 取锁后立刻返回，工作进程是同一文件的 `scan-worker` 分支，不新增常驻进程，受 `discovery.uc` 自带 8 秒预算约束。
- **四态分离**：`running` 来自 procd，`discovered` 来自 SSDP 缓存，`broadcasting` 来自 mDNS 对 `_raop._tcp` 实例的观测，`playback` 恒为未知。三种实测各有缓存与失效期（SSDP 24 小时、mDNS 5 分钟），互不推导。`broadcast.uc` 只做一次有界查询，`status` 只读缓存文件，因此轮询不产生组播流量。
- **不做破坏性动作**：冲突检测只报告旧服务、旧二进制或外来进程的存在，绝不终止、删除或修改。`start`/`restart` 在存在冲突时拒绝。
- **请求值不进 shell**：`action` 用请求值在固定表里选命令，命令本身是字面量。

主机测试见 `tests/state/`；真实 rpcd、procd、netifd 与 SSDP 仍属设备验收项，未在主机验证。

### 页面：luci-app-airconnect-manager

继续使用 LuCI 认证与权限，提供 shadcn 风格的静态管理界面。分为音箱、设置、诊断；名称/音量为常用操作，格式/缓冲等折叠为高级设置。页面样式不污染其他 LuCI 页面，隐藏暂停轮询，日志按需读取。

## 新旧服务切换

引擎包本身不启动进程。管理适配层必须检测旧 airconnect 服务或 Docker 实例；不得同时拉起两套广播，也不自动删除旧容器。切换流程为备份、用户可见的配置映射、停用旧实例、启动新实例、验证发现/广播/播放、失败回退。旧单音箱现场配置属于迁移输入，不可写进公共包。

## 实施顺序

1. 验证官方 ZIP 内容、架构与校验和，完成独立引擎包配方。
2. 实现 UCI → XML 转换及配置测试：默认继承、每设备名称/启停/音量、非法输入、转义、失败保留。
3. 实现 procd、受限 RPC 与发现缓存，测试仅启用一个引擎及异常恢复。
4. 实现完整新界面并验证保存、反馈、移动/明暗/键盘体验。
5. 在匹配的稳定 SDK 构建 APK，完成依赖许可核对，再进行有回退的设备验收与发布。

已完成：独立项目初始化、文档迁移、引擎包配方、UCI → XML 适配层（`config.uc`、`runtime.uc`）、
有界发现解析（`discovery.uc`）、procd 启动脚本、`airconnect.manager` rpcd 后端、三个页签的
LuCI 页面与旧实例迁移脚本（`scripts/migrate-legacy.sh`）。这些均有主机测试（见 `tests/`）。
**2026-10-26 补充**：三个包已用 OpenWrt SDK 25.12.6 构建成 APK 并装到真实设备，服务切换也已
完成（旧包及依赖卸载、新服务运行并设为开机自启）；仍未接入真实音箱。构建与设备验收的完整结果
见[验证记录](VERIFICATION.zh-CN.md) 的 S2、S3 两节。
