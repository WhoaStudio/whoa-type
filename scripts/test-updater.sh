#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo 'Usage: scripts/test-updater.sh <derived-data-path>' >&2; exit 1; }
framework_dir="$1/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
app="$work/UpdaterPreferencesCheck.app"
mkdir -p "$app/Contents/MacOS"
python3 - "$app/Contents/Info.plist" <<'PY'
import base64, plistlib, sys, uuid
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleIdentifier': 'studio.whoa.updater-tests.' + uuid.uuid4().hex,
        'CFBundleExecutable': 'UpdaterPreferencesCheck',
        'CFBundleVersion': '1.0.0', 'CFBundleShortVersionString': '1.0.0',
        'SUFeedURL': 'https://example.invalid/appcast.xml',
        # Test-only public key. No network or installation is performed here.
        'SUPublicEDKey': base64.b64encode(bytes(range(32))).decode(),
        'SUEnableAutomaticChecks': True, 'SUAllowsAutomaticUpdates': True,
        'SUAutomaticallyUpdate': False,
    }, f)
PY
xcrun swiftc -parse-as-library -F "$framework_dir" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$framework_dir" \
  whoa-type/Updates/UpdateController.swift Tests/UpdaterIntegration/Preferences.swift \
  -o "$app/Contents/MacOS/UpdaterPreferencesCheck"
"$app/Contents/MacOS/UpdaterPreferencesCheck" write
"$app/Contents/MacOS/UpdaterPreferencesCheck" read
"$app/Contents/MacOS/UpdaterPreferencesCheck" verify

# Exercise the release tooling against a disposable, signed mock newer release.
xcrun swift Tests/UpdaterIntegration/MakeFixture.swift "$work"
codesign --force --sign - "$app"
mkdir -p "$work/release"
ln -s "$1" "$work/release/DerivedData"
hdiutil create -quiet -srcfolder "$app" -format UDZO \
  "$work/release/WhoaType-9999.0.0-macOS.dmg"
printf '%s\n' 'Mock update 9999.0.0: updater integration check.' > "$work/release/notes.md"
SPARKLE_PRIVATE_ED_KEY=$(cat "$work/private-key") WHOA_RELEASE_DIR="$work/release" \
  scripts/generate-update-feed.sh 9999.0.0
python3 - "$work/release/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item = root.find('./channel/item')
assert item.find(ns + 'version').text == '9999.0.0'
assert 'Mock update 9999.0.0' in item.find('description').text
PY
tools="$1/SourcePackages/artifacts/sparkle/Sparkle/bin"
signature=$(python3 - "$work/release/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get(
    '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)
archive="$work/release/WhoaType-9999.0.0-macOS.dmg"
"$tools/sign_update" --ed-key-file "$work/private-key" --verify "$archive" "$signature"
printf '\0' >> "$archive"
if "$tools/sign_update" --ed-key-file "$work/private-key" --verify "$archive" "$signature" >/dev/null 2>&1; then
  echo 'Tampered archive was incorrectly accepted.' >&2
  exit 1
fi
# Altering a signed feed must fail Sparkle's cryptographic verification.
python3 - "$work/release/appcast.xml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('9999.0.0', '9999.0.1'))
PY
if "$tools/sign_update" --ed-key-file "$work/private-key" --verify "$work/release/appcast.xml" >/dev/null 2>&1; then
  echo 'Tampered feed was incorrectly accepted.' >&2
  exit 1
fi
echo 'Signed mock release and tampered archive/feed rejection checks passed.'
