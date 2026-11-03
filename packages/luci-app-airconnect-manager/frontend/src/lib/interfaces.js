/**
 * The LAN interface control.
 *
 * AirConnect binds with SO_BINDTODEVICE, so the value it needs is a bare Linux
 * device name (`br-lan`), not the logical UCI interface (`lan`). The router
 * already knows both, so the field is a select built from
 * `network.interface dump` instead of a text box the user has to fill from
 * memory.
 *
 * Kept out of App.jsx on purpose: the host test runner imports this file
 * directly, and it cannot parse JSX. Everything here is a pure function of the
 * ubus reply and the configured value, so the shape of the option list is a
 * contract the test suite can assert.
 */

// config.uc: `interface: option(source, 'interface', 'br-lan')`. An unset uci
// option therefore still means br-lan at runtime, and the form shows that
// effective value instead of an empty select. Nothing is written to uci until
// the user picks something, so the stored configuration stays as it was.
export const DEFAULT_INTERFACE = 'br-lan';

// `lo` is never a LAN to bridge to. A configured `lo` is still kept by the
// retention rule below, so this only removes the meaningless choice.
const NOT_A_LAN = 'loopback';

/**
 * Turn a `network.interface dump` reply into `{ value, label }` options.
 *
 * The reply is either `{ interface: [...] }` (ubus object) or
 * `{ interface: { name: {...} } }` (the JSON form some callers return); both
 * are accepted. `value` is the Linux device, `label` keeps the logical name
 * when it differs, which is what the router's own network pages show.
 *
 * The configured value is always present, even when that interface is down and
 * absent from the dump, because a Radix select with a value no item matches
 * renders blank. A dump that lists nothing returns null, even when a value is
 * configured: that means the call failed or the ACL is missing, and the caller
 * should keep the text input rather than offer a one-item dropdown the user
 * cannot get out of.
 */
export function interfaceOptionsFrom(data, configured) {
  const list = (data && (data.interface || data.interfaces)) || {};
  const entries = Array.isArray(list)
    ? list.flatMap((item) => {
        if (!item || item.interface === NOT_A_LAN) return [];
        const device = item.l3_device || item.device;
        if (!device) return [];
        const name = item.interface || item.name;
        return [
          {
            value: device,
            label: name && name !== device ? `${name} (${device})` : device,
          },
        ];
      })
    : Object.keys(list).flatMap((name) => {
        if (name === NOT_A_LAN) return [];
        const item = list[name] || {};
        const device = item.l3_device || item.device || name;
        return device
          ? [
              {
                value: device,
                label: name !== device ? `${name} (${device})` : device,
              },
            ]
          : [];
      });
  const unique = [...new Map(entries.map((entry) => [entry.value, entry])).values()];
  if (unique.length === 0) return null;
  if (configured && !unique.some((entry) => entry.value === configured))
    unique.unshift({ value: configured, label: configured });
  return unique;
}

/**
 * Replace the interface descriptor with a select over `options`.
 *
 * A null option list (the dump failed, or the ACL is missing) returns the
 * fields untouched, which leaves the plain text input in place: the user can
 * still type a device name, and nothing silently disappears.
 */
export function withInterfaceSelect(fields, options) {
  if (!options) return fields;
  return fields.map((field) =>
    field.name === 'interface' ? Object.assign({}, field, { kind: 'select', options }) : field,
  );
}

/**
 * The value the form should show for the interface option: what uci holds, or
 * the backend default when the option was never written.
 */
export function interfaceValue(configured) {
  return configured == null || configured === '' ? DEFAULT_INTERFACE : configured;
}
