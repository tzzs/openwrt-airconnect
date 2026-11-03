# OpenWrt AirBridge

<div align="center">

[English Version](README.md) | 中文版本

</div>

---

AirBridge 是直接面向 [philippe44/AirConnect](https://github.com/philippe44/AirConnect) 的独立 OpenWrt/iStoreOS 适配项目。原生引擎负责音频桥接，AirBridge 维护软件包、服务管理、配置转换和 LuCI 界面。

AirBridge 使用独立 Git 历史，不基于 `sbwml/luci-app-airconnect` 的 fork 继续开发；该项目仅作为 OpenWrt 封装方式的参考。

## 命名

产品名是 **AirBridge · 隔空音箱**。内部标识符刻意保留历史上的 `airconnect` 拼写：UCI 配置名仍是 `airconnect-manager`，rpcd 对象仍是 `airconnect.manager`。这样已安装旧包的设备可以原地平滑升级、不丢设置；这些是兼容标识符，不是漏改。

首版目标为 OpenWrt/iStoreOS 25.12、`aarch64_generic`。

- 引擎、管理层和 LuCI 包已实现；四个 APK（含中文翻译包）已用本地 SDK 构建，并在 iStoreOS 25.12.5 / aarch64 设备通过 `apk add` 安装验证。
- 已在参考路由器完成旧服务迁移与切换。新服务运行并设为开机自启；rpcd 方法、扫描和登录态 LuCI 页面渲染已验证。S4 确认中文翻译、三个页面标签及状态展示正常。
- 主机测试与 PR CI 已通过。Release/Pages 的远程发布尚无成功运行记录，仓库 APK 源也尚未签名。
- 尚待验证：真实音箱发现、播放和音量行为；路由器性能；升级后保留配置；迁移回退演练；LuCI 保存、应用和重置。验证时所在网段没有可发现的 UPnP/DLNA 音箱。
- 目前只构建并测试了 `aarch64_generic`；`x86_64` 和 OpenWrt 24.10/IPK 暂未启用。

切换旧安装前请阅读[迁移手册](docs/MIGRATION.zh-CN.md)，发布与剩余验收事项见[发布和安装说明](docs/RELEASE.zh-CN.md)。

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

所有主机测试套件都应通过。

## 文档

- [旧实例迁移手册](docs/MIGRATION.zh-CN.md)：从旧 AirConnect 安装迁移、验证与回退。
- [发布与安装说明](docs/RELEASE.zh-CN.md)：目标平台、发布流程及发布前验收事项。

## 来源与许可

独立编写的封装使用根目录 MIT 许可证。AirConnect 根 LICENSE 声明 MIT，并要求第三方组件遵守各自条件；保留的原文见 `packages/airconnect-engine/files/UPSTREAM-LICENSE`。原生发布包包含的依赖许可及分发义务须在正式发布前完成核对，不以包元数据代替依赖许可审计。

---

<div align="center">

[English Version](README.md) | 中文版本

</div>
