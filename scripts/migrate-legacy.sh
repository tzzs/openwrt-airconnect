#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# migrate-legacy.sh - detect a legacy AirConnect installation and migrate its
# settings into /etc/config/airconnect-manager.
#
# This script runs on the router, so it is POSIX sh (BusyBox ash), not bash.
# The host test suite runs it with `sh` and a sandbox root.
#
#   --dry-run         detect and print the mapping; change nothing (default)
#   --apply           back up, write the mapped /etc/config/airconnect-manager,
#                     stop and disable the legacy service, and stop (never
#                     remove) a matching Docker container. It never starts the
#                     new service: that is the operator step after verifying.
#   --rollback        restore the most recent --apply backup and re-enable the
#                     legacy service. Idempotent.
#   --force-stop-new  let --apply stop a running airconnect-manager first
#
# Safety properties:
#   * no network access, no eval, no package removal, no container removal;
#   * every write is a complete temp file in the destination directory plus a
#     rename, so a half-written file is never left behind;
#   * a second --apply refuses until --rollback, so edits made after the
#     migration are never silently overwritten;
#   * an existing backup directory is never overwritten;
#   * untrusted values from the legacy UCI file are validated and only ever
#     passed as single quoted arguments, never into a shell string.
#
# The legacy values are the operator's own configuration, but they are still
# treated as input: an interface token, a UDN, a boolean and a volume are each
# checked against the same limits config.uc enforces before they are written.
#
# AIRCONNECT_MIGRATE_ROOT prefixes every absolute path. It is empty on the
# router and is only honoured as a plain absolute path to an existing
# directory; it is the sandbox seam the host tests use, the same idea as
# IPKG_INSTROOT in rc.common.

set -u

PROGRAM='migrate-legacy.sh'
MODE='dry-run'
MODE_SET=''
FORCE_STOP_NEW='0'

# Keep these in sync with packages/airconnect-manager/files/etc/config/airconnect-manager.
# tests/package/check-package.sh pins that file, so a change there fails a test.
DEFAULT_INTERFACE='br-lan'
DEFAULT_AIRUPNP='1'
DEFAULT_AIRCAST='0'
DEFAULT_CODEC='flac'
DEFAULT_LATENCY='1000:2000'
DEFAULT_MAX_VOLUME='100'
DEFAULT_MEDIA_VOLUME='0.5'
DEFAULT_LOG_LEVEL='warn'

# --- output ----------------------------------------------------------------

say() {
	printf '%s\n' "$*"
}

warn() {
	printf '%s: warning: %s\n' "${PROGRAM}" "$*" >&2
}

fail() {
	printf '%s: %s\n' "${PROGRAM}" "$*" >&2
	exit 1
}

usage() {
	printf 'usage: sh %s [--dry-run|--apply|--rollback] [--force-stop-new]\n' "${PROGRAM}"
	printf '\n'
	printf '  --dry-run         detect and print the mapping; change nothing (default)\n'
	printf '  --apply           back up, map, stop the legacy instance; never starts the new one\n'
	printf '  --rollback        restore the most recent --apply backup; idempotent\n'
	printf '  --force-stop-new  with --apply: stop a running airconnect-manager first\n'
}

usage_error() {
	printf '%s: %s\n' "${PROGRAM}" "$1" >&2
	usage >&2
	exit 2
}

# --- arguments -------------------------------------------------------------

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dry-run|--apply|--rollback)
			[ -z "${MODE_SET}" ] || usage_error 'choose exactly one of --dry-run, --apply and --rollback'
			MODE_SET="$1"
			MODE="${1#--}"
			;;
		--force-stop-new)
			FORCE_STOP_NEW='1'
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			usage_error "unknown argument: $1"
			;;
	esac
	shift
done

# --- sandbox root ----------------------------------------------------------

