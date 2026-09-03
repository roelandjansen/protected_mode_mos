#!/usr/bin/env bash
set -euo pipefail

#
# Boots the built PC-MOS/386 image under dosemu2.
#

BOOTDIR="SOURCES/src/latest"
MIN_REV=4901

#
# Confirms the installed dosemu2 is new enough. Bails with a clear
# message rather than guessing.
#

check_dosemu_version() {
	local REV

	REV="$(dosemu --version | grep Revision | cut -d ' ' -f 2)"

	if [ -z "$REV" ] || [ "$REV" -lt "$MIN_REV" ]; then
		printf 'At least dosemu2 revision %s is required (see dosemu --version).\n' "$MIN_REV" >&2
		exit 1
	fi
}

#
# Confirms build.sh has already produced a bootable image.
#

check_build_exists() {
	if [ ! -f "$BOOTDIR/"'$$mos.sys' ]; then
		printf 'No built image found in %s.\n' "$BOOTDIR" >&2
		printf 'Run ./build.sh first.\n' >&2
		exit 1
	fi
}

#
# Boots the image.
#

run_dosemu() {
	dosemu --Fdrive_c "$BOOTDIR"
}

check_dosemu_version
check_build_exists
run_dosemu
