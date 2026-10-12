#!/usr/bin/env bash
set -euo pipefail
cd /home/claude/rig
. ./env.sh

#
# kt.sh CMD [WAIT] - type CMD one key at a time at the PC-MOS prompt,
# check the echoed line, press Return, wait, print the screen
#

#
# Map one character to an xdotool key name
#

keyname() {
	case "$1" in
	" ") printf 'space' ;;
	".") printf 'period' ;;
	"\\") printf 'backslash' ;;
	":") printf 'colon' ;;
	*) printf '%s' "$1" ;;
	esac
}

#
# Type a command, compare the echo, then Return
#

type_checked() {
	local CMD="$1"
	local I
	local LINE

	for ((I = 0; I < ${#CMD}; I++)); do
		./rig.sh key "$(keyname "${CMD:I:1}")" >/dev/null
		sleep 0.4
	done
	sleep 2
	LINE="$(./rig.sh screen | cut -c4- | sed 's/ *|$//' | grep -F '[A:\]' | tail -1)"
	if [ "$LINE" != "[A:\\]$CMD" ]; then
		printf 'echo mismatch: %s\n' "$LINE"
		./rig.sh key Escape >/dev/null
		sleep 1
		return 1
	fi
	./rig.sh key Return >/dev/null
}

#
# Clear the screen, run one command, wait for the prompt, print
#

run_one() {
	type_checked cls || type_checked cls
	sleep 3
	type_checked "$1" || type_checked "$1"
	sleep "${2:-30}"
	./waitp.sh 50 2>/dev/null || true
	printf '=== %s\n' "$1"
	./rig.sh screen | cut -c4- | sed 's/ *|$//' | grep -v '^$'
}

run_one "$1" "${2:-30}"
