# Agent guidance

## Commands

- Build: `xcodebuild -project whoa-type.xcodeproj -scheme whoa-type -destination 'platform=macOS' build`.
- Core tests: `swift test`. Include real engine output with `WHOA_AUDIO_INTEGRATION=1 swift test`.
- Synthetic renderer benchmark: `zsh Tools/benchmark.sh`; enable allocator interposition with `WHOA_CHECK_ALLOCATIONS=1`.
- Local universal DMG: `zsh Tools/build-local.sh`. Public release requirements are in `Docs/DISTRIBUTION.md`.

## Architecture and gotchas

- The Xcode target is the app; `Package.swift` tests a subset of the same sources. Passing core tests does not verify UI, TCC or installed-app behavior.
- Capture is the single trigger producer, including Preview. Preserve that ownership and renderer acknowledgement before freeing sample banks. No allocations, locks, I/O or logging on capture/render paths.
- Preview pauses live capture and restores selection; preserve latest-request cancellation and commit selection only after successful installation.
- The project defaults to MainActor isolation; hot-path types explicitly opt out. Follow existing isolation conventions.
- Never log input data or translate physical key codes to text. Probe permission does not authorize the main app.
- Prepared packs intentionally reuse keyboard down/up samples. Names do not identify hardware, and source licensing does not establish recording rights.

See `ARCHITECTURE.md` for module ownership and `Docs/VALIDATION.md` for manual release checks.
