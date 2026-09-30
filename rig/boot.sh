#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# boot.sh IMAGE.img [extra dosbox conf lines file]
# Boots a floppy image headless under Xvfb; PID in state/dosbox.pid,
# emulator log in state/dosbox.log.
#

write_conf() {
	local CONF="$STATE_DIR/boot.conf"
	cat > "$CONF" << EOC
[sdl]
output=texture
texture_renderer=software
fullscreen=false
[dosbox]
memsize=16
[cpu]
core=${CORE:-normal}
cputype=auto
cycles=max
[mixer]
nosound=true
EOC
	if [ -n "${1:-}" ]; then
		cat "$1" >> "$CONF"
	fi
	printf '%s\n' "$CONF"
}

[ "$#" -ge 1 ] || { printf 'usage: %s IMAGE.img [extra.conf]\n' "$0" >&2; exit 1; }
"$RIG_DIR/xstart.sh" >/dev/null
if PID="$(dosbox_pid 2>/dev/null)"; then
	kill "$PID" 2>/dev/null || true
	sleep 1
fi
CONF="$(write_conf "${2:-}")"
setsid nohup "$DOSBOX_BIN" -conf "$CONF" "$1" > "$STATE_DIR/dosbox.log" 2>&1 < /dev/null &
printf '%s\n' "$!" > "$STATE_DIR/dosbox.pid"
printf 'dosbox pid %s\n' "$!"
