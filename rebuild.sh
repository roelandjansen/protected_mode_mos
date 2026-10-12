#!/usr/bin/env bash
set -euo pipefail

#
# rebuild.sh - restore the PC-MOS/386 debug rig after a container reset.
# No sudo: packages are unpacked with dpkg -x into ~/deps/root.
#

HOME_DIR="/home/claude"
UP="/mnt/user-data/uploads"
DEPS="$HOME_DIR/deps"
ROOT="$DEPS/root"
APTO=(-o "Dir::State::Lists=$DEPS/lists" -o "Dir::Cache=$DEPS/cache")
PKGS=(libslirp0 libsdl2-net-2.0-0 libopusfile0 libspeexdsp1 mtools xdotool
	libxdo3 gdb libbabeltrace1 libdebuginfod1t64 libipt2
	libsource-highlight4t64 libboost-regex1.83.0 x11-utils libxxf86dga1
	libxcomposite1 libxtst6 libxmu6 gawk libsigsegv2 libmpfr6)

#
# Print a step header
#

step() {
	printf '=== %s\n' "$*"
}

#
# Unpack the PC-MOS tree and the rig additions
#

unpack_trees() {
	step "unpack trees"
	mkdir -p "$HOME_DIR/pm" "$HOME_DIR/add"
	tar xzf "$UP/pm_tar.gz" -C "$HOME_DIR/pm"
	unzip -o -q "$UP/rig-additions.zip" -d "$HOME_DIR/add"
}

#
# Install the debug emulator and rig from the toolkit
#

restore_toolkit() {
	step "toolkit"
	cd "$HOME_DIR/pm"
	tar xzf pmrig-toolkit.tar.gz
	cd pmrig-toolkit
	./restore.sh || true
	cp "$HOME_DIR"/add/rig/*.sh "$HOME_DIR/rig/"
	chmod +x "$HOME_DIR"/rig/*.sh
}

#
# Fetch and unpack runtime packages user-locally
#

fetch_packages() {
	local P
	local F

	step "packages"
	mkdir -p "$DEPS/lists/partial" "$DEPS/cache/archives/partial" "$ROOT"
	apt-get update "${APTO[@]}" > "$DEPS/update.log" 2>&1 || true
	cd "$DEPS"
	for P in "${PKGS[@]}"; do
		apt-get download "${APTO[@]}" "$P" > /dev/null 2>&1 \
			|| printf 'FAIL %s\n' "$P"
	done
	for F in "$DEPS"/*.deb; do
		dpkg -x "$F" "$ROOT"
	done
	ln -sf gawk "$ROOT/usr/bin/awk"
}

#
# Build libiir 1.9.3 (1.9.4+ lack the out-of-line Cascade ctor)
#

build_libiir() {
	step "libiir"
	rm -rf "$DEPS/iir1"
	git clone -q -c advice.detachedHead=false --branch 1.9.3 --depth 1 \
		https://github.com/berndporr/iir1.git "$DEPS/iir1"
	g++ -O2 -fPIC -shared -I"$DEPS/iir1" -Wl,-soname,libiir.so.1 \
		-o "$ROOT/libiir.so.1" "$DEPS"/iir1/iir/*.cpp
}

#
# Environment file and pid link between rig.sh and common.sh
#

rig_env() {
	step "rig env"
	printf 'L=%s\nexport LD_LIBRARY_PATH=$L:$L/usr/lib/x86_64-linux-gnu\nexport PATH=$L/usr/bin:$PATH\n' \
		"$ROOT" > "$HOME_DIR/rig/env.sh"
	mkdir -p "$HOME_DIR/rig/state" /tmp/pmrig
	ln -sf /tmp/pmrig/dosbox.pid "$HOME_DIR/rig/state/dosbox.pid"
}

#
# DJGPP cross compiler and the test clients
#

build_clients() {
	local N
	local U
	local CC="$HOME_DIR/djgpp/bin/i586-pc-msdosdjgpp-gcc"

	step "djgpp"
	cd "$HOME_DIR"
	curl -sSL -o dj.tar.bz2 \
		https://github.com/andrewwutw/build-djgpp/releases/download/v3.4/djgpp-linux64-gcc1220.tar.bz2
	tar xjf dj.tar.bz2
	rm -f dj.tar.bz2
	mkdir -p "$HOME_DIR/q"
	for N in ftest mtest stest xtest dbench djhello; do
		U="$(printf '%s' "$N" | tr 'a-z' 'A-Z')"
		case "$N" in
		djhello) U="DJHELLO" ;;
		*) U="DJ$U" ;;
		esac
		"$CC" -O2 -s -Wall -o "$HOME_DIR/q/$U.EXE" "$HOME_DIR/add/tests/$N.c"
	done
	cp /mnt/user-data/outputs/q300.c /mnt/user-data/outputs/u76/q900.c "$HOME_DIR/q/"
	"$CC" -O2 -s -Wall -o "$HOME_DIR/q/Q300.EXE" "$HOME_DIR/q/q300.c"
	"$CC" -O2 -s -Wall -o "$HOME_DIR/q/Q900.EXE" "$HOME_DIR/q/q900.c"
	rm -f "$HOME_DIR"/q/*.exe
}

#
# Check the emulator runs
#

verify() {
	step "verify"
	. "$HOME_DIR/rig/env.sh"
	ldd "$HOME_DIR/dosbox-staging/build-dbg/dosbox" | grep 'not found' || true
	"$HOME_DIR/dosbox-staging/build-dbg/dosbox" --version | head -1
	awk --version | head -1
	ls -la "$HOME_DIR/q"
}

unpack_trees
restore_toolkit
fetch_packages
build_libiir
rig_env
build_clients
verify
step "done"
