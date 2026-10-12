#!/usr/bin/env bash
set -euo pipefail

#
# makefloppy.sh -- build a PC-MOS boot floppy image from the latest
# build, for installing PC-MOS on a hard disk (real machine or VM).
#
# usage: makefloppy.sh [--all] [OUT.img]
#
#   OUT.img   output image (default: mosboot.img)
#   --all     after the install set, add every other .COM/.SYS/.EXE
#             from the build until the 1.44 MB floppy is full
#
# TREE=dir overrides the tree; the default is the directory this
# script is in. Needs mtools. Run build.sh first (with Open Watcom
# available, so HDSETUP.EXE is built too).
#
# The install set: the kernel, the shell, $386.SYS, HDSETUP (with its
# .MSG and .HLP), FORMAT and MSYS, a small CONFIG.SYS (memdev=$386.sys)
# and an AUTOEXEC.BAT (so no date/time prompt). See
# pcmos386-howto-boot.md, "Installing on a hard disk".
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE="${TREE:-$SCRIPT_DIR}"
LATEST="$TREE/SOURCES/src/latest"
TEMPLATE="$TREE/IMAGES/template/empty-bootable.img"
INSTALL_SET="\$386.SYS HDSETUP.EXE HDSETUP.MSG HDSETUP.HLP FORMAT.COM MSYS.COM"
OUT="mosboot.img"
ADD_ALL=0
MISSING=0

#
# Parses --all and the output name
#

parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--all)
			ADD_ALL=1
			;;
		-*)
			printf 'usage: %s [--all] [OUT.img]\n' "$(basename "$0")" >&2
			exit 1
			;;
		*)
			OUT="$1"
			;;
		esac
		shift
	done
}

#
# Checks mtools, the template and the kernel
#

check_prereqs() {
	command -v mcopy >/dev/null 2>&1 || { printf 'mtools (mcopy) not found\n' >&2; exit 1; }
	[ -f "$TEMPLATE" ] || { printf 'template not found: %s\n' "$TEMPLATE" >&2; exit 1; }
	[ -f "$LATEST/\$\$MOS.SYS" ] || { printf 'no $$MOS.SYS in %s: run build.sh first\n' "$LATEST" >&2; exit 1; }
}

#
# Copies one file from the build onto the floppy; notes it if missing
#

put_file() {
	local NAME="$1"

	if [ ! -f "$LATEST/$NAME" ]; then
		printf 'missing: %s\n' "$NAME" >&2
		MISSING=1
		return
	fi
	mcopy -o -i "$OUT" "$LATEST/$NAME" "::$NAME"
}

#
# Kernel, shell, install set and CONFIG.SYS
#

build_install_set() {
	local NAME

	cp "$TEMPLATE" "$OUT"
	mcopy -o -i "$OUT" "$LATEST/\$\$MOS.SYS" '::$$MOS.SYS'
	if [ -f "$LATEST/\$\$SHELL.SYS" ]; then
		mcopy -o -i "$OUT" "$LATEST/\$\$SHELL.SYS" '::$$SHELL.SYS'
	elif [ -f "$LATEST/__SHELL.SYS" ]; then
		mcopy -o -i "$OUT" "$LATEST/__SHELL.SYS" '::$$SHELL.SYS'
	else
		printf 'missing: $$SHELL.SYS (or __SHELL.SYS)\n' >&2
		MISSING=1
	fi
	for NAME in $INSTALL_SET; do
		put_file "$NAME"
	done
	printf 'smpsize=64\r\ncache=16\r\nmemdev=$386.sys\r\n' | mcopy -o -i "$OUT" - '::CONFIG.SYS'
	printf 'echo off\r\necho PC-MOS install floppy: HDSETUP, FORMAT C:, MSYS C:\r\n' | mcopy -o -i "$OUT" - '::AUTOEXEC.BAT'
}

#
# Adds the remaining utilities until the floppy is full (--all)
#

add_the_rest() {
	local F
	local NAME

	shopt -s nocaseglob nullglob
	for F in "$LATEST"/*.COM "$LATEST"/*.SYS "$LATEST"/*.EXE; do
		NAME="$(basename "$F")"
		case "$NAME" in
		'$$MOS.SYS' | '$$SHELL.SYS' | __SHELL.SYS) continue ;;
		esac
		mdir -i "$OUT" "::$NAME" >/dev/null 2>&1 && continue
		mcopy -i "$OUT" "$F" "::$NAME" 2>/dev/null || printf 'no room: %s\n' "$NAME" >&2
	done
	shopt -u nocaseglob nullglob
}

parse_args "$@"
check_prereqs
build_install_set
if [ "$ADD_ALL" -eq 1 ]; then
	add_the_rest
fi
if [ "$MISSING" -eq 1 ]; then
	printf 'floppy: %s (incomplete, see above)\n' "$OUT"
	exit 1
fi
printf 'floppy: %s\n' "$OUT"
