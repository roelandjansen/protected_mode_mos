#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# key.sh 'text' [--enter] | key.sh --key Return -- keystrokes into the window
#

send_keys() {
	local WIN
	WIN="$(xdotool search --pid "$(dosbox_pid)" 2>/dev/null | tail -1)"
	[ -n "$WIN" ] || { printf 'no emulator window\n' >&2; exit 1; }
	if [ "$1" = "--key" ]; then
		shift
		xdotool key --window "$WIN" --delay 80 "$@"
		return
	fi
	xdotool type --window "$WIN" --delay 80 "$1"
	if [ "${2:-}" = "--enter" ]; then
		xdotool key --window "$WIN" Return
	fi
}

[ "$#" -ge 1 ] || { printf 'usage: %s TEXT [--enter] | --key KEYS...\n' "$0" >&2; exit 1; }
send_keys "$@"
