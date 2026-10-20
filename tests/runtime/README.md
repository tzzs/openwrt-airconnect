# Runtime adapter tests

From the repository root, on a host with the OpenWrt `ucode` interpreter:

```sh
~/.local/opt/ucode-host/bin/ucode -L ~/.local/opt/ucode-host/lib/ucode tests/runtime/run.uc
```

The runner loads `runtime.uc` and drives it with a fake UCI cursor and a unique
temporary directory under `/tmp`, which it removes when it finishes. It never
reads router configuration, writes outside its sandbox, starts AirConnect or
contacts the network. Nonzero exit means failure; output uses TAP-style
assertions.

## Why `loadfile()` instead of `import`

`runtime.uc` has to be both a module and a directly executed CLI, and ucode
makes those two modes mutually exclusive at compile time: a file containing
`export` cannot be executed, and a file without `export` cannot be imported by
name. `runtime.uc` therefore stays in script mode and returns its API object
from a trailing expression, which `loadfile(path)()` exposes. See the header of
`runtime.uc` for the full reasoning.

## Coverage

- **`loadConfig`** — reads the `main` section and every `device` section through
  an injected cursor, drops UCI metadata (`.name`, `.type`, `.anonymous`),
  keeps the section name as the device id, forwards an explicit package name,
  returns raw strings without validating, and tolerates a missing main section.
- **`applyConfig` happy path** — both engines are written with bytes identical
  to `renderXml()`, a missing directory is created 0750, an already normalized
  configuration is accepted, only the requested engines are rendered, and no
  temporary file survives.
- **Validation failure** — `max_volume = '0'` produces `ok:false`, writes no
  file, creates no directory and leaves a pre-existing valid XML byte-identical.
  This is the "keep last good file" proof.
- **Asymmetric render failure** — a configuration whose `main.codec` is `pcm`
  renders for UPnP but is rejected for Cast, so the UPnP file is updated, the
  Cast file is untouched, and `ok:false` names the Cast path. Note this is *not*
  the mechanism the original task description suggested: giving a cast *device*
  `codec: 'pcm'` makes `renderXml()` reject both engines, because the renderer
  revalidates the whole configuration.
- **`dry_run`** — renders into `rendered` and writes nothing, not even the
  directory.
- **Modes** — XML files and `status.json` are 0640, nothing is world-readable.
- **`status.json`** — valid JSON with an integer `applied_at`, the written
  engines, and a `config_digest` that is stable for identical input and changes
  when the rendered XML changes. No status file is written when an engine fails.
- **Persistent config is read-only** — a populated `/etc/config` sandbox is
  untouched by `applyConfig`.
- **CLI contract** — `apply` prints JSON and returns 0/1, `validate` returns 0/1
  with human text, `show` prints one engine's XML, and unknown commands or wrong
  arity return exit 2.
