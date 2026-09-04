#!/usr/bin/env bash
set -euo pipefail

#
# Builds PC-MOS/386 under DOSBox using the original DOS-era toolchain.
# Was dosemu2-based; switched because dosemu2's current command-line
# syntax (-K's drive-mapping behaviour specifically) doesn't do what
# this build needs on a current install, and DOSBox does, verified
# end to end (full kernel + utilities + import.exe, real MASM/LINK).
# See the tooling policy / Linux-native-build notes for the planned
# UASM/Open Watcom replacement -- this script is the old-toolchain
# path either way, just on a different emulator now.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$SCRIPT_DIR/toolchain"
KERNEL_IMAGE="$SCRIPT_DIR/SOURCES/src/latest/\$\$MOS.SYS"

CONF_FILE=""

#
# This script takes no arguments -- --testconfig is a run.sh flag,
# not a build.sh one (build.sh doesn't touch CONFIG.SYS/AUTOEXEC.BAT
# at all, run.sh does). Bail with a clear message rather than
# silently ignoring anything passed, since that would look like the
# flag was accepted when it wasn't.
#

check_no_args() {
	if [ "$#" -gt 0 ]; then
		printf 'build.sh takes no arguments (got: %s).\n' "$*" >&2
		printf -- '--testconfig is a run.sh flag, not a build.sh one.\n' >&2
		exit 1
	fi
}

#
# If ci_prereq.sh has already set up the native UASM/Open Watcom
# toolchain, source its env file. Nothing below consumes it yet --
# the actual build still goes through the old DOS-era toolchain
# until the module-by-module port described in the Linux-native-
# build note is validated. This is just so build.sh doesn't need
# editing again once that lands.
#

use_native_toolchain_if_present() {
	local ENV_FILE="$TOOLCHAIN_DIR/env.sh"

	if [ -f "$ENV_FILE" ]; then
		# shellcheck disable=SC1090
		source "$ENV_FILE"
	fi
}

#
# Confirms dosbox is installed. Bails with a clear message rather
# than a confusing failure further down.
#

check_dosbox_installed() {
	if ! command -v dosbox >/dev/null 2>&1; then
		printf 'dosbox is required but not found on PATH.\n' >&2
		printf 'Install it via zypper, e.g.: zypper install dosbox\n' >&2
		exit 1
	fi
}

#
# Writes a throwaway DOSBox config: fast CPU cycles, and an autoexec
# that mounts the repo as C:, runs the real MAKEMOS.BAT build, then
# quits. Uses CALL before MAKEMOS.BAT -- invoking a .bat from
# DOSBox's autoexec without CALL permanently transfers control and
# never returns to run the following "exit" line, a real DOS
# batch-chaining quirk, faithfully emulated, that looks like a hang.
#

write_dosbox_conf() {
	CONF_FILE="$(mktemp)"

	cat > "$CONF_FILE" << EOF
[cpu]
cycles=max

[autoexec]
mount c $SCRIPT_DIR
c:
cd SOURCES\src
call MAKEMOS.BAT
exit
EOF
}

#
# Runs the build. DOSBox itself exits 0 regardless of whether the
# DOS-side build succeeded -- check_build_output is what actually
# confirms success.
#

run_build() {
	dosbox -conf "$CONF_FILE"
	rm -f "$CONF_FILE"
}

#
# Confirms the kernel image was actually produced.
#

check_build_output() {
	if [ ! -f "$KERNEL_IMAGE" ]; then
		printf 'Build finished but $$MOS.SYS was not produced -- check the DOSBox output above.\n' >&2
		exit 1
	fi

	printf 'Build succeeded: %s\n' "$KERNEL_IMAGE"
}

check_no_args "$@"
use_native_toolchain_if_present
check_dosbox_installed
write_dosbox_conf
run_build
check_build_output
