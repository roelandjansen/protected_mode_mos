#!/usr/bin/env bash
set -euo pipefail

#
# Prints one partition table entry: type, abs start, size, CHS fields
#

pt_entry() {
	local IMG="$1"
	local SEC="$2"
	local N="$3"
	local BASE="$4"
	local B

	B=($(dd if="$IMG" bs=512 skip="$SEC" count=1 status=none | od -An -v -tu1 -j$((446 + N * 16)) -N16))
	TYPE=${B[4]}
	START=$(( B[8] + B[9] * 256 + B[10] * 65536 + B[11] * 16777216 ))
	SIZE=$(( B[12] + B[13] * 256 + B[14] * 65536 + B[15] * 16777216 ))
	printf '  type %02x start %10d (abs %10d) size %10d  chs %d/%d/%d-%d/%d/%d\n' "$TYPE" "$START" $((BASE + START)) "$SIZE" \
		$(( B[3] + (B[2] & 192) * 4 )) "${B[1]}" $(( B[2] & 63 )) $(( B[7] + (B[6] & 192) * 4 )) "${B[5]}" $(( B[6] & 63 ))
}

#
# Walks the MBR and the EBR chain of an image
#

IMG="$1"
printf 'MBR\n'
EXT=0
for I in 0 1 2 3; do
	pt_entry "$IMG" 0 "$I" 0
	if [ "$TYPE" = 5 ] || [ "$TYPE" = 15 ]; then
		EXT=$START
	fi
done
EBR=$EXT
while [ "$EBR" != 0 ]; do
	printf 'EBR at %d\n' "$EBR"
	pt_entry "$IMG" "$EBR" 0 "$EBR"
	pt_entry "$IMG" "$EBR" 1 "$EXT"
	if [ "$TYPE" = 5 ] || [ "$TYPE" = 15 ]; then
		EBR=$(( EXT + START ))
	else
		EBR=0
	fi
done
