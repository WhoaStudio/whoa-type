# GitHub and Homebrew distribution

Repository: https://github.com/WhoaStudio/Whoa-Typer. The Homebrew cask lives in
`Casks/whoa-type.rb` here. Releases require macOS 26.5+ and contain arm64 and x86_64.

## Release

Run `scripts/release.sh 1.2` from clean, synchronized `stable`. No other command is
needed for a release. See the README for installation and the GitHub UI alternative.
The release command refuses existing tags and a branch ahead of or behind origin.
It uses an atomic push so a rejected push cannot publish just the branch or tag.
A failed push leaves the local commit/tag for inspection; it never force-pushes.

Actions needs `contents: write` and permission to push version/cask commits to
`stable`. Configure branch and tag rules accordingly. The UI trigger must be on
the default branch. UI-created tags use `GITHUB_TOKEN` and do not trigger a second
run; the dispatch run builds and publishes directly. The workflow serializes
releases. Re-run a failed run to finish publication/cask updates; do not move a
published tag. For a failed UI run after tag creation, rerun the failed jobs or dispatch the same
version again; an existing tag is validated and reused without another version
commit. Never reuse a version for different app contents.

## Optional signing secrets

Set these repository Actions secrets (never commit credential values):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key exported as P12 |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `MACOS_SIGNING_IDENTITY` | Full `Developer ID Application: …` identity |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for that account |

If any secret is absent, Actions builds unsigned and says so in the release notes.
If all are present, invalid credentials or failed notarization fail the job rather
than silently downgrading signing. Credentials are imported into a temporary
keychain and removed in an always-run cleanup step. The app and DMG are signed,
notarized, and stapled before the final checksum is calculated.

For local signed packaging, configure a Developer ID identity in Keychain and
store a notarytool profile interactively:

```sh
xcrun notarytool store-credentials whoa-type-notary
WHOA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAM_ID)' \
WHOA_TEAM_ID=TEAM_ID WHOA_NOTARY_PROFILE=whoa-type-notary \
  scripts/build-dmg.sh 1.2
```

Without all three `WHOA_*` signing variables, the shared packager builds unsigned.
`WHOA_RELEASE_DIR` optionally overrides `build/release`. Local Finder layout
requires a logged-in GUI session and Finder automation permission; `CI=true`
skips that interactive layout step (as on hosted runners), preserving the app
and Applications shortcut. The old
`Tools/build-local.sh` and `Tools/release.sh` delegate to this packager.

## Local validation

```sh
scripts/build-dmg.sh 1.2
hdiutil attach -readonly -nobrowse build/release/WhoaType-1.2-macOS.dmg
# Check /Volumes/Whoa Type 1.2/Whoa Type.app, then detach that volume.
actionlint .github/workflows/release-build.yml
brew tap-new --no-git WhoaStudio/release-validation
mkdir -p "$(brew --repository WhoaStudio/release-validation)/Casks"
cp Casks/whoa-type.rb "$(brew --repository WhoaStudio/release-validation)/Casks/whoa-type.rb"
brew trust --cask WhoaStudio/release-validation/whoa-type # Homebrew 7+
brew audit --cask --strict WhoaStudio/release-validation/whoa-type
brew style Casks/whoa-type.rb
```

`Tools/generate-cask.py <dmg> --version 1.2` regenerates the production cask from
the final artifact. `--repository owner/repo` overrides the GitHub repository;
`--url file:///absolute/path/to.dmg --output /path/to/test-cask.rb` supports local
validation without publishing. A mount check does not establish Gatekeeper or
interactive sound/Input Monitoring behavior; see VALIDATION.md.

Bundled recordings have no supplied provenance/license; confirm redistribution
rights and supply attribution before publishing. LICENSE covers source code and
does not grant rights to the recordings.
