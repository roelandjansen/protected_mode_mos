#!/usr/bin/env bash
set -euo pipefail

#
# Cleans build artifacts without building -- equivalent to
# ./build.sh --clean-only, kept as a separate script for anyone who
# prefers a dedicated name over remembering the flag. Deliberately a
# thin wrapper rather than a second copy of the file list, so there's
# exactly one place (build.sh's clean_build_artifacts, itself kept in
# sync with SOURCES/src/CLEANALL.BAT) that defines what "clean" means.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/build.sh" --clean-only
