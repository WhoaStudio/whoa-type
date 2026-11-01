import Foundation
import Synchronization

final nonisolated class RequestGeneration: Sendable {
    let value = Atomic<UInt64>(0)
    func matches(_ candidate: UInt64) -> Bool {
        value.load(ordering: .acquiring) == candidate
    }
}

@MainActor final class PreviewController {
    enum Request { case select(String), preview(String), previewKey(String), selectAndPreview(String), previewMouse, reconcile, rebuild }
    let generation = RequestGeneration()
    private var pending: (Request, UInt64)?
    private var worker: Task<Void, Never>?
    private let capture: KeyCaptureService
    init(capture: KeyCaptureService) {
        self.capture = capture
    }

    func submit(_ request: Request, perform: @escaping @MainActor (Request, UInt64) async -> Void) {
        let revision = generation.value.load(ordering: .relaxed) &+ 1
        generation.value.store(revision, ordering: .releasing)
        pending = (request, revision)
        capture.cancelPreview()
        guard worker == nil else { return }
        worker = Task {
            while let (request, revision) = pending {
                pending = nil
                await perform(request, revision)
            }
            worker = nil
        }
    }

    func shutdown() async {
        pending = nil
        generation.value.store(generation.value.load(ordering: .relaxed) &+ 1, ordering: .releasing)
        capture.cancelPreview()
        await worker?.value
        worker = nil
    }
}
