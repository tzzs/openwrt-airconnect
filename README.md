# OpenWrt AirConnect

直接面向 [philippe44/AirConnect](https://github.com/philippe44/AirConnect) 的独立 OpenWrt/iStoreOS 适配项目。原生引擎负责音频桥接，本项目维护软件包、服务管理、配置转换和 LuCI 界面。

本项目使用独立 Git 历史，不基于 `sbwml/luci-app-airconnect` 的 fork 继续开发。该项目仅作为 OpenWrt 封装方式的参考，见 [架构决策](docs/ARCHITECTURE.zh-CN.md)。

## 当前状态

- 已迁入界面、设备管理、原生能力审计和性能需求。
- 三个包的代码都已写入仓库：`airconnect-engine` 是引擎包配方（固定官方 1.12.4 发布包及 SHA256，
  安装到独立的 libexec 路径，不注册服务）；`airconnect-manager` 包含 UCI 校验、原子生成 XML、
  procd 启动脚本和 `airconnect.manager` rpcd 后端；`luci-app-airconnect-manager` 是音箱、设置、
  诊断三个页签的静态 LuCI 页面。
- 目前只有主机验证：`bash scripts/run-tests.sh` 的 11 个套件全部通过（2465 项断言），命令与结果
  记录在 [验证记录](docs/VERIFICATION.zh-CN.md)，说明见 [测试运行与 CI](docs/TESTING.zh-CN.md)。
- CI 工作流（`.github/workflows/test.yml`）已实现，但从未执行过：没有任何一次 CI 运行结果可查。
- 以下事情都还没有发生：没有用 SDK 构建过任何 APK 或 IPK；没有在真实路由器上安装或运行；
  没有接入真实音箱，AirPlay 满音量映射与播放未经验证；LuCI 页面只在 `dev/` 的模拟后端下检查过，
  没有在真实 rpcd/UCI 中加载；旧实例迁移与回退脚本只有主机测试，从未在路由器上执行。
- 本地开发不会替换路由器现有服务。首次切换需要备份、停用旧实例、迁移配置、验证并提供回退。
- 旧实例的检测、配置映射、停用与回退步骤见 [旧实例迁移手册](docs/MIGRATION.zh-CN.md)（未在真实硬件上执行）。

## 三层结构

| 层 | 职责 | 状态 | 未完成 |
| --- | --- | --- | --- |
| `airconnect-engine` | 官方 airupnp/aircast 二进制、版本与来源追踪 | 已实现并有主机测试 | 只有配方静态检查（`tests/engine/check-recipe.sh`）；未经 SDK 构建，95 MB 上游归档未在本环境完整下载 |
| `airconnect-manager` | UCI 校验、原子生成 XML、procd、受限诊断 RPC | 已实现并有主机测试 | 真实 rpcd 注册、procd/netifd 返回形状、真实 SSDP 发现、设备上的 init 脚本行为均未验证 |
| `luci-app-airconnect-manager` | shadcn 风格静态 LuCI 页面，设备和常用设置优先 | 已实现，未经真实设备验证 | 只有 `rules.js` 有主机测试；页面本身只在 `dev/` 的模拟后端下检查过，未在真实 LuCI 与 rpcd/UCI 中加载 |
| `tests/` | 主机测试与静态检查 | 已实现并有主机测试 | 没有在 CI 上跑过：工作流已写好但从未触发 |

状态只按仓库里的文件判定：没有对应代码或没有对应测试的层不写成已实现；构建与设备验收的结果见 [验证记录](docs/VERIFICATION.zh-CN.md)。

首版验证目标：OpenWrt/iStoreOS 25.12、aarch64_generic；随后验证 x86_64。24.10/IPK 单独构建。不能将 SNAPSHOT 的可安装性替代稳定版 SDK 构建与设备验收。

## 开发入口

- [产品定位](PRODUCT.md)
- [实施计划](ROADMAP.zh-CN.md)
- [封装参考与独立架构](docs/ARCHITECTURE.zh-CN.md)
- [UI 与设备信息需求](docs/UI-REQUIREMENTS.zh-CN.md)
- [上游原生能力映射](docs/AIRCONNECT-CAPABILITIES.zh-CN.md)
- [性能约束](docs/PERFORMANCE.zh-CN.md)
- [验证记录](docs/VERIFICATION.zh-CN.md)
- [测试运行与 CI](docs/TESTING.zh-CN.md)
- [旧实例迁移手册](docs/MIGRATION.zh-CN.md)

使用匹配目标版本的 OpenWrt SDK，将 `packages/airconnect-engine` 链接到 SDK 的 `package/` 下，再运行 `make defconfig` 和 `make package/airconnect-engine/compile V=s`。后续 CI 必须固定 SDK 和 Action 版本，并记录实际验证过的架构；目前没有发布构建成功声明。

## 来源与许可

独立编写的封装使用根目录 MIT 许可证。AirConnect 根 LICENSE 声明 MIT，并要求第三方组件遵守各自条件；保留的原文见 `packages/airconnect-engine/files/UPSTREAM-LICENSE`。原生发布包包含的依赖许可及分发义务须在正式发布前完成核对，不以包元数据代替依赖许可审计。
