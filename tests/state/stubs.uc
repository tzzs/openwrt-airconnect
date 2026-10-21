// SPDX-License-Identifier: MIT
// The fake `uci` and `ubus` modules used by every host test that drives the real
// rpcd plugin (tests/state/plugin.uc and tests/performance/measure-status.uc).
//
// They live here, in one file, for two reasons:
//
//   1. the fakes must be identical in every suite, or a suite could pass because
//      its fake is more forgiving than the other one;
//   2. the ucode module cache is process-wide, so the two stub files may only be
//      installed once per process. install() is idempotent for that reason:
//      writing the same bytes twice is harmless, but doing it from two places
//      with different text is not.
//
// Both stubs re-read `<stubdir>/config.json` on every call, so a test changes
// their behaviour by rewriting that one file rather than reinstalling modules.
//
// Usage:
//
//   import { install } from './stubs.uc';
//   install(STUBS);              // writes uci.uc and ubus.uc into STUBS
//
// The caller must put STUBS on the module search path (`ucode -L <STUBS>`); a
// module written at runtime cannot be found otherwise.

import * as fs from 'fs';

// The fake answer to every uci call the plugin makes. `get_all` returns the
// `main` object and `foreach` walks the `devices` array of config.json, which is
// exactly the shape runtime.uc's loadConfig expects from a real cursor.
export const UCI_SOURCE =
	'import * as fs from "fs";\n' +
	'let self = fs.dirname(sourcepath());\n' +
	'({ cursor: function() { return {\n' +
	'  load: function(name) { },\n' +
	'  get_all: function(name, section) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    return config.main ?? null;\n' +
	'  },\n' +
	'  foreach: function(name, kind, callback) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    for (let device in config.devices ?? [])\n' +
	'      if (callback(device) === false)\n' +
	'        break;\n' +
	'    return true;\n' +
	'  }\n' +
	'}; } })\n';

// The fake ubus answers exactly the three calls the plugin makes: procd's
// service list, netifd's device status and netifd's interface dump. Anything
// else returns an empty object, which is what an unknown ubus object looks like.
export const UBUS_SOURCE =
	'import * as fs from "fs";\n' +
	'let self = fs.dirname(sourcepath());\n' +
	'({ connect: function() { return {\n' +
	'  call: function(object, method, args) {\n' +
	'    let config = json(fs.readfile(self + "/config.json")) ?? {};\n' +
	'    if (object == "service" && method == "list") {\n' +
	'      let reply = {};\n' +
	'      let services = config.services ?? {};\n' +
	'      if (services[args.name] != null)\n' +
	'        reply[args.name] = services[args.name];\n' +
	'      return reply;\n' +
	'    }\n' +
	'    if (object == "network.device" && method == "status")\n' +
	'      return { "ipv4-address": [ { address: "192.0.2.10" } ] };\n' +
	'    return {};\n' +
	'  }\n' +
	'}; } })\n';

function writeIfChanged(path, data) {
	let current = fs.readfile(path);
	if (type(current) == 'string' && current == data)
		return;
	fs.writefile(path, data);
}

// Install both stubs into `stubDir`. Returns the two paths so a caller can
// report them.
export function install(stubDir) {
	writeIfChanged(stubDir + '/uci.uc', UCI_SOURCE);
	writeIfChanged(stubDir + '/ubus.uc', UBUS_SOURCE);
	return { uci: stubDir + '/uci.uc', ubus: stubDir + '/ubus.uc' };
}

// Write `<stubDir>/config.json`, the single knob both stubs read. Defaults match
// what the plugin sees on a fresh, working router so a test only states what it
// cares about.
export function configure(stubDir, options) {
	options = options ?? {};
	let config = {
		main: options.main ?? {
			enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '0', codec: 'flac',
			latency: '1000:2000', max_volume: '100', media_volume: '0.5', log_level: 'warn'
		},
		devices: options.devices ?? [],
		services: options.services ?? {}
	};
	fs.writefile(stubDir + '/config.json', sprintf('%J\n', config));
	return config;
}