ROOT=''
if [ -n "${AIRCONNECT_MIGRATE_ROOT:-}" ]; then
	case "${AIRCONNECT_MIGRATE_ROOT}" in
		/*)
			[ -d "${AIRCONNECT_MIGRATE_ROOT}" ] ||
				fail "AIRCONNECT_MIGRATE_ROOT is not an existing directory: ${AIRCONNECT_MIGRATE_ROOT}"
			ROOT="${AIRCONNECT_MIGRATE_ROOT}"
			while [ "${#ROOT}" -gt 1 ] && [ "${ROOT%/}" != "${ROOT}" ]; do
				ROOT="${ROOT%/}"
			done
			;;
		*)
			fail 'AIRCONNECT_MIGRATE_ROOT must be an absolute path'
			;;
	esac
	# The root ends up in the generated file's audit comment, so a path with
	# unexpected bytes is refused instead of being quoted into a comment.
	case "${ROOT}" in
		*[!A-Za-z0-9_./-]*)
			fail 'AIRCONNECT_MIGRATE_ROOT must contain only letters, digits, dot, slash, underscore and dash'
			;;
	esac
fi

CONFIG_DIR="${ROOT}/etc/config"
LEGACY_CONFIG="${CONFIG_DIR}/airconnect"
TARGET_CONFIG="${CONFIG_DIR}/airconnect-manager"
LEGACY_INIT="${ROOT}/etc/init.d/airconnect"
TARGET_INIT="${ROOT}/etc/init.d/airconnect-manager"
BACKUP_ROOT="${ROOT}/etc/airconnect-manager-backup"
LEGACY_BIN_DIR="${ROOT}/usr/bin"
# The generated file keeps the mode the packaged conffile already had, so a
# migration does not silently change who can read it. 0600 is the fallback when
# there is no previous file to copy the mode from.
TARGET_MODE='0600'

# --- small helpers ---------------------------------------------------------

have() {
	command -v "$1" >/dev/null 2>&1
}

file_mode() {
	# GNU/BusyBox stat first, then BSD/macOS stat. Prints nothing on failure.
	fm_mode=$(stat -c '%a' "$1" 2>/dev/null) || fm_mode=''
	if [ -z "${fm_mode}" ]; then
		fm_mode=$(stat -f '%Lp' "$1" 2>/dev/null) || fm_mode=''
	fi
	[ -n "${fm_mode}" ] || return 1
	printf '%s' "${fm_mode}"
}

normalize_bool() {
	case "$1" in
		1|on|true|enabled|yes) printf '1' ;;
		0|off|false|disabled|no) printf '0' ;;
		*) return 1 ;;
	esac
}

# The same token config.uc accepts for main.interface: 1..15 ASCII bytes,
# starting with a letter, digit or underscore, then letters, digits, _ . -
valid_interface() {
	case "$1" in
		''|.|..) return 1 ;;
		[A-Za-z0-9_]*) ;;
		*) return 1 ;;
	esac
	case "$1" in
		*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
	[ "${#1}" -ge 1 ] && [ "${#1}" -le 15 ]
}

# A UPnP UDN as the engines use it: a uuid: prefix and no control bytes or
# characters that would need XML escaping. Anything else is not guessed at.
valid_udn() {
	case "$1" in
		uuid:?*) ;;
		*) return 1 ;;
	esac
	[ "${#1}" -le 255 ] || return 1
	case "$1" in
		*[!A-Za-z0-9._:-]*) return 1 ;;
	esac
	return 0
}

# config.uc accepts 1..100, canonical decimal (no leading zero).
valid_volume() {
	case "$1" in
		0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;;
		*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 100 ]
}

valid_container_name() {
	case "$1" in
		[A-Za-z0-9]*) ;;
		*) return 1 ;;
	esac
	[ "${#1}" -le 128 ] || return 1
	case "$1" in
		*[!A-Za-z0-9_.-]*) return 1 ;;
	esac
	return 0
}

# uci_get <package>.<section>.<option>
# Prints the value and returns 0 only when the option exists and is non-empty.
# BusyBox `uci -q get` returns nonzero for a missing key, which is handled here
# instead of being mistaken for an empty string.
uci_get() {
	ug_value=$(uci -q get "$1" 2>/dev/null) || return 1
	[ -n "${ug_value}" ] || return 1
	printf '%s' "${ug_value}"
}

# --- detection -------------------------------------------------------------

LEGACY_CONFIG_FOUND='0'
LEGACY_INIT_FOUND='0'
LEGACY_ENABLED='no'
LEGACY_RUNNING='no'
DOCKER_STATE='absent'
DOCKER_NAMES=''
OLD_BINARIES=''
TARGET_RUNNING='0'

detect() {
	say '== legacy detection =='

	# 1. the old UCI service
	if [ -f "${LEGACY_CONFIG}" ] && [ -f "${LEGACY_INIT}" ]; then
		say "legacy: ${LEGACY_CONFIG} and ${LEGACY_INIT} are present (old UCI service)"
		LEGACY_CONFIG_FOUND='1'
		LEGACY_INIT_FOUND='1'
	elif [ -f "${LEGACY_CONFIG}" ]; then
		say "legacy: ${LEGACY_CONFIG} is present, ${LEGACY_INIT} is not (leftover configuration)"
		LEGACY_CONFIG_FOUND='1'
	elif [ -f "${LEGACY_INIT}" ]; then
		say "legacy: ${LEGACY_INIT} is present, ${LEGACY_CONFIG} is not (service without configuration)"
		LEGACY_INIT_FOUND='1'
	else
		say "legacy: no ${LEGACY_CONFIG} and no ${LEGACY_INIT}"
	fi

	if [ -f "${LEGACY_INIT}" ]; then
		if [ -x "${LEGACY_INIT}" ]; then
			"${LEGACY_INIT}" enabled >/dev/null 2>&1 && LEGACY_ENABLED='yes'
			"${LEGACY_INIT}" running >/dev/null 2>&1 && LEGACY_RUNNING='yes'
		else
			warn "${LEGACY_INIT} is not executable; it cannot be queried or stopped"
		fi
		say "legacy: service enabled at boot: ${LEGACY_ENABLED}; running now: ${LEGACY_RUNNING}"
	fi

	# 2. a Docker container whose name or image mentions airconnect
	if have docker; then
		DOCKER_STATE='ok'
		# A pipe is a safe separator here: neither a container name nor an image
		# reference may contain one, and the format string is a literal.
		dd_output=$(docker ps --format '{{.Names}}|{{.Image}}' 2>/dev/null) || {
			DOCKER_STATE='error'
			dd_output=''
		}
		if [ "${DOCKER_STATE}" = 'error' ]; then
			say "legacy: docker is installed but 'docker ps' failed; containers cannot be inspected"
		else
			dd_matches='0'
			while IFS= read -r dd_line; do
				[ -n "${dd_line}" ] || continue
				case "${dd_line}" in
					*'|'*) ;;
					*)
						warn 'ignoring an unexpected docker line (no name|image separator)'
						continue
						;;
				esac
				dd_name=${dd_line%%|*}
				dd_image=${dd_line#*|}
				if ! valid_container_name "${dd_name}"; then
					warn "ignoring an unexpected docker container name: ${dd_name}"
					continue
				fi
				case "${dd_image}" in
					''|*[!A-Za-z0-9._/:@-]*)
						warn "ignoring an unexpected docker image for ${dd_name}"
						continue
						;;
				esac
				dd_lower=$(printf '%s %s' "${dd_name}" "${dd_image}" | tr '[:upper:]' '[:lower:]')
				case "${dd_lower}" in
					*airconnect*)
						dd_matches='1'
						DOCKER_NAMES="${DOCKER_NAMES}${dd_name}
"
						say "legacy: docker container '${dd_name}' (image ${dd_image}) is running; apply would stop it and keep it"
						;;
				esac
			done <<EOF
${dd_output}
EOF
			[ "${dd_matches}" = '1' ] || say 'legacy: docker is installed; no running container matches airconnect'
		fi
	else
		say 'legacy: docker is not installed (skipped)'
	fi

	# 3. the old /usr/bin layout
	#
	# The packaged engines live in /usr/libexec/airconnect and are never counted
	# as legacy, so a correct install does not report itself as a conflict.
	for db_name in airupnp aircast; do
		db_path="${LEGACY_BIN_DIR}/${db_name}"
		if [ -f "${db_path}" ]; then
			OLD_BINARIES="${OLD_BINARIES} ${db_path}"
			say "legacy: old engine binary ${db_path} is present (owned by the old package; never removed here)"
		elif [ -f "${ROOT}/usr/libexec/airconnect/${db_name}" ]; then
			say "legacy: ${db_path} is absent; the packaged engine is at /usr/libexec/airconnect/${db_name}"
		fi
	done

	# The rpcd backend owns process-level conflict detection; this script does
	# not duplicate it. Say so once, so the report is not read as a second,
	# independent conflict check.
	say 'conflict detection: the airconnect.manager backend also refuses start while a legacy service, legacy binary or foreign engine process exists'
}

# --- mapping ---------------------------------------------------------------

MAPPED_ENABLED=''
MAPPED_ENABLED_SOURCE=''
MAPPED_INTERFACE=''
MAPPED_AIRUPNP=''
MAPPED_AIRCAST=''
MAPPED_UDN=''
MAPPED_MAX_VOLUME="${DEFAULT_MAX_VOLUME}"
MAPPED_DEVICE_VOLUME=''
# A device section is written only when it carries an override. A UDN without
# an override would render exactly the inherited configuration.
MAPPED_DEVICE='0'

mapping() {
	say ''
	say '== configuration mapping =='

	if [ "${LEGACY_CONFIG_FOUND}" != '1' ]; then
		say 'mapping: skipped (no legacy UCI configuration to read)'
		return 0
	fi
	have uci || fail "cannot read ${LEGACY_CONFIG}: the uci command is not available"
	# A corrupt legacy file must not silently migrate as "all defaults".
	uci -q show airconnect >/dev/null 2>&1 ||
		fail "cannot parse ${LEGACY_CONFIG}; fix or restore it before migrating"

	# enabled. With no key in the legacy file the only evidence of intent is the
	# legacy service itself, so its boot and run state decide. Never guess "on"
	# from silence: a migration must not start broadcasting by itself.
	mk_seen='0'
	if mk_value=$(uci_get airconnect.main.enabled); then
		mk_seen='1'
		if mk_norm=$(normalize_bool "${mk_value}"); then
			MAPPED_ENABLED="${mk_norm}"
			MAPPED_ENABLED_SOURCE='legacy configuration'
			say "airconnect.main.enabled=${mk_value} -> airconnect-manager.main.enabled=${mk_norm}"
		else
			say "airconnect.main.enabled=${mk_value} -> skipped (not a boolean: 0/1, on/off, true/false, yes/no)"
		fi
	fi
	if [ -z "${MAPPED_ENABLED}" ]; then
		if [ "${LEGACY_ENABLED}" = 'yes' ] || [ "${LEGACY_RUNNING}" = 'yes' ]; then
			MAPPED_ENABLED='1'
			MAPPED_ENABLED_SOURCE='legacy service enabled or running'
			if [ "${mk_seen}" = '1' ]; then
				say "airconnect.main.enabled=(no usable value) -> airconnect-manager.main.enabled=1 (the legacy service is enabled at boot or running)"
			else
				say "airconnect.main.enabled=(absent) -> airconnect-manager.main.enabled=1 (the legacy service is enabled at boot or running)"
			fi
		else
			MAPPED_ENABLED='0'
			MAPPED_ENABLED_SOURCE='default (legacy service disabled)'
			if [ "${mk_seen}" = '1' ]; then
				say "airconnect.main.enabled=(no usable value) -> airconnect-manager.main.enabled=0 (the legacy service is not enabled and not running)"
			else
				say "airconnect.main.enabled=(absent) -> airconnect-manager.main.enabled=0 (the legacy service is not enabled and not running)"
			fi
		fi
	fi

	# interface: old files use one of interface / iface / binding
	mk_seen='0'
	mk_used_key=''
	for mk_key in interface iface binding; do
		if mk_value=$(uci_get "airconnect.main.${mk_key}"); then
			mk_seen='1'
			if valid_interface "${mk_value}"; then
				if [ -z "${MAPPED_INTERFACE}" ]; then
					MAPPED_INTERFACE="${mk_value}"
					mk_used_key="${mk_key}"
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.main.interface=${mk_value}"
				else
					say "airconnect.main.${mk_key}=${mk_value} -> skipped (airconnect.main.${mk_used_key} was used)"
				fi
			else
				say "airconnect.main.${mk_key}=${mk_value} -> skipped (not a bare interface token of 1..15 ASCII bytes)"
			fi
		fi
	done
	if [ -z "${MAPPED_INTERFACE}" ]; then
		MAPPED_INTERFACE="${DEFAULT_INTERFACE}"
		if [ "${mk_seen}" = '1' ]; then
			say "airconnect.main.interface=(no usable value) -> airconnect-manager.main.interface=${DEFAULT_INTERFACE} (default)"
		else
			say "airconnect.main.interface=(absent) -> airconnect-manager.main.interface=${DEFAULT_INTERFACE} (default)"
		fi
	fi

	# engine toggles
	mk_seen='0'
	mk_used_key=''
	for mk_key in upnp airupnp; do
		if mk_value=$(uci_get "airconnect.main.${mk_key}"); then
			mk_seen='1'
			if mk_norm=$(normalize_bool "${mk_value}"); then
				if [ -z "${MAPPED_AIRUPNP}" ]; then
					MAPPED_AIRUPNP="${mk_norm}"
					mk_used_key="${mk_key}"
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.main.airupnp=${mk_norm}"
				else
					say "airconnect.main.${mk_key}=${mk_value} -> skipped (airconnect.main.${mk_used_key} was used)"
				fi
			else
				say "airconnect.main.${mk_key}=${mk_value} -> skipped (not a boolean)"
			fi
		fi
	done
	if [ -z "${MAPPED_AIRUPNP}" ]; then
		MAPPED_AIRUPNP="${DEFAULT_AIRUPNP}"
		if [ "${mk_seen}" = '1' ]; then
			say "airconnect.main.upnp=(no usable value) -> airconnect-manager.main.airupnp=${DEFAULT_AIRUPNP} (default)"
		else
			say "airconnect.main.upnp=(absent) -> airconnect-manager.main.airupnp=${DEFAULT_AIRUPNP} (default)"
		fi
	fi

	mk_seen='0'
	mk_used_key=''
	for mk_key in aircast cast; do
		if mk_value=$(uci_get "airconnect.main.${mk_key}"); then
			mk_seen='1'
			if mk_norm=$(normalize_bool "${mk_value}"); then
				if [ -z "${MAPPED_AIRCAST}" ]; then
					MAPPED_AIRCAST="${mk_norm}"
					mk_used_key="${mk_key}"
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.main.aircast=${mk_norm}"
				else
					say "airconnect.main.${mk_key}=${mk_value} -> skipped (airconnect.main.${mk_used_key} was used)"
				fi
			else
				say "airconnect.main.${mk_key}=${mk_value} -> skipped (not a boolean)"
			fi
		fi
	done
	if [ -z "${MAPPED_AIRCAST}" ]; then
		MAPPED_AIRCAST="${DEFAULT_AIRCAST}"
		if [ "${mk_seen}" = '1' ]; then
			say "airconnect.main.aircast=(no usable value) -> airconnect-manager.main.aircast=${DEFAULT_AIRCAST} (default)"
		else
			say "airconnect.main.aircast=(absent) -> airconnect-manager.main.aircast=${DEFAULT_AIRCAST} (default)"
		fi
	fi

	# UDN: the only device identity. A speaker name or an address is not one,
	# so neither is ever copied into a device section.
	if mk_value=$(uci_get airconnect.main.udn); then
		if valid_udn "${mk_value}"; then
			MAPPED_UDN="${mk_value}"
			say "airconnect.main.udn=${mk_value} -> airconnect-manager.device_legacy.udn=${mk_value} (device section only if a volume limit exists)"
		else
			say "airconnect.main.udn=${mk_value} -> skipped (not a uuid: UDN of at most 255 bytes)"
		fi
	fi
	if [ -z "${MAPPED_UDN}" ]; then
		mk_keys=$(uci -q show airconnect.main 2>/dev/null |
			sed -n "s/^airconnect\.main\.\([A-Za-z0-9_][A-Za-z0-9_]*\)='uuid:.*/\1/p") || mk_keys=''
		while IFS= read -r mk_key; do
			[ -n "${mk_key}" ] || continue
			[ "${mk_key}" = 'udn' ] && continue
			if mk_value=$(uci_get "airconnect.main.${mk_key}"); then
				if valid_udn "${mk_value}"; then
					MAPPED_UDN="${mk_value}"
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.device_legacy.udn=${mk_value} (found by uuid: prefix; used only with a volume limit)"
					break
				fi
			fi
		done <<EOF
