# Package tests

Host-side checks for `packages/airconnect-manager`. They need neither OpenWrt,
nor a router, nor a C toolchain: everything runs from a checkout on Linux or
macOS. The router itself only has BusyBox ash, so the packaged scripts are
plain POSIX sh and are tested here under the same constraints.

```sh
bash tests/package/check-package.sh    # static contract checks
sh tests/package/run-init-script.sh    # behavioural checks of the init script
```

Both exit nonzero on the first failing check they report.

## check-package.sh

Static assertions over the recipe and the packaged files:

- the Makefile declares `conffiles` for `/etc/config/airconnect-manager`, never
  for generated files under `/var/etc`, and ships no `postinst`, because
  installing a package must not start broadcasting AirPlay;
- the default UCI file contains exactly the sixteen documented options with the
  documented defaults, in one `config main 'main'` section, single-quoted; the
  seven advanced options all carry the upstream engine default, so a
  configuration written before they existed normalizes to the same values;
- the engine command line passes `-Z` and `-x <generated xml>`, never `-z` (the
  engine must not self-daemonize behind procd) and never `-b` (the binding lives
  in the generated XML);
- `reload_service` publishes its instance set through `rc_procd`;
- the init script never writes to UCI or `/etc/config`, never uses `eval`, and
  validates the interface token before using it;
- every file named by the Install rule exists and every payload file is
  actually installed;
- the recipe pins the version, license, maintainer, section, architecture
  restriction and dependency list, and downloads nothing;
- the scripts parse under `dash` (or BusyBox `ash` when `dash` is absent).

The `-z` check is scoped to the command line on purpose: `[ -z "$var" ]` is a
shell test, not an engine flag, and must not trip it.

## run-init-script.sh

Sources the real init script and replaces only its outside world: the UCI
helpers, procd's wrappers, `logger`, and the `runtime.uc` renderer. Assertions
inspect what the init script asked procd to do.

It covers the disabled default, one engine and both engines, the full procd
parameter set, a missing/non-executable renderer, a renderer that rejects the
configuration, a renderer that writes no XML, a missing engine binary,
enabled-without-an-engine, a reload through `rc_procd`, and hostile interface
values (`;reboot`, `$(id)`, backticks, `../`, `.`, `..`, overlong).

Two properties are worth calling out because they are easy to get wrong:

- **A rejected configuration publishes nothing.** rc.common calls
  `procd_close_service` unconditionally, so the registered instances *are* the
  complete set and procd stops every instance missing from it. An engine that
  is still serving from the last valid XML must therefore survive a failed
  render, which is why every fatal check runs before the first
  `procd_open_instance`.
- **The instance list is all-or-nothing.** Starting only the engines that
  happen to be present would silently halve the service.

`AIRCONNECT_MANAGER_ROOT` prefixes `/var` and `/usr` so the tests never touch
the host system. It is empty on the router, where the defaults are the real
paths, and is only honoured as an absolute path to an existing directory — the
same idea as `IPKG_INSTROOT` in `rc.common`.

Renderer behaviour is selected per sandbox (`ok`, `fail`, `empty`, `absent`,
`noexec`), so `absent` reproduces today's state, where `runtime.uc` belongs to
a later task and must not be referenced by the recipe.
