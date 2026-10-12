#!/usr/bin/env bash
set -euo pipefail

#
# Builds PC-MOS/386 under DOSBox using the original DOS-era toolchain.
# Was dosemu2-based; switched because dosemu2's current command-line
# syntax (-K's drive-mapping behaviour specifically) doesn't do what
# this build needs on a current install, and DOSBox does, verified
# end to end (full kernel + utilities + IMPORT.EXE, real MASM/LINK).
# See the tooling policy / Linux-native-build notes for the planned
# UASM/Open Watcom replacement -- this script is the old-toolchain
# path either way, just on a different emulator now.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$SCRIPT_DIR/toolchain"
KERNEL_IMAGE="$SCRIPT_DIR/SOURCES/src/latest/\$\$MOS.SYS"

CONF_FILE=""
DO_CLEAN=0
CLEAN_ONLY=0

#
# build.sh takes at most one argument: --clean or --clean-only.
# --testconfig is a run.sh flag, not a build.sh one (build.sh doesn't
# touch CONFIG.SYS/AUTOEXEC.BAT at all, run.sh does). Bail with a
# clear message on anything else, rather than silently ignoring it.
#

check_args() {
	if [ "$#" -eq 0 ]; then
		return
	fi
	if [ "$#" -eq 1 ] && [ "$1" = "--clean" ]; then
		DO_CLEAN=1
		return
	fi
	if [ "$#" -eq 1 ] && [ "$1" = "--clean-only" ]; then
		CLEAN_ONLY=1
		return
	fi
	printf 'build.sh takes at most one argument: --clean or --clean-only (got: %s).\n' "$*" >&2
	printf -- '--testconfig is a run.sh flag, not a build.sh one.\n' >&2
	exit 1
}

#
# Mirrors SOURCES/src/CLEANALL.BAT's own file list, directory by
# directory -- kept in sync with it deliberately, so CLEANALL.BAT
# stays the authoritative "what does a clean build mean" reference.
# Done here in bash rather than by actually invoking CLEANALL.BAT
# inside DOSBox: that script has an interactive `pause`, which would
# hang a non-interactive build.sh run waiting for a keypress that
# never comes.
#

clean_build_artifacts() {
	local SRC="$SCRIPT_DIR/SOURCES/src"

	printf 'Cleaning build artifacts (mirrors CLEANALL.BAT)...\n'

	rm -f "$SRC/unterm/"*.SYS 2>/dev/null || true

	rm -f "$SRC/ulib/"*.OBJ "$SRC/ulib/ULIB.LIB" "$SRC/ulib/ULIB.BAK" 2>/dev/null || true

	rm -f "$SRC/import/"*.EXE "$SRC/import/"*.OBJ "$SRC/import/"*.MAP 2>/dev/null || true

	rm -f "$SRC/acu/"*.EXE "$SRC/acu/"*.OBJ "$SRC/acu/"*.MAP 2>/dev/null || true

	rm -f "$SRC/cutils/"*.EXE "$SRC/cutils/"*.OBJ "$SRC/cutils/"*.MAP 2>/dev/null || true

	rm -f "$SRC/latest/"*.SYS "$SRC/latest/"*.EXE "$SRC/latest/"*.COM \
		"$SRC/latest/"*.OBJ "$SRC/latest/"*.MAP "$SRC/latest/"*.PUB \
		"$SRC/latest/"*.PSS "$SRC/latest/"*.NDX \
		"$SRC/latest/HDSETUP.MSG" "$SRC/latest/HDSETUP.HLP" 2>/dev/null || true

	rm -f "$SRC/cdlink/"*.SYS "$SRC/cdlink/"*.EXE "$SRC/cdlink/"*.COM \
		"$SRC/cdlink/"*.OBJ "$SRC/cdlink/"*.MAP "$SRC/cdlink/"*.PUB 2>/dev/null || true

	printf 'Build artifacts cleaned.\n'
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

#
# Builds HDSETUP.EXE with Open Watcom (cutils/HDBUILD.SH) and puts it,
# with its HDSETUP.MSG and HDSETUP.HLP, next to the other utilities in
# SOURCES/src/latest. MAKEMOS.BAT can't build it: it is Borland C and
# there is no Borland compiler. Uses WATCOM, or else the Open Watcom
# that ci_prereq.sh installs in toolchain/; skipped with a note if neither.
#

build_hdsetup() {
	local LATEST="$SCRIPT_DIR/SOURCES/src/latest"
	local OUT

	if [ -z "${WATCOM:-}" ] && [ -d "$TOOLCHAIN_DIR/open-watcom/h" ]; then
		WATCOM="$TOOLCHAIN_DIR/open-watcom"
		export WATCOM
	fi
	if [ -z "${WATCOM:-}" ]; then
		printf 'HDSETUP skipped: set WATCOM to the Open Watcom root to build it.\n'
		return
	fi
	OUT="$(mktemp -d)"
	OUT="$OUT" "$SCRIPT_DIR/SOURCES/src/cutils/HDBUILD.SH"
	cp "$OUT/HDSETUP.EXE" "$OUT/HDSETUP.MSG" "$OUT/HDSETUP.HLP" "$LATEST/"
	rm -rf "$OUT"
	printf 'HDSETUP built: %s\n' "$LATEST/HDSETUP.EXE"
}

check_args "$@"
if [ "$CLEAN_ONLY" -eq 1 ]; then
	clean_build_artifacts
	exit 0
fi
use_native_toolchain_if_present
check_dosbox_installed
if [ "$DO_CLEAN" -eq 1 ]; then
	clean_build_artifacts
fi
write_dosbox_conf
run_build
check_build_output
build_hdsetup
