# Whoa Type — End-to-end audit

- **Audited revision:** `origin/stable` @ `2efdf7a` (tag `v1.0.0` + cask bump)
- **Date:** 2026-11-01
- **Scope:** security, architecture/code quality, performance, docs. No source files were modified; this report is the only change.
- **Codebase size:** ~2,100 lines of app Swift, ~700 lines of tests, 16 bundled sound packs (6.3 MB).

Severity scale: **Critical**: legal or release-blocking. **High**: the core feature breaks for users, or the issue undermines the project's stated guarantees. **Medium**: a real defect or risk with limited blast radius. **Low**: hygiene or polish.

---

## Build verification: NOT CONFIRMED

The build couldn't run here. This audit ran in a Linux x86_64 container with no Xcode, `xcodebuild`, or Swift toolchain (`swift: command not found`). The project can't build on Linux anyway: it targets macOS 26.5 and imports AppKit, AVFoundation, CoreGraphics, Carbon and ServiceManagement. That includes the SwiftPM core target, which imports AVFoundation and CoreGraphics.

**Build status is unverified, not passing.** Run these on a Mac with Xcode 26.x and add any failures to this report:

```bash
xcodebuild -project whoa-type.xcodeproj -scheme whoa-type -destination 'platform=macOS' build
```

```bash
swift test
```

```bash
WHOA_AUDIO_INTEGRATION=1 swift test --sanitize=thread
```

The repository makes this worse: **no CI workflow builds or tests pull requests** (finding H3). The last recorded build evidence is the historical note in `Docs/VALIDATION.md:9-12`, which predates the current test count and pack set.

Static risks to check when you build:
- No shared scheme is committed (`whoa-type.xcodeproj/xcshareddata/xcschemes/` is absent). `-scheme whoa-type` only works because Xcode auto-creates schemes, and that can fail in clean CI or when auto-creation is turned off (L10).
- The app target compiles in Swift 5 mode, while SwiftPM compiles the same files in Swift 6 mode with a different default isolation (H4). Code can pass `swift test` and still produce different diagnostics or behaviour in the Xcode build.

---

## Top 5 — fix first

| # | Severity | Finding | Where |
|---|---|---|---|
| 1 | Critical | A "Personal use only" sound pack and other packs with unconfirmed licences ship in the public v1.0.0 DMG and Homebrew cask | `whoa-type/Resources/SoundPacks/keychron-q3-bluex/LICENSE.txt:1`, `LICENSE:1-2` |
| 2 | High | Keyboard capture permanently gives up after 3 cumulative tap interruptions per session. Sounds silently stop. | `whoa-type/App/AppCoordinator.swift:95-98`, `whoa-type/Input/KeyCaptureService.swift:80-82,134-138` |
| 3 | High | Hovering over the switch list decodes two full sound banks per row and pauses live capture | `whoa-type/AppShell/MenuBarView.swift:103-105`, `whoa-type/App/AppCoordinator.swift:213-231` |
| 4 | High | No CI build or test gate. Releases publish signed binaries without running tests, and branch protection points at a check that doesn't exist. | `.github/workflows/release-build.yml:69-72`, `Tools/protect-branches.sh:11` |
| 5 | High | The shipped app and the tested package use different language modes and default isolation, so tests don't validate the shipped concurrency semantics | `whoa-type.xcodeproj/project.pbxproj:703,706,738,741`, `Package.swift:9-11` |

---

## Critical

