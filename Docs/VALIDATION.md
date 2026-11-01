# Validation — 2026-10-31

Implementation is present for each source module. Release acceptance is still gated by the manual evidence below; no claim is made that the full release-validation milestone is complete.

## Historical automated checks

The following results are historical records, not checks rerun by a documentation edit. Counts refer to the stages described below.

Environment: Apple M4, macOS 26.7.2, Xcode 26.6 / Swift 6.3.3. Deployment target remains macOS 26.5. The older deployment OS has not been exercised here.

- Xcode Release build for arm64 and x86_64 passes. Only arm64 has been executed locally.
- 19 Swift Testing tests cover preferences/state, 100,000 concurrent ring records, capacity/wraparound, all 38 pack conversions, malformed manifests, escaping/symlink paths, duplicate IDs, file/memory caps, lookup precedence, pitch pairing/pan/gain/reset, bounded overload, physical geometry/modifier pairs, loader cancellation, serialized latest-request behavior, and synthetic auditions without a tap.
- The opt-in real AVAudioEngine test starts silent output, installs a bank, performs twelve bank swaps/resets, and stops after renderer acknowledgements. No input permission is required for this test.
- Address Sanitizer and Thread Sanitizer runs pass, including the real engine test. They do not establish real-time allocation behavior or hardware latency.
- UInt64 acquire/release atomics compile to ARM64 `ldapr`/`stlr` instructions on this machine. Other supported hardware still needs runtime validation.

Commands:

```sh
xcodebuild -project whoa-type.xcodeproj -scheme whoa-type -configuration Release \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build
swift test
WHOA_AUDIO_INTEGRATION=1 swift test
WHOA_AUDIO_INTEGRATION=1 swift test --sanitize=address
WHOA_AUDIO_INTEGRATION=1 swift test --sanitize=thread
WHOA_CHECK_ALLOCATIONS=1 Tools/benchmark.sh
```

## Synthetic performance

Optimized offline renderer, 48 kHz, 128 frames, 64 active voices and 64 synthetic triggers per quantum, 500 warm-up + 3,000 measured quanta. One run while other builds were active reported CPU callback times: p50 0.0293 ms, p95 0.0441 ms, p99 0.0538 ms, max 0.7103 ms. Scheduling outliers are included. This excludes event delivery, hardware, Bluetooth transport, and engine underruns; it is not a physical latency measurement.

Test-only allocator interposition observed zero malloc/calloc/realloc/free/posix_memalign activity within those 3,000 warmed synthetic callbacks. This is narrower than a complete Instruments audit: capture callbacks and framework internals still require allocation profiling. No instrumentation is linked into the app and no real keystroke records are collected.

## Manual release evidence still required

- On macOS 26.5 and current macOS, test the signed main app's grant, unavailable access, revoke while menu closed, relaunch, and retry flows. Probes have separate identities; a probe grant does not authorize the main app.
- Confirm both sandboxed/direct probes separately, then actual passive input delivery in the sandboxed main app. Sandbox remains enabled pending this evidence. If required capture fails under sandboxing, record the result before changing that setting.
- Verify no Dock icon or automatic Settings window, visible Settings on request, keyboard/accessibility navigation, menu persistence after closing Settings, and reliable Quit.
- Verify real ANSI/ISO/JIS positions, both modifier sides together, Caps Lock toggles, repeat suppression, lost releases, and Secure Input suppression without bypass.
- Audition all packs and independently check loudness, onset and fade quality. Initial packs explicitly reuse recordings for both phases; distinct release recordings remain deferred by maintainer decision.
- Rapidly select/preview/mute, including while input access is unavailable; confirm latest-request behavior, selection restoration, zero volume, and failure retention.
- Test device unplug, built-in/wired/Bluetooth route changes, sample-rate changes, sleep/wake, and quit during a load/preview. Confirm actual route quantum in Settings.
- Use external loopback/recording hardware for physical switch-to-speaker p50/p95/p99 and dropouts. Record device, route, sample rate and buffer size. Target wired p95 ≤12 ms/p99 ≤20 ms remains unverified.
- Profile capture/render allocations, CPU, energy, memory, and warm-engine idle behavior in Instruments. Confirm no input records in logs/crash payloads.
- Test login-item enabled/disabled/approval/error behavior and installed-app onboarding under a clean account.
- Complete Developer ID notarization and Gatekeeper verification using Tools/release.sh before public distribution.

## Physical-key character update

Physical-key gain/pitch shading adds regression coverage for the same-sample identity, heavier/lighter gain ordering, pitch bounds, and down/up pairing across 100 synthetic seeds. The warmed 3,000-callback benchmark with this change reported p50 0.0302 ms, p95 0.0462 ms, p99 0.0670 ms, max 0.2893 ms, with zero intercepted allocator activity. These remain synthetic CPU timings rather than acoustic latency or listening-test evidence.

## Stronger positional tone update

A fixed ±180-cent positional offset is now applied in addition to the bounded pack jitter. A preallocated per-voice one-pole tone blend makes the left warmer and the right brighter. Random jitter is reduced so position is not masked by randomness. Synthetic signal tests verify a 360-cent edge-to-edge spread, a measurable high-frequency energy difference independent of stereo balance, the same sample identity, selected-geometry mapping, and paired press/release pitch. This is DSP-derived variation, not recorded per-key acoustics. Preview now traverses left/center/right before Space.

The warmed synthetic benchmark reported p50 0.0344 ms, p95 0.0637 ms, p99 0.1068 ms, max 0.4056 ms, with zero intercepted allocator activity. Acoustic listening approval remains subjective and is not established by these signal tests.

## Trackpad/mouse click support

Four added tests cover passive button event masks (no movement/drag/scroll subscription), independent held state, double-click pairs, duplicate/unmatched transitions, bounded auxiliary-button indices, distinct preloaded press/release samples, centered playback, pitch pairing, expanded-slot reset, and silent pointer slots in older keyboard-only packs. All 27 tests pass under Address Sanitizer, including the real-engine integration test. Physical trackpad and mouse behavior still requires an interactive listening check after relaunch.

The existing warmed 64-voice synthetic renderer benchmark reports p50 0.0346 ms, p95 0.0517 ms, p99 0.0649 ms, max 0.1258 ms, with zero intercepted allocator activity. No live input is logged or instrumented.

## Click variety

All bundled packs now contain six distinct click-press recordings with consistent peak headroom and the existing release recording. Synthetic tests exercise 300 presses across different buttons, observing all six sample buffers and no adjacent repeated press sample; release events do not reset the press selection. Discontinuities clear the previous-variant state, and one-variant packs remain playable. File hashes confirm six distinct prepared recordings. Both trackpad and mouse share the pool; no hardware classification was added.

The warmed renderer benchmark reported p50 0.0337 ms, p95 0.0353 ms, p99 0.0446 ms, max 0.0730 ms, with zero intercepted allocator activity. This run used Xcode 27.2 / Swift 6.4.2; earlier measurements above used the toolchain stated in their environment section.
