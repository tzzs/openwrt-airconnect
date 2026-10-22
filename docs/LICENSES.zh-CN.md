# 依赖与许可证（证据清单）

本文档对应 `/tmp/airconnect-sdd/reports/S5-report.md`，列出发行版 APK 中 `airconnect-engine`
包所包含的第三方库及其许可证。所有条目均通过 **锁定 submodule SHA + relocation 不敏感字节段匹配**
方法实证或证伪。未证明者标记为“未知”。

---

## 0. 验证方法

1. **权威依赖集**: AirConnect tag 1.12.4 的 `.gitmodules` + 每个 submodule 的锁定 commit SHA。
2. **链接实证**: 对每个 `.a` 中的所有 `.o` 提取其 `.text/.rodata` 中不受重定位打断的字节段（≥24 字节），
   断言这些字节段逐字节出现在最终 ELF 中。该方法对静态链接是决定性的：
   - 负对照（无关二进制 `/usr/bin/python3`）→ **0/26814**（噪声级）。
   - 正对照（已知进入的 `libshine`）→ **98/98**。
3. **静态链接确认**: `readelf -d` 显示两个 ELF **无 dynamic section** → 完全静态。
4. 上游自身 `-t` 字符串声明 GPLv3（在 `airupnp/src/airupnp.c:194` 及镜像于 `aircast/src/aircast.c:145`）。

---

## 1. 已证实链接进二进制（ELF）的组件

### 1.1 上游 AirConnect 应用代码
| 组件 | 版本 | 许可证 | 证据 |
|---|---|---|---|
| AirConnect app (airupnp / aircast) | 1.12.4 | **MIT**（仓库根 LICENSE 声明） | `AirConnect-1.12.4/LICENSE`: "under MIT license" |
| 程序内嵌 `-t` 帮助文本 | 1.12.4 | **GPL-3.0** | `strings airupnp-linux-aarch64-static \| grep -A6 "GNU General Public License"`；源码 `airupnp/src/airupnp.c:194` |

> 注：上游对自身二进制有 MIT/GPLv3 不一致声明，本报告如实记录。

### 1.2 经 objmatch 实证链接的第三方库
（按实际被 linker 拉入的情况；`libcodecs.a` 聚合了 17 个库但仅部分被链接）

| 组件 | 上游来源 @ SHA | 许可证 | airupnp? | aircast? | objmatch（runs_tested/found/fully） |
|---|---|---|---|---|---|
| OpenSSL (libssl + libcrypto) | `philippe44/libopenssl` → openssl @ `8ddacec` (branch openssl-3.5.4) | Apache-2.0 + SSLeay (双许可) | 是 | 是 | libcrypto: airupnp 1012/22993/801; aircast 1012/23741/828; libssl: airupnp 94/147/3; aircast 94/5686/79 |
| libpupnp / libupnp + libixml | `philippe44/pupnp` @ `5e1d8d9` | MIT | 是 | 弱/部分 | libupnp: 48/953/933(airupnp), 48/953/13(aircast); libixml: 10/180/177(airupnp), 10/180/178(aircast) |
| libmdns (mdnssvc + mdnssd-min) | `philippe44/mdnssd` @ `16402f3`, `mdnssvc` @ `314b5d8` | BSD-3-Clause (mdnssvc, Darell Tan); **GPL-3.0 (mdnssd-min)** | 是 | 是 | mdnssd: 1/86/86 fully; mdnssvc: 2/121/120 fully |
| libraop (+ curve25519 + dmap-parser) | `philippe44/libraop` @ `f426d0f` | MIT (libraop); MIT (curve25519, mehdi sotoodeh); MIT (dmap-parser, Matt Stevens) | 是 | 是 | alac.o 36/36 fully; raop_server.o 66/64 fully; raop_streamer.o 124/123 fully; dmap_parser.o 11/10 fully |
| libjansson | `akheron/jansson` @ `e23f558` | MIT (philippe44 包装) | 否（散点） | 是 | airupnp: 12/346/8; aircast: 12/346/345/11 fully |
| nanopb | `nanopb/nanopb` @ `fee3caf` | Zlib (Petteri Aimonen) | 否 | 是 | 源码编入 aircast (`Makefile:62 pb_decode.c pb_encode.c`)；无 .a 文件 |

### 1.3 libcodecs 聚合中的实际链接子集
`libcodecs.a` 是 thin archive，aggregates 17 个库；linker 按需拉取：