### C1. Bundled recordings include a "Personal use only" pack and other packs whose licences are unconfirmed, and they ship in public releases
- **Where:** `whoa-type/Resources/SoundPacks/keychron-q3-bluex/LICENSE.txt:1` ("Personal use only."), `whoa-type/Resources/SoundPacks/keychron-q3-bluex/manifest.json:4` (`"Keychron Q3 Blue"`), `LICENSE:1-2` ("their licensing is pending"), `README.md:22-24`, `Casks/whoa-type.rb:5`. 15 other packs credit "kbs.im" or "monkeytype" in their `displayName` but have no `license` field.
- **Why it matters:** The release workflow (`.github/workflows/release-build.yml:69-97`) publishes these files in a public DMG, and the cask makes them installable through Homebrew. Redistributing a personal-use-only recording breaks its licence. The monkeytype project is copyleft-licensed, so its assets may carry obligations that conflict with the MIT grant. The display name also uses a hardware trademark, which contradicts `CLAUDE.md:17` and `ARCHITECTURE.md:31` ("Names do not identify hardware"). The repo's own docs (`README.md:22-24`, `CONTRIBUTING.md:33-34`) treat redistribution rights as a release requirement, and v1.0.0 shipped without meeting it.
- **Fix:** Pull `keychron-q3-bluex` from the bundle now and cut a v1.0.1. For each remaining pack, record provenance and licence in `manifest.json` (`license` is already supported and validated in `SoundPackValidator.swift:23`). Make the validator, or a release-time check in `scripts/build-dmg.sh`, reject packs without a `license` file. Rename any pack that uses brand names. Decide whether v1.0.0 assets need to be withdrawn.

---

## High

### H1. Capture recovery has a lifetime cap of 3 attempts. After the 3rd tap interruption, key sounds stop silently.
- **Where:** `whoa-type/App/AppCoordinator.swift:95-98`. `recoveryAttempts` is incremented but **never reset after a successful restart**. It's only reset on wake (`:79`), on a sound or geometry setting change (`:116`), or on `refresh()` (`:272`). `whoa-type/Input/KeyCaptureService.swift:80-82,134-138` responds to `tapDisabledByTimeout`/`tapDisabledByUserInput` by tearing the tap down instead of re-enabling it.
- **Why it matters:** macOS disables event taps from time to time, for example on callback timeouts under load or around user-input/secure-input transitions. Each event costs 1–3 s of silence while the 1 s and 2 s health timers rebuild the tap. On the 4th event in a session, the coordinator sets `captureActive = false` and stops trying. This is the app's core feature, and the user only finds out if they open the menu.
- **Fix:** Follow Apple's standard pattern. Inside the tap callback, on `.tapDisabledByTimeout`/`.tapDisabledByUserInput`, call `CGEvent.tapEnable(tap:enable:true)` on the existing tap, which the run loop thread already owns, and clear `held`/`pointerHeld` to handle the discontinuity. Keep teardown and rebuild as a fallback only. Reset `recoveryAttempts = 0` whenever `capture.start()` returns `true`. Replace the hard cap with exponential backoff.

### H2. Hover-to-preview does two full bank decodes per hovered row and interrupts live typing sounds
- **Where:** `whoa-type/AppShell/MenuBarView.swift:103-105` (`.onHover { coordinator.preview(pack.id) }`), `whoa-type/AppShell/IntroView.swift:163-167`, and `whoa-type/App/AppCoordinator.swift:213-231`. The preview path pauses capture, resets audio, calls `ensurePack(id)` (validate, decode and resample every WAV in the pack), plays, then calls `ensurePack(selectedPackID)`, which decodes the selected pack again from disk.
- **Why it matters:** Moving the cursor down the 16-row list queues a load for every row it crosses. Latest-wins cancellation (`PreviewController.swift:21-33`) only takes effect at per-file checkpoints, so each cancelled request still does some I/O and decoding. Live key sounds stay paused for the whole time the pointer is over the list. VoiceOver and keyboard-only users can't trigger previews at all.
- **Fix:** Cache decoded `PreparedSoundBank`s in a small LRU on the loader queue that always keeps the selected bank. Then "restore selection" becomes an install with no decode. Debounce hover previews by about 250 ms, or move preview to an explicit ▶︎ button as `IntroView` and Settings already do. Don't pause live capture for an audition: inject preview triggers into a second SPSC ring, or mix the preview bank through a separate voice group.

