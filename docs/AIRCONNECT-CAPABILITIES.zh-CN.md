# 原生 AirConnect 能力与增强版接入范围

本报告区分原生引擎已有能力、LuCI 需要开发的管理能力，以及不能通过换界面实现的功能。分类为产品建议，并非已完成的功能。

核对基线：AirConnect [`1.12.4`](https://github.com/philippe44/AirConnect/tree/1.12.4)；检索到的上游 HEAD 为 [`613c6b31c88a6b7cd5b2417828e9461353d3eadf`](https://github.com/philippe44/AirConnect/tree/613c6b31c88a6b7cd5b2417828e9461353d3eadf)。本文涉及的两个配置解析器、两个头文件、aircast 主程序及 README 在这两个版本间相同；airupnp 主程序有计时回绕和 `NO_MEDIA_PRESENT` 状态处理修改。当前 HEAD 的版本宏仍为 v1.12.4，不能因此声称这些额外修改已在发布版二进制中。证据：[版本宏](https://github.com/philippe44/AirConnect/blob/613c6b31c88a6b7cd5b2417828e9461353d3eadf/airupnp/src/airupnp.h)、[基线至 HEAD 差异](https://github.com/philippe44/AirConnect/compare/1.12.4...613c6b31c88a6b7cd5b2417828e9461353d3eadf)。

## 首版：应直接接入

| 能力 | 原生支持与边界 | 增强版设计 |
| --- | --- | --- |
| AirPlay 显示名称 | 两个引擎均读取每台设备的 XML `name`，并用它创建 AirPlay 接收端；这是桥接名称覆盖，不是给原厂音箱改名。[UPnP 解析](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L126-L145)、[接收端创建](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L838-L844)、[Cast 解析](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L123-L145) | 分开显示“设备原名称”和可编辑的“AirPlay 名称”；留空表示跟随原名称。保存前显示将广播的名称，不把改名写回设备。 |
| 每台音箱启用/停用 | 两引擎用 `udn` 找到设备配置，复制 common 配置后覆盖设备设置；`enabled` 可控制桥接。[UPnP 设备匹配/覆盖](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L166-L205)、[UPnP 添加设备](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L916-L928)、[Cast 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c) | 按引擎类型及 UDN 保存，不以 IP 为配置主键；离线设备保留设置，明确标为离线。 |
| UPnP 音量上限 | `max_volume` 读入 MaxVolume；独立音箱把 AirPlay 归一化音量乘以 MaxVolume 后发给音箱。Sonos 分组采用相对音量逻辑，不能把单音箱验收结果套给分组。[配置字段](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L126-L141)、[音量处理](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L335-L372) | 单独给 UPnP 音箱提供 1–100 整数上限。默认 100 维持上游行为；用户可选择 30。说明这是 AirPlay 指令映射，不是实体键、语音或原厂 App 的全局硬件限幅。 |
| 发现与设备详情 | `-i` 发现并保存 XML，`-I` 随扫描保存；保存的设备项主要是 UDN、桥接名称、虚拟 MAC、enabled，不是完整设备清单 API。[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L140-L162)、[XML 保存](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L79-L96)、[Cast CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L98-L118) | 增加只读发现快照；原名称、型号、厂商、地址、协议、最后发现时间应来自真实发现结果。缺失字段显示“未提供”，不从型号猜兼容能力。持久配置与扫描快照分开，避免扫描覆盖用户设置。 |
| 服务与发现状态 | 原生有日志等级、日志文件、PID 文件及内部设备/播放状态，但公开 CLI 没有承诺通用 HTTP/JSON 管理 API。[UPnP CLI 与交互实现](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c)、[Cast CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L98-L123) | 通过受限 rpcd 后端读取 procd、发现快照及必要日志。分别展示“服务运行”“发现音箱”“AirPlay 广播已验证”，不要把进程存在等同于手机发现或已播放。 |

设备名称输入必须作为不可信数据处理。两个配置解析器均用 `strcpy(Conf->Name, val)`，两引擎的 `Name` 缓冲区均为 `char Name[STR_LEN]`，且 `STR_LEN=256`。因此生成 XML 前，后端必须检查解码后的名称不超过 **255 个 UTF-8 字节**并拒绝 NUL；前端不能只依赖 `maxlength` 的字符数。证据：[UPnP 名称复制](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L141)、[UPnP 缓冲区](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.h#L30-L65)、[Cast 名称复制](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L135)、[Cast 缓冲区](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.h#L27-L53)。

实施要求：前后端一致按 UTF-8 字节校验；在上述原生缓冲区边界之内，可先采用更保守的 **63 字节产品上限**并单独验证 Bonjour 名称行为，此值是增强版的产品选择，不能描述成上游 `Name` 的缓冲区大小。拒绝控制字符及只有空白的显式名称；正确转义 XML 的 `& < > " '`，以 DOM/textContent 展示设备字符串；不得把名称插入 shell 命令、C 格式字符串 `-N` 或未转义 HTML。空名称与删除覆盖配置应采用明确语义，避免自动保存时丢失原名称。

## 高级设置：原生支持，但应折叠展示

| 能力 | 上游依据 | 接入建议 |
| --- | --- | --- |
| 输出编码与码率 | 两引擎有 `codec`/`-c`，含 FLAC、MP3、AAC、WAV；PCM 是 UPnP 侧选项。FLAC 可带压缩等级/块大小，MP3/AAC 可带码率。[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L140-L154)、[Cast CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L98-L108) | 提供经过校验的选择项和“跟随默认值”，不要要求普通用户填写自由文本。设备支持的格式需实测，不能因为引擎能编码就标为设备支持。 |
| 缓冲与时钟漂移 | 两引擎读取 `latency`、`drift`；CLI 支持 RTP/HTTP 缓冲及强制静音填充。[UPnP 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L136-L141)、[Cast 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L129-L135)、[缓冲说明](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md#latency-parameters-explained) | 用“播放卡顿时调整”的高级面板，明确缓冲通常增加延迟。先保留默认，不提供“消除视频延迟”的开关。 |
| HTTP 传输兼容 | UPnP `http_length`/`-g` 可设省略 Content-Length、chunked 或固定虚拟长度。[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L144-L147)、[配置解析](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L129-L133) | 仅在 UPnP 设备高级配置显示，使用可读枚举；恢复默认操作应明确。 |
| UPnP 搜索版本、型号/名称筛选 | `upnp_max`/`-u` 控制搜索版本；`-m` 排除型号、`-n` 排除名称、`-o` 仅包含型号并覆盖前两项。[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L149-L162) | 首选逐设备启停；筛选放在全局高级设置，解释匹配与覆盖规则。不要把这些 UPnP 参数传给 Cast。 |
| 元数据、封面 | 两引擎解析 `metadata`、`artwork`；对 UPnP，曲目信息是否可见依赖输出编码与音箱接收能力。[UPnP 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L135-L141)、[Cast 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L129-L135)、[上游格式说明](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md) | 把“发送曲目信息”和可选封面 URL 放入高级设置；不承诺每个音箱显示封面。封面 URL 是用户指定的网络资源，不自动上传用户文件。 |
| FLUSH 处理 | 两引擎 `flush`，UPnP CLI 有 `--noflush`；忽略 FLUSH 会改变暂停/切歌行为。[配置解析](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L135-L141)、[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L155-L170)、[上游提示](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md#misc-tips) | 仅作为兼容选项，默认继承上游，提示可能影响暂停体验。 |
| 绑定接口、端口范围、日志 | `-b`、`-a`、`-d`、`-f`；有 `max_players`、`log_limit` 等全局参数。[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L140-L170)、[UPnP 全局解析](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L150-L163)、[Cast 全局解析](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c) | 保留接口选择；日志有大小限制并默认脱敏。端口设置应说明用途，不自动开放公网或修改现有防火墙/DNS。 |

## 后续：需设备验证或额外管理后端

- **Chromecast 音量缩放。** 原生参数为 `media_volume`，范围 0–1；Cast CLI 将 `-v` 描述为分组 MediaVolume 系数。配置被传入 Cast 设备上下文，不能直接复用 UPnP `max_volume=30` 并标成相同的硬件上限。先做设备/分组验证，再决定中文标签与默认值。[Cast 解析](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L126-L135)、[CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L98-L104)、[上下文创建](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L654-L685)。
- **Sonos 与 Chromecast 分组展示。** 原生识别现有组；Sonos 组以主设备桥接、跳过从设备，组音量有专门的相对计算。应先只读展示组关系，不声称可以在增强版中创建任意跨品牌同步组。[Sonos 实现](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L335-L372)、[跳过 Sonos 从设备](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L1035-L1039)、[Cast 分组发现](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L430-L510)。
- **Cast 接收应用停止行为。** 有 `stop_receiver` 配置；需要针对暂停、断连与重新连接验证交互后再公开。[Cast 配置](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c#L126-L135)、[上下文创建](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c#L683)。
- **播放状态、扫描进度与一键诊断。** 引擎有内部播放状态、发现循环与 CLI 输出，但未找到文档承诺的结构化管理 API。增强版需自己设计受限 RPC、日志/快照适配和错误语义；不能把模糊日志匹配包装成准确实时播放状态。[UPnP 主程序](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c)、[Cast 主程序](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/aircast.c)。

## 不承诺的能力

- **视频音画同步或零延迟。** 原生音频桥接的时序模型无法控制 UPnP/HTTP 音箱精确出声时间；调低缓冲不等于修复视频同步。[上游明确限制](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md#latency-parameters-explained)。
- **AirPlay 2、HomeKit 或 Siri 原生配对。** 本次核对的 README、配置和 CLI 没有给出这些能力的支持承诺。产品应使用“AirPlay 音频桥接”，在取得明确实现及设备验收前不标注上述兼容认证。[上游项目定位及接口](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md)、[UPnP CLI](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L140-L170)。这是未发现支持证据后的范围决定，不是对全部依赖源码的穷尽性否定。
- **把不支持 DLNA/UPnP/Chromecast 的音箱变为接收器。** 原生桥接依赖对应设备协议，不包含厂商账号接入。[上游项目定位](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md)。
- **音箱固件改名、Wi-Fi 配网、厂商账号/音乐服务管理。** 本次配置与 CLI 只覆盖桥接侧行为，没有对应的设备管理接口；不要把“AirPlay 名称”写成“音箱系统名称”。[UPnP 配置项](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/config_upnp.c#L126-L163)、[Cast 配置项](https://github.com/philippe44/AirConnect/blob/1.12.4/aircast/src/config_cast.c)。

## 性能接入要求

原生将输入音频解码并按 `codec` 输出，编码选择、FLAC 参数、同时播放的流数会影响持续负载；上游明确提醒 FLAC 的 CPU 成本，并提供 `max_players` 控制容量。[编码及容量说明](https://github.com/philippe44/AirConnect/blob/1.12.4/README.md#config-file-parameters)、[每设备线程与接收端创建](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L838-L844)、[设备线程](https://github.com/philippe44/AirConnect/blob/1.12.4/airupnp/src/airupnp.c#L1041-L1042)。因此不能用单台空闲设备的 CPU 数据保证多流播放性能，也不应通过限制发现数量来暗示已完成并发容量测试。

增强版的界面采用预构建静态资源，继续由 LuCI 提供页面和受限 RPC，不要求路由器常驻 Node.js、Vite 或新的前端 Web 服务。这是我们选择的实现约束，而不是声称上游已经提供这样的增强后端。优先复用已有发现循环；设备动态信息用有界缓存，日志按需读取，隐藏页面暂停轮询，避免每个标签重复启动扫描。完整测量方法见 [性能与资源设计](PERFORMANCE.zh-CN.md)。

## 本轮建议

先实现“设备列表 → 编辑 AirPlay 名称/启停/音量上限 → 保存应用 → 确认广播名称”闭环；首版只承诺有证据可展示的设备信息。编码、缓冲与兼容参数做按协议区分的高级页。原生引擎已有参数不等于 LuCI 已有运行时 API，应在架构和验收中单列发现、状态、日志后端。
