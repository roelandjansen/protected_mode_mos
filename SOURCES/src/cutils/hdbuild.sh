#!/usr/bin/env bash
set -euo pipefail

#
# hdbuild.sh -- build HDSETUP.EXE with Open Watcom (no Borland C needed)
#
# TREE=dir   PC-MOS tree (default /home/claude/pm), sources in SOURCES/src
# OUT=dir    output directory (default /tmp/claude-0/hdbuild)
#
# Sources are copied with CR and ^Z removed; the tree is not touched.
#

TREE="${TREE:-/home/claude/pm}"
OUT="${OUT:-/tmp/claude-0/hdbuild}"
WATCOM="${WATCOM:-/home/claude/ow}"
SRC="$TREE/SOURCES/src"

# ulib modules HDSETUP uses (the others need Borland's dir.h)
ULMODS="ulbeep ulchar2v ulclrbox ulcls uldrwbox uldrwhbr uldrwvbr uldspdec
	uleatkey ulexptab ulfilbox ulformt ulfsize ulgetcho ulgetcur ulgetkey
	ulgetkst ulgetstr ulgetxy ulifkey ulismos ulmessag ulopclwn ulqualt
	ulscrldn ulscrlup ulsetatr ulsetcur ulsetvpt ulstock ulstr2v ulview
	ulwrlbl"

export WATCOM
export PATH="$WATCOM/binl64:$WATCOM/binl:$PATH"
export INCLUDE="$WATCOM/h"

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
		( cd "$OUT/ul" && wcc -ms -zq -i=. -fo="$M.obj" "$M.c" ) \
			| grep -v 'Warning\|Note' || true
		[ -f "$OUT/ul/$M.obj" ] || { printf 'ulib %s failed\n' "$M" >&2; exit 1; }
	done
	( cd "$OUT/ul" && wasm -zq -ms -fo=ulsvrswn.obj ulsvrswn.asm )
}

#
# Compiles and links HDSETUP
#

build_hdsetup() {
	local F

	for F in "$SRC"/cutils/*.C "$SRC"/cutils/*.H "$SRC"/cutils/*.INC; do
		clean_copy "$F" "$OUT"
	done
	( cd "$OUT" && wcc -ms -zq -i=. -fo=hdsetup.obj hdsetup.c ) \
		| grep -v 'Warning\|Note' || true
	[ -f "$OUT/hdsetup.obj" ] || { printf 'hdsetup.c failed\n' >&2; exit 1; }
	( cd "$OUT" && wlink system dos option quiet name HDSETUP.EXE \
		file hdsetup.obj file '{' ul/*.obj '}' )
	cp "$SRC/latest/SIDECAR/HDSETUP.MSG" "$SRC/latest/SIDECAR/HDSETUP.HLP" "$OUT/"
	printf '%s %s bytes\n' "$OUT/HDSETUP.EXE" "$(stat -c %s "$OUT/HDSETUP.EXE")"
}

rm -rf "$OUT"
mkdir -p "$OUT"
build_ulib
build_hdsetup
