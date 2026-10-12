#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# combuild.sh NAME -- build NAME.ASM (org 100h) into NAME.COM in
# $TREE/SOURCES/src/latest; MASM error gate, listing kept as NAME.LST
#

#
# Assemble, link and exe2bin one .COM inside the emulator, then gate on
# the MASM error count and the presence of the output
#

build_com() {
	local NAME="$1"
	local LATEST="$TREE/SOURCES/src/latest"
	local CONF="$STATE_DIR/combuild.conf"
	rm -f "$LATEST/$NAME.OBJ" "$LATEST/$NAME.EXE" "$LATEST/$NAME.COM" "$LATEST"/RIG*.LOG
	printf '@echo off\r\npath c:\\bin\r\nset TMP=c:\\TMP\r\ncd \\SOURCES\\src\\latest\r\nmasm %s,%s,%s; > RIGMASM.LOG\r\nif not exist %s.obj goto done\r\nlink %s; > RIGLINK.LOG\r\nif not exist %s.exe goto done\r\nexe2bin %s %s.com > RIGE2B.LOG\r\n:done\r\nexit\r\n' \
		"$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" > "$TREE/RIGBLD.BAT"
	mkdir -p "$TREE/TMP"
	printf '[sdl]\noutput=texture\ntexture_renderer=software\n[cpu]\ncycles=max\n[mixer]\nnosound=true\n[autoexec]\nmount c %s\nc:\ncall RIGBLD.BAT\nexit\n' "$TREE" > "$CONF"
	"$RIG_DIR/xstart.sh" >/dev/null
	timeout 300 "$DOSBOX_BIN" -conf "$CONF" > "$STATE_DIR/combuild-dosbox.log" 2>&1 < /dev/null || true
	rm -f "$TREE/RIGBLD.BAT"
	tr -d '\r' < "$LATEST/RIGMASM.LOG" | grep -v '^\s*$' | tail -8
	grep -q ' 0 Severe  Errors' "$LATEST/RIGMASM.LOG" || { printf 'BUILD FAILED: MASM errors\n' >&2; exit 1; }
	ls "$LATEST" | grep -qi "^$NAME.com$" || { printf 'BUILD FAILED: no %s.COM\n' "$NAME" >&2; exit 1; }
	rm -f "$LATEST"/RIG*.LOG
	ls -la "$LATEST"/"$NAME".[Cc][Oo][Mm]
}

[ "$#" -eq 1 ] || { printf 'usage: %s NAME\n' "$0" >&2; exit 1; }
build_com "$1"
