#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# Start Xvfb on DISPLAY_NUM if it is not already up
#

start_xvfb() {
	if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
		return 0
	fi
	setsid nohup Xvfb "$DISPLAY" -screen 0 1280x1024x24 -nolisten tcp > "$STATE_DIR/xvfb.log" 2>&1 < /dev/null &
	sleep 2
	xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || { printf 'Xvfb failed\n' >&2; exit 1; }
}

start_xvfb
printf 'Xvfb up on %s\n' "$DISPLAY"
