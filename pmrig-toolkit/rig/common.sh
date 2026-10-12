#!/usr/bin/env bash
# Shared settings for the headless PC-MOS/386 rig (sourced, not run).

RIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOSBOX_BIN="${DOSBOX_BIN:-/home/claude/dosbox-staging/build-dbg/dosbox}"
TREE="${TREE:-/home/claude/pm}"
STATE_DIR="$RIG_DIR/state"
DISPLAY_NUM="${DISPLAY_NUM:-:99}"
export DISPLAY="$DISPLAY_NUM"

mkdir -p "$STATE_DIR"

#
# Print the PID of the running emulator, or fail
#

dosbox_pid() {
	local PID
	PID="$(cat "$STATE_DIR/dosbox.pid" 2>/dev/null || true)"
	if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
		printf 'dosbox not running\n' >&2
		return 1
	fi
	printf '%s\n' "$PID"
}

#
# Run a batch of gdb commands against the running emulator
#

gdb_batch() {
	local PID
	PID="$(dosbox_pid)"
	gdb -q -batch -p "$PID" "$@" 2>&1 | grep -v '^\[New LWP\|^\[Thread debugging\|^Using host libthread\|^0x0000.* in \|^[0-9]*\t\.\./\|^\[Inferior\|warning: \|^$' || true
}
