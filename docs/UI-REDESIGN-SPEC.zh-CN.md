# AirConnect LuCI 界面改造规格

本文件是这次改造的唯一事实来源。subagent 按此实现，不自行增加范围。

## 一、必须解决的问题

### 1. 横向溢出（已量化）

Argon 主题的 `#maincontent > .container` 使用 `margin: 0 1.25rem 1rem` 且 `width: 100%`。
父级 `#maincontent` 宽 1240px，`.container` 因 `width:100%` 加左右各 20px 外边距，实际占据
208→1468，而视口右边界只有 1448，因此**向右溢出 20px**。

实测：`document.documentElement.scrollWidth` = 1458 > `clientWidth` = 1240。

**修法**：`.ac-root` 必须自己约束宽度，不能跟随父级的 `width:100%`：

```css
.ac-root {
    margin-right: 20px;   /* 抵消 Argon .container 的右外边距 */
    width: auto;          /* 不再继承 width:100% */
    max-width: 100%;
    box-sizing: border-box;
}
```

同时 `.ac-console` 及所有子元素必须 `min-width: 0`，否则 grid/flex 子项的
`min-content` 会撑破容器。

**验收**：任意窗口宽度下 `document.documentElement.scrollWidth === document.documentElement.clientWidth`。

### 2. 纵向超高

当前 `.ac-root { min-height: 600px }`、`.ac-console { min-height: 680px }` 是硬编码高度，
与视口无关，页面总高 1068px 超出视口 834px。

**修法**：
- 去掉硬编码 `min-height`，改为 `min-height: 100%` 语义（由内容撑开）。
- 三个工作区（设备列表 / 中央内容 / 工具栏）内部各自滚动，页面本身不产生多余滚动：
  `.ac-console-layout` 用 `min-height: 0`，`.ac-device-list`、`.ac-main-workspace`、
  `.ac-utility-rail` 各自 `overflow-y: auto`。
- 若三栏在低高度下过于拥挤，允许中央内容区自然增高（纵向滚动是允许的，
  用户明确说"上下滑动还是可以的"），但**不得出现横向滚动**。

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

## 二、布局重新设计

用户要求"基于对应的空间对当前的 UI 布局进行重新设计，让它更加合理"。

### 桌面（容器宽度 ≥ 1120px）

三栏，但**宽度按内容重要性重新分配**：
- 设备列表栏：固定 260px（当前 270px），深色，可折叠。
- 中央工作区：`minmax(0, 1fr)`，自适应剩余空间，**这是页面的主角**。
- 工具栏：固定 260px，当前 278px。

三栏之间用 1px 分隔线，不留大间隙。

### 中等（760px ≤ 容器宽度 < 1120px）

- 设备列表栏 + 中央工作区两栏。
- 工具栏移到中央工作区**下方**，横向排列为三个区块（服务控制 / 信号 / 日志），
  与当前 `@media (max-width:1120px)` 的做法一致，但容器查询要基于 `.ac-root` 的
  容器宽度（已实现），不是视口宽度。

### 窄（容器宽度 < 760px）

- 单列纵向堆叠：设备列表（横向滚动的紧凑行）→ 中央工作区 → 工具栏。
- 设备列表横向滚动是允许的，但**只在设备列表内部滚动**，不能让整页横向滚动。

### 高度

- `.ac-console-layout` 高度用 `min-height: 0` + 内部滚动，让工具栏和设备列表
  在长内容时各自滚动，而不是把页面撑得很长。
- 中央工作区内容多时允许整页纵向滚动。

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
- `frontend/src/lib/i18n.js` — 内置中英文案表、`createTranslator(lang, luciTranslate)`、
  `detectLanguage()`、`readPreference()` / `writePreference()`。
- `frontend/src/lib/theme.js` — 主题状态管理（`readTheme()` / `applyTheme()` /
  `toggleTheme()`）。

修改文件：
- `frontend/src/App.jsx` — 接入语言/主题状态，把统一的 `t` 传给 rules/fields/presentation。
- `frontend/src/components/workspace.jsx` — 顶栏加入语言与主题控件；按钮统一。
- `frontend/src/styles.css` — 横向溢出修复、高度修复、dark token 抽取、按钮统一。
- `frontend/src/components/feedback.jsx` — `Alert` 的两种 tone 当前图标相同，修正。
- `htdocs/luci-static/resources/view/airconnect-manager/overview.js` — 删除三个
  handle 方法，传入语言/主题上下文。

不改动：`frontend/src/lib/rules.js`、`fields.js`、`presentation.js` 的**逻辑**，
只改它们的 `t` 参数来源（保持函数签名不变）。

## 五、测试要求

- `tests/i18n/check.sh` 必须通过：POT 覆盖前端全部 `_()` 字符串，PO 无空 msgstr。
- `tests/luci/run.mjs`、`tests/luci/diagnostics.mjs` 必须通过（签名未变）。
- `tests/parity/check-frontend.mjs` 必须通过。
- `tests/performance/measure-payload.sh` 必须通过。注意 `app.css` 当前 32672 字节，
  上限 32768，**只剩 96 字节余量**。新增样式前必须先腾出空间：
  - 把 `styles.css` 中的重复声明合并；
  - 或临时提高 `tests/performance/measure-payload.sh` 中 app.css 的 cap，
    并在注释里写明新的实测值和理由（该脚本注释明确允许按实测值调整 cap）。
- `npm run build` 必须成功，且 `check-bundle.mjs` 通过。
- 完整 `bash scripts/run-tests.sh` 全部通过。

## 六、交付方式

改造完成后由主 agent 统一提交、推送和部署。subagent **不要**执行 git commit、
git push 或任何写入远程设备的操作。
