#!/usr/bin/env bash
set -euo pipefail

#
# Boots the built PC-MOS/386 image under DOSBox. Was dosemu2-based;
# switched for the same reason build.sh was -- dosemu2's current
# command-line drive-mounting syntax (--Fdrive_c specifically, which
# no longer exists) doesn't do what this needs on a current install.
#
# DOSBox can't just mount a directory and boot it the way dosemu2's
# old --Fdrive_c did -- booting needs an actual disk image with a
# boot sector. IMAGES/template/empty-bootable.img (already in the
# repo, prepared by MSYS from mos501src) provides that; this script
# copies it fresh each run and populates it with the current build
# output via mtools. Verified end to end: boots to PC-MOS's real
# startup banner, then a live, responsive [A:\] command prompt.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTDIR="$SCRIPT_DIR/SOURCES/src/latest"
KERNEL_IMAGE="$BOOTDIR/\$\$MOS.SYS"
TEMPLATE_IMAGE="$SCRIPT_DIR/IMAGES/template/empty-bootable.img"
SHELL_IMAGE=""
RUN_IMAGE=""

#
# Confirms dosbox and mtools are installed. Bails with a clear
# message rather than a confusing failure further down.
#

check_prereqs_installed() {
	local MISSING=()

	command -v dosbox >/dev/null 2>&1 || MISSING+=(dosbox)
	command -v mcopy >/dev/null 2>&1 || MISSING+=(mtools)

	if [ "${#MISSING[@]}" -gt 0 ]; then
		printf 'Required but not found: %s\n' "${MISSING[*]}" >&2
		printf 'Install via zypper, e.g.: zypper install %s\n' "${MISSING[*]}" >&2
		exit 1
	fi
}

#
# Confirms build.sh has already produced a bootable image, and
# resolves the actual shell filename. MAKEMOS.BAT's own rename step
# (__SHELL.SYS -> $$SHELL.SYS) doesn't reliably take effect the same
# way in every environment -- seen both ways in practice -- so this
# checks for the correctly-renamed name first and only falls back to
# the pre-rename one if that's what's actually on disk.
#

check_build_exists() {
	if [ ! -f "$KERNEL_IMAGE" ]; then
		printf 'No built image found in %s.\n' "$BOOTDIR" >&2
		printf 'Run ./build.sh first.\n' >&2
		exit 1
	fi

	if [ -f "$BOOTDIR/\$\$SHELL.SYS" ]; then
		SHELL_IMAGE="$BOOTDIR/\$\$SHELL.SYS"
	elif [ -f "$BOOTDIR/__SHELL.SYS" ]; then
		SHELL_IMAGE="$BOOTDIR/__SHELL.SYS"
	else
		printf 'Neither $$SHELL.SYS nor __SHELL.SYS found in %s.\n' "$BOOTDIR" >&2
		exit 1
	fi
}

#
# Builds a throwaway boot floppy from the template plus the current
# build output.
#

build_boot_floppy() {
	if [ ! -f "$TEMPLATE_IMAGE" ]; then
		printf 'Boot floppy template not found: %s\n' "$TEMPLATE_IMAGE" >&2
		exit 1
	fi

	RUN_IMAGE="$(mktemp --suffix=.img)"
	cp "$TEMPLATE_IMAGE" "$RUN_IMAGE"

	mcopy -i "$RUN_IMAGE" "$KERNEL_IMAGE" '::$$MOS.SYS'
	mcopy -i "$RUN_IMAGE" "$SHELL_IMAGE" '::$$SHELL.SYS'
	mcopy -i "$RUN_IMAGE" "$BOOTDIR/COMMAND.COM" '::COMMAND.COM'

	printf 'smpsize=16\r\ncache=16\r\n' | mcopy -i "$RUN_IMAGE" - '::CONFIG.SYS'
}

#
# Boots the floppy interactively.
#

run_dosbox() {
	dosbox -c "cycles=max" -c "boot -l a $RUN_IMAGE"
	rm -f "$RUN_IMAGE"
}

check_prereqs_installed
check_build_exists
build_boot_floppy
run_dosbox
