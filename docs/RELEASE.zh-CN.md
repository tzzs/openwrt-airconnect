# 发布流程

本文件说明 openwrt-airconnect 如何出包、如何发版，以及哪些环节是自动的、哪些仍然需要人工确认。

---

## 概览

```
main 分支
   │
   │  符合 Conventional Commits 的提交
   ▼
release-please  ──打开/更新──▶  "chore: release x.y.z" PR
   │                                  │
   │                                  │  人工合并
   ▼                                  ▼
（什么都不做）                     创建 tag vX.Y.Z
                                         │
                                         ▼
                                  build 工作流
                                  ├─ 下载固定版本 OpenWrt SDK
                                  ├─ 编译四个 APK（含中文翻译包）
                                  ├─ 校验 APK 内容并生成 packages.adb
                                  ├─ 上传到 GitHub Release
                                  └─ 发布到 GitHub Pages APK 仓库
```

---

## 1. 提交规范决定版本号

release-please 只读提交信息，不看代码。所以版本号完全由 Conventional Commits 决定：

| 提交类型 | 版本变化 | 例 |
| --- | --- | --- |
| `feat:` | 次版本 +1 | `feat(manager): 支持按设备覆盖 codec` |
| `fix:` | 修订号 +1 | `fix(migration): 读取真实的 section 名` |
| `perf:` | 修订号 +1 | `perf(luci): 状态刷新不再重排表单` |
| `feat!:` 或 `BREAKING CHANGE:` | 主版本 +1 | `feat(luci)!: 重命名菜单项` |
| `docs:` `test:` `ci:` `chore:` `refactor:` | **不变** | `docs: 补充许可证说明` |

`docs`/`test`/`ci` 等不会触发发版，但仍会出现在 PR 的 changelog 里（默认隐藏，可在 `release-please-config.json` 的 `changelog-sections` 打开）。

scope 只是给人看的，不影响版本号。当前使用的 scope：`manager`、`luci`、`dev`、`docs`、`engine`、`ci`、`test`。

---

## 2. 版本号写在哪里

三处，由 release-please 的 release PR 一次性更新：

| 文件 | 字段 |
| --- | --- |
| `package.json` | `version` |
| `packages/airconnect-manager/Makefile` | `PKG_VERSION` |
| `packages/luci-app-airconnect-manager/Makefile` | `PKG_VERSION` |

`.release-please-manifest.json` 记录"上次发到哪一版"，release-please 靠它算下一个版本号，**不要手改**。

`airconnect-engine` 的 `PKG_VERSION` **不**跟随仓库版本：它固定是上游 AirConnect 的版本（当前 `1.12.4`），只有上游出新版时才改。它的 `PKG_RELEASE` 在重新打包同一上游版本时 +1。

---

## 3. 构建目标

### 当前构建

| 目标 | SDK | 状态 |
| --- | --- | --- |
| `armsr-armv8` / `aarch64_generic` | 25.12.6, gcc 14.3.0, musl | 启用 |

已确认的参考设备：**EasePi R1**（RK3588 / ARMv8 / 4 GB / 5 网口），iStoreOS 25.12.5。
它属于 armsr-armv8 目标，是本仓库目前唯一做过真机验证的架构。

### 尚未启用

| 目标 | 原因 |
| --- | --- |
| `x86-64` / `x86_64_generic` | 没有任何 x86_64 设备可以验证。当前唯一的参考设备是 RK3588 ARM 开发板，`release.yml` 里对应 matrix 项保持注释，直到有一台 x86_64 设备跑通为止 |
| OpenWrt 24.10 的 IPK | 24.10 用 IPK 而不是 APK，包格式和依赖解析都不同，需要单独一条构建链 |

> **不要把 SNAPSHOT 等同于稳定版。** 上游 AirConnect 的 CI 只构建 `openwrt-24.10` 和 `SNAPSHOT`，但这两者都不等于 25.12 的 SDK。发版必须用与目标版本号匹配的 SDK。

---

## 4. 发布前必须人工确认的事

CI 能保证"包能编译、内容完整"，不能保证"包在设备上是对的"。每次发版前需要确认：

- [ ] 四个 APK（engine、manager、LuCI、中文翻译）已在一台真实的 armsr/armv8 设备上安装并启动成功
- [ ] `/etc/init.d/airconnect-manager start|stop|reload` 行为正确
- [ ] `ubus call airconnect.manager.status` 返回预期结构
- [ ] 升级一个已安装的旧版本后，`/etc/config/airconnect-manager` 保留
- [ ] `scripts/migrate-legacy.sh --apply` 在真实旧配置上演练过，且回滚可用
- [ ] `docs/VERIFICATION.zh-CN.md` 的"仍未验证"一节与当前认知一致

