import Testing
@testable import WhoaTypeCore

struct HealthPolicyTests {
    private func decide(enabled: Bool = true, engine: Bool = true, was: Bool = true, now: Bool = true,
                        capture: Bool = true, error: Bool = false, retries: Int = 0) -> HealthAction {
        HealthAction.decide(soundEnabled: enabled, engineRunning: engine, wasAuthorized: was, authorized: now,
            captureActive: capture, hasError: error, retries: retries)
    }

    @Test func healthyStateNeedsNothing() {
        #expect(decide() == .none)
    }

    @Test func disabledSoundNeverActs() {
        #expect(decide(enabled: false, engine: false, capture: false) == .none)
    }

    @Test func stoppedEngineIsRebuiltBeforeAnythingElse() {
        #expect(decide(engine: false, was: true, now: false, capture: false) == .rebuild)
    }

    @Test func permissionChangeReconciles() {
        #expect(decide(was: false, now: true, capture: false) == .reconcile)
        #expect(decide(was: true, now: false) == .reconcile)
    }

    @Test func lostCaptureIsRetriedThenGivenUp() {
        for retries in 0..<HealthAction.maxCaptureRetries {
            #expect(decide(capture: false, retries: retries) == .retryCapture)
        }
        #expect(decide(capture: false, retries: HealthAction.maxCaptureRetries) == .giveUp)
    }

    @Test func retryBudgetOnlyAppliesWhileCaptureIsDown() {
        // The coordinator resets its counter whenever capture is active, so a healthy tap
        // is never "given up on" regardless of how many interruptions came before.
        #expect(decide(capture: true, retries: 99) == .none)
    }

    @Test func existingErrorSuppressesCaptureRetries() {
        #expect(decide(capture: false, error: true) == .none)
    }

    @Test func unauthorizedStateDoesNotRetryCapture() {
        #expect(decide(was: false, now: false, capture: false) == .none)
    }
}