### H3. No CI gate for builds and tests. Releases publish without running tests. Branch-protection script requires a nonexistent check.
- **Where:** `.github/workflows/release-build.yml` is the only workflow. It builds (`:69-72`) and publishes (`:73-97`) without running `swift test`. `Tools/protect-branches.sh:11` requires a status check named `"build"` that no workflow produces, plus `enforce_admins` and 1 review (`:12-16`), while the release workflow pushes straight to `stable` (`:120`). `CONTRIBUTING.md:27` says merges happen "after CI".
- **Why it matters:** Regressions in the real-time audio and capture code (the riskiest code here) can reach a published release. If someone applies the protection script, every PR is blocked waiting for a phantom check, and the workflow's cask commit to `stable` is rejected.
- **Fix:** Add `.github/workflows/ci.yml` on `pull_request` and `push: stable`, running on `macos-26`, with a job named `build` that runs `xcodebuild … build` and `swift test` (optionally `--sanitize=thread`). Add `swift test` before "Build DMG" in the release workflow. In `protect-branches.sh`, let `github-actions[bot]` bypass via a ruleset, or have the release workflow open a cask PR instead of pushing to `stable`.

### H4. The app ships in Swift 5 mode with MainActor-default isolation. Tests compile the same files in Swift 6 mode with nonisolated default.
- **Where:** `whoa-type.xcodeproj/project.pbxproj:706,741` (`SWIFT_VERSION = 5.0`) and `:703,738` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), versus `Package.swift:1` (tools 6.2, so Swift 6 language mode) with no `swiftSettings: [.defaultIsolation(MainActor.self)]` at `Package.swift:9-11`.
- **Why it matters:** The code relies on many `@unchecked Sendable` types and hand-written atomics (`AudioService`, `KeyCaptureService`, `SPSCRing`, `AudioRenderer`). In Swift 5 mode, data-race diagnostics in the shipped target are warnings at most. Any unannotated declaration is `@MainActor` in the app but `nonisolated` in tests, so the tests can pass against isolation semantics the product doesn't have. `CLAUDE.md:15` says "the project defaults to MainActor isolation", which is only true for one of the two builds.
- **Fix:** Set `SWIFT_VERSION = 6.0` on the app target. Add `swiftSettings: [.defaultIsolation(MainActor.self)]` (plus the same upcoming features, e.g. `MemberImportVisibility`) to the `WhoaTypeCore` target so both builds compile identically. Fix any diagnostics that appear.

---

## Medium

### M1. The capture hot path allocates and hops actors on every Return key, against the project's own rule
- **Where:** `whoa-type/Input/KeyCaptureService.swift:128` calls `returnDing?()` on the event-tap thread. The closure, built at `whoa-type/App/AppCoordinator.swift:142-146`, creates a `Task { @MainActor … }`, which allocates. The ding then runs `NSSound(named:)?.copy()` (`:151-156`).
- **Why it matters:** `CLAUDE.md:13` and `ARCHITECTURE.md:25` say "no allocations … on capture/render paths". The ding also bypasses the low-latency renderer, so it has different latency and volume behaviour from every other sound.
- **Fix:** Treat the ding as a sample. Add a reserved slot to `PreparedSoundBank` (as pointer slots already work) and push an `AudioTrigger` from the tap. If `NSSound` has to stay, post a pre-allocated signal (an `Atomic` flag polled by a main-thread `DispatchSource`) instead of creating a `Task` per keystroke.

### M2. Launch validates every pack, then re-validates and decodes the selected pack
- **Where:** `whoa-type/SoundPacks/SoundPackRepository.swift:20` runs `SoundPackValidator.validate` (one `AVAudioFile` open per WAV, about 265 files) for all 16 packs during `discover`. `:34` validates the selected pack again in `load`, then decodes it. Bootstrap is at `whoa-type/App/AppCoordinator.swift:121-138`.
- **Why it matters:** Hundreds of file opens before the first sound can play adds launch latency. That matters most at login, when the disk is busy. The packs are signed bundle resources, so validating them at runtime protects against very little.
- **Fix:** In `discover`, only decode `manifest.json` and run the cheap metadata checks. Defer per-file `AVAudioFile` validation to `load`. Keep full validation in `swift test` (`AudioTests.bundledPacksValidateAndConvert` already does this).

