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
