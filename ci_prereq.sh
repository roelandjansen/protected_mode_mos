#!/usr/bin/env bash
set -euo pipefail

#
# Installs everything the build needs: dosemu2 for the existing
# DOS-era build path, and the gcc/UASM/Open Watcom toolchain for the
# native-Linux build path it's migrating to. See the tooling policy
# and Linux-native-build notes. Targets openSUSE Leap 15.x, Leap
# 16.x, and Tumbleweed only.
#
# Package installs need root; nothing else here does. Does not use
# sudo anywhere -- run this as root already (e.g. inside a root CI
# container image), or as root manually.
#

DOSEMU2_REPO_ALIAS="dosemu2"
DOSEMU2_REPO_URL="https://download.opensuse.org/repositories/home:/mnhauke:/dosemu2/openSUSE_Tumbleweed/"

UASM_REPO_URL="https://github.com/Terraspace/UASM.git"
OPENWATCOM_INSTALLER_URL="https://github.com/open-watcom/open-watcom-v2/releases/download/Current-build/open-watcom-2_0-c-linux-x64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$SCRIPT_DIR/toolchain"

#
# Confirms we're running with the privileges zypper needs, without
# escalating ourselves.
#

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		printf 'This script needs to run as root (no sudo here by policy).\n' >&2
		printf 'Run it inside a root CI container, or as root manually.\n' >&2
		exit 1
	fi
}

#
# Installs dosemu2 if it isn't already present. Tries the default
# repos first; falls back to adding the OBS repo only if needed.
#

install_dosemu2() {
	if command -v dosemu >/dev/null 2>&1; then
		printf 'dosemu2 already installed, skipping.\n'
		return 0
	fi

	if zypper --non-interactive install dosemu; then
		return 0
	fi

	printf 'dosemu2 not found in default repos, adding OBS repo.\n'
	printf 'Verify %s still matches your distro/version before relying on this in CI.\n' "$DOSEMU2_REPO_URL" >&2

	zypper --non-interactive addrepo --refresh "$DOSEMU2_REPO_URL" "$DOSEMU2_REPO_ALIAS"
	zypper --non-interactive --gpg-auto-import-keys refresh "$DOSEMU2_REPO_ALIAS"
	zypper --non-interactive install dosemu
}

#
# Installs the packages the native toolchain needs to build/fetch
# itself: a C compiler and make (to build UASM), git (to fetch UASM's
# source), curl (to fetch the Open Watcom installer).
#

install_build_tools() {
	zypper --non-interactive install gcc make git curl
}

#
# Builds UASM from source into TOOLCHAIN_DIR. No system install, no
# root needed -- it's a single static binary.
#

build_uasm() {
	local BUILD_DIR="$TOOLCHAIN_DIR/uasm-src"

	if [ -x "$TOOLCHAIN_DIR/bin/uasm" ]; then
		printf 'UASM already built, skipping.\n'
		return 0
	fi

	mkdir -p "$TOOLCHAIN_DIR/bin"
	rm -rf "$BUILD_DIR"
	git clone --depth 1 "$UASM_REPO_URL" "$BUILD_DIR"

	(
		cd "$BUILD_DIR"
		make -f gccLinux64.mak
	)

	cp "$BUILD_DIR/GccUnixR/uasm" "$TOOLCHAIN_DIR/bin/uasm"
}

#
# Fetches the Open Watcom v2 Linux installer into TOOLCHAIN_DIR and
# runs it targeting a local, non-system install directory.
#
# NOT VALIDATED: the exact unattended-install flags below are a
# best guess based on the installer's usual (InstallBuilder-style)
# conventions, not a confirmed working invocation. If this fails,
# run "$TOOLCHAIN_DIR/open-watcom-installer" by hand instead and
# point it at the same OPENWATCOM_DIR.
#

install_open_watcom() {
	local INSTALLER="$TOOLCHAIN_DIR/open-watcom-installer"
	local OPENWATCOM_DIR="$TOOLCHAIN_DIR/open-watcom"

	if [ -d "$OPENWATCOM_DIR" ]; then
		printf 'Open Watcom already installed, skipping.\n'
		return 0
	fi

	mkdir -p "$TOOLCHAIN_DIR"
	curl -fL -o "$INSTALLER" "$OPENWATCOM_INSTALLER_URL"
	chmod +x "$INSTALLER"

	if ! "$INSTALLER" --mode unattended --unattendedmodeui none --prefix "$OPENWATCOM_DIR"; then
		printf 'Unattended Open Watcom install failed -- run %s by hand.\n' "$INSTALLER" >&2
		exit 1
	fi
}

#
# Prints the PATH/environment additions needed to actually use what
# was just installed. build.sh sources this same TOOLCHAIN_DIR once
# the per-module port to this toolchain is far enough along -- for
# now this is setup only, nothing consumes it yet.
#

print_toolchain_env() {
	printf 'Toolchain installed under: %s\n' "$TOOLCHAIN_DIR"
	printf 'Add to PATH once the build actually uses it:\n'
	printf '  %s/bin:%s/open-watcom/binl64\n' "$TOOLCHAIN_DIR" "$TOOLCHAIN_DIR"
}

require_root
install_dosemu2
install_build_tools
build_uasm
install_open_watcom
print_toolchain_env
