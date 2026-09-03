#!/usr/bin/env bash
set -euo pipefail

#
# Installs dosemu2 via zypper. Targets openSUSE Leap 15.x, Leap 16.x,
# and Tumbleweed only -- see the tooling policy doc.
#
# Does not use sudo. This is meant to run as root already (e.g. inside a
# root CI container image); if it isn't, it fails with an instructive
# message instead of trying to escalate itself.
#

REPO_ALIAS="dosemu2"
REPO_URL="https://download.opensuse.org/repositories/home:/mnhauke:/dosemu2/openSUSE_Tumbleweed/"

#
# Confirm we're running with the privileges zypper needs, without
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
# Install dosemu2 if it isn't already present. Tries the default repos
# first; falls back to adding the OBS repo only if needed.
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
	printf 'Verify %s still matches your distro/version before relying on this in CI.\n' "$REPO_URL" >&2

	zypper --non-interactive addrepo --refresh "$REPO_URL" "$REPO_ALIAS"
	zypper --non-interactive --gpg-auto-import-keys refresh "$REPO_ALIAS"
	zypper --non-interactive install dosemu
}

require_root
install_dosemu2