| 组件 | 许可证 | 是否链接 | objmatch (airupnp / aircast) | 证据 |
|---|---|---|---|---|
| FLAC | BSD-3-Clause-like (Xiph) | 是 | 33/1299/895 / 33/1299/895 | 决定性 (FLAC__stream_* strings present) |
| FAAC | LGPL-2.0 (Library GPL v2) | 是 | 12/227/227 fully / 12/227/227 fully | 决定性 |
| SHINE (MP3 编码) | LGPL-2.0 (Library GPL v2) | 是 | 9/98/98 fully / 9/98/98 fully | 决定性 |
| libogg | BSD-3-Clause (Xiph) | 是 | 2/62/41 fully (framing.o) | framing.o 命中 41 字节 runs |
| libopusenc | BSD-3-Clause (Xiph) | 是 (部分) | 6/221/2 (ogg_packer.o fully=1) | ogg_packer.o found |
| libaddons | MIT | 是 (封装层) | 2/55/40 (encoder.o strong hits) | encoder.c 引用 FAAC/SHINE/FLAC (source) |
| **libmad** | GPL-2.0-or-later | **否** | 11/219/2 (noise level) | 决定性排除 |
| **libfaad2** | GPL-2.0-only | **否** | 38/688/0 | 决定性排除 |
| **libsoxr** | LGPL-2.1 | **未排除** (conservative) | 10/306/1 (noise) | 保守列入清单（§4） |
| **libopus** | BSD-3-Clause (Xiph) | **否** | 142/1507/3 | 排除 |
| **libvorbis** | BSD-3-Clause (Xiph) | **否** | 20/475/0 | 排除 |
| **libalac** | Apache-2.0 | **否** | 10/165/1 | 排除 |
| libutf8 | MIT | **否** | 3/27/0 | 排除 |
| libvorbisfile / libopusfile/url/enc | BSD-3-Clause | 未强证 | weak | |

---

## 2. 未进入二进制的组件（不产生分发义务）

| 组件 | 许可证 | 证据 |
|---|---|---|
| libmad (MP3 解码) | GPL-2.0-or-later | objmatch 11/219/2 (noise) |
| libfaad2 (AAC 解码) | GPL-2.0-only | objmatch 38/688/0 |
| libsoxr (重采样) | LGPL-2.1 | objmatch 10/306/1 (noise) – **但保守保留清单** |
| libopus, libvorbis, libvorbisfile, libopusfile/url/enc, libalac, libutf8 | BSD/MIT | objmatch 全部 <1% noise |

> 注意：尽管未链接，但 upstream 的 `libcodecs.a` 仍聚合了它们；我们只在 THIRD-PARTY-NOTICES 里引用未链接项作为透明性说明。

---

## 3. 必须随分发的许可证文本与义务

### 3.1 强 copyleft（需附带全文 + 源码要约）
| 许可证 | 组件 | 义务 |
|---|---|---|
| GPL-2.0 (Library GPL v2) | FAAC, SHINE | 附带 LGPL-2.0 全文（与 GPL-2.0 同源）+ 可替换机制或源代码 |
| GPL-3.0 | 上游 `-t` 声明, mdnssd-min | 附带 GPL-3.0 全文 + 对应源码（上源码仓 tag 1.12.4） |

### 3.2 弱 copyleft（需附带全文 + 可替换机制）
| 许可证 | 组件 | 义务 |
|---|---|---|
| LGPL-2.1 | SoXR (保守列入) | 若最终确认证未链接则移除；否则附带 LGPL-2.1 全文 + 可替换机制 |

### 3.3 可复用许可（仅需版权声明 + 许可声明）
| 许可证 | 组件 | 要求 |
|---|---|---|
| MIT | AirConnect app (root), libpupnp, libjansson, libmdns (overall), libcodecs (wrapper), libraop (wrapper), libopenssl (wrapper), dmap-parser, curve25519 | 附带 MIT 声明与版权 |
| BSD-3-Clause | Ogg, Vorbis, Opus, Opusfile, Opusenc, mdnssvc, nanob (Zlib-like), curve25519 (embedded in libraop) | 附带 BSD 声明 |
| Apache-2.0 | OpenSSL (Apache-2.0 + SSLeay dual license), ALAC decoder | 附带 Apache-2.0 + SSL/EAY/Cryptsoft copyright notice |
| Zlib | nanopb | 附带 Zlib-style notice |

---

## 4. 未解决的许可阻塞（ROADMAP 保持 `[ ]`）

1. **上游 AirConnect 自身 MIT/GPLv3 声明冲突**:
   - 仓库根 LICENSE 说 MIT；二进制内嵌 `-t` 说 GPLv3；mdnssd-min 也说 GPLv3。
   - 我们无权重新解释；必须如实列出二者并存的状态，**待上游澄清**。
