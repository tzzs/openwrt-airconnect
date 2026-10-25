# 从旧 AirConnect 迁移到 airconnect-manager

状态：**已于 2026-10-26 在一台真实设备上执行过一次**（iStoreOS 25.12.5、rockchip/armv8、
aarch64_generic、APK）：`--dry-run` 与 `--apply` 跑通，旧包及其依赖已卸载，新服务已在运行并
设为开机自启。**仍未验证**：真实音箱的发现与播放（本次扫描未发现任何 UPnP/DLNA 渲染器）、
`--rollback` 的实际执行、真实 Docker 现场。完整记录见文末“首次执行记录”。

适用对象：

- 已安装 `sbwml/luci-app-airconnect`（`/etc/config/airconnect` + `/etc/init.d/airconnect`）的现场；
- 用 Docker 跑 AirConnect 镜像的现场；
- 仍保留旧 `/usr/bin/airupnp`、`/usr/bin/aircast` 布局的现场。

目标：把旧配置映射成 `/etc/config/airconnect-manager`，停用旧实例，**在验证通过之后**才启动新
实例；任何一步失败都能回到旧实例。

工具：`scripts/migrate-legacy.sh`（随仓库提供，POSIX sh，BusyBox ash 可运行）。

## 为什么不能“装了再切”

两套 AirConnect 同时广播，同一台音箱会在 AirPlay 菜单里出现两个接收器；iOS 可能连到即将被停用的
那个，播放会中途断开，而且很难判断是谁在响。所以流程固定为：

备份 → 用户可见的配置映射 → 停用旧实例 → 启动新实例 → 验证发现/广播/播放 → 失败回退。

脚本只做前半段（备份、映射、停用），启动与验证必须由人来做。这是刻意的：脚本无法确认音箱是否
真的出现，也无法确认播放是否真的出声。

## 一、预检（动手前先记录）

在路由器上执行并**把输出保存到路由器之外**（截图、复制到电脑，或写到 U 盘）：

```sh
# 1. 现有软件包（24.10/IPK 与 25.12/APK 的包管理器不同，两条都记）
opkg list-installed 2>/dev/null | grep -i airconnect
apk list --installed 2>/dev/null | grep -i airconnect

# 2. 旧配置原样备份（这是脚本之外的第二份备份，放在持久位置）
cat /etc/config/airconnect

# 3. 旧服务的开机与运行状态
/etc/init.d/airconnect enabled; echo "enabled=$?"
/etc/init.d/airconnect running; echo "running=$?"

# 4. Docker 现场：容器名、镜像、启动参数
docker ps --format '{{.Names}}|{{.Image}}|{{.Status}}'
docker inspect --format '{{.Name}} {{.Config.Image}} {{.HostConfig.RestartPolicy.Name}}' $(docker ps -q)

# 5. 预期出现在 AirPlay 菜单里的音箱：写下来（几台、什么名字）
#    这是后面“验证”的对照物，不记录就无法判断迁移是否成功。

# 6. 网络接口（新配置的 binding 必须与旧的一致）
ip -4 addr show
```

同时确认：

- 有可用的 LuCI 会话和 SSH 会话，且**不是**正在播放音乐的时候；
- 已安装 `airconnect-engine` 与 `airconnect-manager`（`/etc/config/airconnect-manager` 存在），
  且新服务当前**没有**运行；
- 知道如何重新安装旧包（旧 IPK/APK 文件或 opkg 缓存），以防需要重建旧实例。

> **明确警告**：切换会短暂中断 AirPlay。停用旧实例到新实例验证通过之间，音箱不会出现在 AirPlay
> 菜单里。这段时间通常以分钟计；如果现场对“随时可播放”有要求，请在维护窗口执行。

## 二、命令序列

以下命令在路由器上以 root 执行。脚本没有网络访问，也不会删除任何软件包、容器或配置。

### 1. 试运行（默认模式，不改动任何文件）

