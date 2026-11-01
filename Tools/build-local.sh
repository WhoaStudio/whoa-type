#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export WHOA_RELEASE_DIR="${WHOA_RELEASE_DIR:-$PWD/build/local}"
exec scripts/build-dmg.sh "${WHOA_VERSION:-1.0.0}"