---

## 5. 在路由器上直接安装验证（不是构建）

发布包**只能**来自 CI 的 SDK 构建。路由器上不构建 APK，原因见下。CI 还会把同一批四个 APK
和 `packages.adb` 发布到 GitHub Pages，作为可供 OpenWrt 25.12 `apk` 解析依赖的静态仓库；GitHub Release
仍然保留单文件下载和版本归档。当前 Pages 仓库是未签名测试仓库，使用前必须明确允许不受信任的索引和包。

### 为什么不在路由器上手工组装 APK

这三个包确实都不编译代码——`airconnect-engine` 只解包上游静态二进制并校验，另两个只安装文件。所以曾经尝试过在路由器上按 `.PKGINFO` + `data.tar.gz` 的结构直接拼 APK。

**实测结论：行不通。** apk-tools 3.x 的 APK v3 容器以一个 `ADBd` 签名块开头，其长度字段既不是大端也不是小端的 32 位整数（在真实包上读出 3,973,805,168 这种值），且整个包里**找不到任何 gzip 魔数**——说明 data 段用的不是 gzip。手工拼出来的文件 `apk add` 一律报 `file format is invalid or inconsistent`。

这不是值得继续投入的方向：收益只是省掉一次 CI 运行，而代价是要逆向一个没有公开规范的容器格式。脚本已从仓库删除，不做保留。

### 路由器上真正该做的事

路由器（iStoreOS 25.12.5 / aarch64_generic）的价值在于**运行**验证，不是构建。把 CI 产出的 APK 拷上去安装：

```sh
# CI 产物下载到本地后推上路由器
scp airconnect-engine-*.apk airconnect-manager-*.apk \
    luci-app-airconnect-manager-*.apk luci-i18n-airconnect-manager-zh-cn-*.apk router:/tmp/

# 安装（本地构建的未签名包）
ssh router 'apk add --allow-untrusted /tmp/airconnect-engine-*.apk \
                                      /tmp/airconnect-manager-*.apk \
                                      /tmp/luci-app-airconnect-manager-*.apk \
                                      /tmp/luci-i18n-airconnect-manager-zh-cn-*.apk'

# 然后真正跑起来
ssh router '/etc/init.d/airconnect-manager start'
ssh router 'ubus call airconnect.manager.status "{}"'
ssh router 'logread -f'
```

这一步已经做过**部分**验证：把 `packages/airconnect-manager/files/` 按安装后的目录布局放到路由器上，`ubus call airconnect.manager.status` 返回了正确结构，五个 rpcd 方法全部注册成功。证据见 `docs/VERIFICATION.zh-CN.md` 的"真实设备验证"一节。**尚未做**的是通过 `apk add` 完整安装，因此 conffiles 处理、升级保留、`apk del` 卸载都还没验证。

### 先在 x86_64 主机上本地编译

发布产物由 CI 生成，但在第一次触发 CI 之前，先在本地把同样的步骤跑通会更省时间——CI 上一次失败要几分钟才知道，本地可以马上看到错误。

`scripts/build-local.sh` 与 `release.yml` 的 `build` job 做**完全相同**的步骤、相同顺序：

```bash
# 任何 x86_64 Linux 主机都可以，包括 Windows 上的 WSL2 Ubuntu
sudo apt install zstd apk-tools        # Debian/Ubuntu 的依赖

bash scripts/build-local.sh
```

它做的事，以及为什么每件都不能省：

| 步骤 | 为什么 |
| --- | --- |
| 固定 SDK 版本 `25.12.6 / gcc 14.3.0 / musl` | 用错版本会在几分钟后以难以理解的错误失败 |
| 安装 packages + luci 两个 feed | 三个包依赖 ucode、rpcd、curl、luci-base |
| `CONFIG_LIBCURL_OPENSSL=y` | 不选 TLS 后端，curl 的 configure 会以 "TLS not detected" 失败，而那不是 manager 的问题 |
| 按 `PKG_HASH` 校验 95 MB 归档 | 那两个静态二进制是 `airconnect-engine` 的全部载荷 |
| 四个包分别 `make compile` | 失败时能指名是哪个包，而不是停在某个匿名目标上；中文包由 `luci.mk` 根据 `po/zh_Hans` 动态生成 |
| 用 `apk manifest` 回读产物 | 空的 `bin/packages` 或缺少中文翻译包会被当成成功发布 |