```sh
sh /path/to/scripts/migrate-legacy.sh --dry-run
```

不带任何参数时默认就是 `--dry-run`。它会打印：

- **检测结果**：旧 UCI 服务、Docker 容器、旧 `/usr/bin` 二进制，逐条一行；
- **映射报告**：每一条都是 `old-key=value -> new-key=value` 或 `old-key=value -> skipped (原因)`；
- **结果预览**：最终写入 `/etc/config/airconnect-manager` 的全部键值；
- **前置条件**：目标配置文件是否存在、新服务是否在运行、是否有上一次 `--apply` 尚未回退。

### 2. 阅读映射报告

必须逐行确认，特别是这几类：

| 报告内容 | 含义与处理 |
| --- | --- |
| `airconnect.main.iface=br-lan -> ...interface=br-lan` | 旧文件用的是 `iface`，脚本接受 `interface`/`iface`/`binding` 三种拼写 |
| `airconnect.main.enabled=(absent) -> ...enabled=1 (the legacy service is enabled at boot or running)` | 旧文件没有 `enabled` 键时，用旧服务的开机/运行状态推断，不用“沉默=默认关”猜 |
| `... -> skipped (not a bare interface token of 1..15 ASCII bytes)` | 旧值不是合法接口名，脚本回退到 `br-lan`；请手工改成真实接口 |
| `...max_volume=30 -> ...device_legacy.max_volume=30` | 找到 UDN，音量上限写进该设备的段 |
| `...max_volume=30 -> ...main.max_volume=30 (no UDN found; per-device attribution needs a scan)` | **没有 UDN**，音量上限只能写成全局值；见“已知限制” |
| `...udn=... -> skipped (not a uuid: UDN of at most 255 bytes)` | 旧 UDN 不合法，不会被猜成别的值；需要扫描后再设 |

脚本**不会**把音箱名称或 IP 地址写进设备段：它们不是设备身份，换个 DHCP 租约或改个名字就失效。

### 3. 应用（备份 + 映射 + 停用旧实例）

```sh
sh /path/to/scripts/migrate-legacy.sh --apply
```

`--apply` 会：

1. 在 `/etc/airconnect-manager-backup/<UTC 时间戳>/` 建备份，`manifest.txt` 记录每个原文件的
   路径与权限位，并记录旧服务与容器状态；已存在的备份目录**拒绝覆盖**；
2. 用临时文件 + rename 写新的 `/etc/config/airconnect-manager`（不会留下半写文件）；文件权限沿用
   原有配置文件的权限位，`--dry-run` 会提前打印出来；
3. `stop` 并 `disable` 旧 `/etc/init.d/airconnect`；
4. 对匹配 `airconnect` 的 Docker 容器执行 `docker stop`（**不删除**）。

它**不会**：启动新服务、删除旧软件包、删除容器、删除旧配置、重启旧服务、访问网络。

如果新服务正在运行，`--apply` 会拒绝执行并说明“会同时出现两套广播”；确认要让它先停掉新服务时
才加 `--force-stop-new`。

同一个备份未回退之前，第二次 `--apply` **会拒绝执行**（而不是幂等重写），这样迁移之后在 LuCI
里改过的设置不会被静默覆盖。需要重新应用时先 `--rollback`。

### 4. 移除旧包（脚本不做）

`airconnect.manager` 后端在检测到旧服务、旧二进制或外来引擎进程时会拒绝 `start`/`restart`，
所以必须先把旧包卸掉。**注意拦截只发生在 RPC 路径**（也就是 LuCI 页面发出的操作），init 脚本
本身不检查：2026-10-26 在 iStoreOS 25.12.5 上实测，旧包仍在时 `/etc/init.d/airconnect-manager
start` 返回 0 并真的启动了引擎，而 `ubus call airconnect.manager action '{"action":"start"}'`
返回 `{"ok":false,"error":"Conflicting AirConnect instance detected"}`。

