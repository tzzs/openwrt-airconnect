# Validation parity tests

The LuCI view validates in the browser and `config.uc` validates again on the
router. When the two disagree, a value the form accepts is rejected by the
backend with a different message: one wasted round trip and two phrasings of
"invalid". This suite keeps them honest.

```sh
~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/parity/run.uc
node tests/parity/check-frontend.mjs
```

Both commands exit nonzero on disagreement. Neither needs a router, a network
connection, npm or a build step.

## The contract

`cases.json` is a hand-maintained array of `{ field, value, expect }` where
`expect` is `accept` or `reject`. It is the contract, not a mirror of either
implementation: when a case fails, decide which side is wrong before touching
anything.

- `field` is one of `interface`, `log_level`, `latency`, `max_volume`,
  `media_volume`, `name`, `metadata`, `flush`, `drift`, `stop_receiver`,
  `http_length`, `upnp_max`, `artwork`.
- `value` may be a string or a number (UCI can hold either).
- `scope` is optional. It defaults to both `main` and a device override for the
  fields that exist in both, and to the only section that has the field
  (`interface`/`log_level` are main-only, `name` is device-only).
- `note` is free text for the reader.

## What each runner does

`run.uc` decides every case with the real backend: it builds the `main` or
`device` section that `runtime.uc` would hand over and calls `normalizeConfig`.
A rejection counts only when the error message starts with a field path, so a
crash is not mistaken for a verdict. It also asserts the table covers every
field and both scopes, and that `main` and a device override agree wherever the
backend applies the same rule. `--verdicts` prints one JSON array of backend
verdicts instead of TAP output; the node runner consumes it so backend logic
exists in exactly one place.

`check-frontend.mjs` evaluates
`packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airconnect-manager/rules.js`
in a `new Function` shim with `_` supplied (and again with `_` absent), runs the
same values through the exported rule functions, and compares them with the
backend verdicts. It fails when a rule is missing, when a rejection returns
something other than a non-empty message string, or when the frontend and the
backend disagree on any case.

Empty values are the one place the scopes differ on purpose: on a device an
empty `max_volume`, `media_volume`, `latency` or advanced parameter means
"inherit the global value" (`config.uc`'s `inherited()`), while in `main` an
empty string is invalid. The table marks those cases `"scope": "main"`.

`upnp_max` is main-only, like `interface` and `log_level`, but for a source-level
reason rather than a UI one: upstream parses it into the device struct yet only
ever reads `glMRConfig.UPnPMax` when it builds the search topics, so a per-device
value would be dead XML. A case that scopes it to a device fails the schema
check on purpose.

## Adding a case

Add it to `cases.json` with the value, the expected verdict and a short note,
then run both commands. If the backend disagrees with the table, the backend
changed; if the frontend disagrees, tighten `rules.js` - never loosen
`config.uc` to make the browser look right.
