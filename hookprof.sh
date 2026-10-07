#!/usr/bin/env bash
set -euo pipefail

#
# hookprof.sh MAP LOG FROM TO
#
# Label-run profile of a pmtrace hook log ("H cs:eip ..." lines).
# MAP is a LINK map of $386.SYS built with every label PUBLIC
# (include _386.pub); FROM/TO are line numbers in the H-only log.
# Prints one line per run of instructions under the same label:
# run number, label, first offset, instruction count, then a total.
#

#
# Abort with a message
#

die() {
	printf 'hookprof: %s\n' "$*" >&2
	exit 1
}

#
# Write "decimal-offset LABEL" for every non-absolute public, sorted
#

map_labels() {
	local MAP="$1"
	local A
	local N

	tr -d '\r' < "$MAP" \
		| awk '/Publics by Value/ {F = 1; next}
			F && $1 ~ /^0000:/ && $2 != "Abs" {split($1, P, ":"); print P[2], $2}' \
		| sort -u \
		| while read -r A N; do
			printf '%d %s\n' "0x$A" "$N"
		done
}

#
# Write "decimal-offset hex-offset" for each H line in FROM..TO
#

log_offsets() {
	local LOG="$1"
	local FROM="$2"
	local TO="$3"
	local H

	awk -v S="$FROM" -v E="$TO" 'NR >= S && NR <= E && /^H / {
			split($2, P, ":"); print toupper(substr(P[2], 5))}' "$LOG" \
		| while read -r H; do
			printf '%d %s\n' "0x$H" "$H"
		done
}

#
# Fold offsets into label runs
#

fold_runs() {
	awk 'NR == FNR {L[NR] = $1; N[NR] = $2; C = NR; next}
		{
			X = $1 + 0; LAB = "?"
			for (I = C; I >= 1; I--)
				if (L[I] <= X) { LAB = N[I]; break }
			if (LAB != PREV) { R++; ORD[R] = LAB; FIRST[R] = $2; PREV = LAB }
			CNT[R]++; T++
		}
		END {
			for (I = 1; I <= R; I++)
				printf "%3d %-10s %4s %d\n", I, ORD[I], FIRST[I], CNT[I]
			printf "total %d\n", T
		}' "$1" "$2"
}

[ "$#" -eq 4 ] || die "usage: hookprof.sh MAP LOG FROM TO"
[ -f "$1" ] || die "no map $1"
[ -f "$2" ] || die "no log $2"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
map_labels "$1" > "$TMP/lab"
log_offsets "$2" "$3" "$4" > "$TMP/off"
fold_runs "$TMP/lab" "$TMP/off"
