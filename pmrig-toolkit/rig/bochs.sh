#!/usr/bin/env bash
set -euo pipefail

#
# bochs.sh -- boot a floppy image in Bochs, a strict x86 emulator:
# write-protected code segments, segment limits and descriptor rules
# fault the way a real CPU (VMware) does, unlike DOSBox and QEMU's TCG.
#
# usage: bochs.sh FLOPPY [INSNS] [MEM_MB]
#
#   FLOPPY   1.44 MB boot image
#   INSNS    instructions to run before stopping (default 2000000000)
#   MEM_MB   memory (default 16)
#
# BOCHS_HD=image attaches a hard disk image as ata0-master, geometry
# BOCHS_HDGEOM=cyls,heads,spt (default 4161,16,63: a 2 GB VMware disk).
#
# Prints the 80x25 text screen at the stop, then every CPU error from
# the Bochs log (write to a read-only segment, limit violations, ...)
# with its count. The first error has the instruction count; rerun with
# "sba COUNT-1" (BOCHS_CMDS) to stop just before it.
#
# Setup, no sudo (Ubuntu 24.04 packages), see RIG.md "Bochs":
#   apt-get download bochs bochsbios vgabios bochs-x; dpkg-deb -x each
#   into $BOCHS_ROOT. Needs Xvfb (the X frontend, on DISPLAY :99).
#

BOCHS_ROOT="${BOCHS_ROOT:-/tmp/claude-0/bochs/root}"
WORK="${BOCHS_WORK:-/tmp/claude-0/bochs/run}"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"

#
# Writes the Bochs configuration (legacy BIOS: rombios32 of the latest
# BIOS image crashes during POST in this build)
#

write_conf() {
	local FLOPPY="$1"
	local MEM="$2"

	printf 'megs: %s\n' "$MEM" > "$WORK/bochsrc"
	printf 'romimage: file=%s/usr/share/bochs/BIOS-bochs-legacy\n' "$BOCHS_ROOT" >> "$WORK/bochsrc"
	printf 'vgaromimage: file=%s/usr/share/bochs/VGABIOS-lgpl-latest\n' "$BOCHS_ROOT" >> "$WORK/bochsrc"
	printf 'floppya: 1_44=%s, status=inserted\n' "$FLOPPY" >> "$WORK/bochsrc"
	if [ -n "${BOCHS_HD:-}" ]; then
		IFS=, read -r HC HH HS <<< "${BOCHS_HDGEOM:-4161,16,63}"
		printf 'ata0-master: type=disk, path=%s, mode=flat, cylinders=%s, heads=%s, spt=%s, translation=auto\n' "$BOCHS_HD" "$HC" "$HH" "$HS" >> "$WORK/bochsrc"
	fi
	printf 'boot: floppy\ndisplay_library: x\nlog: %s/bochs.log\n' "$WORK" >> "$WORK/bochsrc"
	printf 'panic: action=report\nerror: action=report\ninfo: action=ignore\ndebug: action=ignore\n' >> "$WORK/bochsrc"
	printf 'clock: sync=none\ncpu: count=1, ips=50000000\nspeaker: enabled=0\n' >> "$WORK/bochsrc"
}

#
# Starts Xvfb if no X server answers on DISPLAY_NUM
#

start_x() {
	if ! pgrep -x Xvfb >/dev/null; then
		rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM#:}"
		setsid nohup Xvfb "$DISPLAY_NUM" -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 < /dev/null &
		sleep 2
	fi
}

#
# Decodes the debugger's "xp /2000hx 0xb8000" dump into 25 text rows
#

show_screen() {
	grep -E '^0x00000000000b[89a-f]' "$1" | sed 's/^[^:]*:[[:space:]]*//' | tr -s ' \t' '\n' | grep '^0x' | head -2000 | awk '
	BEGIN { h = "0123456789abcdef" }
	{ lo = tolower(substr($0, length($0) - 1, 2)); c = (index(h, substr(lo, 1, 1)) - 1) * 16 + index(h, substr(lo, 2, 1)) - 1
	  if (c < 32 || c > 126) c = 32; line = line sprintf("%c", c); n++
	  if (n % 80 == 0) { printf "%02d|%s|\n", n / 80 - 1, line; line = "" } }'
}

[ "$#" -ge 1 ] || { printf 'usage: %s FLOPPY [INSNS] [MEM_MB]\n' "$(basename "$0")" >&2; exit 1; }
FLOPPY="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
INSNS="${2:-2000000000}"
MEM="${3:-16}"
CMDS="${BOCHS_CMDS:-}"

mkdir -p "$WORK"
write_conf "$FLOPPY" "$MEM"
start_x
rm -f "$WORK/bochs.log"
{ printf 'sba %s\nc\n' "$INSNS"; [ -n "$CMDS" ] && printf '%b\n' "$CMDS"; printf 'xp /2000hx 0xb8000\nq\n'; sleep 5; } |
	DISPLAY="$DISPLAY_NUM" LTDL_LIBRARY_PATH="$BOCHS_ROOT/usr/lib/x86_64-linux-gnu/bochs/plugins" \
	timeout 900 "$BOCHS_ROOT/usr/bin/bochs-bin" -q -f "$WORK/bochsrc" > "$WORK/dbg.out" 2>&1 || true
show_screen "$WORK/dbg.out"
[ -n "$CMDS" ] && grep -E '^(r[a-z0-9]{1,2}|eflags|[cdefgs]s|ldtr|tr|gdtr|idtr|[0-9a-f]{16}):' "$WORK/dbg.out" | head -60
printf -- '--- CPU errors\n'
grep -E '^[0-9]+e\[CPU' "$WORK/bochs.log" | sed 's/^0*\([0-9]*\)e\[CPU0 *\] /\1 /' | awk '{ k = $0; sub(/^[0-9]+ /, "", k); if (!(k in n)) first[k] = $1; n[k]++ } END { for (k in n) printf "%8d x  first at %s  %s\n", n[k], first[k], k }'