后果是：跳过这一步不会报错，只会得到一个"进程在跑、但 LuCI 页面点重启必定失败"的服务。
`status` 的 `conflicts` 字段会一直显示 `Legacy binaries found in /usr/bin.`。

```sh
opkg list-installed | grep -i airconnect     # 24.10 / IPK
apk list --installed | grep -i airconnect    # 25.12 / APK

# 24.10 / IPK，按上一步查到的实际包名
opkg remove luci-app-airconnect airconnect

# 25.12 / APK，同样按实际包名（翻译包名带版本后缀，用通配符）
apk del luci-i18n-airconnect-zh-cn-* luci-app-airconnect airconnect
```

**卸载前先把旧包的安装文件复制到持久位置。** 回退（`--rollback`）只能恢复配置，不能重装已被
卸载的包；而现场通常只在 `/tmp` 里留着一份 APK，`/tmp` 在重启后会清空。复制一份到 `/root` 或
U 盘，回退路径才算真的留着：

```sh
mkdir -p /root/legacy-airconnect-apk
cp /tmp/airconnect-*.apk /tmp/luci-*airconnect*.apk /root/legacy-airconnect-apk/ 2>/dev/null
```

需要重装时：

```sh
apk add --allow-untrusted /root/legacy-airconnect-apk/*.apk
```

Docker 现场不需要卸载任何包，但容器要保持 `stopped`（脚本已经停过）。

### 5. 启动新实例

```sh
uci set airconnect-manager.main.enabled='1'
uci commit airconnect-manager
/etc/init.d/airconnect-manager start
```

**开关是 UCI 的 `enabled`，不是 init 脚本的 `enable`。** OpenWrt 的 `default_postinst` 在安装时
已经把 init 脚本加进 `/etc/rc.d`（`S95airconnect-manager`），所以 `/etc/init.d/airconnect-manager
enabled` 一直返回 0。真正决定是否广播的是 `airconnect-manager.main.enabled`：为 0 时
`start_service` 不注册任何 procd 实例，装完也不会广播。

`uci set` 与 `start` 分开执行，是为了让“持久设置”和“本次运行”两个状态都能单独观察。

### 6. 验证并保留备份

先完成下一节的四条验证，再保留备份 **N = 7 天**（至少覆盖一次路由器重启和一次完整使用周期）。
备份目录 `/etc/airconnect-manager-backup/<UTC 时间戳>/` 在 7 天内不要删除：这是回退的唯一依据。
7 天后确认稳定，再手工删除（脚本不自动清理，见“已知限制”）。

## 三、验证步骤

四条**互相独立**的检查。服务进程在跑，不蕴含音箱被发现；被发现，不蕴含 AirPlay 菜单里有；菜单里
有，不蕴含能出声。必须逐条看到结果，不能因为上一条通过就跳过下一条。

### 1. 服务确实在运行（按引擎分别看）

```sh
# 1a. procd 报告的实例集合（每个引擎一条）
ubus call service list '{"name":"airconnect-manager"}'

# 1b. 运行时 XML 确实生成了，且与持久配置一致
#     只对启用的引擎执行；例如只启用了 UPnP 就只看 upnp
ls -l /var/etc/airconnect-manager/
/usr/share/airconnect-manager/runtime.uc show upnp

# 1c. 旧实例确实不在了
/etc/init.d/airconnect running; echo "old-running=$?"
docker ps --format '{{.Names}}|{{.Image}}'
```

期望：`ubus` 输出里启用的每个引擎各有一个实例且 `running` 为 `true`；`runtime.uc show <engine>`
的 `<binding>` 与配置里的 `interface` 一致、`<max_volume>`/`<media_volume>` 与配置一致；旧服务
`old-running` 非 0（未运行）；`docker ps` 里没有 `airconnect` 容器。

只启用了 aircast 时，UPnP 实例不应出现；反之亦然。两个都启用时，两个实例都要在。注意 `running`
只说明 procd 里有一个进程，不说明它已经成功绑定接口或注册到网络。

