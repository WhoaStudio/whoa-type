#!/bin/zsh
# Compatibility entry point for local Developer ID packaging.
set -euo pipefail
cd "${0:A:h}/.."
: "${WHOA_SIGNING_IDENTITY:?Set WHOA_SIGNING_IDENTITY}"
: "${WHOA_TEAM_ID:?Set WHOA_TEAM_ID}"
: "${WHOA_NOTARY_PROFILE:?Set WHOA_NOTARY_PROFILE}"
exec scripts/build-dmg.sh "${WHOA_VERSION:-1.0.0}"
