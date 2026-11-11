# Whoa Type architecture

## Context and scope

Whoa Type is a native macOS 26.5+ menu bar keyboard and pointer-button sound utility. The Xcode app target uses SwiftUI, Core Graphics passive input observation and AVAudioEngine. App Sandbox, hardened runtime and LSUIElement are enabled in both build configurations. There are no third-party package dependencies.

## Modules and ownership

Source folders below are under `whoa-type`:

| Module | Responsibility |
| --- | --- |
| App | Main-actor desired/effective state and serialized lifecycle coordination. |
| AppShell | Window-style MenuBarExtra popover and Settings panes. Hover auditions a switch; clicking selects it. |
| Permissions | Input Monitoring preflight/request and System Settings guidance. |
| Input | Dedicated passive tap run loop, physical ANSI/ISO/JIS mapping and transient held-key/button state. |
| SoundPacks | Manifest validation, asynchronous PCM loading, immutable banks and latest-request preview coordination. |
| Audio | Engine control, bounded trigger/control channels and fixed voice renderer. |
| Settings | Versioned UserDefaults preferences and actual SMAppService login-item status. |

`Package.swift` builds selected core sources from the same tree for `Tests/WhoaTypeCoreTests`; it excludes the app shell, coordinator, permissions, login-item service and resources.

## Development tools

Run `python3 Tools/prepare_soundpacks.py /path/to/originals` to convert external source recordings with macOS `afconvert`. Loose source audio is excluded from the bundle. `Tools/benchmark.sh` runs synthetic audio workloads. `Tools/CaptureProbe/main.swift` is a standalone feasibility probe outside the app build and CI.

## Threading and real-time contract

The main actor owns UI and lifecycle decisions. Capture has a dedicated run loop; loading and engine control use separate queues. Capture is the sole trigger producer, including synthetic Preview events. The renderer consumes bounded commands and mixes preloaded samples through a fixed voice pool. Keep allocation, locks, file I/O, logging, UI updates and graph mutations out of capture/render callbacks.

Bank installation and resets use renderer acknowledgements so retained PCM remains alive until rendering finishes. Preview pauses live capture, auditions through the same renderer at the current volume, and restores the selected pack. Latest requests cancel older work. Selection is persisted only after a successful installation.

## Sound-pack contract

`whoa-type/Resources/SoundPacks` contains 15 switch packs, each with `manifest.json`, the source `config.json` and a `prepared/` folder of PCM samples. Names are descriptive labels, not hardware identifications. Keyboard down/up phases may share the same recording. Pointer presses share six variants without immediate repeats and use a separate release sample.

The validator accepts schema version 1, mono PCM WAV at 44.1/48/96 kHz, 16/24-bit integer or Float32, at most 500 ms per sample and 64 MiB decoded per pack. It checks paths, mappings, preview pairing and bounds. License references are optional but validated when present; packs without one are an open release blocker. Recording redistribution rights remain a release requirement.

Physical key position controls pan, pitch and tone; key-specific shading makes large keys heavier and modifiers lighter. Pointer sounds are centered and bypass keyboard positional tone shading.

## Permission and lifecycle

Sound defaults off, volume to 0.5 and geometry to ANSI. Preferences store sound state, volume, selected pack, geometry and schema version. Login-item status comes from macOS.

Live capture requires enabled sound, Input Monitoring authorization and prepared audio. Preview can run without input permission and while sound is off; volume zero remains silent. Accessibility is not requested. Secure Input may suppress delivery. Sleep, route changes, permission changes and Quit coordinate capture pauses and audio resets; permission and engine health are periodically checked while enabled.

## Distribution and validation

See [distribution](DISTRIBUTION.md) for local universal packaging and Developer ID notarization, [validation](VALIDATION.md) for historical measurements and outstanding interactive checks, and [privacy](PRIVACY.md) for the input-data contract. `ci.yml` builds and tests every pull request; the Release workflow tests, builds and publishes the DMG and cask.