产物在 `packages/output/`，可以直接 `scp` 到路由器上装。

**Windows 用户**：装 WSL2 + Ubuntu 22.04，然后在 WSL 里运行上面的命令即可，不需要额外配置。x86_64 原生编译，没有虚拟化开销。

---

## 6. 发一个版本的完整步骤

1. 确认 `main` 上的提交都符合 Conventional Commits
2. 确认 `.github/workflows/test.yml` 在最近的 main 上是绿的
3. 等 release-please 自动开出 `chore: release x.y.z` PR
4. 检查 PR 里的版本号和 changelog 是否符合预期
5. **批准该 PR 的 workflow 运行**。release-please 用 `GITHUB_TOKEN` 创建 PR，GitHub 不会自动为它
   触发 workflow，PR 上会显示 `action_required`。在 PR 的 Checks 区域点 "Approve and run workflows"
   （或 Actions 运行页的 "Review deployments"）后，`test.yml` 才会真正跑起来。这是平台对
   `GITHUB_TOKEN` 的防递归限制，不能用仓库设置关掉，也不要为此换成权限更大的 PAT
6. 确认该 PR 上的 Host tests 通过
7. **合并该 PR** —— 这一步同时创建 tag 和 GitHub Release
8. `build` 工作流自动跑完，APK 附到 Release 上
9. 在仓库 Settings → Pages 中把 Source 设为 **GitHub Actions**（首次启用时需要人工设置）
10. 下载四个 APK，在一台真实设备上 `apk add --allow-untrusted` 安装并验证；或配置 Pages 仓库后用入口包测试依赖解析
11. 验证通过后，该 Release 才标记为正式可用

---

## 7. 出问题时

| 情况 | 处理 |
| --- | --- |
| 版本号算错了 | 不要手改 manifest。回退那个提交，重新用正确的类型提交 |
| release PR 的 changelog 漏了东西 | 检查提交信息是否符合规范，不是 release-please 的问题 |
| `build` 工作流失败 | 看具体哪一步。SDK 下载失败换重试；编译失败把 `V=s` 的输出贴出来 |
| 发布的包有问题 | 发一个 `fix:` 提交走新版本，**不要删 tag** |
| 需要在没有新提交的情况下手动重跑发布工作流 | `workflow_dispatch`；它仍要求 `release-please` 在本次运行中报告 `release_created`，否则不会进入构建与上传 |

---

## 8. GitHub Pages APK 仓库

Pages 发布的目录固定为（OpenWrt 25.12 / apk-tools 3 使用 ADB v3 索引）：

```text
aarch64_generic/base/
├── packages.adb
├── airconnect-engine-*.apk
├── airconnect-manager-*.apk
├── luci-app-airconnect-manager-*.apk
└── luci-i18n-airconnect-manager-zh-cn-*.apk
```

启用 Pages 后，设备可以使用：

```sh
cat >> /etc/apk/repositories <<'EOF'
https://tzzs.github.io/openwrt-airconnect/aarch64_generic/base
EOF
apk --allow-untrusted update
apk add --allow-untrusted luci-app-airconnect-manager
apk add --allow-untrusted luci-i18n-airconnect-manager-zh-cn
```

`luci-app-airconnect-manager` 会通过包依赖自动拉取 `airconnect-manager`、
`airconnect-engine` 和 `luci-base`；中文包是 LuCI 按语言生成的独立资源包，不能让主包反向依赖它，
否则会形成循环依赖。正式发布前仍应配置 APK 签名密钥，将公钥安装到设备 `/etc/apk/keys/`，并让 workflow
签名 `packages.adb` 与 APK；完成后才能去掉 `--allow-untrusted`。在此之前，不要把 Pages URL
当作生产环境的可信软件源。

## 9. 密钥与权限

`release.yml` 使用内置的 `secrets.GITHUB_TOKEN`，并申请 `contents: write`（上传 GitHub Release）、
`pull-requests: write`（release-please 创建发布 PR）、`pages: write` 和 `id-token: write`（部署 Pages）。没有自定义 secret。仓库 Settings → Pages 的
Source 必须设为 **GitHub Actions**；这是仓库设置，workflow 不能替用户自动修改。