### M3. The About banner decodes the full desktop wallpaper synchronously on the main thread on every activation or Space change
- **Where:** `whoa-type/AppShell/SettingsView.swift:463-470` (`NSImage(contentsOf:)` on the wallpaper URL) and `:518-524` (the `didBecomeActive` and `activeSpaceDidChange` triggers).
- **Why it matters:** 5K/6K and dynamic HEIC wallpapers can be tens of MB, and decoding them on the main actor causes visible hitches. It also re-runs on every Space switch while Settings is open.
- **Fix:** Load a downsampled thumbnail off the main actor (`CGImageSourceCreateThumbnailAtIndex`, max ~600 px) in a `.task(id:)` and cache it by URL. Or drop the decorative wallpaper.

### M4. CI signing hygiene: unpinned action in a job holding signing secrets, and keys imported with `-A`
- **Where:** `.github/workflows/release-build.yml:23` (`actions/checkout@v4` by tag) with workflow-wide `permissions: contents: write` (`:11-12`). `scripts/configure-signing.sh:23` (`security import … -A`).
- **Why it matters:** A retargeted tag would run with the Developer ID P12 and notary credentials in the environment. `-A` lets any process use the private key without a prompt. The keychain is short-lived, so the risk is limited, but this is a supply-chain hardening gap.
- **Fix:** Pin actions to a commit SHA. Scope secrets to the signing and build steps only (already mostly done) and restrict `contents: write` to the job that needs it. Replace `-A` with `-T /usr/bin/codesign -T /usr/bin/productsign`.

