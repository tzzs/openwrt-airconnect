#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 tzzs
#
# Extract the two AirConnect engine binaries from the upstream release zip and
# place them into the package build directory. Pure POSIX sh so it runs on the
# router's BusyBox ash as well as a minimal host SDK container.
#
# Usage: extract-engines.sh <zip-path> <target-dir> <arch>
#   zip-path    path to AirConnect-<ver>.zip
#   target-dir  directory the binaries are written into
#   arch        normalized upstream architecture token (e.g. aarch64, x86_64)
#
# Exits non-zero on any failure, after printing the archive's real listing to
# stderr so the next person sees the names that actually exist instead of
# guessing why the file was not found.

set -u

ZIP="${1:-}"
TARGET="${2:-}"
ARCH="${3:-}"

if [ -z "${ZIP}" ] || [ -z "${TARGET}" ] || [ -z "${ARCH}" ]; then
	printf 'extract-engines: usage: extract-engines.sh <zip> <target> <arch>\n' >&2
	exit 2
fi
if [ ! -f "${ZIP}" ]; then
	printf 'extract-engines: archive not found: %s\n' "${ZIP}" >&2
	exit 2
fi

UPNP="airupnp-linux-${ARCH}-static"
CAST="aircast-linux-${ARCH}-static"

mkdir -p "${TARGET}" || {
	printf 'extract-engines: cannot create target directory %s\n' "${TARGET}" >&2
	exit 3
}

# Unpack into a scratch directory so a partial or mis-shaped archive never
# leaves half-written binaries in the build directory.
WORK="$(mktemp -d "${TARGET}/.airconnect-extract.XXXXXX")" || {
	printf 'extract-engines: cannot create scratch directory in %s\n' "${TARGET}" >&2
	exit 3
}
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

if ! unzip -q -o -d "${WORK}" "${ZIP}"; then
	printf 'extract-engines: failed to unpack %s\n' "${ZIP}" >&2
	printf 'extract-engines: archive contents were:\n' >&2
	unzip -l "${ZIP}" 2>/dev/null | head -60 >&2
	exit 4
fi

UPNP_PATH="$(find "${WORK}" -type f -name "${UPNP}" | head -1)"
if [ -z "${UPNP_PATH}" ]; then
	printf 'extract-engines: %s missing from %s\n' "${UPNP}" "${ZIP}" >&2
	printf 'extract-engines: archive contents were:\n' >&2
	unzip -l "${ZIP}" 2>/dev/null | head -60 >&2
	exit 5
fi
CAST_PATH="$(find "${WORK}" -type f -name "${CAST}" | head -1)"
if [ -z "${CAST_PATH}" ]; then
	printf 'extract-engines: %s missing from %s\n' "${CAST}" "${ZIP}" >&2
	printf 'extract-engines: archive contents were:\n' >&2
	unzip -l "${ZIP}" 2>/dev/null | head -60 >&2
	exit 5
fi

mv "${UPNP_PATH}" "${TARGET}/${UPNP}" || {
	printf 'extract-engines: cannot place %s\n' "${UPNP}" >&2
	exit 6
}
mv "${CAST_PATH}" "${TARGET}/${CAST}" || {
	printf 'extract-engines: cannot place %s\n' "${CAST}" >&2
	exit 6
}

exit 0
