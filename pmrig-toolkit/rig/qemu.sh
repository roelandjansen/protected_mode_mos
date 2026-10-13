#!/usr/bin/env bash
set -euo pipefail

#
# qemu.sh start FLOPPY [HDIMG] [MEM_MB] | screen | key KEY... | mon CMD | stop
# QEMU with SeaBIOS: a real bios with option roms, unlike dosbox.
# QEMU is unpacked without sudo into $QD (see RIG.md, "QEMU").
# headless QEMU (SeaBIOS, TCG) with a monitor on tcp 4444
#

QD=/tmp/claude-0/qemu
export LD_LIBRARY_PATH=$QD/root/usr/lib/x86_64-linux-gnu:/home/claude/deps/root/usr/lib/x86_64-linux-gnu
QEMU="$QD/root/usr/bin/qemu-system-i386"
PORT=4444
export QEMU_MODULE_DIR=$QD/root/usr/lib/x86_64-linux-gnu/qemu

#
# Sends one monitor command, prints the reply
#

mon() {
	exec 3<>/dev/tcp/127.0.0.1/$PORT
	printf '%s\n' "$1" >&3
	sleep "${2:-0.5}"
	timeout 1 cat <&3 || true
	exec 3>&-
}

#
# Prints the 80x25 text screen from b8000
#

screen() {
	local R
	local HEX
	R="$(mon 'xp /4000xb 0xb8000' 1)"
	HEX="$(printf '%s\n' "$R" | grep '^00000000000b' | sed 's/^[0-9a-f]*: //' | tr ' ' '\n' | grep '^0x' | sed 's/^0x//' | awk 'NR % 2 == 1' | tr -d '\n')"
	printf '%b' "$(printf '%s' "$HEX" | sed 's/../\\x&/g')" | tr -c ' -~' ' ' | fold -w 80 | awk '{ printf "%02d|%s|\n", NR - 1, $0 }'
}

case "$1" in
start)
	ARGS=(-machine pc -m "${4:-32}" -bios "$QD/root/usr/share/seabios/bios-256k.bin" -L "$QD/root/usr/share/seabios"
		-L "$QD/root/usr/share/qemu" -display none -monitor tcp:127.0.0.1:$PORT,server,nowait
		-nic none -drive file="$2",if=floppy,format=raw -boot a)
	if [ -n "${3:-}" ]; then
		ARGS+=(-drive file="$3",if=ide,index=0,format=raw)
	fi
	setsid nohup "$QEMU" "${ARGS[@]}" > "$QD/qemu.log" 2>&1 < /dev/null &
	printf '%s\n' "$!" > "$QD/qemu.pid"
	sleep 2
	printf 'qemu pid %s\n' "$(cat "$QD/qemu.pid")"
	;;
screen)
	screen
	;;
key)
	shift
	for K in "$@"; do
		mon "sendkey $K" 0.3 >/dev/null
	done
	;;
mon)
	mon "$2" "${3:-1}"
	;;
stop)
	kill "$(cat "$QD/qemu.pid")" 2>/dev/null || true
	;;
esac
