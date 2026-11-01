#!/bin/bash
# Finder layout only; the caller handles building, signing and notarization.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: scripts/package-dmg.sh <app> <version> <output.dmg>' >&2; exit 1; }
app=$1
version=$2
dmg=$3
assets="$(cd "$(dirname "$0")" && pwd)/dmg"
[[ -d $app ]] || { echo "Missing app: $app" >&2; exit 1; }
mkdir -p "$(dirname "$dmg")"
work=$(mktemp -d "$(dirname "$dmg")/dmg-layout.XXXXXX")
work=$(cd "$work" && pwd)
mounted=false
cleanup() {
  if $mounted; then
    # Keep the working image if it cannot be detached safely.
    hdiutil detach "$work/mount" || return
  fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/root/.background" "$work/mount"
ditto "$app" "$work/root/Whoa Type.app"
ln -s /Applications "$work/root/Applications"
# A multi-resolution TIFF lets Finder choose 1x or 2x at the same point size.
tiffutil -cathidpicheck "$assets/background.png" "$assets/background@2x.png" \
  -out "$work/root/.background/background.tiff"
hdiutil create -ov -fs HFS+ -format UDRW -volname "Whoa Type $version" \
  -srcfolder "$work/root" "$work/layout.dmg"
hdiutil attach -readwrite -noautoopen -mountpoint "$work/mount" "$work/layout.dmg"
mounted=true
# Hosted CI cannot grant interactive Finder automation permission.
if [[ ${CI:-} != true ]]; then
  osascript "$assets/layout.applescript" "$work/mount"
  [[ -s "$work/mount/.DS_Store" ]] || { echo 'Finder did not save the DMG layout.' >&2; exit 1; }
fi
sync
hdiutil detach "$work/mount"
mounted=false
hdiutil convert "$work/layout.dmg" -ov -format UDZO -o "$dmg"
