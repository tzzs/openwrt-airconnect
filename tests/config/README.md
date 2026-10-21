# Configuration core tests

From the repository root, on a host with the OpenWrt `ucode` interpreter:

```sh
ucode tests/config/run.uc
```

The runner imports the pure module and synthetic fixtures by relative path. It
does not require UCI, read router configuration, write files, run AirConnect, or
contact the network. Nonzero exit means failure; output uses TAP-style assertions.

Coverage includes typed defaults, explicit overrides and inheritance, both XML
roots, per-engine device/volume separation, all boolean fields, numeric bounds and
non-finite input, codec/latency allowlists, interface tokens, UTF-8 validation and
byte limits, Unicode whitespace, duplicate UDNs per engine, XML escaping, unknown
metadata, immutable input, deterministic serialization and renderer revalidation.

The supported codec subset is `wav`, `pcm` (UPnP only), `flac[:0..9]`,
`mp3[:32..320]`, and `aac[:16..320]` with integer bitrates. FLAC block sizes and
the optional upstream latency force flag are intentionally outside the first
release contract. Names may be empty to inherit discovery; explicit whitespace
names are rejected. Device `codec`, `latency`, `max_volume`, and `media_volume`
inherit when omitted or empty, while null is invalid.

The advanced engine parameters are `metadata`, `flush`, `drift`, `artwork`,
`http_length`, `upnp_max` and `stop_receiver`. `metadata`, `flush`, `drift` and
`stop_receiver` are 0/1 flags; `http_length` is one of the three documented
transfer modes (-3, -1, 0); `upnp_max` is a search version in 1..9; `artwork` is
an http(s) URL of at most 512 bytes. Every one of them inherits like `codec`,
and each is rendered only into the engine that reads it: `http_length` and
`upnp_max` into `<airupnp>` only, `stop_receiver` into `<aircast>` only.
`upnp_max` is a global option because upstream only ever reads
`glMRConfig.UPnPMax`. All seven default to the upstream value, so a
configuration that predates them renders the same XML.
