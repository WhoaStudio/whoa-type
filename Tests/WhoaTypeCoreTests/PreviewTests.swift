import Foundation
import Testing
@testable import WhoaTypeCore

struct PreviewTests {
    @Test func syntheticPreviewWorksWithoutEnablingCapture() async throws {
        let ring = TriggerRing(capacity: 256, empty: AudioTrigger())
        let capture = KeyCaptureService(triggers: ring)
        await capture.setGeometry(.ansi)
        #expect(!capture.isActive)
        let m = try AudioTests.manifest()
        try await capture.preview(m.preview)
        var phases: [KeyPhase] = []
        while let event = ring.pop() { phases.append(event.phase) }
        #expect(phases == m.preview.map(\.phase))
        #expect(!capture.isActive)
        await capture.shutdown()
    }
    @Test func cancelledLoaderPublishesNoBank() async throws {
        let m = try AudioTests.manifest()
        let pack = SoundPack(root: AudioTests.fixtureRoot, manifest: m)
        do {
            _ = try await SoundPackRepository().load(pack, rate: 48000, isCurrent: { false })
            Issue.record("Cancelled loader produced a bank")
        } catch is CancellationError { }
    }
    @MainActor @Test func latestRequestWinsAndExecutionIsSerialized() async {
        let capture = KeyCaptureService(triggers: TriggerRing(capacity: 256, empty: AudioTrigger()))
        let controller = PreviewController(capture: capture)
        var started: [String] = []
        var concurrent = 0
        var maximum = 0
        let operation: @MainActor (PreviewController.Request, UInt64) async -> Void = { request, _ in
            if case .preview(let id) = request { started.append(id) }
            concurrent += 1; maximum = max(maximum, concurrent)
            try? await Task.sleep(for: .milliseconds(30))
            concurrent -= 1
        }
        controller.submit(.preview("one"), perform: operation)
        try? await Task.sleep(for: .milliseconds(5))
        controller.submit(.preview("two"), perform: operation)
        controller.submit(.preview("three"), perform: operation)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(started == ["one", "three"])
        #expect(maximum == 1)
        await controller.shutdown()
        await capture.shutdown()
    }
}

struct AudioEngineIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHOA_AUDIO_INTEGRATION"] == "1"))
    func actualEngineAcknowledgesBankAndReset() async throws {
        let service = AudioService()
        let rate = try await service.prepare()
        #expect(rate > 0)
        service.setGain(0) // exercise the real callback without playing sound
        let manifest = try AudioTests.manifest()
        let pack = SoundPack(root: AudioTests.fixtureRoot, manifest: manifest)
        let bank = try await SoundPackRepository().load(pack, rate: rate)
        do {
            try await service.install(bank)
            for _ in 0..<12 {
                let candidate = try await SoundPackRepository().load(pack, rate: rate)
                try await service.install(candidate)
                try await service.reset()
            }
            await service.stop()
        } catch {
            await service.stop()
            throw error
        }
    }
}
