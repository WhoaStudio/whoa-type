#!/bin/bash
# CI only: keep credentials in an ephemeral keychain; never echo their values.
set -euo pipefail
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY APPLE_TEAM_ID APPLE_ID APPLE_APP_PASSWORD; do
  if [[ -z ${!name:-} ]]; then
    echo 'Signing secrets are incomplete; building unsigned.'
    echo 'signed=false' >> "$GITHUB_OUTPUT"
    exit 0
  fi
done
keychain="$RUNNER_TEMP/whoa-release.keychain-db"
password=$(openssl rand -hex 32)
echo "::add-mask::$password"
printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/whoa-certificate.p12"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$RUNNER_TEMP/whoa-certificate.p12" -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
xcrun notarytool store-credentials whoa-release --keychain "$keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" >/dev/null
# Pass the temporary keychain explicitly to notarization.
{
  echo "WHOA_SIGNING_IDENTITY=$MACOS_SIGNING_IDENTITY"
  echo "WHOA_TEAM_ID=$APPLE_TEAM_ID"
  echo 'WHOA_NOTARY_PROFILE=whoa-release'
  echo "WHOA_NOTARY_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
echo 'signed=true' >> "$GITHUB_OUTPUT"
