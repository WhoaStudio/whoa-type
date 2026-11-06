#!/bin/bash
# Generate and sign the feed only after the final DMG has been notarized/stapled.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo 'Usage: scripts/generate-update-feed.sh <version>' >&2; exit 1; }
version=$1
python3 scripts/version.py "$version"
: "${SPARKLE_PRIVATE_ED_KEY:?Set the Sparkle private key in the signing environment}"
output="${WHOA_RELEASE_DIR:-$PWD/build/release}"
tools="$output/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
feed_dir=$(mktemp -d)
trap 'rm -rf "$feed_dir"' EXIT
archive="WhoaType-$version-macOS.dmg"
cp "$output/$archive" "$feed_dir/$archive"
cp "$output/notes.md" "$feed_dir/WhoaType-$version-macOS.md"
prefix="https://github.com/${GITHUB_REPOSITORY:-WhoaStudio/whoa-type}/releases/download/v$version/"
# The private key is sent on stdin, never as a process argument or log message.
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$tools/generate_appcast" \
  --ed-key-file - --download-url-prefix "$prefix" --embed-release-notes \
  --maximum-deltas 0 "$feed_dir"
python3 - "$feed_dir/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
signature = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'
enclosures = root.findall('./channel/item/enclosure')
if not enclosures or any(not item.get(signature) for item in enclosures):
    raise SystemExit('Refusing to publish a feed without signed update archives; check that the public and private keys match.')
PY
printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$tools/sign_update" --ed-key-file - --verify "$feed_dir/appcast.xml"
cp "$feed_dir/appcast.xml" "$output/appcast.xml"