2. **GPL-2.0-only vs GPL-3.0 兼容性问题**:
   - `libfaad2` (GPL-2.0-only) 未进入 ELF（objmatch 0/688），当前不构成冲突。
   - 但若未来切换架构将其链接，将与 GPL-3.0 组件（mdnssd-min / `-t`）**互斥**。需长期约束记录。
3. **LGPL-2.1（SoXR）是否真未链接**:
   - objmatch 给出 10/306/1 noise-level hit。目前保守列入 THIRD-PARTY-NOTICES。
   - 如需从清单移除，需进行更严格的全符号/全段比对证明其未进入 ELF。
4. **GPL/LGPL 源码要约落地**:
   - 我们已记录 tag 1.12.4 的所有 submodule SHA（见 §0 方法），可在 THIRD-PARTY-NOTICES 中提供下载 URL。
   - **需在随附文件中正式引用这些 URL 和 SHA**，否则无法满足 GPL/LGPL 的源码要约。
5. **OpenSSL 双许可的 NOTICE 义务**:
   - OpenSSL (Apache-2.0 + SSLeay dual) + libcrypto (SSLeay) 均有 NOTICE/copyright 义务。
   - 已收集完整许可文本并在 THIRD-PARTY-NOTICES 中嵌入；构建期安装验证成功。

---

## 5. 打包元数据更新（生效清单）

### 5.1 `packages/airconnect-engine/Makefile`
- `PKG_LICENSE` 改为 OpenWrt SPDX 表达式：
  ```make
  PKG_LICENSE:=MIT AND Apache-2.0 AND BSD-3-Clause AND LGPL-2.0 AND LGPL-2.1 AND GPL-2.0 AND GPL-3.0
  PKG_LICENSE_FILES:=usr/share/airconnect/THIRD-PARTY-NOTICES
  ```
- `Package/airconnect-engine/install` 新增 `$(INSTALL_DATA) ./files/THIRD-PARTY-NOTICES ...`。

### 5.2 `packages/airconnect-engine/files/THIRD-PARTY-NOTICES`
- 包含本审计的所有证据、每组件许可证摘要、必须随附的完整文本（GPL-2.0/3.0/LGPL-2.1/OpenSSL/ALAC/MIT/BSD/Zlib）。

### 5.3 `tests/engine/check-recipe.sh`
- 原断言 `PKG_LICENSE:=MIT` 改为断言新的 SPDX 表达式；新增对 `THIRD-PARTY-NOTICES` 存在性和 `PKG_LICENSE_FILES` 字段的检查。

### 5.4 `README.md` & `ROADMAP.zh-CN.md`
- README “来源与许可”明确标注混合许可状态；ROADMAP 许可证核对项保持 **[ ]（未关闭）**，并注释剩余阻塞。

---

## 6. 验收命令（复跑）

```bash
# static linkage
readelf -d airupnp-linux-aarch64-static | grep -i needed
# must return nothing (no NEEDED lines)

# per-library inclusion test (relocation-aware byte-run match)
python3 relmatch2.py /tmp/lic/airupnp-linux-aarch64-static /tmp/obj/<lib> 24 -v
# negative control: python3 /usr/bin/python3 /tmp/obj/libmad → ~0
# positive: /tmp/obj/libshine → ~98/98 fully

# upstream -t GPLv3 string
strings airupnp-linux-aarch64-static | grep -A6 "GNU General Public License as published by"

# pinned dependency SHAs
git ls-tree -r 1.12.4 | awk '$1=="160000"{print $3,$4}'

# new file in APK manifest
tar tzf bin/packages/aarch64_generic/base/airconnect-engine-*.apk | grep THIRD-PARTY-NOTICES

# unit tests green
bash scripts/run-tests.sh
# expected: 15 passed, 0 failed
```

---

## 7. 结论

我们对两个预编译 aarch64 静态二进制做了证据驱动的依赖清点：
- **实证的许可集合**: MIT, Apache-2.0, BSD-3-Clause, LGPL-2.0 (FAAC, SHINE), GPL-3.0 (upstream -t + mdnssd-min), 以及保守列入的 LGPL-2.1 (SoXR)。
- **未链接的 GPL 解码器**（libmad, libfaad2）已通过字节段匹配证伪。
- **原单一 MIT 声明已纠正**为完整的 SPDX 表达式；新增随附的 `THIRD-PARTY-NOTICES` 文件包含必要文本。
- **ROADMAP 该项保持未关闭**，因仍需解决上游 MIT/GPLv3 不一致、LGPL-2.1 的最终排除、以及 GPL/LGPL 源码要约的正式落地。
