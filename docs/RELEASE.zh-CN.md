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
                                  ├─ 编译三个包
                                  ├─ 校验 APK 内容
                                  └─ 上传到 GitHub Release
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

### 尚未启用

| 目标 | 原因 |
| --- | --- |
| `x86-64` / `x86_64_generic` | 没有在真实 x86_64 设备上验证过。`release.yml` 里已注释掉对应 matrix 项，启用前需先在设备上跑通 |
| OpenWrt 24.10 的 IPK | 24.10 用 IPK 而不是 APK，包格式和依赖解析都不同，需要单独一条构建链 |

> **不要把 SNAPSHOT 等同于稳定版。** 上游 AirConnect 的 CI 只构建 `openwrt-24.10` 和 `SNAPSHOT`，但这两者都不等于 25.12 的 SDK。发版必须用与目标版本号匹配的 SDK。

---

## 4. 发布前必须人工确认的事

CI 能保证"包能编译、内容完整"，不能保证"包在设备上是对的"。每次发版前需要确认：

- [ ] 三个包已在一台真实的 armsr/armv8 设备上安装并启动成功
- [ ] `/etc/init.d/airconnect-manager start|stop|reload` 行为正确
- [ ] `ubus call airconnect.manager.status` 返回预期结构
- [ ] 升级一个已安装的旧版本后，`/etc/config/airconnect-manager` 保留
- [ ] `scripts/migrate-legacy.sh --apply` 在真实旧配置上演练过，且回滚可用
- [ ] `docs/VERIFICATION.zh-CN.md` 的"仍未验证"一节与当前认知一致

---

## 5. 路由器上的本地构建（不是发布包）

`scripts/build-apk.sh` 在**路由器本机**直接组装 APK，用于本地安装验证，**不用于发布**。

为什么需要它：这三个包都不编译代码——`airconnect-engine` 只是解包上游静态二进制并校验，另两个只装文件。所以在目标架构的机器上手工组装 APK 是可行的，而且能立刻 `apk add` 安装，把 init 脚本、rpcd 插件、conffiles 真正跑起来。

为什么不能用于发布：手工 APK 没有 SDK 生成的包索引、签名和元数据，只能 `apk add --allow-untrusted` 安装，无法作为仓库源分发。

```sh
# 把仓库拷上路由器
COPYFILE_DISABLE=1 tar czf /tmp/ac.tgz -C <repo> packages scripts
scp /tmp/ac.tgz router:/tmp/
ssh router 'tar xzf /tmp/ac.tgz -C /tmp && mkdir -p /tmp/airconnect-src && \
            tar xzf /tmp/ac.tgz -C /tmp/airconnect-src'

# 暂存上游二进制（从 SDK 构建产物或手动拷贝）
ssh router 'mkdir -p /tmp/airconnect-src/engine-binaries && \
            cp airupnp-linux-aarch64-static aircast-linux-aarch64-static /tmp/airconnect-src/engine-binaries/'

# 构建并安装
ssh router 'sh /tmp/airconnect-src/scripts/build-apk.sh --install'
```

产物在路由器的 `/tmp/airconnect-apk/`。

---

## 6. 发一个版本的完整步骤

1. 确认 `main` 上的提交都符合 Conventional Commits
2. 确认 `.github/workflows/test.yml` 在最近的 main 上是绿的
3. 等 release-please 自动开出 `chore: release x.y.z` PR
4. 检查 PR 里的版本号和 changelog 是否符合预期
5. **合并该 PR** —— 这一步同时创建 tag 和 GitHub Release
6. `build` 工作流自动跑完，APK 附到 Release 上
7. 下载 APK，在一台真实设备上 `apk add --allow-untrusted` 安装并验证
8. 验证通过后，该 Release 才标记为正式可用

---

## 7. 出问题时

| 情况 | 处理 |
| --- | --- |
| 版本号算错了 | 不要手改 manifest。回退那个提交，重新用正确的类型提交 |
| release PR 的 changelog 漏了东西 | 检查提交信息是否符合规范，不是 release-please 的问题 |
| `build` 工作流失败 | 看具体哪一步。SDK 下载失败换重试；编译失败把 `V=s` 的输出贴出来 |
| 发布的包有问题 | 发一个 `fix:` 提交走新版本，**不要删 tag** |
| 需要在没有提交的情况下手动触发构建 | `workflow_dispatch`，但它只在 tag 存在时才会上传产物 |

---

## 8. 密钥与权限

`release.yml` 只申请了 `contents: read`，上传产物时用内置的 `secrets.GITHUB_TOKEN`。没有自定义 secret，所以 fork 出来的仓库也能直接跑，不需要额外配置。
