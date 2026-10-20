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
