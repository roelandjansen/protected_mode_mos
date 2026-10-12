#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# Stop the emulator
#

if PID="$(dosbox_pid 2>/dev/null)"; then
	kill "$PID"
	printf 'stopped %s\n' "$PID"
fi
