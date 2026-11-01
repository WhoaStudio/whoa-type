# Source layout

The module folders in ARCHITECTURE.md now contain the implementation. The app target remains a single Xcode target; Package.swift compiles the same core sources for the core library and automated Swift Testing tests.

- `App`: desired/effective state, serialized lifecycle and request coordination.
- `AppShell`: menu, Settings, and Input Monitoring guidance.
- `Input`: dedicated passive tap run loop, transient state and physical pan tables.
- `Audio`: bounded SPSC channels, source-node renderer, voices and serialized engine control.
- `SoundPacks`: manifest validation, immutable PCM banks, loader and latest-request serialization.
- `Permissions`: Input Monitoring preflight, request and settings guidance.
- `Settings`: versioned preferences and actual SMAppService status.
- `Resources/SoundPacks/switch-01` through `switch-38`: named PCM packs derived from the existing recordings.

`python3 Tools/prepare_soundpacks.py /path/to/originals` reproduces asset conversion with macOS afconvert from external source recordings; loose source audio is not bundled. `Tools/benchmark.sh` runs only synthetic audio work. `Tools/CaptureProbe` is a separate disposable feasibility app. Release and manual-validation status is recorded in `Docs`.
