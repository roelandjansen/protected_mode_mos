#!/usr/bin/env bash
set -euo pipefail

#
# waitp.sh [TRIES] -- wait until the last non-empty screen line is a bare
# A:\ prompt. With other tasks busy, PC-MOS's console drops keystrokes
# typed while it is still printing: type only at an idle prompt.
#

RIG="$(dirname "${BASH_SOURCE[0]}")"
TRIES="${1:-40}"

#
# The last non-empty line of the screen, frame and padding stripped
#

last_line() {
	timeout 15 "$RIG/screen.sh" 2>/dev/null | grep -v '^[0-9]*| *|$' | tail -1 | cut -c4- | sed 's/ *|$//; s/ *$//' || true
}

for ((I = 0; I < TRIES; I++)); do
	[ "$(last_line)" = '[A:\]' ] && exit 0
	sleep 3
done
printf 'waitp: no idle prompt\n' >&2
exit 1