${mk_keys}
EOF
	fi

	# The old single-speaker volume limit. Without a UDN the limit cannot be
	# attributed to one device, so it becomes the global limit and the report
	# says a scan is needed. No name or address is used as a substitute key.
	mk_seen='0'
	mk_key=''
	for mk_candidate in max_volume volume_limit volume; do
		if mk_value=$(uci_get "airconnect.main.${mk_candidate}"); then
			mk_seen='1'
			mk_key="${mk_candidate}"
			if valid_volume "${mk_value}"; then
				if [ -n "${MAPPED_UDN}" ]; then
					MAPPED_DEVICE_VOLUME="${mk_value}"
					MAPPED_DEVICE='1'
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.device_legacy.max_volume=${mk_value} (engine upnp, udn ${MAPPED_UDN})"
					if [ "${MAPPED_AIRUPNP}" != '1' ]; then
						say '  note: main.airupnp is 0, so this device section stays inert until UPnP is enabled'
					fi
				else
					MAPPED_MAX_VOLUME="${mk_value}"
					say "airconnect.main.${mk_key}=${mk_value} -> airconnect-manager.main.max_volume=${mk_value} (no UDN found; per-device attribution needs a scan)"
				fi
			else
				say "airconnect.main.${mk_key}=${mk_value} -> skipped (expected an integer 1..100)"
			fi
			break
		fi
	done
	if [ -z "${MAPPED_DEVICE_VOLUME}" ] && [ "${mk_seen}" = '0' ]; then
		say "airconnect.main.max_volume=(absent) -> airconnect-manager.main.max_volume=${DEFAULT_MAX_VOLUME} (default)"
	fi
	if [ -n "${MAPPED_UDN}" ] && [ "${MAPPED_DEVICE}" != '1' ]; then
		say 'device section: skipped (a UDN alone needs no override; no per-device volume limit was found)'
	fi
}

