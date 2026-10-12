#!/usr/bin/env bash
set -euo pipefail

#
# restore.sh - put the PC-MOS/386 debug rig back in a fresh container.
#
# usage:  tar xzf pmrig-toolkit.tar.gz && cd pmrig-toolkit && ./restore.sh
#
# Installs the prebuilt debug DOSBox Staging 0.82.2 if its libraries
# resolve here; otherwise rebuilds it from upstream plus the pmtrace,
# int13ext and hdd4 patches. Never uses sudo.
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DBX_DIR="/home/claude/dosbox-staging"
DBX_BIN="$DBX_DIR/build-dbg/dosbox"
RIG_DIR="/home/claude/rig"

#
# Install the rig scripts
#

install_rig() {
	mkdir -p "$RIG_DIR/state"
	cp -a "$HERE"/rig/. "$RIG_DIR"/
	chmod +x "$RIG_DIR"/*.sh
	gcc -O2 -Wall -o "$RIG_DIR/txtscr" "$RIG_DIR/txtscr.c"
	gcc -O2 -Wall -o "$RIG_DIR/mkpt" "$RIG_DIR/mkpt.c"
	gcc -O2 -Wall -o "$RIG_DIR/mkmbr" "$RIG_DIR/mkmbr.c"
	printf 'rig installed in %s\n' "$RIG_DIR"
}

#
# Try the prebuilt binary first
#

install_prebuilt() {
	mkdir -p "$DBX_DIR/build-dbg"
	gzip -dc "$HERE/dosbox.gz" > "$DBX_BIN"
	chmod +x "$DBX_BIN"
	if ldd "$DBX_BIN" | grep -q 'not found'; then
		printf 'prebuilt binary has missing libraries here:\n'
		ldd "$DBX_BIN" | grep 'not found'
		rm -f "$DBX_BIN"
		return 1
	fi
	"$DBX_BIN" --version | head -1
	return 0
}

#
# Rebuild from upstream 0.82.2 plus the patch
#

rebuild() {
	printf 'rebuilding DOSBox Staging 0.82.2 with the pmtrace, int13ext and hdd4 patches...\n'
	rm -rf "$DBX_DIR"
	git clone --depth 1 --branch v0.82.2 \
		https://github.com/dosbox-staging/dosbox-staging.git "$DBX_DIR"
	cd "$DBX_DIR"
	git apply "$HERE/dosbox-pmtrace.patch"
	git apply "$HERE/dosbox-int13ext.patch"
	patch -p1 < "$HERE/dosbox-hdd4.patch"
	meson setup build-dbg --buildtype=debug -Denable_debugger=heavy
	ninja -C build-dbg
	"$DBX_BIN" --version | head -1
}

install_rig
if ! install_prebuilt; then
	rebuild
fi
printf 'done. See RIG.md for usage.\n'
