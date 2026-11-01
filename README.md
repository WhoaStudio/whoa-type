# Whoa Type

A native macOS 26.5+ menu bar utility that plays bundled keyboard samples on physical key presses and releases, plus click/release sounds for trackpad and mouse buttons. SwiftUI, a passive Core Graphics session tap, and an AVAudioSourceNode mixer; no third-party runtime dependencies or network services.

## Install

Requires macOS 26.5 or later, on Apple Silicon or Intel.
Download the versioned DMG from [GitHub Releases](https://github.com/WhoaStudio/Whoa-Typer/releases),
open it, and drag Whoa Type to Applications.

Or add this repository as a Homebrew tap and install its cask:

```sh
brew tap WhoaStudio/whoa-typer https://github.com/WhoaStudio/Whoa-Typer.git
brew install --cask WhoaStudio/whoa-typer/whoa-type
open -a "Whoa Type"
```

Releases without signing credentials are unsigned and not notarized; their release
notes explicitly say so. macOS may block those downloads from opening.

Source code is under the [MIT license](LICENSE). Bundled recordings are
excluded from that grant pending confirmation of their redistribution rights.
See [distribution](Docs/DISTRIBUTION.md) before publishing.

## Build

Build with Xcode and the macOS SDK. The Swift package requires Swift tools 6.2 or later:

```sh
xcodebuild -project whoa-type.xcodeproj -scheme whoa-type -destination 'platform=macOS' build
swift test
```

Launch the signed app, open its menu bar icon, then Settings. Sound starts off. Enable Whoa Type in System Settings → Privacy & Security → Input Monitoring, relaunch if macOS requests it, and enable Sound. The two capture probes are separate apps: granting them permission does not grant the main app permission.

The menu bar popover includes the sound toggle, volume slider, and switch list. Click a switch to select it; hovering a switch starts a preview.

Settings uses a sidebar with Playback, Switch Library, Input Access, and Startup panes. Open it from Whoa Type Settings… in the menu bar, or press ⌘, while the app menu is active. Playback includes volume and ANSI/ISO/JIS geometry; Switch Library provides selection and Preview; Input Access manages keyboard permission; Startup manages launch at login. Playback preferences persist between launches, and macOS manages login-item registration. Preview works without Input Monitoring and while Sound is off; volume zero remains silent. Switch names are descriptive labels for the existing recordings, not hardware identifications. Both phases explicitly use the same source recording in this initial asset set. Physical-key gain and pitch shading makes Space, Return, and Delete heavier and modifiers lighter. Across the keyboard, pitch and tone move from deeper/warmer on the left to brighter/higher on the right while retaining the selected recording. Preview traverses that range.

Secure Input/password contexts may suppress sounds. Bluetooth introduces substantial variable delay. Tap-creation failures are shown separately from missing Input Monitoring permission. Retry is available in Settings. Closing Settings keeps the menu bar utility running; choose Quit to shut it down.

See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and real-time contracts, [validation](Docs/VALIDATION.md) for measured results and outstanding manual checks, and [distribution](Docs/DISTRIBUTION.md) for GitHub packaging.

Mouse and trackpad clicks follow the same Sound toggle and volume. Left, right, and auxiliary buttons use six existing press recordings, randomly varied without immediate repeats, plus the existing release recording. Both mouse and trackpad use this shared pool. Pointer movement, scrolling, pressure, and gestures do not produce sounds or get recorded.

## Imported sound packs

Sixteen filename-based packs from the Neptune archive collection are bundled alongside the original switches. Reproduce the import with `python3 Tools/import_soundpacks.py /path/to/zips`; existing destination folders are never overwritten and source ZIPs are preserved. Each imported folder retains its config and original recordings, plus PCM samples and a manifest for the existing loader.

The importer explicitly maps named Enter, Space/Spacebar, Backspace and Tab recordings to macOS physical codes 36, 49, 51 and 48. Other keys, including A (0), use fallback variants. Release recordings are used when `support-events` is true; press-only packs use silence on release. Mouse samples come from the existing shared click pool. Undocumented `key_N` recordings remain preserved but are not assigned speculative key mappings.

Unsupported configs and samples are skipped and listed in `whoa-type/Resources/SoundPacks/neptune-import.log`. Cherry MX Blue was skipped because its fallback recording exceeds the loader's 500 ms limit. These archives contain no Mechvibes `single`/`multi` configs or sprite mappings; this importer supports their filename-based format only.

## Testing and packaging

`swift test` runs the core Swift Testing suite, not UI or permission checks. Use `WHOA_AUDIO_INTEGRATION=1 swift test` to include the real audio-engine test. No application environment variables or external services are required for normal use.

For a universal local DMG, run `scripts/build-dmg.sh 1.2`. Output is
`build/release/WhoaType-1.2-macOS.dmg`. Local and CI builds use the same script.
It builds unsigned unless Developer ID signing and notary credentials are configured.
See [distribution](Docs/DISTRIBUTION.md) for signing setup.

## Releasing

From a clean `stable` branch that exactly matches `origin/stable`, run:

```sh
scripts/release.sh 1.2
```

Use one to three numeric components, without `v` (e.g. `1`, `1.2`, `1.2.3`).
The command bumps both Xcode version settings, commits, tags `v1.2`, and pushes
both atomically. It prints the Actions link and watches the run when `gh` is
installed and authenticated. No Makefile is used in this project.

The Release workflow checks that the tag is on `stable`, builds the universal
DMG using the tag version, publishes generated release notes and the DMG, and
commits the final checksum and version to `Casks/whoa-type.rb` on `stable`.
Pull that cask commit before your next release. Alternatively, select **Actions →
Release → Run workflow** and enter the version without `v`; this performs the same
version commit/tag operation on `stable` and continues publishing in that run.
Manual pushes of `v*` tags also publish; packaging always takes its version from
the tag, even if the project settings differ.

Repository setup: publish the initial commit and `stable` branch, put this workflow
on the default branch for the UI trigger, and allow Actions to write repository
contents. Branch/tag protection must permit the maintainer's release push and the
workflow's version/cask commits. Signing secrets and local verification commands
are listed in [distribution](Docs/DISTRIBUTION.md).
