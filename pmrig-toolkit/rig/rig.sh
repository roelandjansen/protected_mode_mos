#!/usr/bin/env bash
set -euo pipefail

#
# Headless PC-MOS/386 test rig around a DOSBox Staging 0.82.2 debug
# build. Private troubleshooting tooling, not part of the project tree.
#
# rig.sh start [--testconfig] [--bootdir DIR] [--configsys FILE] [--add FILE]...
# rig.sh screen [--attr]      text screen from vga.mem.linear offset 0
# rig.sh cpu                  CR0/pmode/regs/segs
# rig.sh mem PHYS LEN         guest physical memory hex dump (MemBase+PHYS)
# rig.sh ivt VEC              real-mode IVT entry
# rig.sh type TEXT            type TEXT, then Return
# rig.sh key KEYSYM...        xdotool key names (Return, ctrl+c, F5 ...)
# rig.sh gdb CMD...           raw gdb batch commands against the live process
# rig.sh log                  tail emulator log
# rig.sh stop
#

RIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOSBOX="${DOSBOX:-/home/claude/dosbox-staging/build-dbg/dosbox}"
PM_ROOT="${PM_ROOT:-/home/claude/pm}"
STATE_DIR="/tmp/pmrig"
DISPLAY_NUM=":99"
TXTSCR="$RIG_DIR/txtscr"

#
# Aborts with a message
#

die() {
	printf 'rig: %s\n' "$*" >&2
	exit 1
}

#
# Builds the C helper when missing or stale
#

ensure_helper() {
	if [ ! -x "$TXTSCR" ] || [ "$RIG_DIR/txtscr.c" -nt "$TXTSCR" ]; then
		gcc -O2 -Wall -o "$TXTSCR" "$RIG_DIR/txtscr.c"
	fi
}

#
# Returns the running dosbox pid or fails
#

get_pid() {
	local PID

	[ -f "$STATE_DIR/dosbox.pid" ] || die "not running"
	PID="$(cat "$STATE_DIR/dosbox.pid")"
	kill -0 "$PID" 2>/dev/null || die "dosbox pid $PID is gone (see: rig.sh log)"
	printf '%s' "$PID"
}

#
# Runs gdb batch commands against the live emulator
#

gdb_batch() {
	local PID
	local ARGS=()
	local C

	PID="$(get_pid)"
	for C in "$@"; do
		ARGS+=(-ex "$C")
	done
	gdb -q -batch -p "$PID" "${ARGS[@]}" 2>&1 \
		| grep -vE '^\[New LWP|^\[Inferior|^[0-9]+\t|^\[(New )?Thread|^Using host libthread|^[0-9]+\s.*in .*\(\)$|^0x[0-9a-f]+ in |^warning:|^$|Download failed|debuginfod| at \.\./' || true
}

#
# Assembles the boot floppy from template + build output
#

