#!/bin/bash
# Shared local/CI packager. Local builds use an Apple Development identity.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo 'Usage: scripts/build-dmg.sh <version>' >&2; exit 1; }
version=$1
python3 scripts/version.py "$version"
output="${WHOA_RELEASE_DIR:-$PWD/build/release}"
mkdir -p "$output"
output=$(cd "$output" && pwd)
signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
updater_settings=()
if [[ -n ${SPARKLE_PUBLIC_ED_KEY:-} ]]; then
  updater_settings+=("SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_ED_KEY")
fi
if [[ -n ${SPARKLE_FEED_URL:-} ]]; then
  updater_settings+=("SPARKLE_FEED_URL=$SPARKLE_FEED_URL")
fi
signed=false
timestamp=(--timestamp=none)
if [[ -n ${WHOA_SIGNING_IDENTITY:-} && -n ${WHOA_TEAM_ID:-} && -n ${WHOA_NOTARY_PROFILE:-} ]]; then
  signed=true
  identity=$WHOA_SIGNING_IDENTITY
  timestamp=(--timestamp)
  signing=(CODE_SIGN_STYLE=Manual "DEVELOPMENT_TEAM=$WHOA_TEAM_ID"
    "CODE_SIGN_IDENTITY=$WHOA_SIGNING_IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp)
else
  identity=${WHOA_LOCAL_SIGNING_IDENTITY:-}
  if [[ -z $identity ]]; then
    identity=$(security find-identity -v -p codesigning | awk '/"Apple Development: / { id=$2; count++ } END { if (count == 1) print id }')
  fi
  [[ -n $identity ]] || {
    echo 'Install an Apple Development signing identity or set WHOA_LOCAL_SIGNING_IDENTITY to select one.' >&2
    exit 1
  }
fi
echo "Building $version (Developer ID signed: $signed)"
xcodebuild -quiet -project whoa-type.xcodeproj -scheme whoa-type \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$output/DerivedData" ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$version" ${updater_settings[@]+"${updater_settings[@]}"} \
  "${signing[@]}" build
app="$output/DerivedData/Build/Products/Release/Whoa Type.app"
[[ -d $app ]] || { echo "Missing app: $app" >&2; exit 1; }
architectures=$(lipo -archs "$app/Contents/MacOS/Whoa Type")
[[ $architectures == *arm64* && $architectures == *x86_64* ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist") == "$version" ]]
# Match Sparkle's signing identity to the app for hardened runtime library validation.
framework="$app/Contents/Frameworks/Sparkle.framework"
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign "$identity" --options runtime "${timestamp[@]}" \
    --preserve-metadata=entitlements "$framework/Versions/B/$helper"
done
codesign --force --sign "$identity" --options runtime "${timestamp[@]}" "$framework"
codesign --force --sign "$identity" --options runtime "${timestamp[@]}" \
  --preserve-metadata=entitlements "$app"
if $signed; then
  notary_args=(--keychain-profile "$WHOA_NOTARY_PROFILE")
  if [[ -n ${WHOA_NOTARY_KEYCHAIN:-} ]]; then notary_args+=(--keychain "$WHOA_NOTARY_KEYCHAIN"); fi
  codesign --verify --deep --strict "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$output/notarization.zip"
  xcrun notarytool submit "$output/notarization.zip" "${notary_args[@]}" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute "$app"
fi
dmg="$output/WhoaType-${version}-macOS.dmg"
scripts/package-dmg.sh "$app" "$version" "$dmg"
if $signed; then
  codesign --sign "$WHOA_SIGNING_IDENTITY" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
else
  echo 'Local testing build: development-signed app bundle.'
fi
shasum -a 256 "$dmg"
