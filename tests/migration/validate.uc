// SPDX-License-Identifier: MIT
// Cross-check for tests/migration/run.sh: read a generated
// /etc/config/airconnect-manager with a minimal UCI-shaped reader and run it
// through the real validator and renderer. This is what proves the migrated
// file is not merely well-formed text but a configuration the manager accepts.
//
// usage: ucode validate.uc <generated-config>
// Exit status: 0 when validation and rendering succeed, 1 otherwise.

import * as fs from 'fs';
import { normalizeConfig, renderXml } from '../../packages/airconnect-manager/files/usr/share/airconnect-manager/config.uc';

function load(path) {
	let text = fs.readfile(path);
	if (type(text) != 'string')
		die('cannot read ' + path);
	let main = {}, devices = [], current = null;
	for (let line in split(text, '\n')) {
		let section = match(line, /^config[ \t]+([a-z]+)[ \t]+'([^']*)'$/);
		if (section) {
			current = { '.name': section[2] };
			if (section[1] == 'main')
				main = current;
			else
				push(devices, current);
			continue;
		}
		let option = match(line, /^[ \t]*option[ \t]+([A-Za-z0-9_]+)[ \t]+'([^']*)'$/);
		if (option && current != null)
			current[option[1]] = option[2];
	}
	return { main: main, devices: devices };
}

let path = ARGV[0];
if (type(path) != 'string' || path == '')
	die('usage: validate.uc <generated-config>');

let config;
try {
	config = normalizeConfig(load(path));
}
catch (error) {
	printf('invalid: %s\n', type(error) == 'object' ? error.message : error);
	exit(1);
}
printf('valid: upnp=%d cast=%d interface=%s devices=%d\n',
	config.main.airupnp, config.main.aircast, config.main.interface, length(config.devices));
for (let device in config.devices)
	printf('device: engine=%s udn=%s max_volume=%d\n', device.engine, device.udn, device.max_volume);
for (let engine in ['upnp', 'cast']) {
	if (engine == 'upnp' && !config.main.airupnp)
		continue;
	if (engine == 'cast' && !config.main.aircast)
		continue;
	try {
		let xml = renderXml(config, engine);
		printf('%s: rendered %d bytes\n', engine, length(xml));
	}
	catch (error) {
		printf('%s: render failed: %s\n', engine, type(error) == 'object' ? error.message : error);
		exit(1);
	}
}
exit(0);