build_floppy() {
	local BOOTDIR="$1"
	local USE_TESTCONFIG="$2"
	local CONFIGSYS="$3"
	shift 3
	local IMG="$STATE_DIR/boot.img"
	local F
	local NAME

	cp "$PM_ROOT/IMAGES/template/empty-bootable.img" "$IMG"

	[ -f "$BOOTDIR/\$\$MOS.SYS" ] || die "no \$\$MOS.SYS in $BOOTDIR"
	mcopy -i "$IMG" "$BOOTDIR/\$\$MOS.SYS" '::$$MOS.SYS'
	if [ -f "$BOOTDIR/\$\$SHELL.SYS" ]; then
		mcopy -i "$IMG" "$BOOTDIR/\$\$SHELL.SYS" '::$$SHELL.SYS'
	elif [ -f "$BOOTDIR/__SHELL.SYS" ]; then
		mcopy -i "$IMG" "$BOOTDIR/__SHELL.SYS" '::$$SHELL.SYS'
	else
		die "no shell in $BOOTDIR"
	fi

	shopt -s nocaseglob
	for F in "$BOOTDIR"/*.COM "$BOOTDIR"/*.SYS "$BOOTDIR"/*.EXE; do
		[ -e "$F" ] || continue
		NAME="$(basename "$F")"
		case "$NAME" in
		'$$MOS.SYS' | '$$SHELL.SYS' | __SHELL.SYS) continue ;;
		esac
		mcopy -o -i "$IMG" "$F" "::$NAME" 2>/dev/null || true
	done
	shopt -u nocaseglob

	if [ "$USE_TESTCONFIG" -eq 1 ]; then
		for F in "$PM_ROOT"/testconfig/*; do
			[ -f "$F" ] || continue
			mcopy -o -i "$IMG" "$F" "::$(basename "$F")"
		done
	elif [ -n "$CONFIGSYS" ]; then
		mcopy -o -i "$IMG" "$CONFIGSYS" '::CONFIG.SYS'
	else
		printf 'smpsize=16\r\ncache=16\r\n' | mcopy -o -i "$IMG" - '::CONFIG.SYS'
	fi

	for F in "$@"; do
		mcopy -o -i "$IMG" "$F" "::$(basename "$F")"
	done
}

#
# Starts Xvfb and the emulator in the background
#

cmd_start() {
	local USE_TESTCONFIG=0
	local BOOTDIR="$PM_ROOT/SOURCES/src/latest"
	local CONFIGSYS=""
	local ADD=()
	local PID

	while [ "$#" -gt 0 ]; do
		case "$1" in
		--testconfig) USE_TESTCONFIG=1; shift ;;
		--bootdir) BOOTDIR="$2"; shift 2 ;;
		--configsys) CONFIGSYS="$2"; shift 2 ;;
		--add) ADD+=("$2"); shift 2 ;;
		*) die "unknown start arg: $1" ;;
		esac
	done

	if [ -f "$STATE_DIR/dosbox.pid" ] && kill -0 "$(cat "$STATE_DIR/dosbox.pid")" 2>/dev/null; then
		die "already running, rig.sh stop first"
	fi
	rm -rf "$STATE_DIR"
	mkdir -p "$STATE_DIR"

	if [ -n "${BOOTIMG:-}" ]; then
		cp "$BOOTIMG" "$STATE_DIR/boot.img"
	else
		build_floppy "$BOOTDIR" "$USE_TESTCONFIG" "$CONFIGSYS" "${ADD[@]}"
	fi

	if ! pgrep -f "Xvfb $DISPLAY_NUM" >/dev/null; then
		setsid nohup Xvfb "$DISPLAY_NUM" -screen 0 1280x1024x24 -nolisten tcp >"$STATE_DIR/xvfb.log" 2>&1 &
		sleep 1
	fi

	cat >"$STATE_DIR/dosbox.conf" <<EOF
[sdl]
output=texture
texture_renderer=software
fullscreen=false
mute_when_inactive=false
pause_when_inactive=false

[dosbox]
machine=svga_s3
memsize=16

[cpu]
core=${CORE:-normal}
cputype=auto
cpu_cycles=${CYCLES:-max}

[mixer]
nosound=true

[speaker]
pcspeaker=false

[sblaster]
sbtype=none

[gus]
gus=false
EOF

	# HDIMG=file: attach a hard disk image (CHS from HDGEOM, default
	# 512,63,255,260) as BIOS disk 80h, then boot the floppy
	local BOOTARG="$STATE_DIR/boot.img"
	if [ -n "${HDIMG:-}" ]; then
		printf '\n[autoexec]\nimgmount 2 %s -t hdd -fs none -size %s\nimgmount a %s -t floppy\nboot -l %s\n' \
			"$HDIMG" "${HDGEOM:-512,63,255,260}" "$STATE_DIR/boot.img" "$( [ -n "${HDBOOT:-}" ] && printf c || printf a )" >>"$STATE_DIR/dosbox.conf"
		BOOTARG=""
	fi

	DISPLAY="$DISPLAY_NUM" SDL_AUDIODRIVER=dummy setsid nohup \
		"$DOSBOX" --noprimaryconf --nolocalconf -conf "$STATE_DIR/dosbox.conf" \
		${BOOTARG:+"$BOOTARG"} >"$STATE_DIR/dosbox.log" 2>&1 &
	sleep 1
	PID="$(pgrep -n -f "$STATE_DIR/dosbox.conf")"
	printf '%s' "$PID" >"$STATE_DIR/dosbox.pid"
	sleep 2
	kill -0 "$PID" 2>/dev/null || die "dosbox died at startup (see: rig.sh log)"
	printf 'started pid %s\n' "$PID"
}

#
# Prints the guest text screen
#

cmd_screen() {
	local DUMP="$STATE_DIR/screen.bin"

	ensure_helper
	gdb_batch "dump binary memory $DUMP vga.mem.linear vga.mem.linear+4000" >/dev/null
	"$TXTSCR" "$DUMP" 80 25 "$@"
}

#
# Prints guest CPU state
#

cmd_cpu() {
	gdb_batch \
		'printf "CR0=%08lx pmode=%d cpl=%d\n", cpu.cr0, cpu.pmode, cpu.cpl' \
		'printf "EAX=%08x EBX=%08x ECX=%08x EDX=%08x\n", cpu_regs.regs[0].dword[0], cpu_regs.regs[3].dword[0], cpu_regs.regs[1].dword[0], cpu_regs.regs[2].dword[0]' \
		'printf "ESP=%08x EBP=%08x ESI=%08x EDI=%08x\n", cpu_regs.regs[4].dword[0], cpu_regs.regs[5].dword[0], cpu_regs.regs[6].dword[0], cpu_regs.regs[7].dword[0]' \
		'printf "EIP=%08x EFLAGS=%08x\n", cpu_regs.ip.dword[0], cpu_regs.flags' \
		'printf "ES=%04x/%08x CS=%04x/%08x SS=%04x/%08x DS=%04x/%08x FS=%04x/%08x GS=%04x/%08x\n", Segs.val[0], Segs.phys[0], Segs.val[1], Segs.phys[1], Segs.val[2], Segs.phys[2], Segs.val[3], Segs.phys[3], Segs.val[4], Segs.phys[4], Segs.val[5], Segs.phys[5]'
}

#
# Hex dump of guest physical memory
#

cmd_mem() {
	local ADDR="$1"
	local LEN="${2:-256}"
	local DUMP="$STATE_DIR/mem.bin"
	local OFF
	local REST

	gdb_batch "dump binary memory $DUMP (char*)MemBase+$ADDR (char*)MemBase+$ADDR+$LEN" >/dev/null
	od -A x -t x1z -v "$DUMP" | while read -r OFF REST; do
		[ -n "$REST" ] || continue
		printf '%08x  %s\n' "$((ADDR + 0x$OFF))" "$REST"
	done
}

#
# Real-mode IVT entry
#

cmd_ivt() {
	local VEC="$1"

	gdb_batch "printf \"IVT[%02x] = %04x:%04x\n\", $VEC, *(unsigned short*)((char*)MemBase+($VEC)*4+2), *(unsigned short*)((char*)MemBase+($VEC)*4)"
}

#
# Returns the emulator X window id
#

win_id() {
	DISPLAY="$DISPLAY_NUM" xdotool search --pid "$(get_pid)" 2>/dev/null | tail -n 1
}

#
# Types text followed by Return
#

cmd_type() {
	local W

	W="$(win_id)"
	[ -n "$W" ] || die "no window"
	DISPLAY="$DISPLAY_NUM" xdotool windowfocus --sync "$W" 2>/dev/null || true
	DISPLAY="$DISPLAY_NUM" xdotool type --delay 80 "$*"
	DISPLAY="$DISPLAY_NUM" xdotool key Return
}

#
# Sends named keys
#

cmd_key() {
	local W

	W="$(win_id)"
	[ -n "$W" ] || die "no window"
	DISPLAY="$DISPLAY_NUM" xdotool windowfocus --sync "$W" 2>/dev/null || true
	DISPLAY="$DISPLAY_NUM" xdotool key --delay 80 "$@"
}

#
# Stops the emulator and Xvfb
#

cmd_stop() {
	if [ -f "$STATE_DIR/dosbox.pid" ]; then
		kill "$(cat "$STATE_DIR/dosbox.pid")" 2>/dev/null || true
		rm -f "$STATE_DIR/dosbox.pid"
	fi
	pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
	printf 'stopped\n'
}

[ "$#" -ge 1 ] || die "usage: rig.sh start|screen|cpu|mem|ivt|type|key|gdb|log|stop"
CMD="$1"
shift
case "$CMD" in
start) cmd_start "$@" ;;
screen) cmd_screen "$@" ;;
cpu) cmd_cpu ;;
mem) cmd_mem "$@" ;;
ivt) cmd_ivt "$@" ;;
type) cmd_type "$@" ;;
key) cmd_key "$@" ;;
gdb) gdb_batch "$@" ;;
log) tail -n "${1:-40}" "$STATE_DIR/dosbox.log" ;;
stop) cmd_stop ;;
*) die "unknown command: $CMD" ;;
esac
