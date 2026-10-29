// Built-in i18n for the AirConnect Manager frontend.
//
// The LuCI view (`overview.js`) hands its `_` to the React app via
// `context.translate`; that is the server-side translation (the compiled
// `.lmo`). But the device may ship an older `.lmo`, so the page used to show a
// mix of Chinese and English. This module ships a full Chinese table inside the
// bundle so a language switch is instant and pure-frontend, while still
// deferring to LuCI's `_()` when it has a translation this table lacks.
//
// Contract:
//   - `t(text)` returns the string to render for the current language.
//   - When `lang === 'en'`, the English source is returned unchanged.
//   - When `lang === 'zh'`, the built-in table wins; if it misses, LuCI's `_()`
//     is tried; if that also returns the source unchanged, the source is shown.
//   - `luciTranslate` may be undefined or not a function - we must be resilient.

export const LANGUAGES = [
	{ value: 'zh', label: '中文' },
	{ value: 'en', label: 'English' }
];

const STORAGE_KEY = 'airconnect.lang';
const VALID_LANGS = new Set(LANGUAGES.map((entry) => entry.value));

// Built-in Simplified Chinese table. Covers every translatable source string
// in frontend/src/** (213 entries) so the page never shows a mixed-language view
// even when the device's `.lmo` is stale. Proper nouns are kept in English per
// the spec: UPnP / DLNA, Chromecast, AirPlay, AirConnect, FLAC, HTTP.
const ZH = {
	'-1: no content-length (default)': '-1：无 content-length（默认）',
	'-3: chunked encoding': '-3：分块传输',
	'0: fixed dummy length': '0：固定的虚拟长度',
	'Add a host after http:// or https://.': '在 http:// 或 https:// 之后填写主机地址。',
	'Advanced': '高级',
	'Advanced audio settings': '高级音频设置',
	'Advanced settings': '高级设置',
	'AirConnect Manager': 'AirConnect 管理器',
	'AirConnect health overview': 'AirConnect 健康概览',
	'AirPlay advertised': '已广播 AirPlay',
	'AirPlay bridge': 'AirPlay 桥接',
	'AirPlay broadcast': 'AirPlay 广播',
	'AirPlay broadcast (Chromecast)': 'AirPlay 广播（Chromecast）',
	'AirPlay broadcast (UPnP)': 'AirPlay 广播（UPnP）',
	'AirPlay broadcast unknown': 'AirPlay 广播未知',
	'AirPlay lists these receivers under one name. Give each speaker its own name.': 'AirPlay 会将这些接收器显示为同一个名称。请为每个音箱设置独立名称。',
	'AirPlay name': 'AirPlay 名称',
	'AirPlay name override is active.': 'AirPlay 名称覆盖已启用。',
	'Another AirConnect instance was detected.': '检测到另一个 AirConnect 实例。',
	'Applied when a speaker does not define its own value.': '在音箱没有单独设置时使用。',
	'Apply failed — changes remain pending': '应用失败 — 更改仍处于待应用状态',
	'Apply requested — check LuCI confirmation': '已请求应用 — 请检查 LuCI 确认信息',
	'Applying…': '正在应用…',
	'Audio and compatibility': '音频与兼容性',
	'Audio defaults': '音频默认值',
	'Audio format': '音频格式',
	'Bind discovery and AirPlay to your local network interface.': '将发现和 AirPlay 绑定到本地网络接口。',
	'Both engines. Off adjusts timing by adding or dropping a frame, which can be audible as a click; on avoids the click but risks underruns.': '两个引擎都适用。关闭时通过增加或丢弃帧来调整时序，可能听到咔嗒声；开启可避免咔嗒声，但可能发生欠载。',
	'Buffer and latency': '缓冲与延迟',
	'Changes are kept locally until you save.': '更改会保留在本地，直到你保存。',
	'Changes only the virtual AirPlay receiver name. Leave empty to use the original name.': '只修改虚拟 AirPlay 接收器名称。留空则使用原名称。',
	'Changes take effect after Save & Apply. Applying briefly disconnects AirPlay.': '保存并应用后更改才会生效。应用配置时 AirPlay 会短暂断开。',
	'Choose -3 (chunked), -1 (no content-length) or 0 (fixed length).': '选择 -3（分块编码）、-1（无内容长度）或 0（固定长度）。',
	'Choose error, warn, info or debug.': '选择 error、warn、info 或 debug。',
	'Choose off (0) or on (1).': '选择关闭（0）或开启（1）。',
	'Choose which bridge engines are available on this router.': '选择此路由器上可用的桥接引擎。',
	'Chromecast': 'Chromecast',
	'Chromecast compatibility option. The UPnP engine ignores this.': 'Chromecast 兼容性选项。UPnP 引擎会忽略此项。',
	'Chromecast discovery': 'Chromecast 发现',
	'Chromecast media volume': 'Chromecast 媒体音量',
	'Chromecast receiver': 'Chromecast 接收器',
	'Chromecast speakers': 'Chromecast 音箱',
	'Clear search': '清除搜索',
	'Close settings': '关闭设置',
	'Compatibility and detail options. Leave the defaults unless a speaker needs them.': '兼容性与细节选项。除非某个音箱需要，否则保持默认。',
	'Compatibility only. Change this when a UPnP speaker cannot play at all; the default works for most devices.': '仅用于兼容性。当 UPnP 音箱完全无法播放时再修改此项；默认值适用于大多数设备。',
	'Compatibility option, both engines. Turning it off can change pause and track-change behaviour, so keep it on unless a speaker misbehaves.': '两个引擎都适用的兼容性选项。关闭后可能改变暂停和切歌行为，除非音箱表现异常，否则请保持开启。',
	'Configuration': '配置',
	'Configuration validation failed.': '配置校验失败。',
	'Configure speaker': '配置音箱',
	'Could not load settings. ': '无法加载设置。',
	'Could not start discovery.': '无法开始发现。',
	'Cover art URL': '封面图片 URL',
	'Create a local profile to give it an AirPlay name, set its volume and choose how it bridges audio.': '创建本地配置，为音箱设置 AirPlay 名称和音量，并选择音频桥接方式。',
	'Dark': '深色',
	'Default maximum volume, from 1 to 100.': '默认最大音量，范围为 1 到 100。',
	'Default media volume, from 0 to 1. This is not a volume limit.': '默认媒体音量，范围为 0 到 1。这不是音量上限。',
	'Defaults for every speaker without a local override.': '所有未单独设置的音箱默认使用这些值。',
	'Device facts': '设备信息',
	'Device identifier': '设备标识',
	'Device identifier (UDN)': '设备标识符（UDN）',
	'Diagnostics': '诊断',
	'Disabled': '已禁用',
	'Discovered': '已发现',
	'Discovered on your network. Configure this speaker to override its AirPlay name and volume.': '已在网络中发现。配置此音箱可以覆盖其 AirPlay 名称和音量。',
	'Discovery error': '发现错误',
	'Discovery is available': '发现功能可用',
	'Discovery is in progress.': '正在发现设备。',
	'Discovery unknown': '发现状态未知',
	'Enable AirConnect': '启用 AirConnect',
	'Enable UPnP or Chromecast discovery in Global settings first.': '请先在全局设置中启用 UPnP 或 Chromecast 发现。',
	'Enable an engine to scan': '启用引擎后才能扫描',
	'Enable bridging': '启用桥接',
	'Enter an interface name of 1-15 characters that starts with a letter or digit.': '输入 1 至 15 个字符的接口名称，以字母或数字开头。',
	'Everyday controls': '常用控制',
	'FLAC can use more CPU. Choose a format supported by your speaker.': 'FLAC 可能占用更多 CPU。请选择音箱支持的格式。',
	'Find the speakers on your network': '查找网络中的音箱',
	'Find your speakers': '查找你的音箱',
	'Format: 1000:2000. Lower values may cause audio dropouts.': '格式：1000:2000。数值过低可能导致音频断续。',
	'General settings': '常规设置',
	'Global defaults apply unless a speaker has its own override.': '除非音箱有单独覆盖值，否则使用全局默认值。',
	'Global settings': '全局设置',
	'HTTP transfer mode': 'HTTP 传输模式',
	'HTTP transfer mode (UPnP only)': 'HTTP 传输模式（仅 UPnP）',
	'Handle FLUSH': '处理 FLUSH',
	'Highest UPnP MediaRenderer version to search. The Chromecast engine ignores this.': '要搜索的最高 UPnP MediaRenderer 版本。Chromecast 引擎会忽略此项。',
	'IP address': 'IP 地址',
	'Inherit global setting': '继承全局设置',
	'Interface': '接口',
	'LAN interface': '局域网接口',
	'Last attempt:': '上次尝试：',
	'Last discovered': '最后发现时间',
	'Last scan': '上次扫描',
	'Last scan: ': '上次扫描：',
	'Leave empty to inherit the global Chromecast volume.': '留空以继承全局 Chromecast 音量。',
	'Leave empty to inherit the global UPnP limit.': '留空以继承全局 UPnP 音量上限。',
	'Leave empty to inherit the global setting.': '留空以继承全局设置。',
	'Let the timing reference drift': '允许时序参考漂移',
	'Light': '浅色',
	'Load recent logs': '加载最近日志',
	'Loading speakers and status…': '正在加载音箱和状态…',
	'Log detail': '日志详细程度',
	'Logs appear here when requested.': '请求后将在此显示日志。',
	'Logs are loaded only when requested.': '仅在请求时加载日志。',
	'Manager version': '管理器版本',
	'Manufacturer': '制造商',
	'Media volume': '媒体音量',
	'Model': '型号',
	'More than one speaker uses the same AirPlay name.': '多个音箱使用了相同的 AirPlay 名称。',
	'Network and discovery': '网络与发现',
	'No': '否',
	'No AirPlay advertisement': '没有 AirPlay 广播',
	'No engine': '无引擎',
	'No log entries.': '没有日志条目。',
	'No scan has been completed.': '尚未完成扫描。',
	'No speaker matches this search.': '没有匹配此搜索的音箱。',
	'No speakers discovered yet.': '尚未发现音箱。',
	'No unsaved changes': '没有未保存的更改',
	'No — the scan found no advertisement': '否 — 扫描未发现广播',
	'Not currently discovered': '当前未发现',
	'Not measured': '未测量',
	'Not playing': '未播放',
	'Not provided': '未提供',
	'Not saved — check settings': '未保存 — 请检查设置',
	'Observed': '观测时间',
	'Off (0)': '关闭（0）',
	'Older log lines were omitted.': '较早的日志行已省略。',
	'On (1)': '开启（1）',
	'Optional http:// or https:// image the speaker fetches itself. Leave empty for none. The router never downloads it.': '可选的 http:// 或 https:// 图片地址，由音箱自行获取。留空表示不使用。路由器不会下载图片。',
	'Original name': '原名称',
	'Playback': '播放',
	'Playing': '播放中',
	'Rail menu': '列表菜单',
	'Ready to discover': '可以开始发现',
	'Recent AirConnect logs': '最近的 AirConnect 日志',
	'Recent logs': '最近日志',
	'Refresh status': '刷新状态',
	'Remove control or invalid characters from the AirPlay name.': '从 AirPlay 名称中移除控制字符或无效字符。',
	'Remove spaces, quotes or control characters from the artwork URL.': '从封面图片 URL 中移除空格、引号或控制字符。',
	'Reported by the last discovery response.': '由上次发现响应提供。',
	'Reset': '重置',
	'Restart': '重启',
	'Restart service': '重启服务',
	'Running': '运行中',
	'Save': '保存',
	'Save and apply': '保存并应用',
	'Saved; pending apply': '已保存；等待应用',
	'Scan failed: ': '扫描失败：',
	'Scan for speakers': '扫描音箱',
	'Scanning speakers': '正在扫描音箱',
	'Scanning…': '扫描中…',
	'Search speakers': '搜索音箱',
	'Send track information': '发送曲目信息',
	'Sends the title and artist to the speaker. Both engines read this. A speaker may still show nothing.': '将标题和艺术家发送给音箱。两个引擎都会读取此项，但音箱仍可能不显示。',
	'Service action failed.': '服务操作失败。',
	'Service actions': '服务操作',
	'Service actions use the last applied settings. Stopping or restarting briefly disconnects AirPlay.': '服务操作使用最近一次应用的设置。停止或重启服务会使 AirPlay 短暂断开。',
	'Service control': '服务控制',
	'Service running': '服务运行中',
	'Service running does not confirm AirPlay availability or playback.': '服务运行不代表 AirPlay 可用或正在播放。',
	'Service stopped': '服务已停止',
	'Set the AirPlay name and volume for each speaker.': '为每个音箱设置 AirPlay 名称和音量。',
	'Set up this speaker': '设置此音箱',
	'Signal report': '信号报告',
	'Speaker bridge': '音箱桥接',
	'Speakers': '音箱',
	'Start': '启动',
	'Start a discovery scan to see compatible UPnP and Chromecast speakers. They will appear here with a separate profile for each receiver.': '开始发现扫描以查找兼容的 UPnP 和 Chromecast 音箱。每个接收器都会以独立配置显示在这里。',
	'Start discovery': '开始发现',
	'Start service': '启动服务',
	'Status unavailable. Displayed information may be stale. ': '状态不可用。显示的信息可能已过期。',
	'Stop service': '停止服务',
	'Stop the existing instance before starting these engines.': '启动这些引擎前请先停止现有实例。',
	'Stop the receiver': '停止接收器',
	'Stop the receiver (Chromecast only)': '停止接收器（仅 Chromecast）',
	'Stopped': '已停止',
	'System': '跟随系统',
	'The log response was invalid.': '日志响应无效。',
	'The settings you are most likely to change.': '最常修改的设置。',
	'This speaker is discovered': '已发现此音箱',
	'Turn on a discovery engine in Settings, then scan. Keep your speaker online on the same LAN and enable DLNA when required.': '先在“设置”中启用发现引擎，再进行扫描。请保持音箱在线并与路由器处于同一局域网；必要时启用 DLNA。',
	'UPnP': 'UPnP',
	'UPnP / DLNA': 'UPnP / DLNA',
	'UPnP / DLNA receiver': 'UPnP / DLNA 接收器',
	'UPnP / DLNA speakers': 'UPnP / DLNA 音箱',
	'UPnP discovery': 'UPnP 发现',
	'UPnP search version (UPnP only)': 'UPnP 搜索版本（仅 UPnP）',
	'UPnP volume limit': 'UPnP 音量上限',
	'Unknown': '未知',
	'Unknown — no completed mDNS observation. This needs the engine running and its receiver advertised on this LAN.': '未知 — 没有完成的 mDNS 观测。这需要引擎运行，并在此局域网中广播接收器。',
	'Unknown — not measured': '未知 — 尚未测量',
	'Unknown — the engines expose no documented playback status, so this is never inferred from the broadcast state.': '未知 — 引擎没有文档化的播放状态，因此不会根据广播状态推断。',
	'Unnamed speaker': '未命名音箱',
	'Unsaved changes': '未保存的更改',
	'Use a lowercase http:// or https:// URL.': '使用小写的 http:// 或 https:// 网址。',
	'Use a name that is not only spaces.': '名称不能仅由空格组成。',
	'Use a number from 0 to 1, for example 0.5.': '使用 0 到 1 之间的数字，例如 0.5。',
	'Use a whole number from 1 to 100.': '使用 1 到 100 之间的整数。',
	'Use a whole number from 1 to 9.': '使用 1 到 9 之间的整数。',
	'Use at most 512 bytes for the artwork URL.': '封面图片 URL 长度不超过 512 字节。',
	'Use at most 63 bytes for the AirPlay name.': 'AirPlay 名称长度不超过 63 字节。',
	'Use two whole numbers from 0 to 10000 separated by a colon, for example 1000:2000.': '使用两个 0 到 10000 之间的整数，以冒号分隔，例如 1000:2000。',
	'Using the original speaker name.': '正在使用音箱原始名称。',
	'Validating…': '正在校验…',
	'Version unknown': '版本未知',
	'Volume limit': '音量上限',
	'Workspace': '工作区',
	'Yes': '是',
	'Yes — an AirPlay receiver is advertised': '是 — 已广播 AirPlay 接收器',
	'discovery engine': '发现引擎',
	'last AirPlay observation': '上次 AirPlay 观测',
	'observed': '已观测',
	'speakers discovered': '已发现音箱'
};