### 2. 扫描能找到预期的音箱

在 LuCI 页面（AirConnect 管理 → 诊断）点“重新扫描”，或通过 RPC 触发。对照预检第 5 步记录的
名单：数量与名字都要对得上。

扫描为空时**不要**先改防火墙、DNS 或关掉隔离；先确认音箱在线、与路由器在同一网段、DLNA/UPnP
开启。扫描结果按 UDN 去重，同一台音箱不会因为换了 IP 出现两次。

### 3. 至少一台音箱出现在 iOS AirPlay 菜单里

在 iPhone/iPad 控制中心打开 AirPlay 列表，确认目标音箱出现，且显示名称是预期名称（有覆盖值时
是覆盖值，没有时是设备原名）。

### 4. 至少播放一首曲目

从该音箱播放一段音频，确认：有声音、能调音量、暂停/继续有效、拖动进度不会断流。

> 只有第 4 步通过才算“迁移成功”。前三步都是必要条件，不是充分条件。

## 四、回退

```sh
sh /path/to/scripts/migrate-legacy.sh --rollback
```

`--rollback` 会：

1. 若新服务在运行，先 `stop` 它（绝不让两套同时广播）；
2. 按 `manifest.txt` 恢复 `/etc/config/airconnect` 与 `/etc/config/airconnect-manager` 的**原始
   字节**与原权限位；
3. 旧服务原本开机启用则 `enable`，原本在运行则 `start`；
4. 把备份目录标记为 `rolled-back`（目录本身保留，供审计）。

`--rollback` 是幂等的：没有待回退的备份时打印 `nothing to roll back` 并以 0 退出；重复执行不会
再次改动文件。若某一步失败（例如旧包已被卸载），它**不会**标记为已回退，修正后可以重跑。

### 回退无法恢复的内容

- **已经卸载的旧软件包**：脚本从不卸载包，但如果你手工卸了，回退不会重装；需要手工装回。
- **已经删除的容器**：`--rollback` 只能 `docker start` 一个仍然存在的容器。脚本不删容器，但若你
  在验证期间手工 `docker rm`，回退无法重建。
- **迁移之后在 LuCI 里做的新修改**：回退恢复的是 `--apply` 那一刻的字节，之后改的设置会丢失。
- **运行时 XML 与日志**：`/var/etc/airconnect-manager/` 是生成物，回退不处理；下次启动会按恢复后
  的 UCI 重新生成。
- **播放会话**：任何切换都会中断正在播放的流，回退也不能续播。

## 五、Docker 现场

检测：脚本执行 `docker ps --format '{{.Names}}|{{.Image}}'`，容器名或镜像名包含 `airconnect`
（不区分大小写）即视为旧实例。`docker ps` 失败时脚本**不会**假装没有容器：`--dry-run` 会报告
无法检查，`--apply` 会拒绝执行。

停止（脚本在 `--apply` 中自动做）：

```sh
docker stop <容器名>
```

**不要 `docker rm`**。原因：

- 容器停着不占 CPU，也不广播，不构成冲突；
- 一旦删除，回退就只能靠重新 `docker run`，而重建命令里的参数（网络模式、挂载、环境变量）很可能
  没有被完整记录；
- 脚本的职责边界是“停用旧实例”，不是“销毁用户的部署”。

容器随主机重启自动拉起的情况（`--restart always` / `unless-stopped`）需要额外处理，脚本不会修改
容器的重启策略：

```sh
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' <容器名>
```

若是 `always`，请在验证通过后手工 `docker update --restart=no <容器名>`，否则重启路由器时旧容器会
自己回来，与新服务同时广播。`--rollback` 会 `docker start` 该容器，但不会恢复原来的重启策略。

## 六、已知限制

- **从未在真实硬件上执行**。脚本有主机测试（假 root 目录树 + 假 `uci`/`docker`），测试覆盖默认
  模式不改动、映射、备份、回退、二次应用拒绝、备份目录冲突、`--force-stop-new`。测试**没有**覆盖
  真实 uci、真实 procd、真实 docker、真实 init 脚本和真实音箱。
