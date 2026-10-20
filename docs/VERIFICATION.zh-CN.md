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

未部署新服务，路由器继续使用之前已安装的版本。独立管理层、新界面及稳定版 APK 发布仍待实现与验收。

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
