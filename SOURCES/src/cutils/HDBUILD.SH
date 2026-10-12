#!/usr/bin/env bash
set -euo pipefail

#
# HDBUILD.SH -- build HDSETUP.EXE with Open Watcom (no Borland C needed)
#
# WATCOM=dir   Open Watcom root (required, e.g. /opt/watcom)
# OUT=dir      output directory (default: ./hdbuild in the current directory)
#
# -zp1: byte packed structures, as Borland C.  The disk structures
# (boot sector BPB, partition entries, IOCTL blocks) depend on it.
#
# The sources are found relative to this script (SOURCES/src/cutils).
# They are copied with CR and ^Z removed; the tree is not touched.
# This file keeps LF line endings (bash does not accept CRLF).
#

SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$PWD/hdbuild}"

# ulib modules HDSETUP uses (the others need Borland's dir.h)
ULMODS="ulbeep ulchar2v ulclrbox ulcls uldrwbox uldrwhbr uldrwvbr uldspdec
	uleatkey ulexptab ulfilbox ulformt ulfsize ulgetcho ulgetcur ulgetkey
	ulgetkst ulgetstr ulgetxy ulifkey ulismos ulmessag ulopclwn ulqualt
	ulscrldn ulscrlup ulsetatr ulsetcur ulsetvpt ulstock ulstr2v ulview
	ulwrlbl"

#
# Checks the Watcom installation and sets its environment
#

check_watcom() {
	if [ -z "${WATCOM:-}" ] || [ ! -d "$WATCOM/h" ]; then
		printf 'set WATCOM to the Open Watcom root (WATCOM/h must exist)\n' >&2
		exit 1
	fi
	export WATCOM
	export PATH="$WATCOM/binl64:$WATCOM/binl:$PATH"
	export INCLUDE="$WATCOM/h"
	command -v wcc >/dev/null || { printf 'wcc not found under %s\n' "$WATCOM" >&2; exit 1; }
}

#
# Copies one source file in lower case, without CR and ^Z
#

clean_copy() {
	local F="$1"
	local D="$2"
	local N

	N="$(basename "$F" | tr 'A-Z' 'a-z')"
	tr -d '\r\032' <"$F" >"$D/$N"
}

#
# Compiles the ulib modules and the asm window helpers
#

build_ulib() {
	local M

	mkdir -p "$OUT/ul"
	for M in "$SRC"/ulib/*.C "$SRC"/ulib/*.H "$SRC"/ulib/*.ASM; do
		clean_copy "$M" "$OUT/ul"
	done
	for M in $ULMODS; do
		( cd "$OUT/ul" && wcc -ms -zp1 -zq -i=. -fo="$M.obj" "$M.c" ) 2>&1 \
			| grep -i 'error' || true
		[ -f "$OUT/ul/$M.obj" ] || { printf 'ulib %s failed\n' "$M" >&2; exit 1; }
	done
	( cd "$OUT/ul" && wasm -zq -ms -fo=ulsvrswn.obj ulsvrswn.asm )
}

#
# Compiles and links HDSETUP, copies its message and help files
#

build_hdsetup() {
	local F

	for F in "$SRC"/cutils/*.C "$SRC"/cutils/*.H "$SRC"/cutils/*.INC; do
		clean_copy "$F" "$OUT"
	done
	( cd "$OUT" && wcc -ms -zp1 -zq -i=. -fo=hdsetup.obj hdsetup.c ) 2>&1 \
		| grep -i 'error' || true
	[ -f "$OUT/hdsetup.obj" ] || { printf 'hdsetup.c failed\n' >&2; exit 1; }
	( cd "$OUT" && wlink system dos option quiet name HDSETUP.EXE \
		file hdsetup.obj file '{' ul/*.obj '}' )
	cp "$SRC/latest/SIDECAR/HDSETUP.MSG" "$SRC/latest/SIDECAR/HDSETUP.HLP" "$OUT/"
	printf '%s %s bytes\n' "$OUT/HDSETUP.EXE" "$(stat -c %s "$OUT/HDSETUP.EXE")"
}

check_watcom
rm -rf "$OUT"
mkdir -p "$OUT"
build_ulib
build_hdsetup