- **架构限制**：`airconnect-engine` 首版只支持 aarch64 / x86_64。`riscv64` 等架构在构建时明确
  失败。**EPYC/AMD 服务器上跑 x86_64 二进制**属于 x86_64 目标，但没有在 EPYC 上验证过；若旧现场
  是 ARM 设备而新包只有 x86_64，迁移无从谈起，请先确认架构匹配。
- **每设备音量归属需要扫描**：旧配置若只有“一个音量上限”而没有 UDN，脚本只能写进
  `main.max_volume`（全局）。要让限制只作用于某台音箱，需要先扫描拿到 UDN，再在 LuCI 里为那台
  设备单独设置。脚本不会用音箱名或 IP 代替 UDN。
- **`enabled` 的推断**：旧文件没有 `enabled` 键时，用旧服务的开机/运行状态推断。若旧服务当时既
  未启用也未运行，迁移后新服务也是关闭的——这是有意的，脚本不会替用户打开广播。
- **接口名**：旧值不合法时回退 `br-lan`。若现场用的是 `eth0`、`br-wan` 或自定义网桥，请在
  `--apply` 之后手工核对 `option interface`，否则引擎会绑到错误接口，表现为“扫描不到音箱”。
- **备份保留期**：脚本不自动清理 `/etc/airconnect-manager-backup/`。建议保留 7 天并至少跨过一次
  重启；确认稳定后手工删除旧目录（`rm -rf /etc/airconnect-manager-backup/<时间戳>`），这是本流程
  里唯一需要人工删除的路径。
- **不可用的检测源**：旧包的配置文件路径与键名以现场实际为准。脚本接受 `interface`/`iface`/
  `binding`、`upnp`/`airupnp`、`aircast`/`cast`、`max_volume`/`volume_limit`/`volume`，其他拼写会
  被报告为 `(absent)` 并按默认值处理，不会静默套用错误值。
- **没有做的事**：不检测“旧进程是否真的退出”（只信 init 脚本与 `docker stop` 的返回值）；不验证
  生成的 XML 能被引擎接受（需要真机）；不清理旧包的残留文件（`/usr/bin/airupnp` 等由包管理器负责）。

## 首次执行记录（2026-10-26）

### 设备与旧安装形态

- iStoreOS 25.12.5，`DISTRIB_TARGET=rockchip/armv8`，`DISTRIB_ARCH=aarch64_generic`，APK 包管理。
- 旧安装形态是 **UCI 包**：`airconnect-1.12.4-r1`、`luci-app-airconnect-1.0.3-r1`、
  `luci-i18n-airconnect-zh-cn-26.216.59507~71e1bd6`；`/etc/config/airconnect` +
  `/etc/init.d/airconnect` 都在，服务 enabled 且 running，引擎进程为
  `/usr/bin/airupnp -x /var/etc/airconnect-airupnp.xml -l 1000:2000 -Z -b br-lan -S broadcast`。
- 没有匹配 `airconnect` 的 Docker 容器（设备上确实装了 docker，跑的是 homeassistant）。

### `--dry-run` 与 `--apply`

旧配置只有六个键，映射结果：

| 旧键 | 结果 |
| --- | --- |
| `enabled=1` | → `main.enabled=1` |
| `interface=br-lan` | → `main.interface=br-lan` |
| `airupnp=1` | → `main.airupnp=1` |
| `aircast=0` | → `main.aircast=0` |
| `max_volume=30` | → `main.max_volume=30 (no UDN found; per-device attribution needs a scan)` |
| `stream_type=broadcast` | → `skipped (no equivalent option in airconnect-manager; not carried over)` |

