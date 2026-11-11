# App updates

Whoa Type uses Sparkle 2.10.1. Sparkle owns the scheduler, preference storage,
release-notes window, downloads, Ed25519 verification, installer, and relaunch.
General Settings and the menu bar expose the same updater. Checks run on launch
and at the selected interval while the app runs, unless automatic checks are off.
Automatic downloads/installations are opt-in and normally install on quit.

## Release configuration (required before shipping)

1. Use Sparkle's `bin/generate_keys --account whoa-type` on a trusted Mac.
   Back up that key securely. Never commit it. Set the printed public key as the
   GitHub Actions repository **variable** `SPARKLE_PUBLIC_ED_KEY`.
2. Export the private key with `bin/generate_keys --account whoa-type -x <secure-file>`.
   Import the file contents into the repository **secret**
   `SPARKLE_PRIVATE_ED_KEY`, then remove the exported file securely. For example,
   `gh secret set SPARKLE_PRIVATE_ED_KEY < <secure-file>` avoids terminal output.
3. Configure the existing Developer ID and notarization secrets used by
   `scripts/configure-signing.sh`. Updater releases now fail instead of publishing
   unsigned builds when these credentials are missing.
4. Run the existing Release workflow. It builds a universal app, signs Sparkle's
   nested helpers, notarizes/staples the app and DMG, then runs
   `scripts/generate-update-feed.sh`. The feed embeds release notes and signs
   both the final archive and the XML. Generation rejects missing signatures or
   mismatched public/private keys. Both assets are uploaded before the draft
   release is published.

The default feed is
`https://github.com/WhoaStudio/whoa-type/releases/latest/download/appcast.xml`.
Each stable release must include that asset. GitHub serves the DMG from its
version-specific release URL. Keep `CFBundleVersion` increasing; it is the update
comparison version. Do not alter the DMG or feed after signing.

Local builds can pass `SPARKLE_PUBLIC_ED_KEY=...` and `SPARKLE_FEED_URL=https://...`
to `xcodebuild`, or export these variables when using `scripts/build-dmg.sh`.
A build without a valid public key deliberately disables updates and explains
this in Settings; it never accepts unverified archives. Feed signatures and
archive verification before extraction are required. Keep Developer ID identity
and signing keys stable between releases.

## Automated checks

After the Debug build:

```sh
scripts/test-updater.sh /absolute/path/to/DerivedData
swift test --filter SettingsTests
```

The updater check compiles the production controller into an isolated app bundle,
tests all three preferences across three separate processes, and checks that the
last-check time restores. It exercises no-update, offline, and signature-failure
status messages. It then creates a mock version 9999.0.0 DMG with disposable keys,
runs the production feed generator, verifies the signed feed with Sparkle, and
asserts that tampered archives and feeds are rejected. Temporary keys stay outside Keychain
and are deleted with the fixture. This does not perform installation or restart.

## Full manual check: detect → notify → download → install → restart

Run this in a clean macOS VM with a Developer ID signing identity. The app is
sandboxed, so signing/notarization and the XPC installer must be exercised on real
app bundles; delegate mocks cannot establish that installation works.
Use a separate public GitHub test repository and test signing keys. Do not publish
the fixture to the production repository or run it over a production installation.

1. Generate a separate key with `generate_keys --account whoa-type-fixture`.
   Export its private seed to a protected file outside the checkout. Configure
   the normal `WHOA_SIGNING_IDENTITY`, `WHOA_TEAM_ID`, `WHOA_NOTARY_PROFILE`
   environment variables for the packaging script.
2. Set `SPARKLE_PUBLIC_ED_KEY` to the fixture public key and
   `SPARKLE_FEED_URL` to
   `https://github.com/TEST_OWNER/TEST_REPO/releases/latest/download/appcast.xml`.
   Set `GITHUB_REPOSITORY=TEST_OWNER/TEST_REPO`. Choose an absolute temporary
   fixture directory, then build the two versions:

   ```sh
   WHOA_RELEASE_DIR="$fixture/old" scripts/build-dmg.sh 9998.0.0
   WHOA_RELEASE_DIR="$fixture/new" scripts/build-dmg.sh 9999.0.0
   printf '%s\n' 'Mock release: update installation test.' > "$fixture/new/notes.md"
   SPARKLE_PRIVATE_ED_KEY=$(cat "$fixture/private-key") \
     WHOA_RELEASE_DIR="$fixture/new" scripts/generate-update-feed.sh 9999.0.0
   gh release create v9999.0.0 --repo "$GITHUB_REPOSITORY" \
     "$fixture/new/WhoaType-9999.0.0-macOS.dmg" "$fixture/new/appcast.xml" \
     --title 'Mock updater release' --notes 'Disposable update fixture'
   ```

3. Install version 9998.0.0 from its DMG into `/Applications`, unmount the DMG,
   and launch. With automatic checks on, expect Sparkle to offer **9999.0.0**
   and show the mock release notes. The menu bar and Settings should also show
   the available version. Choose **Remind Me Later**, then use **Check for
   Updates…** to bring the offer back.
4. Select **Install Update**, watch the download complete, then select
   **Install and Relaunch**. Expect the app to quit, replace the old bundle,
   restart, and report **9999.0.0** in General Settings. Verify the selected
   sound pack and update preferences persisted.
5. Check again: expect **You're up to date** and an updated last-checked time.
   Quit/relaunch after toggling automatic checks off and changing frequency;
   ensure the preferences restore and no launch check occurs. Manual checks
   must still work. Re-enable automatic checks to resume scheduling.
6. Restore the old fixture app. Enable automatic download/install, detect the
   update, let it download, and quit normally. Expect the update to install on
   quit and the next launch to show 9999.0.0. Recheck both toggles after launch.
7. Restore the old fixture for each failure case: disconnect networking before
   a manual check; interrupt a download; serve a signed feed whose archive URL
   returns 404; and serve an altered archive with its original signature.
   Expect a clear error with retry possible and the old app still installed.
   Tampered signatures must never reach the installer. Re-sign a feed when
   intentionally changing its URL; otherwise feed verification should fail first.

Record macOS version, both bundle versions, feed URL, and pass/fail for each step
in the release checklist. Remove the test release and dispose of its keys afterward.
The full installation/relaunch check requires release credentials and is separate
from the automated preference/signature checks.
