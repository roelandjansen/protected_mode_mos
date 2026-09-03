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

ARGS=()

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

check_dosemu_version
set_build_args
run_build
