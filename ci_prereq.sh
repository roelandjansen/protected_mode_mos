#!/usr/bin/env bash
set -euo pipefail

#
# Installs everything the build needs: dosbox and mtools for the
# DOS-era build/boot path (build.sh/run.sh), and the gcc/UASM/Open
# Watcom toolchain for the native-Linux build path it's migrating
# to. See the tooling policy and Linux-native-build notes. Targets
# openSUSE Leap 15.x, Leap 16.x, and Tumbleweed only.
#
# Package installs need root; nothing else here does. Does not use
# sudo anywhere -- run this as root already (e.g. inside a root CI
# container image), or as root manually.
#

UASM_REPO_URL="https://github.com/Terraspace/UASM.git"
UASM_PATCH_DBGCV_URL="https://github.com/clouds56/UASM/commit/806d54cf778246c96dcbe61a4649bf0aebcb0eba.patch"
UASM_PATCH_PTRCMP_URL="https://github.com/clouds56/UASM/commit/9cd3a400990e230571e06d4c758bd3bd35f90ab6.patch"
OPENWATCOM_ARCHIVE_URL="https://github.com/open-watcom/open-watcom-v2/releases/download/Current-build/open-watcom-2_0-c-linux-x64"

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
# Installs dosbox if it isn't already present. Standard Factory-
# derived package on Tumbleweed and Leap 15.x -- unlike dosemu2, no
# OBS fallback repo needed.
#

install_dosbox() {
	if command -v dosbox >/dev/null 2>&1; then
		printf 'dosbox already installed, skipping.\n'
		return 0
	fi

	zypper --non-interactive install dosbox
}

#
# Installs mtools if it isn't already present. run.sh needs mcopy
# to assemble the boot floppy from IMAGES/template/empty-bootable.img
# plus the current build output.
#

install_mtools() {
	if command -v mcopy >/dev/null 2>&1; then
		printf 'mtools already installed, skipping.\n'
		return 0
	fi

	zypper --non-interactive install mtools
}

#
# Installs the packages the native toolchain needs to build/fetch
# itself: a C compiler and make (to build UASM), git (to fetch UASM's
# source), curl (to fetch Open Watcom's archive and UASM's upstream
# portability patches), patch (to apply those patches), unzip (to
# extract Open Watcom's archive directly -- see install_open_watcom).
#

install_build_tools() {
	zypper --non-interactive install gcc make git curl patch unzip
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

		# UASM's gcc build doesn't compile clean on a current toolchain
		# as-is. Verified against actual HEAD -- seven separate fixes
		# needed below, all previously known or independently confirmed
		# here against real HEAD, not guessed. A full clean rebuild
		# with all seven applied together completes with zero errors:
		curl -fL "$UASM_PATCH_DBGCV_URL" | patch -p1
		curl -fL "$UASM_PATCH_PTRCMP_URL" | patch -p1

		# -std=gnu17: modern gcc defaults to -std=c23+, where "bool" is
		# a reserved keyword and clashes with H/bool.h's own
		# "typedef unsigned char bool;".
		# -fcommon: modern gcc defaults to -fno-common, and UASM's
		# global tentative definitions (evex/broadflags/etc., repeated
		# across translation units) rely on old-style common-symbol
		# linking -- otherwise it's a "multiple definition" link error.
		# -Wno-error=implicit-function-declaration: two genuine
		# upstream bugs -- assemble.c has "//#include \"simd.h\"", so
		# AddSimdTypes() (and types.c's SymSimd()) get called with no
		# visible prototype, and strupr() (defined in apiemu.c, the
		# Unix build's replacement for the MSVC CRT function) is never
		# declared anywhere the _strupr macro's call sites can see.
		# -Wno-error=incompatible-pointer-types: codegenv2.c passes
		# fixed-size array pointers (e.g. "unsigned char (*)[3]") where
		# a plain pointer is expected in several spots -- legal, if
		# sloppy, C.
		# -Wno-error=int-conversion: macho64.c does
		# "mm.header.flags = NULL;" where flags is a uint32_t --
		# harmless (NULL is 0), just badly typed.
		# -Wno-discarded-qualifiers: UASM's source routinely returns/
		# assigns "const char*" where plain "char*" is expected (its
		# own macro tables, string literals passed around loosely) --
		# harmless, high-volume noise, not worth patching upstream
		# source for. Verified this flag actually silences it (via
		# -fdiagnostics-show-option) without affecting error count or
		# the resulting binary.
		#
		# Two more warning classes exist (a harmless "alloca redefined"
		# from memalloc.h vs stdlib.h, and a "so large it is unsigned"
		# note on a 64-bit FNV hash constant) but neither is tied to an
		# individually toggleable -W flag in this gcc -- confirmed via
		# -fdiagnostics-show-option showing no [-Wxxx] tag on either,
		# and several plausible flag names (-Wno-macro-redefined,
		# -Wno-redefined, -Wno-cpp, -Wno-overflow) all silently no-op.
		# Only "-w" (disable all warnings outright) would kill these
		# too, not worth it for two cosmetic messages.
		# All four -Wno-error flags are functionally harmless (correct
		# values/calling convention, nothing actually miscompiled),
		# which is why old gcc only warned; gcc 14+ makes the first
		# three errors by default. Same class of fix the Gentoo
		# package for UASM carries for a subset of these (its issues
		# #143 and #197), extended here to what its older gcc
		# apparently didn't hit.
		make -f gccLinux64.mak CFLAGS='-std=gnu17 -fcommon -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-discarded-qualifiers'
	)

	cp "$BUILD_DIR/GccUnixR/uasm" "$TOOLCHAIN_DIR/bin/uasm"
}