// navigator.language may be undefined in non-browser test contexts; fall back
// to 'en' so the page always has a deterministic default.
export function detectLanguage() {
	if (typeof navigator === 'undefined' || !navigator || !navigator.language) return 'en';
	return navigator.language.toLowerCase().indexOf('zh') === 0 ? 'zh' : 'en';
}

// Read the stored preference; if it is missing or invalid, fall back to the
// detected default. localStorage may throw (private mode, disabled storage) so
// every access is guarded.
export function readLanguage() {
	let stored = null;
	try {
		stored = window.localStorage && window.localStorage.getItem(STORAGE_KEY);
	} catch (_) {
		stored = null;
	}
	return VALID_LANGS.has(stored) ? stored : detectLanguage();
}

// Persist the preference and mirror it onto <html lang> so screen readers and
// browser search see the right language. Both are best-effort: storage may be
// unavailable, and document may be undefined in a test harness.
export function writeLanguage(lang) {
	try {
		if (window.localStorage) window.localStorage.setItem(STORAGE_KEY, lang);
	} catch (_) {
		/* storage unavailable - preference is session-only */
	}
	if (typeof document !== 'undefined' && document && document.documentElement) {
		document.documentElement.lang = lang === 'zh' ? 'zh-Hans' : 'en';
	}
}

// Build the `t(text)` translator the React tree uses.
//
//   lang          - 'zh' or 'en' (any other value behaves as 'en').
//   luciTranslate - LuCI's `_`, passed in from overview.js via services.t.
//                   May be undefined or not a function; we tolerate that.
export function createTranslator(lang, luciTranslate) {
	if (lang === 'zh') {
		const luci = typeof luciTranslate === 'function' ? luciTranslate : null;
		return function t(text) {
			const own = ZH[text];
			if (own != null) return own;
			if (luci) {
				const external = luci(text);
				// If LuCI returned the source unchanged it has no translation
				// for this string; showing the English source is the honest
				// fallback rather than mixing in a stale partial.
				return external != null && external !== text ? external : text;
			}
			return text;
		};
	}
	// 'en' (and any unknown value): English source is the render text.
	return function t(text) { return text; };
}
