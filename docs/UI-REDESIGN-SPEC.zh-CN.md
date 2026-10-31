# AirConnect LuCI 界面改造规格

本文件是这次改造的唯一事实来源。subagent 按此实现，不自行增加范围。

## 一、必须解决的问题

### 1. 横向溢出（已量化）

Argon 主题的 `#maincontent > .container` 使用 `margin: 0 1.25rem 1rem` 且 `width: 100%`。
父级 `#maincontent` 宽 1240px，`.container` 因 `width:100%` 加左右各 20px 外边距，实际占据
208→1468，而视口右边界只有 1448，因此**向右溢出 20px**。

实测：`document.documentElement.scrollWidth` = 1458 > `clientWidth` = 1240。

**修法（当前实现）**：在页面作用域内覆盖 Argon 的直接容器，避免 `width: 100%`
与宿主左右外边距叠加；`.ac-root` 本身再使用 `width: auto`、`max-width: 100%` 和
`box-sizing: border-box`，所有 grid/flex 子项设置 `min-width: 0`：

```css
#maincontent > .container {
    box-sizing: border-box;
    max-width: 100%;
    width: auto;
}

.ac-root {
    box-sizing: border-box;
    max-width: 1400px;
    min-width: 0;
    width: auto;
}
```

这样修复的是溢出的来源，而不是用额外右边距抵消结果。

**验收**：任意窗口宽度下 `document.documentElement.scrollWidth === document.documentElement.clientWidth`。

### 2. 纵向超高

旧版 `.ac-root` 和三栏工作区使用了与视口无关的硬编码最小高度，导致页面被无意义地
撑高。当前实现移除这些固定高度，主工作区由内容自然撑开，服务抽屉内部单独纵向滚动。

**修法**：
- 主页面不设置固定最小高度，允许中央内容在低高度窗口中自然增高；
- 设备栏在窄屏收起，展开后的列表只在自身内容区滚动；
- 页面允许正常纵向滚动，但不得出现横向滚动。

### 3. 语言混杂

设备上的 `airconnect-manager.zh-cn.lmo` 仍是旧版本，页面 210 条新文案没有对应翻译，
于是中英混排。

**修法**：
- 重新生成 `po/templates/airconnect-manager.pot` 与 `po/zh_Hans/airconnect-manager.po`，
  覆盖 `frontend/src/**` 中全部 `_()` 字符串。
- `po/zh_Hans/airconnect-manager.po` 必须为**每一条** msgid 提供简体中文 msgstr，
  不允许空 msgstr（`tests/i18n/check.sh` 已断言这一点）。
- 术语对照（保持与既有译文一致）：
  - Save → 保存；Save and apply → 保存并应用；Reset → 重置
  - Global settings → 全局设置；Speakers → 音箱；Scan for speakers → 扫描音箱
  - Service running → 服务运行中；Service stopped → 服务已停止
  - Working directory → 工作目录；Devices → 设备；Settings → 设置
  - Log level → 日志级别；Max volume → 最大音量；Interface → 接口
  - Enable → 启用；Disabled → 已禁用；Enabled → 已启用；Unknown → 未知
- 保留英文专有名词不翻译：UPnP / DLNA、Chromecast、AirPlay、AirConnect、FLAC、HTTP。
- 重新生成 `.lmo` 需要在设备上执行：
  `msgfmt -o /usr/lib/lua/luci/i18n/airconnect-manager.zh-cn.lmo po/zh_Hans/airconnect-manager.po`

### 4. 语言切换（新增功能）

页面需要能在中文/英文之间切换，不能依赖 LuCI 全局语言。

**实现约束**：
- 语言状态存于 `localStorage`，键名 `airconnect.lang`，取值 `zh` / `en`。
- 默认值：检测 `navigator.language`，以 `zh` 开头则 `zh`，否则 `en`。
- 翻译表必须**内置在 bundle 内**（`frontend/src/lib/i18n.js`），不依赖 LuCI 的 `_()`。
  这样切换是即时的、纯前端的。
- 但**已有 LuCI 翻译必须继续可用**：当 LuCI 传入的 `_()` 返回的字符串与英文原文
  相同（说明 LuCI 侧没有该翻译），页面应回退到内置英文表，而不是显示英文与中文混杂。
- 实现方式：
  - 内置表 `MESSAGES = { zh: { 'Save': '保存', ... }, en: {} }`。
  - 页面统一通过 `t(text)` 取文案：先查内置表（当前语言），未命中则调用 LuCI 的 `_()`。
  - 现有 `createRules(t)` / `createFields(t)` / `createPresentation(t)` 的 `t` 参数
    改为这个统一的 `t`，保持调用点不变。