#
# Prints a path relative to the current directory for display, so
# instructions read as e.g. "toolchain/open-watcom-installer" instead
# of a full absolute path when run from the repo (or somewhere under
# it). Falls back to the absolute path if $PWD isn't a sensible base
# (e.g. running from outside the repo entirely).
#

display_path() {
	local ABS_PATH="$1"
	local REL_PATH

	REL_PATH="$(realpath --relative-to="$PWD" "$ABS_PATH" 2>/dev/null || true)"

	if [ -n "$REL_PATH" ] && [ "${#REL_PATH}" -lt "${#ABS_PATH}" ]; then
		printf '%s' "$REL_PATH"
	else
		printf '%s' "$ABS_PATH"
	fi
}

#
# Fetches Open Watcom v2 and extracts it directly into TOOLCHAIN_DIR,
# bypassing its own installer entirely.
#
# The installer binary itself is broken in several independently
# confirmed ways on a current system: it mangles the target directory
# it's given (a literal "~" in a typed path doesn't get shell-expanded
# and gets concatenated rather than rejected; even a plain "-d" value
# or its own untouched default gets its old Windows/OS2-era "drive
# letter" default subpath glued onto whatever prefix you give it,
# e.g. ".../toolchain/usr/bin/watcom" instead of the path actually
# given); its disk-space check reports 0 bytes free for every path
# including its own default, on drives independently confirmed to
# have plenty of room (most likely a statically-linked 20-year-old
# binary reading a "statfs" struct whose layout has since changed);
# and in unattended mode it can hang indefinitely rather than fail
# cleanly. None of that is a real problem with the target system.
#
# It also turns out to be unnecessary to fight any of that: this
# installer .run file is just a zip archive with an ELF stub prepended
# ("unzip -l" reads it directly, no extraction tool needed), and the
# actual compiler/assembler/linker binaries (binl64/wcc, wasm, wlink,
# wlib, etc.) are plain files inside it -- so this just unzips them
# straight into place instead of running the installer's own broken
# copy/verify logic. Verified against the real downloaded archive:
# the extracted binl64/wcc runs and correctly reports itself as the
# 16-bit DOS C compiler.
#

install_open_watcom() {
	local ARCHIVE="$TOOLCHAIN_DIR/open-watcom-installer"
	local OPENWATCOM_DIR="$TOOLCHAIN_DIR/open-watcom"

	if [ -d "$OPENWATCOM_DIR" ]; then
		printf 'Open Watcom already installed, skipping.\n'
		return 0
	fi

	mkdir -p "$OPENWATCOM_DIR"
	curl -fL -o "$ARCHIVE" "$OPENWATCOM_ARCHIVE_URL"
	unzip -q "$ARCHIVE" -d "$OPENWATCOM_DIR"
	chmod +x "$OPENWATCOM_DIR"/binl64/*
	rm -f "$ARCHIVE"
}

#
# Everything above runs as root (needed for the zypper steps), so
# everything it creates -- including TOOLCHAIN_DIR, which nothing
# else here actually needs root for -- ends up root-owned. That
# leaves the normal developer account unable to write into it (e.g.
# to run the Open Watcom installer interactively as themselves and
# have it create files there). Hand it back to whoever owns the repo
# checkout itself (SCRIPT_DIR), since that's who actually cloned this
# and will be using the toolchain day to day.
#

fix_toolchain_ownership() {
	local OWNER

	if [ ! -d "$TOOLCHAIN_DIR" ]; then
		return 0
	fi

	OWNER="$(stat -c '%u:%g' "$SCRIPT_DIR")"
	chown -R "$OWNER" "$TOOLCHAIN_DIR"
}

#
# Writes a sourceable env file rather than just printing a PATH
# suggestion, so anything that actually needs the toolchain -- this
# shell interactively, or another script -- has one real source of
# truth instead of everyone reconstructing the same PATH addition.
# build.sh sources this same file.
#

write_toolchain_env() {
	local ENV_FILE="$TOOLCHAIN_DIR/env.sh"

	cat > "$ENV_FILE" << SCRIPT_EOF
#!/usr/bin/env bash
# Generated by ci_prereq.sh -- source this, don't edit it directly.
PATH="$TOOLCHAIN_DIR/bin:$TOOLCHAIN_DIR/open-watcom/binl64:\$PATH"
export PATH
SCRIPT_EOF

	chown "$(stat -c '%u:%g' "$SCRIPT_DIR")" "$ENV_FILE"

	printf 'Toolchain installed under: %s\n' "$(display_path "$TOOLCHAIN_DIR")"
	printf 'For interactive use, source: %s\n' "$(display_path "$ENV_FILE")"
}

require_root
install_dosbox
install_mtools
install_build_tools
build_uasm
install_open_watcom
fix_toolchain_ownership
write_toolchain_env