# The exact values that --apply writes. Printed by both modes, so a dry run is
# a complete preview and the apply report is auditable on its own.
print_result() {
	say ''
	say '== resulting airconnect-manager configuration =='
	say "main.enabled=${MAPPED_ENABLED}"
	say "main.interface=${MAPPED_INTERFACE}"
	say "main.airupnp=${MAPPED_AIRUPNP}"
	say "main.aircast=${MAPPED_AIRCAST}"
	say "main.codec=${DEFAULT_CODEC}"
	say "main.latency=${DEFAULT_LATENCY}"
	say "main.max_volume=${MAPPED_MAX_VOLUME}"
	say "main.media_volume=${DEFAULT_MEDIA_VOLUME}"
	say "main.log_level=${DEFAULT_LOG_LEVEL}"
	if [ "${MAPPED_DEVICE}" = '1' ]; then
		say 'device_legacy.engine=upnp'
		say "device_legacy.udn=${MAPPED_UDN}"
		say 'device_legacy.enabled=1'
		say "device_legacy.max_volume=${MAPPED_DEVICE_VOLUME}"
	fi
}

# --- backups ---------------------------------------------------------------

APPLIED_BACKUP=''

find_applied_backup() {
	APPLIED_BACKUP=''
	[ -d "${BACKUP_ROOT}" ] || return 0
	for fb_dir in "${BACKUP_ROOT}"/*; do
		[ -d "${fb_dir}" ] || continue
		[ -f "${fb_dir}/applied" ] || continue
		[ -f "${fb_dir}/rolled-back" ] && continue
		APPLIED_BACKUP="${fb_dir}"
	done
	return 0
}

BK_DIR=''
BK_STAMP=''

create_backup() {
	BK_STAMP=$(date -u '+%Y%m%dT%H%M%SZ' 2>/dev/null) || BK_STAMP=''
	[ -n "${BK_STAMP}" ] || fail 'cannot read the current UTC time'
	BK_DIR="${BACKUP_ROOT}/${BK_STAMP}"

	mkdir -p "${BACKUP_ROOT}" 2>/dev/null ||
		fail "cannot create ${BACKUP_ROOT}"
	if ! (umask 077 && mkdir "${BK_DIR}" 2>/dev/null); then
		fail "refusing to overwrite the existing backup directory ${BK_DIR}; wait one second and re-run"
	fi
	(umask 077 && mkdir -p "${BK_DIR}/etc/config") ||
		fail "cannot create ${BK_DIR}/etc/config"

	BK_LEGACY=''
	BK_TARGET=''
	LEGACY_CONFIG_MODE=''
	TARGET_CONFIG_MODE=''
	if [ -f "${LEGACY_CONFIG}" ]; then
		cp "${LEGACY_CONFIG}" "${BK_DIR}/etc/config/airconnect" ||
			fail "cannot back up ${LEGACY_CONFIG}"
		BK_LEGACY='1'
		LEGACY_CONFIG_MODE=$(file_mode "${LEGACY_CONFIG}") || LEGACY_CONFIG_MODE=''
		[ -z "${LEGACY_CONFIG_MODE}" ] || chmod "${LEGACY_CONFIG_MODE}" "${BK_DIR}/etc/config/airconnect"
	fi
	if [ -f "${TARGET_CONFIG}" ]; then
		cp "${TARGET_CONFIG}" "${BK_DIR}/etc/config/airconnect-manager" ||
			fail "cannot back up ${TARGET_CONFIG}"
		BK_TARGET='1'
		TARGET_CONFIG_MODE=$(file_mode "${TARGET_CONFIG}") || TARGET_CONFIG_MODE=''
		[ -z "${TARGET_CONFIG_MODE}" ] || chmod "${TARGET_CONFIG_MODE}" "${BK_DIR}/etc/config/airconnect-manager"
	fi

	write_manifest
}

write_manifest() {
	WM_TMP="${BK_DIR}/.manifest.tmp"
	{
		printf '%s\n' '# airconnect-manager legacy migration backup'
		printf '%s\n' '# One line per copied file: file=<path relative to /> mode=<octal mode>'
		printf '%s\n' '# The legacy service state is recorded as a flag, not as a file copy: what'
		printf '%s\n' '# --apply changes there is the /etc/rc.d symlink, which --rollback recreates.'
		printf 'created=%s\n' "${BK_STAMP}"
		printf 'mode=%s\n' "${MODE}"
		printf 'legacy_enabled=%s\n' "${LEGACY_ENABLED}"
		printf 'legacy_running=%s\n' "${LEGACY_RUNNING}"
		if [ -n "${BK_LEGACY}" ]; then
			printf 'legacy_config=%s\n' 'etc/config/airconnect'
			printf 'legacy_config_mode=%s\n' "${LEGACY_CONFIG_MODE:-unknown}"
		fi
		if [ -n "${BK_TARGET}" ]; then
			printf 'target_config=%s\n' 'etc/config/airconnect-manager'
			printf 'target_config_mode=%s\n' "${TARGET_CONFIG_MODE:-unknown}"
		fi
		while IFS= read -r WM_NAME; do
			[ -n "${WM_NAME}" ] || continue
			printf 'docker_container=%s\n' "${WM_NAME}"
		done <<EOF
${DOCKER_NAMES}
EOF
		if [ -n "${BK_LEGACY}" ]; then
			printf 'file=%s mode=%s\n' 'etc/config/airconnect' "${LEGACY_CONFIG_MODE}"
		fi
		if [ -n "${BK_TARGET}" ]; then
			printf 'file=%s mode=%s\n' 'etc/config/airconnect-manager' "${TARGET_CONFIG_MODE}"
		fi
	} > "${WM_TMP}" || {
		rm -f "${WM_TMP}"
		fail "cannot write ${WM_TMP}"
	}
	mv "${WM_TMP}" "${BK_DIR}/manifest.txt" || {
		rm -f "${WM_TMP}"
		fail "cannot write ${BK_DIR}/manifest.txt"
	}
}

# --- the new UCI file ------------------------------------------------------

write_target_config() {
	WT_TMP="${CONFIG_DIR}/.airconnect-manager.migrate.$$"
	# The temp file is written with a restrictive umask and only then chmod'd to
	# the final mode, so there is no window in which the configuration is more
	# readable than the file it replaces.
	(
	umask 077
	{
		printf '%s\n' '# SPDX-License-Identifier: MIT'
		printf '%s\n' '#'
		printf '%s\n' '# AirConnect manager configuration.'
		printf '%s\n' '#'
		printf '%s\n' '# Written by scripts/migrate-legacy.sh from the legacy configuration.'
		printf '# Backup: %s\n' "${BK_DIR}"
		printf '%s\n' '#'
		printf '%s\n' '# This file is the single persistent source of truth. The manager reads and'
		printf '%s\n' '# validates it, then regenerates the engine XML under'
		printf '%s\n' '# /var/etc/airconnect-manager/ on every start or reload. Runtime files are'
		printf '%s\n' '# disposable output: never edit them, and never move device configuration'
		printf '%s\n' '# into them. A rejected write keeps the previous valid XML.'
		printf '%s\n' '#'
		printf '# enabled=%s came from: %s.\n' "${MAPPED_ENABLED}" "${MAPPED_ENABLED_SOURCE}"
		printf '%s\n' '# Installing or migrating never starts broadcasting: the operator starts'
		printf '%s\n' '# airconnect-manager after verifying discovery.'
		printf '\n'
		printf "config main 'main'\n"
		printf "\toption enabled '%s'\n" "${MAPPED_ENABLED}"
		printf "\toption interface '%s'\n" "${MAPPED_INTERFACE}"
		printf "\toption airupnp '%s'\n" "${MAPPED_AIRUPNP}"
		printf "\toption aircast '%s'\n" "${MAPPED_AIRCAST}"
		printf "\toption codec '%s'\n" "${DEFAULT_CODEC}"
		printf "\toption latency '%s'\n" "${DEFAULT_LATENCY}"
		printf "\toption max_volume '%s'\n" "${MAPPED_MAX_VOLUME}"
		printf "\toption media_volume '%s'\n" "${DEFAULT_MEDIA_VOLUME}"
		printf "\toption log_level '%s'\n" "${DEFAULT_LOG_LEVEL}"
		if [ "${MAPPED_DEVICE}" = '1' ]; then
			printf '\n'
			printf "config device 'device_legacy'\n"
			printf "\toption engine 'upnp'\n"
			printf "\toption udn '%s'\n" "${MAPPED_UDN}"
			printf "\toption enabled '1'\n"
			printf "\toption max_volume '%s'\n" "${MAPPED_DEVICE_VOLUME}"
		fi
	} > "${WT_TMP}"
	) || {
		rm -f "${WT_TMP}"
		fail "cannot write ${WT_TMP}; nothing outside ${BK_DIR} was changed, so a later --apply is still allowed"
	}
	chmod "${TARGET_MODE}" "${WT_TMP}" || {
		rm -f "${WT_TMP}"
		fail "cannot set mode ${TARGET_MODE} on ${WT_TMP}; nothing outside ${BK_DIR} was changed"
	}
}

# --- dry run ---------------------------------------------------------------

dry_run() {
	say ''
	say '== planned actions (dry run: nothing is changed) =='
	find_applied_backup

	if [ "${LEGACY_CONFIG_FOUND}" != '1' ] && [ "${LEGACY_INIT_FOUND}" != '1' ] &&
		[ -z "${DOCKER_NAMES}" ] && [ -z "${OLD_BINARIES}" ]; then
		say 'no legacy AirConnect installation was detected; there is nothing to migrate'
		say ''
		say 'dry run: no files were changed'
		return 0
	fi

	DR_PLANNED_MODE="${TARGET_MODE}"
	if [ -f "${TARGET_CONFIG}" ]; then
		DR_EXISTING_MODE=$(file_mode "${TARGET_CONFIG}") || DR_EXISTING_MODE=''
		[ -z "${DR_EXISTING_MODE}" ] || DR_PLANNED_MODE="${DR_EXISTING_MODE}"
	fi
	if [ "${LEGACY_CONFIG_FOUND}" = '1' ]; then
		say "  - back up ${LEGACY_CONFIG} and ${TARGET_CONFIG} to ${BACKUP_ROOT}/<UTC timestamp>/ with a manifest"
		say "  - write ${TARGET_CONFIG} with the values above (mode ${DR_PLANNED_MODE})"
	else
		say "  - back up the pre-migration state to ${BACKUP_ROOT}/<UTC timestamp>/ with a manifest"
		say '  - no legacy UCI configuration: the airconnect-manager configuration is left unchanged'
	fi
	if [ "${LEGACY_INIT_FOUND}" = '1' ]; then
		say "  - stop and disable ${LEGACY_INIT}; the old package and its files stay installed"
	fi
	if [ -n "${DOCKER_NAMES}" ]; then
		say '  - stop the matching Docker container(s); the container is kept, never removed'
	fi
	say '  - never start airconnect-manager; that is the operator step after verification'

	say ''
	say 'preconditions:'
	if [ "${LEGACY_CONFIG_FOUND}" = '1' ] && [ ! -f "${TARGET_CONFIG}" ]; then
		say "  - MISSING: ${TARGET_CONFIG}; install airconnect-manager before --apply"
	else
		say '  - airconnect-manager configuration is present'
	fi
	if [ "${TARGET_RUNNING}" = '1' ]; then
		say '  - the new service is running: --apply refuses unless --force-stop-new is given'
	else
		say '  - the new service is not running'
	fi
	if [ -n "${APPLIED_BACKUP}" ]; then
		say "  - an earlier --apply is still in effect (${APPLIED_BACKUP}): --apply refuses until --rollback"
	else
		say '  - no earlier --apply is waiting for --rollback'
	fi
	say ''
	say 'dry run: no files were changed'
}

# --- apply -----------------------------------------------------------------

next_steps() {
	say ''
	say 'next steps (manual):'
	say '  1. review the mapping above and the new /etc/config/airconnect-manager'
	if [ "${LEGACY_INIT_FOUND}" = '1' ] || [ -n "${OLD_BINARIES}" ]; then
		say '  2. remove the old AirConnect package (this script never removes packages):'
		say '       opkg list-installed | grep -i airconnect     # 24.10 / IPK'
		say '       apk list --installed | grep -i airconnect    # 25.12 / APK'
		say '     The airconnect.manager backend refuses start while old binaries or a'
		say '     legacy service are still present, so remove the package before starting.'
	else
		say '  2. the stopped container is kept; remove it only after the new setup works'
	fi
	say '  3. start the new service:'
	say '       /etc/init.d/airconnect-manager enable'
	say '       /etc/init.d/airconnect-manager start'
	say '  4. verify discovery, the iOS AirPlay menu and one played track (docs/MIGRATION.zh-CN.md)'
	say "  5. keep ${BK_DIR} until the new setup has been stable for the documented retention period"
	say '  6. if anything fails: sh migrate-legacy.sh --rollback'
}

apply_migration() {
	say ''
	say '== apply =='

	if [ "${LEGACY_CONFIG_FOUND}" != '1' ] && [ "${LEGACY_INIT_FOUND}" != '1' ] &&
		[ -z "${DOCKER_NAMES}" ]; then
		if [ -n "${OLD_BINARIES}" ]; then
			fail "only old engine binaries were found (${OLD_BINARIES}); this script never removes packages, so remove the old AirConnect package manually and re-run"
		fi
		fail 'no legacy AirConnect installation was detected; nothing to migrate'
	fi
	if [ "${DOCKER_STATE}" = 'error' ]; then
		fail "docker is installed but 'docker ps' failed, so a running container cannot be ruled out; fix docker or stop the container manually, then re-run"
	fi
	if [ "${LEGACY_CONFIG_FOUND}" = '1' ]; then
		[ -f "${TARGET_CONFIG}" ] ||
			fail "airconnect-manager is not installed: ${TARGET_CONFIG} is missing. Install the package first, then re-run --dry-run and --apply"
		[ -x "${TARGET_INIT}" ] ||
			fail "airconnect-manager is not installed correctly: ${TARGET_INIT} is missing or not executable"
	fi
	if [ -f "${LEGACY_INIT}" ] && [ ! -x "${LEGACY_INIT}" ]; then
		fail "${LEGACY_INIT} is not executable, so the legacy service cannot be stopped; fix its mode first"
	fi

	# Two broadcasters on one LAN are the failure this whole flow exists to
	# prevent, so a running new service is a hard stop unless the operator
	# explicitly lets this script stop it.
	if [ "${TARGET_RUNNING}" = '1' ]; then
		if [ "${FORCE_STOP_NEW}" = '1' ]; then
			say 'new service: running; stopping it first because --force-stop-new was given'
			"${TARGET_INIT}" stop >/dev/null 2>&1 ||
				fail 'could not stop the running airconnect-manager service; stop it manually and re-run'
		else
			fail 'the new airconnect-manager service is running; continuing would leave two AirPlay broadcasters on the LAN. Stop it first, or pass --force-stop-new to let this script stop it.'
		fi
	fi

	find_applied_backup
	if [ -n "${APPLIED_BACKUP}" ]; then
		fail "a previous --apply is still in effect (${APPLIED_BACKUP}); run --rollback before applying again"
	fi

	create_backup
	say "backup: ${BK_DIR} (manifest.txt lists the copied files and their modes)"
	if [ -n "${TARGET_CONFIG_MODE:-}" ]; then
		TARGET_MODE="${TARGET_CONFIG_MODE}"
	fi

	if [ "${LEGACY_CONFIG_FOUND}" = '1' ]; then
		print_result
		# A failure inside write_target_config changes nothing outside the backup
		# directory, and that backup has no `applied` marker yet, so a later
		# --apply is still allowed.
		write_target_config
		# The marker is written before the rename: a failure after this point
		# still leaves a rollback path, and a failure before it changes nothing.
		: > "${BK_DIR}/applied" || {
			rm -f "${WT_TMP}"
			fail "cannot write ${BK_DIR}/applied"
		}
		mv "${WT_TMP}" "${TARGET_CONFIG}" || {
			rm -f "${WT_TMP}"
			fail "cannot replace ${TARGET_CONFIG}"
		}
		say "wrote: ${TARGET_CONFIG} (mode ${TARGET_MODE})"
	else
		say 'no legacy UCI configuration was found; the airconnect-manager configuration is left unchanged'
		: > "${BK_DIR}/applied" || fail "cannot write ${BK_DIR}/applied"
	fi

	APPLY_FAILED='0'

	if [ -f "${LEGACY_INIT}" ]; then
		if [ "${LEGACY_RUNNING}" = 'yes' ]; then
			if "${LEGACY_INIT}" stop >/dev/null 2>&1; then
				say "stopped: ${LEGACY_INIT} stop"
			else
				APPLY_FAILED='1'
				say "failed: ${LEGACY_INIT} stop returned nonzero; the old service may still be running"
			fi
		else
			say "old service: not running (${LEGACY_INIT} running returned nonzero); no stop needed"
		fi
		if [ "${LEGACY_ENABLED}" = 'yes' ]; then
			if "${LEGACY_INIT}" disable >/dev/null 2>&1; then
				say "disabled: ${LEGACY_INIT} disable (the old service will not start at boot)"
			else
				APPLY_FAILED='1'
				say "failed: ${LEGACY_INIT} disable returned nonzero; the old service may start at boot"
			fi
		else
			say 'old service: not enabled at boot; no disable needed'
		fi
	fi

	if [ -n "${DOCKER_NAMES}" ]; then
		while IFS= read -r dn_name; do
			[ -n "${dn_name}" ] || continue
			if docker stop "${dn_name}" >/dev/null 2>&1; then
				say "stopped: docker container ${dn_name} (kept, not removed)"
			else
				APPLY_FAILED='1'
				say "failed: docker stop ${dn_name} returned nonzero"
			fi
		done <<EOF
${DOCKER_NAMES}
EOF
	fi

	say ''
	if [ "${APPLY_FAILED}" = '0' ]; then
		say "apply: completed; backup kept at ${BK_DIR}"
	else
		say "apply: completed with failures; backup kept at ${BK_DIR}"
		say 'do not start the new service until the old instance is stopped; --rollback is available'
	fi
	next_steps
	[ "${APPLY_FAILED}" = '0' ] || exit 1
	exit 0
}

# --- rollback --------------------------------------------------------------

restore_file() {
	RF_REL="$1"
	RF_MODE="$2"
	RF_SRC="${BK_DIR}/${RF_REL}"
	RF_DST="${ROOT}/${RF_REL}"
	RF_DIR="${RF_DST%/*}"
	RF_TMP="${RF_DIR}/.${RF_DST##*/}.rollback.$$"
	[ -f "${RF_SRC}" ] || return 1
	[ -d "${RF_DIR}" ] || return 1
	# The temp file must never be more readable than the file it replaces, so it
	# is copied under a restrictive umask and chmod'd afterwards.
	(umask 077 && cp "${RF_SRC}" "${RF_TMP}") || return 1
	if [ -n "${RF_MODE}" ]; then
		chmod "${RF_MODE}" "${RF_TMP}" || {
			rm -f "${RF_TMP}"
			return 1
		}
	fi
	mv "${RF_TMP}" "${RF_DST}" || {
		rm -f "${RF_TMP}"
		return 1
	}
	return 0
}

