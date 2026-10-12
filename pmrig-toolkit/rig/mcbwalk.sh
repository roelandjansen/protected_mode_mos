#!/usr/bin/env bash
set -euo pipefail

#
# mcbwalk.sh DUMP -- find and print the DOS MCB chain in a dump of
# conventional memory (./mem.sh 0 a0000 DUMP). The first paragraph from
# 60h that starts a chain of at least four 'M' blocks ending in 'Z' wins.
#

#
# Read LEN bytes at OFFSET from the dump as a hex string
#

rd() {
	od -An -tx1 -j "$1" -N "$2" "$DUMP" | tr -d ' \n'
}

#
# Walk the chain from paragraph $1; print it if it is valid
#

walk() {
	local Q="$1"
	local N=0
	local OUT=""
	local S O Z NM
	while :; do
		S=$(rd $((Q * 16)) 1)
		[ "$S" = 4d ] || [ "$S" = 5a ] || return 1
		O=$(rd $((Q * 16 + 1)) 2)
		O=${O:2:2}${O:0:2}
		Z=$(rd $((Q * 16 + 3)) 2)
		Z=$((16#${Z:2:2}${Z:0:2}))
		NM=$(od -An -c -j $((Q * 16 + 8)) -N 8 "$DUMP" | tr -d ' \n' | tr -c '[:print:]' '.')
		OUT="$OUT$(printf '%04x %s owner %s size %5x %s' "$Q" "$S" "$O" "$Z" "$NM")\n"
		N=$((N + 1))
		[ "$S" = 5a ] && break
		Q=$((Q + Z + 1))
		(( Q < 0xa000 && N < 60 )) || return 1
	done
	(( N >= 4 )) || return 1
	printf 'chain from %04x, %d blocks:\n' "$1" "$N"
	printf '%b' "$OUT"
	return 0
}

[ "$#" -eq 1 ] || { printf 'usage: %s DUMP\n' "$0" >&2; exit 1; }
DUMP="$1"
[ -s "$DUMP" ] || { printf 'no dump: %s\n' "$DUMP" >&2; exit 1; }
for ((P = 0x60; P < 0x1000; P++)); do
	[ "$(rd $((P * 16)) 1)" = 4d ] || continue
	walk "$P" && exit 0
done
printf 'no chain found\n'
exit 1
