#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# ubuild.sh TARGET -- build one utility target (e.g. ADDTASK.COM) via
# MAKEUTIL.MAK in $TREE; the target is deleted first
#

build_util() {
	local TARGET="$1"
	local LATEST="$TREE/SOURCES/src/latest"
	local CONF="$STATE_DIR/ubuild.conf"
	rm -f "$LATEST/$TARGET" "$LATEST"/RIG*.LOG
	printf '@echo off\r\npath c:\\bin\r\nset TMP=c:\\TMP\r\nset INCLUDE=..\\..\\..\\include;..\\include\r\nset LIB=..\\..\\..\\lib;..\\libs\r\ncd \\SOURCES\\src\\latest\r\nmake -f MAKEUTIL.MAK %s > RIGMAKE.LOG\r\nexit\r\n' "$TARGET" > "$TREE/RIGBLD.BAT"
	mkdir -p "$TREE/TMP"
	printf '[sdl]\noutput=texture\ntexture_renderer=software\n[cpu]\ncycles=max\n[mixer]\nnosound=true\n[autoexec]\nmount c %s\nc:\ncall RIGBLD.BAT\nexit\n' "$TREE" > "$CONF"
	"$RIG_DIR/xstart.sh" >/dev/null
	timeout 900 "$DOSBOX_BIN" -conf "$CONF" > "$STATE_DIR/ubuild-dosbox.log" 2>&1 < /dev/null || true
	rm -f "$TREE/RIGBLD.BAT"
	tr -d '\r' < "$LATEST/RIGMAKE.LOG" | grep -v '^\s*$' | tail -12
	ls -la "$LATEST/$TARGET"
}

[ "$#" -eq 1 ] || { printf 'usage: %s TARGET\n' "$0" >&2; exit 1; }
build_util "$1"
