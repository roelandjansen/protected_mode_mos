#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#
# mkfloppy.sh OUT.img [CFGDIR] [OVERLAYDIR]
# Same layout as run.sh --testconfig: template + latest build output,
# then CFGDIR (CONFIG.SYS, AUTOEXEC.BAT, extras), then OVERLAYDIR files
# (e.g. original shipped binaries for cross-tests) overwrite anything.
#

build_floppy() {
	local OUT="$1"
	local CFG="${2:-}"
	local OVL="${3:-}"
	local LATEST="$TREE/SOURCES/src/latest"
	local F
	local NAME

	cp "$TREE/IMAGES/template/empty-bootable.img" "$OUT"
	mcopy -o -i "$OUT" "$LATEST/\$\$MOS.SYS" '::$$MOS.SYS'
	if [ -f "$LATEST/\$\$SHELL.SYS" ]; then
		mcopy -o -i "$OUT" "$LATEST/\$\$SHELL.SYS" '::$$SHELL.SYS'
	else
		mcopy -o -i "$OUT" "$LATEST/__SHELL.SYS" '::$$SHELL.SYS'
	fi
	[ -f "$LATEST/HELP.SRC" ] && mcopy -o -i "$OUT" "$LATEST/HELP.SRC" '::HELP.SRC'
	shopt -s nocaseglob nullglob
	for F in "$LATEST"/*.COM "$LATEST"/*.SYS "$LATEST"/*.EXE; do
		NAME="$(basename "$F")"
		case "$NAME" in
		'$$MOS.SYS' | '$$SHELL.SYS' | __SHELL.SYS) continue ;;
		esac
		mcopy -o -i "$OUT" "$F" "::$NAME" 2>/dev/null || printf 'skip %s (disk full?)\n' "$NAME" >&2
	done
	if [ -n "$CFG" ]; then
		for F in "$CFG"/*; do
			[ -f "$F" ] && mcopy -o -i "$OUT" "$F" "::$(basename "$F")"
		done
	else
		printf 'smpsize=16\r\ncache=16\r\n' | mcopy -o -i "$OUT" - '::CONFIG.SYS'
	fi
	if [ -n "$OVL" ]; then
		for F in "$OVL"/*; do
			[ -f "$F" ] && mcopy -o -i "$OUT" "$F" "::$(basename "$F")"
		done
	fi
	shopt -u nocaseglob nullglob
}

[ "$#" -ge 1 ] || { printf 'usage: %s OUT.img [CFGDIR] [OVERLAYDIR]\n' "$0" >&2; exit 1; }
build_floppy "$@"
printf 'floppy: %s\n' "$1"