- 语言切换控件放在顶栏，是一个 `Select`（或两个分段按钮），切换后立即重渲染。
  切换后需要把当前语言写入 `document.documentElement.lang`。

### 5. 主题切换（新增功能）

- 主题状态存于 `localStorage`，键名 `airconnect.theme`，取值 `light` / `dark` / `system`。
- `system` 跟随 `prefers-color-scheme`。
- 主题通过 `.ac-root` 上的 class 生效：`light` / `dark` / 无（system 时跟随媒体查询）。
- 现有的 `.ac-root.dark { ... }` token 覆盖块已经存在，保留并扩展 `system` 的处理：
  ```css
  @media (prefers-color-scheme: dark) {
      .ac-root:not(.ac-theme-light) { <dark tokens> }
  }
  .ac-root.ac-theme-dark { <dark tokens> }
  ```
  实现时把 dark token 抽成一个可复用的声明块，避免三处重复。
- 主题切换控件放在顶栏，与语言切换控件并排。

### 6. 按钮重复（已确认的根因）

LuCI 的 `view.extend` 用**方法是否存在**决定页脚按钮：

```js
// /www/luci-static/resources/luci.js
handleSaveApply ? new ComboButton(...) : E([])
... this.handleSave ? E('button', {'class':'cbi-button cbi-button-save'}) : E([])
... this.handleReset ? E('button', {'class':'cbi-button cbi-button-reset'}) : E([])
```

当前加载器同时定义了 `handleSave`、`handleSaveApply`、`handleReset`，因此 LuCI 在页脚
渲染"保存并应用 / 保存 / 重置"，与我们顶栏的按钮重复，且样式体系不同（LuCI 的
`.btn.cbi-button` vs shadcn `Button`）。

**修法**：
- **删除**加载器里的 `handleSave`、`handleSaveApply`、`handleReset` 三个方法，
  让 LuCI 不再渲染页脚按钮。
- 页面**自己**在顶栏提供"保存 / 保存并应用"两个按钮，样式统一用 shadcn `Button`。
- 应用自己调用 `uci.save()` + `ui.changes.init()`（保存）和
  `ui.changes.apply(rollback)`（保存并应用），保持 LuCI 的回滚语义。
- "重置"改为顶栏的图标按钮，语义是"放弃未保存的更改并重新载入"，
  调用 `uci.load()` 重新载入配置 + 重新渲染（**不**用 `window.location.reload()`，
  那会丢掉已保存状态之外的一切；用 reload 也可以但必须明确文案）。
  实际上 `window.location.reload()` 是可接受的，因为它重新读取已保存的 UCI。
  保持 `window.location.reload()` 即可，文案为"重新载入"。

### 7. 按钮布局与样式不一致

当前页面混用三种按钮：
- shadcn `Button`（顶栏、工具栏）
- 原生 `<button>`（搜索框的清除按钮）
- LuCI `.btn`（页脚按钮，将被移除）

**修法**：
- 页面内**只允许**使用 shadcn `Button` 组件。原生 `<button>` 一律替换为
  `Button variant="ghost" size="icon"`。
- 尺寸统一：`size="sm"` 用于工具栏和次级操作，`size="default"` 用于顶栏主要操作，
  `size="icon"` 用于纯图标按钮。不得混用同一区域的不同高度。
- 顶栏按钮组统一用一个容器类 `.ac-header-actions`，按钮之间间距一致，
  主要操作（保存并应用）在最右且为主按钮（filled），保存为次级（outline）。
- 图标按钮必须有 `title` 和 `aria-label`。
- 所有按钮 `type="button"`，防止误触发表单提交。

## 二、布局重新设计（当前实现）

用户要求"基于对应的空间对当前的 UI 布局进行重新设计，让它更加合理"。

### 设计原则

- **同一色系**：设备栏、中央工作区、顶栏和设置页都使用同一组 surface token；
  设备栏用浅色表面和分隔线建立层次，不再使用近黑色的第二套配色。
- **单一容器**：每个页面是一个 `12px` 圆角、带边框和阴影的 `.ac-root` 浮层，
  内部面板统一 `8–10px` 圆角，避免四角直角的表格感。
- **主页面精简**：主页面只保留设备列表、当前音箱配置和健康摘要；服务控制、
  信号报告、最近日志放进右侧 `Drawer`，不再永久占据第三列。
