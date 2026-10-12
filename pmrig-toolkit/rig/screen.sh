#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# Dump the 80x25 text screen from vga.mem.linear (offset 0, M_TEXT)
#

dump_screen() {
	local BIN="$STATE_DIR/vram.bin"
	rm -f "$BIN"
	gdb_batch -ex "dump binary memory $BIN vga.mem.linear vga.mem.linear+4000" >/dev/null
	[ -s "$BIN" ] || { printf 'screen dump failed\n' >&2; exit 1; }
	od -An -v -tu1 -w2 "$BIN" | awk '
		{ c = $1; ch = (c >= 32 && c < 127) ? sprintf("%c", c) : (c == 0 ? " " : "."); line = line ch; n++ }
		n == 80 { printf "%02d|%s|\n", row++, line; line = ""; n = 0 }'
}

dump_screen
