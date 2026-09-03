#!/usr/bin/env bash
set -euo pipefail

#
# Builds PC-MOS/386 under dosemu2 using the original DOS-era toolchain.
# See the tooling policy / Linux-native-build notes for the planned
# UASM/Open Watcom replacement -- this script is the old path until
# that migration lands.
#

MIN_REV=3684
SYNTAX_CHANGE_REV=5709

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$SCRIPT_DIR/toolchain"

ARGS=()

#
# If ci_prereq.sh has already set up the native UASM/Open Watcom
# toolchain, source its env file. Nothing below consumes it yet --
# the actual build still goes through dosemu2 until the module-by-
# module port described in the Linux-native-build note is validated.
# This is just so build.sh doesn't need editing again once that
# lands.
#

use_native_toolchain_if_present() {
	local ENV_FILE="$TOOLCHAIN_DIR/env.sh"

	if [ -f "$ENV_FILE" ]; then
		# shellcheck disable=SC1090
		source "$ENV_FILE"
	fi
}

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

	DOSEMU_REV="$REV"
}

#
# dosemu2's -K/-E argument syntax changed around revision 5709 --
# builds the right ARGS array for whichever side of that we're on.
#

set_build_args() {
	if [ "$DOSEMU_REV" -ge "$SYNTAX_CHANGE_REV" ]; then
		ARGS=(-K '.:SOURCES\src' -E 'MAKEMOS.BAT')
	else
		ARGS=(-K 'SOURCES/src/MAKEMOS.BAT' -U 2)
	fi
}

#
# Runs the build inside dosemu2.
#

run_build() {
	dosemu -td -ks "${ARGS[@]}" 'path=%D\bin;%O'
}

use_native_toolchain_if_present
check_dosemu_version
set_build_args
run_build