- **设置独立成页**：全局设置位于 `/cgi-bin/luci/admin/services/airconnect-manager/settings`，
  按服务与发现、音频默认值、兼容性、诊断四组展示。

### 桌面（容器宽度 > 1180px）

- 设备列表栏：固定 `272px`，与主区使用同一色系，以 1px 分隔线区分。
- 中央工作区：`minmax(0, 1fr)`，自适应剩余空间，这是页面的主角。
- 服务状态不占列宽，通过顶部/底部入口打开右侧抽屉。

### 中等（720px < 容器宽度 ≤ 1180px）

- 设备列表栏收窄至 `240px`，主区保留自适应宽度。
- 容器宽度 ≤ `980px` 时，设备设置表单切换为单列，事实信息切换为两列。

### 窄（容器宽度 ≤ 720px）

- 设备列表变为可折叠面板，默认收起；当前音箱工作区占据首屏。
- 设备列表只在自身内容区滚动，页面允许纵向滚动。
- 容器宽度 ≤ `460px` 时，事实信息切换为单列并隐藏次要品牌副标题。

### 高度与溢出

- 主工作区不设置固定最小高度，由内容自然撑开。
- 必须保持 `document.documentElement.scrollWidth === document.documentElement.clientWidth`；
  宽度约束修在 Argon 的 `.container` 祖先上，而不是只修子元素。
- 抽屉使用 Radix Portal 固定在视口右侧，内部独立纵向滚动。

## 三、断点实现方式

**必须使用容器查询**（`@container airconnect (max-width: Npx)`），因为页面嵌在 LuCI
的 `#maincontent` 里，可用宽度取决于宿主布局和 iStoreOS 左侧菜单，不是视口宽度。
`.ac-root` 已声明 `container: airconnect / inline-size`。

现有实现保留：
```css
.ac-root { container: airconnect / inline-size; min-width: 0; }
```
注意：此声明必须在**普通样式层**（不是 `@layer base`），Tailwind 的 base 层会
移除它。之前踩过这个坑。

## 四、代码组织

新增文件：
- `frontend/src/lib/i18n.js` — 内置中英文案表和统一 translator；
- `frontend/src/lib/theme.js` — 主题状态管理；
- `frontend/src/components/chrome.jsx` — 两个页面共用的顶栏与操作区；
- `frontend/src/components/rail.jsx`、`device.jsx` — 设备列表和设备编辑器；
- `frontend/src/components/service-panel.jsx`、`ui/drawer.jsx` — 服务状态抽屉；
- `frontend/src/components/settings-page.jsx` — 独立设置页分组；
- `htdocs/luci-static/resources/view/airconnect-manager/common.js` — LuCI 共享 bundle loader；
- `htdocs/luci-static/resources/view/airconnect-manager/settings.js` — 独立 settings view；
- `scripts/update-i18n.mjs` — 从源码同步 POT/PO 并支持 `--check`。

修改文件：
- `frontend/src/App.jsx` — 接入语言/主题状态，并按 `mode` 渲染 overview/settings；
- `frontend/src/components/workspace.jsx` — 两栏设备工作台、健康摘要和 drawer 入口；
- `frontend/src/styles.css` — 统一 token、圆角、容器查询和溢出约束；
- `frontend/src/lib/fields.js`、`lib/i18n.js`、`main.jsx` — 字段分组、文案和挂载上下文；
- `htdocs/.../overview.js`、菜单 JSON、POT/PO — 主页面路由、设置入口和翻译目录。

overview 和 settings 两个 LuCI view 都显式将 `handleSave`、`handleSaveApply`、
`handleReset` 设为 `null`，避免 LuCI 基类生成重复页脚按钮。

## 五、测试要求

- `tests/i18n/check.sh` 必须通过：POT 覆盖前端全部 `_()` 字符串，PO 无空 msgstr。
- `tests/luci/run.mjs`、`tests/luci/diagnostics.mjs` 必须通过（签名未变）。
- `tests/parity/check-frontend.mjs` 必须通过。
- `tests/performance/measure-payload.sh` 必须通过。当前脚本记录并约束 app.js/app.css
  的实测值与预算，样式或依赖变更后必须重新运行该检查并同步预算说明（如确实需要调整）。
- `npm run build` 必须成功，且 `check-bundle.mjs` 通过。
- 完整 `bash scripts/run-tests.sh` 全部通过。

## 六、交付方式

改造完成后由主 agent 统一提交、推送和部署。subagent **不要**执行 git commit、
git push 或任何写入远程设备的操作。

