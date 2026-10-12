#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# dosbuild.sh _NAME  -- rebuild one driver (.ASM.SYS recipe) with an error
# gate: stale obj/exe/sys deleted first, MASM listing produced, error
# count checked, output renamed _NAME.SYS -> $NAME.SYS.
#

write_batch() {
	local NAME="$1"
	local LATEST="$TREE/SOURCES/src/latest"
	printf '@echo off\r\npath c:\\bin\r\nset TMP=c:\\TMP\r\nset INCLUDE=..\\..\\..\\include;..\\include\r\nset LIB=..\\..\\..\\lib;..\\libs\r\ncd \\SOURCES\\src\\latest\r\ndel %s.obj\r\ndel %s.exe\r\ndel %s.sys\r\ndel %s.pub\r\npublic %s.asm > RIGPUB.LOG\r\nmasm %s,%s,%s; > RIGMASM.LOG\r\nif not exist %s.obj goto done\r\nlink %s; > RIGLINK.LOG\r\nif not exist %s.exe goto done\r\nexe2bin %s %s.sys > RIGE2B.LOG\r\n:done\r\nexit\r\n' \
		"$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" "$NAME" \
		> "$TREE/RIGBLD.BAT"
	mkdir -p "$TREE/TMP"
	rm -f "$LATEST"/RIG*.LOG
}

run_batch() {
	local CONF="$STATE_DIR/build.conf"
	printf '[sdl]\noutput=texture\ntexture_renderer=software\n[cpu]\ncycles=max\n[mixer]\nnosound=true\n[autoexec]\nmount c %s\nc:\ncall RIGBLD.BAT\nexit\n' "$TREE" > "$CONF"
	"$RIG_DIR/xstart.sh" >/dev/null
	timeout 600 "$DOSBOX_BIN" -conf "$CONF" > "$STATE_DIR/build-dosbox.log" 2>&1 < /dev/null || true
	rm -f "$TREE/RIGBLD.BAT"
}

check_result() {
	local NAME="$1"
	local LATEST="$TREE/SOURCES/src/latest"
	local UP
	local OUT
	UP="$(printf '%s' "$NAME" | tr 'a-z' 'A-Z')"
	for L in RIGPUB RIGMASM RIGLINK RIGE2B; do
		[ -f "$LATEST/$L.LOG" ] && { printf -- '--- %s\n' "$L"; tr -d '\r' < "$LATEST/$L.LOG" | grep -v '^\s*$' | tail -12 || true; }
	done
	grep -q ' 0 Severe  Errors' "$LATEST/RIGMASM.LOG" 2>/dev/null || { printf 'BUILD FAILED: MASM errors\n' >&2; exit 1; }
	OUT="$(ls "$LATEST" | grep -i "^${NAME}.sys$" || true)"
	[ -n "$OUT" ] || { printf 'BUILD FAILED: no %s.SYS\n' "$NAME" >&2; exit 1; }
	mv -f "$LATEST/$OUT" "$LATEST/\$${UP#_}.SYS"
	rm -f "$LATEST"/RIG*.LOG
	ls -la "$LATEST/\$${UP#_}.SYS"
}

[ "$#" -eq 1 ] || { printf 'usage: %s _NAME (e.g. _DPMI)\n' "$0" >&2; exit 1; }
write_batch "$1"
run_batch
check_result "$1"
