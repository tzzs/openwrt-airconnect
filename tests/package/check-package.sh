#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Static packaging checks that need neither OpenWrt nor a router.
# Host only: this script uses bash. The packaged scripts themselves are ash.
#
# Usage: bash tests/package/check-package.sh
# Exit status: 0 when every check passes, 1 otherwise.

set -u
set -o pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "${here}/../.." && pwd)

pkg="${root}/packages/airconnect-manager"
makefile="${pkg}/Makefile"
config="${pkg}/files/etc/config/airconnect-manager"
initscript="${pkg}/files/etc/init.d/airconnect-manager"
ucidefaults="${pkg}/files/etc/uci-defaults/90-airconnect-manager"

passed=0
failed=0

ok() {
	passed=$((passed + 1))
	printf 'ok   - %s\n' "$1"
}

no() {
	failed=$((failed + 1))
	printf 'FAIL - %s\n' "$1"
	[ $# -gt 1 ] && printf '       %s\n' "$2"
}

section() {
	printf '\n# %s\n' "$1"
}

# --- payload files exist ----------------------------------------------------
section 'payload files'
for path in "${makefile}" "${config}" "${initscript}" "${ucidefaults}"; do
	if [ -f "${path}" ]; then
		ok "exists: ${path#"${root}"/}"
	else
		no "exists: ${path#"${root}"/}" 'missing file'
	fi
done
if [ "${failed}" -ne 0 ]; then
	printf '\ncheck-package: %d passed, %d failed\n' "${passed}" "${failed}"
	exit 1
fi

# --- (a) conffiles ----------------------------------------------------------
section 'conffiles'
conffiles_block=$(awk '
	/^define Package\/airconnect-manager\/conffiles$/ { inside = 1; next }
	inside && /^endef$/ { inside = 0 }
	inside { print }
' "${makefile}")

if [ -n "${conffiles_block}" ] && printf '%s\n' "${conffiles_block}" | grep -qx '/etc/config/airconnect-manager'; then
	ok 'conffiles declares /etc/config/airconnect-manager'
else
	no 'conffiles declares /etc/config/airconnect-manager' 'conffiles block missing or incomplete'
fi
if printf '%s\n' "${conffiles_block}" | grep -q '/var/etc'; then
	no 'conffiles excludes generated runtime XML' 'generated files must never be conffiles'
else
	ok 'conffiles excludes generated runtime XML'
fi
if grep -q 'define Package/airconnect-manager/postinst' "${makefile}"; then
	no 'package ships no postinst' 'installing must not start the service'
else
	ok 'package ships no postinst'
fi

# --- (b) default UCI config -------------------------------------------------
section 'default config'
expected_options='enabled=0
interface=br-lan
airupnp=1
aircast=0
codec=flac
latency=1000:2000
max_volume=100
media_volume=0.5
log_level=warn'

# Parse strictly: comments and blank lines are skipped, the section must be
# `config main 'main'`, every option must be single-quoted, and anything else is
# reported so a stray key cannot slip through unnoticed.
actual_options=$(awk '
	/^[[:space:]]*#/ { next }
	/^[[:space:]]*$/ { next }
	/^config[[:space:]]/ {
		if ($0 !~ /^config main .main.[[:space:]]*$/)
			printf "UNEXPECTED_SECTION:%s\n", $0
		next
	}
	/^[[:space:]]*option[[:space:]]/ {
		line = $0
		sub(/^[[:space:]]*option[[:space:]]+/, "", line)
		name = line
		sub(/[[:space:]].*$/, "", name)
		value = line
		sub(/^[^[:space:]]+[[:space:]]+/, "", value)
		if (value !~ /^\x27[^\x27]*\x27$/) {
			printf "UNQUOTED_VALUE:%s\n", line
			next
		}
		gsub(/\x27/, "", value)
		printf "%s=%s\n", name, value
		next
	}
	{ printf "UNEXPECTED_LINE:%s\n", $0 }
' "${config}")

if [ "${actual_options}" = "${expected_options}" ]; then
	ok 'default config has exactly the nine documented options and defaults'
else
	no 'default config has exactly the nine documented options and defaults' \
		"$(printf '%s\n' "${actual_options}" | tr '\n' ' ')"
fi
if [ "$(printf '%s\n' "${actual_options}" | grep -c '=')" -eq 9 ]; then
	ok 'default config declares nine options'
else
	no 'default config declares nine options' 'wrong option count'
fi

# --- (c) -Z is mandatory, -z must never appear ------------------------------
section 'engine command line'
command_lines=$(grep -n 'procd_set_param command' "${initscript}")
if [ -z "${command_lines}" ]; then
	no 'init script registers a procd command' 'no procd_set_param command line'
else
	if printf '%s\n' "${command_lines}" | grep -q -- ' -Z '; then
		ok 'engine command passes -Z (non-interactive, procd-owned)'
	else
		no 'engine command passes -Z (non-interactive, procd-owned)' 'missing -Z'
	fi
	if printf '%s\n' "${command_lines}" | grep -q -- ' -x '; then
		ok 'engine command passes -x with the generated XML'
	else
		no 'engine command passes -x with the generated XML' 'missing -x'
	fi
	if printf '%s\n' "${command_lines}" | grep -q -- ' -b '; then
		no 'engine command leaves -b to the generated XML' 'binding must come from the XML'
	else
		ok 'engine command leaves -b to the generated XML'
	fi
fi

# `[ -z "$var" ]` is a shell test, not an engine flag, so the -z check is
# scoped to the lines that can become an engine command line.
if grep -E 'procd_set_param command' "${initscript}" | grep -q -- ' -z\( \|$\)'; then
	no 'engine command never passes -z' 'the engine must not self-daemonize'
else
	ok 'engine command never passes -z'
fi
if grep -q 'procd_set_param respawn 3600 5 5' "${initscript}"; then
	ok 'init script sets procd respawn 3600 5 5'
else
	no 'init script sets procd respawn 3600 5 5' 'missing respawn policy'
fi
if grep -q 'procd_set_param file ' "${initscript}"; then
	ok 'init script tracks the generated XML so a rewrite restarts the engine'
else
	no 'init script tracks the generated XML so a rewrite restarts the engine' 'missing procd_set_param file'
fi
if grep -q 'procd_add_reload_trigger' "${initscript}"; then
	ok 'init script declares a procd reload trigger'
else
	no 'init script declares a procd reload trigger' 'missing procd_add_reload_trigger'
fi
if grep -q 'reload_service' "${initscript}" && grep -q 'rc_procd start_service' "${initscript}"; then
	ok 'reload_service publishes the instance set through rc_procd'
elif grep -q 'reload_service' "${initscript}"; then
	no 'reload_service publishes the instance set through rc_procd' \
		'a bare start_service call is not wrapped by rc.common, so procd never sees the new set'
else
	no 'reload_service publishes the instance set through rc_procd' 'missing reload_service'
fi

# --- (d) the init script never writes the persistent config ----------------
section 'persistent config is read only'
if grep -Eq '^[[:space:]]*[^#]*\buci[[:space:]]+(set|add|delete|commit|revert|batch|rename|import)' "${initscript}"; then
	no 'init script never modifies UCI' '/etc/config is the only persistent source'
else
	ok 'init script never modifies UCI'
fi
if grep -Eq '>>?[[:space:]]*"?[^ ]*etc/config' "${initscript}"; then
	no 'init script never redirects output into /etc/config' 'found a redirect to /etc/config'
else
	ok 'init script never redirects output into /etc/config'
fi
if grep -Eq '^[[:space:]]*[^#]*/etc/config/airconnect-manager' "${initscript}"; then
	no 'init script reads the config only through config_load' 'direct path reference found'
else
	ok 'init script reads the config only through config_load'
fi
if grep -Eq '\beval\b' "${initscript}"; then
	no 'init script uses no eval' 'eval is forbidden'
else
	ok 'init script uses no eval'
fi
if grep -q 'valid_interface' "${initscript}"; then
	ok 'init script validates the interface token before use'
else
	no 'init script validates the interface token before use' 'no interface validation'
fi

# --- (e) every file referenced by the Install rule exists -------------------
section 'install rule'
install_block=$(awk '
	/^define Package\/airconnect-manager\/install$/ { inside = 1; next }
	inside && /^endef$/ { inside = 0 }
	inside { print }
' "${makefile}")

if [ -z "${install_block}" ]; then
	no 'package defines an Install rule' 'no Package/airconnect-manager/install'
else
	ok 'package defines an Install rule'
	install_paths=$(printf '%s\n' "${install_block}" | grep -o '\./files/[^[:space:]]*' | sort -u)
	if [ -z "${install_paths}" ]; then
		no 'Install rule references files under ./files' 'no ./files paths found'
	else
		while IFS= read -r relative; do
			[ -n "${relative}" ] || continue
			if [ -e "${pkg}/${relative}" ]; then
				ok "install source exists: ${relative#./files/}"
			else
				no "install source exists: ${relative#./files/}" 'referenced by the Install rule but missing'
			fi
		done <<EOF
${install_paths}
EOF
	fi
	# Each payload file must actually be inside the Install rule, not merely
	# present on disk: a file nobody installs is dead weight.
	for payload in \
		files/etc/config/airconnect-manager \
		files/etc/init.d/airconnect-manager \
		files/etc/uci-defaults/90-airconnect-manager \
		files/usr/share/airconnect-manager/config.uc \
		files/usr/share/airconnect-manager/discovery.uc \
		files/usr/share/airconnect-manager/state.uc \
		files/usr/share/airconnect-manager/files.uc \
		files/usr/share/airconnect-manager/VERSION \
		files/usr/share/airconnect-manager/runtime.uc \
		files/usr/share/rpcd/ucode/airconnect-manager
	do
		if printf '%s\n' "${install_block}" | grep -q "${payload}"; then
			ok "payload is installed: ${payload#files/}"
		else
			no "payload is installed: ${payload#files/}" 'present on disk but not in the Install rule'
		fi
	done
fi

# runtime.uc is the renderer the init script executes. T2 landed it, so the
# recipe must now install it as an executable; an INSTALL_DATA line would drop
# the exec bit and make prepare_runtime() fail on the router.
if grep -qF '$(INSTALL_BIN) ./files/usr/share/airconnect-manager/runtime.uc' "${makefile}"; then
	ok 'recipe installs runtime.uc as an executable'
else
	no 'recipe installs runtime.uc as an executable' 'the init script executes it directly, so it needs INSTALL_BIN'
fi

# rpcd skips non-regular and world-writable entries, so the plugin has to land as
# a regular 0755 file. INSTALL_DATA would drop the exec bit and rpcd would then
# silently skip the whole object - every UI call would fail with NO_DATA.
if grep -qF '$(INSTALL_BIN) ./files/usr/share/rpcd/ucode/airconnect-manager $(1)/usr/share/rpcd/ucode/airconnect-manager' "${makefile}"; then
	ok 'recipe installs the rpcd plugin with INSTALL_BIN'
else
	no 'recipe installs the rpcd plugin with INSTALL_BIN' 'rpcd skips a non-executable entry'
fi
if [ -f "${pkg}/files/usr/share/rpcd/ucode/airconnect-manager" ]; then
	ok 'the rpcd plugin is a regular file'
else
	no 'the rpcd plugin is a regular file' 'missing files/usr/share/rpcd/ucode/airconnect-manager'
fi
plugin_mode=$(stat -c '%a' "${pkg}/files/usr/share/rpcd/ucode/airconnect-manager" 2>/dev/null ||
	stat -f '%Lp' "${pkg}/files/usr/share/rpcd/ucode/airconnect-manager" 2>/dev/null)
case "${plugin_mode}" in
	755|0755) ok 'the rpcd plugin is mode 0755 in the tree' ;;
	*) no 'the rpcd plugin is mode 0755 in the tree' "mode is ${plugin_mode:-unknown}" ;;
esac
if grep -qF '$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode' "${makefile}"; then
	ok 'recipe creates the rpcd plugin directory'
else
	no 'recipe creates the rpcd plugin directory' 'missing /usr/share/rpcd/ucode'
fi
if [ -f "${pkg}/files/usr/share/airconnect-manager/VERSION" ] &&
	printf '0.1.0\n' | cmp -s - "${pkg}/files/usr/share/airconnect-manager/VERSION"; then
	ok 'VERSION contains 0.1.0'
else
	no 'VERSION contains 0.1.0' 'the status reply reads this file'
fi
if grep -qF '$(INSTALL_DATA) ./files/usr/share/airconnect-manager/VERSION' "${makefile}"; then
	ok 'recipe installs VERSION'
else
	no 'recipe installs VERSION' 'status would report the version as unknown'
fi

# --- recipe shape -----------------------------------------------------------
section 'recipe'
if grep -qx 'PKG_NAME:=airconnect-manager' "${makefile}" &&
	grep -qx 'PKG_VERSION:=0.1.0' "${makefile}" &&
	grep -qx 'PKG_RELEASE:=1' "${makefile}"; then
	ok 'recipe pins name, PKG_VERSION 0.1.0 and PKG_RELEASE 1'
else
	no 'recipe pins name, PKG_VERSION 0.1.0 and PKG_RELEASE 1' 'wrong or missing version fields'
fi
if grep -qx 'PKG_LICENSE:=MIT' "${makefile}"; then
	ok 'recipe declares PKG_LICENSE MIT'
else
	no 'recipe declares PKG_LICENSE MIT' 'missing license'
fi
if grep -qx 'PKG_MAINTAINER:=AirConnect OpenWrt maintainers' "${makefile}"; then
	ok 'recipe has a non-personal maintainer line'
else
	no 'recipe has a non-personal maintainer line' 'missing or personal maintainer'
fi
if grep -Eq '^PKG_SOURCE(_URL|_HASH|_PROTO|_MIRROR)?:=' "${makefile}"; then
	no 'recipe downloads no sources' 'it installs the checked-in ./files tree'
else
	ok 'recipe downloads no sources'
fi
if grep -Eq '^[[:space:]]*SECTION:=utils$' "${makefile}" && grep -Eq '^[[:space:]]*CATEGORY:=Utilities$' "${makefile}"; then
	ok 'recipe uses SECTION utils and CATEGORY Utilities'
else
	no 'recipe uses SECTION utils and CATEGORY Utilities' 'wrong section or category'
fi
if grep -Eq '^[[:space:]]*TITLE:=AirConnect management adapter$' "${makefile}"; then
	ok 'recipe uses the documented TITLE'
else
	no 'recipe uses the documented TITLE' 'wrong title'
fi
if grep -Eq '^[[:space:]]*DEPENDS:=@\(aarch64\|\|x86_64\)' "${makefile}"; then
	ok 'recipe keeps the engine architecture restriction'
else
	no 'recipe keeps the engine architecture restriction' 'missing @(aarch64||x86_64)'
fi
missing_dependencies=''
for dependency in airconnect-engine ucode ucode-mod-fs ucode-mod-socket ucode-mod-ubus ucode-mod-uci rpcd rpcd-mod-ucode curl; do
	grep -Eq "^[[:space:]]*DEPENDS:=.*\+${dependency}([[:space:]]|$)" "${makefile}" ||
		missing_dependencies="${missing_dependencies} +${dependency}"
done
if [ -z "${missing_dependencies}" ]; then
	ok 'recipe depends on every documented package'
else
	no 'recipe depends on every documented package' "missing:${missing_dependencies}"
fi
if grep -q 'BuildPackage,airconnect-manager' "${makefile}"; then
	ok 'recipe calls BuildPackage'
else
	no 'recipe calls BuildPackage' 'missing BuildPackage'
fi
opens=$(grep -c '^[[:space:]]*define ' "${makefile}")
closes=$(grep -c '^[[:space:]]*endef' "${makefile}")
if [ "${opens}" -eq "${closes}" ]; then
	ok "recipe define/endef blocks are balanced (${opens})"
else
	no "recipe define/endef blocks are balanced (${opens})" "${opens} define vs ${closes} endef"
fi

# --- shell portability ------------------------------------------------------
section 'shell portability'
if head -1 "${initscript}" | grep -qx '#!/bin/sh /etc/rc.common'; then
	ok 'init script uses the /etc/rc.common shebang'
else
	no 'init script uses the /etc/rc.common shebang' 'OpenWrt init scripts must source rc.common'
fi
if head -1 "${ucidefaults}" | grep -qx '#!/bin/sh'; then
	ok 'uci-defaults script uses a POSIX #!/bin/sh shebang'
else
	no 'uci-defaults script uses a POSIX #!/bin/sh shebang' 'wrong shebang'
fi
# BusyBox ash only on the router: parse with a strict POSIX shell when present.
if command -v dash >/dev/null 2>&1; then
	syntax_shell='dash'
elif command -v busybox >/dev/null 2>&1; then
	syntax_shell='busybox'
else
	syntax_shell=''
fi
if [ -n "${syntax_shell}" ]; then
	syntax_failures=0
	for script in "${initscript}" "${ucidefaults}"; do
		if [ "${syntax_shell}" = busybox ]; then
			busybox ash -n "${script}" || syntax_failures=1
		else
			dash -n "${script}" || syntax_failures=1
		fi
	done
	if [ "${syntax_failures}" -eq 0 ]; then
		ok "packaged scripts parse under ${syntax_shell}"
	else
		no "packaged scripts parse under ${syntax_shell}" 'syntax error'
	fi
else
	printf 'skip - no dash or busybox for a POSIX syntax check\n'
fi
if grep -q 'USE_PROCD=1' "${initscript}" && grep -q '^START=95' "${initscript}" && grep -q '^STOP=10' "${initscript}"; then
	ok 'init script declares USE_PROCD, START=95 and STOP=10'
else
	no 'init script declares USE_PROCD, START=95 and STOP=10' 'wrong procd metadata'
fi
if grep -qx 'exit 0' "${ucidefaults}"; then
	ok 'uci-defaults script ends with exit 0'
else
	no 'uci-defaults script ends with exit 0' 'the file must be removed after a successful run'
fi
if grep -q 'chmod 0750' "${ucidefaults}"; then
	ok 'uci-defaults sets the runtime directory to 0750'
else
	no 'uci-defaults sets the runtime directory to 0750' 'missing chmod 0750'
fi
if grep -Eq "enabled='1'|uci set.*enabled" "${ucidefaults}"; then
	no 'uci-defaults does not enable the service' 'installing must not start broadcasting'
else
	ok 'uci-defaults does not enable the service'
fi

printf '\ncheck-package: %d passed, %d failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ] || exit 1
exit 0