`--apply` 成功，备份 `/etc/airconnect-manager-backup/20261025T173836Z`，`manifest.txt` 记录了
`legacy_config=etc/config/airconnect mode=600`、`target_config=etc/config/airconnect-manager
mode=600`、`legacy_enabled=yes`、`legacy_running=yes`，与旧文件一致（旧配置原本就是 600）。
旧服务被 `stop` 并 `disable`，`/etc/rc.d` 里的旧链接消失。

### 四条验证

1. **服务运行**：通过。`ubus call service list '{"name":"airconnect-manager"}'` 报 `airupnp`
   实例 `running: true`，命令为 `/usr/libexec/airconnect/airupnp -Z -x
   /var/etc/airconnect-manager/airupnp.xml`；`runtime.uc show upnp` 与磁盘上的
   `/var/etc/airconnect-manager/airupnp.xml` 逐字节一致，`binding=br-lan`、`max_volume=30`、
   `latency=1000:2000` 都带对了。旧实例不在了：`/etc/init.d/airconnect running` 返回非 0。
2. **扫描**：**部分通过**。`ubus call airconnect.manager scan` 返回 `{"ok":true,"running":true}`，
   随后 `last_scan` 与 `broadcast.observed_at` 都写入了时间戳——说明 `broadcast.uc` 的 mDNS
   观测在真机上真的工作。但 `devices` 为空：该网段没有 AirConnect 能发现的 UPnP/DLNA 渲染器。
3. **iOS AirPlay 菜单**：**未验证**（没有音箱，无从对照）。
4. **播放一首**：**未验证**（同上）。

### 是否回退

没有触发 `--rollback`。备份目录按约定保留，未删除。

### 与本文件的偏差（实测与文档不符之处）

1. **冲突拦截只发生在 RPC 路径，不在 init 脚本路径。** 旧包尚未卸载时：
   `/etc/init.d/airconnect-manager start` 返回 0 并真的启动了引擎，而
   `ubus call airconnect.manager action '{"action":"start"}'` 返回
   `{"ok":false,"error":"Conflicting AirConnect instance detected"}`；`status.conflicts`
   显示 `Legacy binaries found in /usr/bin.`。本文件第 4 步已按此改写。**现实含义**：跳过卸载
   不会报错，只会得到一个"进程在跑、LuCI 点重启必定失败"的服务。
2. **卸载旧包会把新服务一起停掉。** `apk del` 之后 `init status` 变 `inactive`、procd 实例消失。
   需要重新 `start`（卸载后 `conflicts` 已清空，RPC 的 `start` 恢复返回 `{"ok":true}`）。
3. **`apk del` 删不掉名字里带 `~` 的翻译包。** `apk del luci-i18n-airconnect-zh-cn-26.216.59507~71e1bd6`
   报 `No such package`（`~` 是 apk 的版本运算符）。而 `airconnect` 与 `luci-app-airconnect`
   又被它依赖，单独删会被拒绝（`not removed due to: luci-i18n-airconnect-zh-cn`）。
   可行做法是一次性用通配符删三个：`apk del luci-i18n-airconnect-zh-cn* airconnect luci-app-airconnect`。
4. **`/etc/config/airconnect` 与 `/etc/init.d/airconnect` 卸载后仍留在磁盘上**（apk 保留 conffile）。
   `/etc/rc.d` 里没有旧链接，所以不会开机自启，`status.conflicts` 也不再报它；留着反而方便回退。
5. **`stream_type` 静默丢失**。迁移脚本此前对不认识的键完全沉默，报告读起来像无损迁移。
   现已改为把这类键命名为 `skipped`；本设备的 `broadcast` 因此才第一次可见。该键未接入属于
   [能力审计](AIRCONNECT-CAPABILITIES.zh-CN.md) 记录的既定范围，不是本次新发现的功能缺失。
6. **旧 APK 只存在于 `/tmp`**（重启即失），而 `--rollback` 无法重装已卸载的包。执行前已把三个
   旧 APK 复制到持久位置 `/root/legacy-airconnect-apk/`。本文件第 4 步已补上这一步。