rollback() {
	say '== rollback =='
	find_applied_backup
	if [ -z "${APPLIED_BACKUP}" ]; then
		say 'nothing to roll back: no --apply backup is waiting'
		exit 0
	fi
	BK_DIR="${APPLIED_BACKUP}"
	say "using backup: ${BK_DIR}"

	# Restore the old service only after the new one is down: never both.
	if [ "${TARGET_RUNNING}" = '1' ]; then
		say 'new service: running; stopping it before the legacy service returns'
		"${TARGET_INIT}" stop >/dev/null 2>&1 ||
			fail 'cannot stop the running airconnect-manager service; stop it manually and re-run --rollback (the legacy service is not started while the new one runs)'
	fi

	[ -f "${BK_DIR}/manifest.txt" ] ||
		fail "${BK_DIR}/manifest.txt is missing; this backup cannot be used"
	[ -f "${BK_DIR}/applied" ] ||
		fail "${BK_DIR}/applied is missing; this backup cannot be used"

	RB_FAILED='0'
	RB_LEGACY_ENABLED=''
	RB_LEGACY_RUNNING=''

	while IFS= read -r RB_LINE; do
		case "${RB_LINE}" in
			file=*)
				RB_REST=${RB_LINE#file=}
				RB_REL=${RB_REST%% *}
				RB_MODE=${RB_REST#* }
				if [ "${RB_MODE}" = "${RB_REST}" ]; then
					RB_MODE=''
				fi
				RB_MODE=${RB_MODE#mode=}
				case "${RB_REL}" in
					etc/config/airconnect|etc/config/airconnect-manager) ;;
					*)
						say "failed: the manifest lists an unexpected path: ${RB_REL}"
						RB_FAILED='1'
						continue
						;;
				esac
				case "${RB_MODE}" in
					''|[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
					*)
						say "failed: the manifest has an invalid mode for ${RB_REL}: ${RB_MODE}"
						RB_FAILED='1'
						continue
						;;
				esac
				if restore_file "${RB_REL}" "${RB_MODE}"; then
					say "restored: /${RB_REL} (mode ${RB_MODE:-unchanged})"
				else
					say "failed: cannot restore /${RB_REL}"
					RB_FAILED='1'
				fi
				;;
			legacy_enabled=*) RB_LEGACY_ENABLED=${RB_LINE#legacy_enabled=} ;;
			legacy_running=*) RB_LEGACY_RUNNING=${RB_LINE#legacy_running=} ;;
		esac
	done < "${BK_DIR}/manifest.txt"

	if [ "${RB_LEGACY_ENABLED}" = 'yes' ]; then
		if [ -x "${LEGACY_INIT}" ]; then
			if "${LEGACY_INIT}" enable >/dev/null 2>&1; then
				say "enabled: ${LEGACY_INIT}"
			else
				say "failed: cannot re-enable ${LEGACY_INIT}"
				RB_FAILED='1'
			fi
		else
			say "failed: ${LEGACY_INIT} is missing; rollback cannot reinstall the old package"
			RB_FAILED='1'
		fi
	fi
	if [ "${RB_LEGACY_RUNNING}" = 'yes' ]; then
		if [ -x "${LEGACY_INIT}" ]; then
			if "${LEGACY_INIT}" start >/dev/null 2>&1; then
				say "started: ${LEGACY_INIT}"
			else
				say "failed: cannot start ${LEGACY_INIT}"
				RB_FAILED='1'
			fi
		else
			say "failed: ${LEGACY_INIT} is missing; start the old service after reinstalling it"
			RB_FAILED='1'
		fi
	fi

	while IFS= read -r RB_LINE; do
		case "${RB_LINE}" in
			docker_container=*)
				RB_NAME=${RB_LINE#docker_container=}
				if ! valid_container_name "${RB_NAME}"; then
					say 'failed: the manifest has an invalid container name'
					RB_FAILED='1'
					continue
				fi
				if ! have docker; then
					say "failed: docker is not available; start container ${RB_NAME} manually"
					RB_FAILED='1'
					continue
				fi
				if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq -- "${RB_NAME}"; then
					if docker start "${RB_NAME}" >/dev/null 2>&1; then
						say "started: docker container ${RB_NAME}"
					else
						say "failed: docker start ${RB_NAME} returned nonzero"
						RB_FAILED='1'
					fi
				else
					say "failed: container ${RB_NAME} no longer exists; rollback cannot recreate it"
					RB_FAILED='1'
				fi
				;;
		esac
	done < "${BK_DIR}/manifest.txt"

	say ''
	if [ "${RB_FAILED}" = '0' ]; then
		: > "${BK_DIR}/rolled-back" || fail "cannot write ${BK_DIR}/rolled-back"
		say "rollback: completed; ${BK_DIR} is kept for audit"
		exit 0
	fi
	say 'rollback: completed with failures; the backup stays active so a re-run can retry'
	exit 1
}

# --- entry -----------------------------------------------------------------

uid=$(id -u 2>/dev/null) || uid=''
if [ "${uid}" != '0' ]; then
	if [ -n "${ROOT}" ]; then
		say "sandbox root: ${ROOT} (host test mode; the real /etc is not touched)"
	else
		fail "refusing to run as uid ${uid:-unknown}: this script rewrites /etc and stops services, so it must run as root (uid 0)"
	fi
fi

# The new service's state is read before any branch so the dry run can report
# the same precondition that apply enforces.
if [ -x "${TARGET_INIT}" ] && "${TARGET_INIT}" running >/dev/null 2>&1; then
	TARGET_RUNNING='1'
fi

detect

case "${MODE}" in
	dry-run)
		mapping
		if [ "${LEGACY_CONFIG_FOUND}" = '1' ]; then
			print_result
		fi
		dry_run
		;;
	apply)
		mapping
		apply_migration
		;;
	rollback)
		rollback
		;;
	*)
		usage_error "unsupported mode: ${MODE}"
		;;
esac
