import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const bundle = readFileSync(new URL('../htdocs/luci-static/resources/airconnect-manager/app.js', import.meta.url), 'utf8');
const browser = { window: {}, console, setTimeout, clearTimeout };

runInNewContext(bundle, browser, { filename: 'app.js', timeout: 5000 });
assert.equal(typeof browser.window.AirConnectApp?.mount, 'function', '浏览器应能加载 AirConnectApp');
console.log('浏览器环境中的 bundle 初始化成功');