### M5. `SoundHotkey` gives Carbon an unretained `self` and never removes the handler
- **Where:** `whoa-type/App/AppCoordinator.swift:306-311` (`InstallEventHandler(..., Unmanaged.passUnretained(self).toOpaque(), &handler)`, never paired with `RemoveEventHandler`), and `:11` (`var hotkey = SoundHotkey()`).
- **Why it matters:** If `hotkey` is ever reassigned (it's a public `var`) or the coordinator is torn down, the next hotkey press dereferences a freed object and crashes.
- **Fix:** Make it `let hotkey`. Add `isolated deinit` (Swift 6.2), or an explicit `invalidate()`, that calls `UnregisterEventHotKey` and `RemoveEventHandler`. Do the same with `let settings` at `:8`.

### M6. A settings change spawns an unordered `Task` per change, and slider drags spawn dozens
- **Where:** `whoa-type/App/AppCoordinator.swift:103-120`. Each `onChange` creates `Task { @MainActor … await configureEffects() … }` and re-registers.
- **Why it matters:** Dragging the volume or effects slider creates one task per tick. Each one awaits a capture-thread round trip. They can finish out of order and briefly apply a stale `effectsVolume` or `returnDing` configuration, and they add main-actor churn.
- **Fix:** Coalesce updates with a single long-lived `AsyncStream` consumer (or `Observations {}` in Swift 6.2) that always reads the latest settings. Only call `configureEffects` when effects fields actually changed, and call `setGain` without hopping.

### M7. Entitlements are broader than the app needs
- **Where:** `whoa-type.xcodeproj/project.pbxproj:687,722` (`ENABLE_USER_SELECTED_FILES = readonly`) and `:700,735` (`REGISTER_APP_GROUPS = YES`). There's no file picker or app group anywhere in the code.
- **Why it matters:** This is least privilege for an app that observes every keystroke. Reviewers and users judge such apps by their entitlements. Sandbox + hardened runtime + listen-only tap is otherwise a good, minimal posture.
- **Fix:** Remove both settings. Confirm with `codesign -d --entitlements - "Whoa Type.app"` that only `com.apple.security.app-sandbox` remains.

### M8. The coordinator state machine has no automated tests
- **Where:** `Package.swift:10` excludes `App/AppCoordinator.swift`. `perform(_:revision:)` (`AppCoordinator.swift:183-270`) is the most complex branching code in the app (sleep, rebuild, preview, error rollback).
- **Why it matters:** H1 is exactly the kind of bug that tests at this level would catch.
- **Fix:** Put `KeyCaptureService`, `AudioService` and `PermissionController` behind small protocols, move `AppCoordinator` into the core target with injected fakes, and test the recovery, preview-restore and error-rollback paths.

---

## Low

| ID | Finding | Where | Fix |
|---|---|---|---|
| L1 | `NSApplication.activate(ignoringOtherApps:)` is deprecated since macOS 14 | `App/AppCoordinator.swift:125`, `AppShell/MenuBarView.swift:56`, `AppShell/SettingsView.swift:383` | Use `NSApp.activate()` |
| L2 | Closing Settings forces `.accessory` even if the Intro window is still open, and Intro switches to `.regular` in `init`, not on show | `AppShell/SettingsView.swift:386-388`, `AppShell/IntroView.swift:23` | Use a reference-counted "visible windows" policy helper in the coordinator |
| L3 | A 40-entry colour table matches only 1 of 16 real pack names (dead code) | `AppShell/MenuBarView.swift:111-157` | Add an optional `color` to the manifest, or hash the pack ID into a palette |
| L4 | About 1.4 MB of unreferenced raw WAVs and `config.json` per pack, plus 3 empty pack directories, ship inside the app (blue folder reference) | `project.pbxproj:15`; `Resources/SoundPacks/{cherry-mx-black,cream,milky-yellow}` | Keep source audio outside the bundled folder, or exclude it with a build phase |
| L5 | Magic numbers for control commands (`kind` 0/1/2) | `Audio/AudioControlMailbox.swift:4-5`, `Audio/AudioService.swift:49-51` | Use `enum ControlKind: UInt8` |
| L6 | Force unwraps and O(n²) `firstIndex` in the loader (safe only because validation ran earlier) | `SoundPacks/SoundPackRepository.swift:40,68,71,79` | Build `[String: Int]` from `paths` once and use `guard let` with `PackError` |
| L7 | Two overlapping health pollers (2 s main-actor loop and 1 s capture timer), both calling `CGPreflightListenEventAccess` | `App/AppCoordinator.swift:82-101`, `Input/KeyCaptureService.swift:93` | Keep one. With H1 fixed, the capture-side timer is enough for tap health. |
| L8 | No diagnostics: no `os.Logger` for lifecycle failures (engine start, tap creation, ack timeout) | whole app | Add a `Logger(subsystem:category:)` for lifecycle events only, never input data, with `privacy: .public` on static strings only |
| L9 | `.commands { CommandGroup(replacing: .appSettings) }` has no effect for an `LSUIElement` app without a main menu, yet README advertises ⌘, | `whoa_typeApp.swift:11-16`, `README.md:39` | Remove it, or use a SwiftUI `Settings` scene with `SettingsLink` |
| L10 | No shared Xcode scheme committed | `whoa-type.xcodeproj/` (no `xcshareddata/xcschemes`) | Mark the scheme Shared and commit it |
| L11 | Bundle ID isn't reverse-DNS and embeds a personal name; copyright is empty | `project.pbxproj:698,733,692,727` | e.g. `studio.whoa.type` (a breaking change for prefs and TCC, so do it before wider adoption) and set a copyright |
| L12 | Observers are added to `queue: .main` and then hop through `Task { @MainActor }` | `App/AppCoordinator.swift:64-80` | Use `MainActor.assumeIsolated { … }` inside main-queue observers |

---

## Security summary

**Good:**
- No secrets in the tree or history. Scanned all commits for key, token and private-key patterns; only placeholders and docs matched. `.gitignore` covers `.env*`, `*.p12`, `*.p8` and profiles.
- No network code. The two `Link`s at `SettingsView.swift:212-213` open the browser.
- App Sandbox and hardened runtime are on in both configurations.
- Input access is the minimal kind: a `.listenOnly` session tap with Input Monitoring (`CGRequestListenEventAccess`), no Accessibility, and no key-code-to-character translation (`KeyMapper.swift:23-24`).
- Preferences are non-sensitive and correctly stored in `UserDefaults`. There's nothing that belongs in Keychain.
- Manifest paths are protected against traversal and symlinks (`SoundPackValidator.swift:5-15`, tested).
- Packs are size-capped and format-validated.
- Signing secrets go through a temporary keychain that is always cleaned up.

**Gaps:** C1 (licensing), M4 (CI supply chain), M7 (extra entitlements). `PRIVACY.md` is also incomplete (D5).

---

## Docs findings

### CLAUDE.md
| ID | Severity | Finding | Where | Fix |
|---|---|---|---|---|
| D1 | Medium | "The project defaults to MainActor isolation" is true for the Xcode target only. SwiftPM uses nonisolated default and Swift 6 mode (see H4). | `CLAUDE.md:15` | Fix H4, or document the difference |
| D2 | Low | The build and test commands match README and CONTRIBUTING and look correct (unverified, see Build section). Missing: no shared scheme note, no lint/format command although `.swift-format` exists, no mention of `scripts/release.sh` and `scripts/build-dmg.sh` (only the `Tools/` wrappers), and no note that everything requires macOS + Xcode 26 | `CLAUDE.md:3-8` | Add `swift format lint -r whoa-type Tests`, the release and DMG scripts, and a "macOS only" note |

### README.md and other docs
| ID | Severity | Finding | Where | Fix |
|---|---|---|---|---|
| D3 | Medium | Install, tap and security links point to `WhoaStudio/Whoa-Typer`, but the repo and cask are `WhoaStudio/whoa-type`. They only work while GitHub's rename redirect lasts. | `README.md:8,14`, `Docs/DISTRIBUTION.md:3`, `SECURITY.md:11`, `.github/ISSUE_TEMPLATE/config.yml:4`, `Tools/generate-cask.py:11`, `Tools/protect-branches.sh:7` | Replace them all with `WhoaStudio/whoa-type` |
| D4 | Medium | The descriptions of the pack set are wrong. ARCHITECTURE and SCAFFOLD describe "38 packs `switch-01`…`switch-38` with `sample.wav`", but there are 16 imported packs with per-key files. README says the 16 are bundled "alongside the original switches" (there are none), says "Cherry MX Blue was skipped" (`mxblue` is present), and references a `neptune-import.log` that doesn't exist. VALIDATION cites "19 tests … all 38 pack conversions". | `ARCHITECTURE.md:31`, `SCAFFOLD.md:12`, `README.md:49-53`, `Docs/VALIDATION.md:12` | Rewrite them to match `Resources/SoundPacks` |
| D5 | Medium | PRIVACY lists only 5 stored preferences. The app also stores `onboardingCompleted`, `mouseSoundsEnabled`, `returnDingEnabled`, `effectsVolume` and `hotkey.*`, and it registers a Carbon global hotkey. | `Docs/PRIVACY.md:5`; `Settings/SettingsStore.swift:6-26`; `App/AppCoordinator.swift:296-298` | List every key and mention the hotkey |
| D6 | Low | README's description of the Settings panes ("Playback, Switch Library, Input Access, Startup") is out of date. The real panes are General, Sound and About. | `README.md:39` vs `AppShell/SettingsView.swift:3-6` | Update it |
| D7 | Low | README mentions "two capture probes". There's one (`Tools/CaptureProbe`) and nothing builds it. | `README.md:35` | Fix the count and add build instructions, or delete the probe |
| D8 | Low | ARCHITECTURE says "CI only creates a manually requested local validation artifact". In fact CI publishes releases and pushes the cask. CONTRIBUTING mentions CI that doesn't exist. | `ARCHITECTURE.md:45`, `CONTRIBUTING.md:27` | Update after H3 |
| D9 | Low | README is missing screenshots, uninstall steps (including `tccutil reset ListenEvent <bundle id>` and the login item), troubleshooting (Secure Input, Bluetooth latency, how to reset permission), and the global hotkey. It's also a single dense paragraph. | `README.md` | Restructure into What it does, Screenshots, Requirements, Install, Permissions, Usage, Troubleshooting, Uninstall, Build, Release, Licence |

---

## Positive notes (keep these)
- The real-time design is careful. SPSC rings use acquire/release atomics (`TriggerRing.swift`), voices and banks are preallocated, and the renderer acknowledges a bank before it's freed (`AudioService.swift:52-75`). The render callback has no allocations, locks or Obj-C messaging.
- Cancellation with latest-request-wins, and selection committed only after a successful swap (`AppCoordinator.swift:211-212`).
- The input layer has a strong privacy design: physical codes only, no text, no cursor data (`PointerMapper.swift:12-13`).
- Accessibility work in the UI: Reduce Motion, `isSelected` traits, and labels on icon buttons.
