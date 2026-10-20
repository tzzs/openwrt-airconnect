# OpenWrt AirConnect

直接面向 [philippe44/AirConnect](https://github.com/philippe44/AirConnect) 的独立 OpenWrt/iStoreOS 适配项目。原生引擎负责音频桥接，本项目维护软件包、服务管理、配置转换和 LuCI 界面。

本项目使用独立 Git 历史，不基于 `sbwml/luci-app-airconnect` 的 fork 继续开发。该项目仅作为 OpenWrt 封装方式的参考，见 [架构决策](docs/ARCHITECTURE.zh-CN.md)。

## 当前状态

- 已迁入界面、设备管理、原生能力审计和性能需求。
- 已添加独立 `airconnect-engine` 包配方：固定官方 1.12.4 发布包及 SHA256，安装到独立的 libexec 路径，不注册服务。
- 管理适配层（UCI 校验、原子 XML、procd、`airconnect.manager` rpcd 后端）已在主机测试下完成；
  新版 LuCI、SDK 构建和真实设备验收尚未完成，不是可部署的增强版发行包。
- 本地开发不会替换路由器现有服务。首次切换需要备份、停用旧实例、迁移配置、验证并提供回退。

## 三层结构

| 层 | 职责 | 状态 |
| --- | --- | --- |
| `airconnect-engine` | 官方 airupnp/aircast 二进制、版本与来源追踪 | 包配方已编写，待 SDK 构建 |
| `airconnect-manager` | UCI 校验、原子生成 XML、procd、受限诊断 RPC | 适配层与 `airconnect.manager` rpcd 后端已实现，待 SDK 构建与设备验证 |
| `luci-app-airconnect-manager` | shadcn 风格静态 LuCI 页面，设备和常用设置优先 | 需求已确定，待实现 |

首版验证目标：OpenWrt/iStoreOS 25.12、aarch64_generic；随后验证 x86_64。24.10/IPK 单独构建。不能将 SNAPSHOT 的可安装性替代稳定版 SDK 构建与设备验收。

## 开发入口

- [产品定位](PRODUCT.md)
- [实施计划](ROADMAP.zh-CN.md)
- [封装参考与独立架构](docs/ARCHITECTURE.zh-CN.md)
- [UI 与设备信息需求](docs/UI-REQUIREMENTS.zh-CN.md)
- [上游原生能力映射](docs/AIRCONNECT-CAPABILITIES.zh-CN.md)
- [性能约束](docs/PERFORMANCE.zh-CN.md)

使用匹配目标版本的 OpenWrt SDK，将 `packages/airconnect-engine` 链接到 SDK 的 `package/` 下，再运行 `make defconfig` 和 `make package/airconnect-engine/compile V=s`。后续 CI 必须固定 SDK 和 Action 版本，并记录实际验证过的架构；目前没有发布构建成功声明。

## 来源与许可

独立编写的封装使用根目录 MIT 许可证。AirConnect 根 LICENSE 声明 MIT，并要求第三方组件遵守各自条件；保留的原文见 `packages/airconnect-engine/files/UPSTREAM-LICENSE`。原生发布包包含的依赖许可及分发义务须在正式发布前完成核对，不以包元数据代替依赖许可审计。