## 七、本轮修复记录（2026-10-31）

### 1. 页面高度

短内容页面此前在卡片下方留下大片空白。`.ac-root → .ac-app → .ac-chrome →
.ac-workspace → .ac-workspace-body` 改为纵向 flex 链，`.ac-root` 用
`min-height: calc(100dvh - 8rem)` 兜底：内容少时占满视口，内容多时自然撑开并由
文档纵向滚动。窄屏（`@container airconnect (max-width: 720px)`）取消这个兜底，
避免移动端出现空滚动区。

### 2. 顶栏分段控件的选中态

语言/主题按钮由 `aria-pressed` 驱动样式。选中段使用
`hsl(var(--primary) / 0.18)` 半透明填充：浅色下叠在轨道上得到浅靛蓝，深色下得到
更亮的靛蓝。不能直接用 `--accent`，因为浅色主题的 `--accent` 与轨道只差两三个色阶，
选中态几乎不可见。未选中段保持透明，hover 用前景色 7% 叠加，避免"两个都像被选中"。

### 3. Argon 对 `button` 的级联覆盖

Argon 的 `.float-list,.btn,button,select,input` 规则是**未分层**样式，优先级高于
任何 `@layer`。页面用 `:where(.ac-root, .ac-portal) button` 重置
（`appearance`、背景、`border-width`、颜色、`margin`、`padding`），
`:where()` 保证它的特异性与 Argon 相同（0,0,1），Tailwind 工具类（0,1,0）仍然获胜。

两个必须记住的细节：

- 重置只写 `border-width: 0`，**不能**用 `border` 简写：简写会同时写入
  `border-style: none`，之后任何 `border-*` 工具类都无法恢复，开关的 2px 透明边框
  会消失，滑块在开启/关闭时左右间距不对称（2px vs 4px）。
- 基础层的元素规则（`color: inherit; font: inherit`）也必须写成
  `:where(...)`。写成 `.ac-root button`（0,1,1）会压过工具类（0,1,0），
  导致"保存并应用"丢掉 `text-primary-foreground`、所有按钮丢掉 `text-xs`。

### 4. 局域网接口改为下拉

`lib/interfaces.js` 把 `network.interface dump` 归一化成选项：值取 Linux 设备名
（`l3_device`，回退 `device`），因为引擎用 `SO_BINDTODEVICE` 绑定；标签在逻辑名与
设备名不同时显示 `lan (br-lan)`。`loopback` 不列出；已配置但当前 down 的接口仍保留，
否则 Radix Select 会因为没有匹配项而显示空白；dump 为空（权限或调用失败）时返回
`null`，字段退回文本框而不是一个只有一项的下拉。uci 未写 `interface` 时表单显示
`config.uc` 的默认值 `br-lan`，但不会写回 uci。ACL 需要
`network.interface: ["dump"]` 读权限。

### 5. Portal 内容的主题作用域

Radix 把抽屉和下拉菜单 portal 到 `<body>`，而 `.ac-root` 既是 token 作用域，
又带 `overflow: hidden`，所以它们既不能留在卡内，也拿不到卡内的样式。现在：

- 这两个组件给自己加 `ac-portal` 和与根元素相同的 `ac-theme-light` /
  `ac-theme-dark` 类（`components/theme-context.jsx`，由 `App` 提供当前偏好）；
- 三套 token 块（浅色、显式深色、`prefers-color-scheme`）都覆盖 `.ac-portal`；
- `tailwind.config.mjs` 的 `important` 改为 `':where(.ac-root, .ac-portal)'`，
  否则 portal 内容拿不到任何工具类；
- 工具类只匹配**后代**，所以下拉菜单自身的盒子由 `.ac-select-content` 写在
  `styles.css` 里。

### 6. 页面动作归属

刷新只对设备工作台有意义，`PageChrome` 在 settings 页收到 `onRefresh={null}` 时不
渲染刷新按钮；保存、保存并应用、重置两页都保留。

### 7. 两个页面之间的跳转

设置页是独立的 LuCI view，不是工作台上的浮层，所以它需要自己的返回入口。顶栏操作区
最左侧新增"← 返回设备"（`variant="outline" size="sm"`），与工作台页脚的"全局设置"
按钮成对。两个 URL 都由当前地址推导（`lib/navigation.js`），不写死 `/cgi-bin/luci`
前缀：`settingsPageUrl` 追加一段，`parentPageUrl` 去掉末尾的 `settings`，并丢弃查询串
和锚点。
