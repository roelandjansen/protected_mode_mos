#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# kbuild.sh [OBJ ...] -- rebuild the kernel ($$MOS.SYS) via KERNEL.MAK.
# Named OBJs are deleted first to force recompilation. Unlike MAKEMOS.BAT
# this never does "del $*.*", which would wipe the built drivers.
#

LATEST="$TREE/SOURCES/src/latest"

{
	printf '@echo off\r\n'
	printf 'path c:\\bin\r\n'
	printf 'set TMP=c:\\TMP\r\n'
	printf 'set INCLUDE=..\\..\\..\\include;..\\include\r\n'
	printf 'set LIB=..\\..\\..\\lib;..\\libs\r\n'
	printf 'cd \\SOURCES\\src\\latest\r\n'
	for O in "$@"; do
		printf 'del %s.obj\r\n' "$O"
	done
	printf 'del $$MOS.SYS\r\n'
	printf 'make -f KERNEL.MAK $$MOS.SYS > RIGMAKE.LOG\r\n'
	printf 'exit\r\n'
} > "$TREE/RIGBLD.BAT"

mkdir -p "$TREE/TMP"
rm -f "$LATEST"/RIG*.LOG

CONF="$STATE_DIR/build.conf"
printf '[sdl]\noutput=texture\ntexture_renderer=software\n[cpu]\ncycles=max\n[mixer]\nnosound=true\n[autoexec]\nmount c %s\nc:\ncall RIGBLD.BAT\nexit\n' "$TREE" > "$CONF"
"$RIG_DIR/xstart.sh" >/dev/null
timeout 900 "$DOSBOX_BIN" -conf "$CONF" > "$STATE_DIR/build-dosbox.log" 2>&1 < /dev/null || true
rm -f "$TREE/RIGBLD.BAT"

[ -f "$LATEST/RIGMAKE.LOG" ] && tr -d '\r' < "$LATEST/RIGMAKE.LOG" | grep -viE '^\s*$' | tail -20
if tr -d '\r' < "$LATEST/RIGMAKE.LOG" 2>/dev/null | grep -iE 'Severe  Errors' | grep -qv ' 0 Severe'; then
	printf 'BUILD FAILED: MASM severe errors\n' >&2
	exit 1
fi
[ -f "$LATEST/\$\$MOS.SYS" ] || { printf 'BUILD FAILED: no $$MOS.SYS\n' >&2; exit 1; }
ls -la "$LATEST/\$\$MOS.SYS"
