#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# mem.sh PHYS_HEX LEN_HEX [raw OUTFILE] -- hexdump guest physical memory
#

dump_mem() {
	local ADDR="$1"
	local LEN="$2"
	local OUT="${3:-$STATE_DIR/mem.bin}"
	rm -f "$OUT"
	gdb_batch -ex "dump binary memory $OUT (char*)MemBase+0x$ADDR (char*)MemBase+0x$ADDR+0x$LEN" >/dev/null
	[ -s "$OUT" ] || { printf 'mem dump failed\n' >&2; exit 1; }
	od -Ax -tx1z -v "$OUT" | awk -v base=$((16#$ADDR)) '{ if ($1 ~ /^[0-9a-f]+$/ && NF > 1) { $1 = sprintf("%08x", strtonum("0x" $1) + base) } print }'
}

[ "$#" -ge 2 ] || { printf 'usage: %s PHYS_HEX LEN_HEX [OUTFILE]\n' "$0" >&2; exit 1; }
dump_mem "$@"
