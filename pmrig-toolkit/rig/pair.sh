#!/usr/bin/env bash
# pair.sh LOG FUNCREGEX -- each client int 31h call with its return
set -euo pipefail
LOG="$1"
RX="$2"
awk -v rx="$RX" '
function fld(line, key,   i, n, a) {
	n = split(line, a, " ")
	for (i = 1; i <= n; i++)
		if (index(a[i], key "=") == 1)
			return substr(a[i], length(key) + 2)
	return ""
}
$2 == "INT" && $3 == "31" && $0 ~ /vm=0 cpl=3/ {
	f = substr(fld($0, "eax"), 5, 4)
	if (f ~ rx) {
		pend = 1
		want = sprintf("%08s %08s", fld($0, "eip"), fld($0, "cs"))
		gsub(/ /, "0", want)
		sub(/^0*/, "", want)
		call = sprintf("%s f=%s bx=%s cx=%s dx=%s si=%s di=%s", $1, f, substr(fld($0,"ebx"),5), substr(fld($0,"ecx"),5), substr(fld($0,"edx"),5), substr(fld($0,"esi"),5), substr(fld($0,"edi"),5))
		weip = fld($0, "eip"); wcs = sprintf("%08x", strtonum("0x" fld($0, "cs")))
	}
	next
}
pend && $2 == "IRET" {
	p = index($0, "frame: ")
	if (p) {
		split(substr($0, p + 7), fr, " ")
		if (fr[1] == weip && fr[2] == wcs) {
			printf "%s -> ax=%s bx=%s cx=%s dx=%s si=%s di=%s fl=%s\n", call, fld($0,"eax"), fld($0,"ebx"), fld($0,"ecx"), fld($0,"edx"), fld($0,"esi"), fld($0,"edi"), substr(fr[3], 5)
			pend = 0
		}
	}
}
' "$LOG"
