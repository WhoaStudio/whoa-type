import Synchronization

// Exactly one producer and one consumer. Each side owns its cursor; publication
// is release/acquire. Consumed records are overwritten before releasing capacity.
nonisolated final class SPSCRing<Element>: @unchecked Sendable {
    let capacity: Int
    private let empty: Element
    private let storage: UnsafeMutablePointer<Element>
    private let read = Atomic<Int>(0)
    private let write = Atomic<Int>(0)
    init(capacity: Int, empty: Element) {
        precondition(capacity > 0)
        self.capacity = capacity; self.empty = empty
        storage = .allocate(capacity: capacity + 1)
        storage.initialize(repeating: empty, count: capacity + 1)
    }
    @inline(__always) func push(_ value: Element) -> Bool {
        let w = write.load(ordering: .relaxed)
        let next = (w + 1) % (capacity + 1)
        guard next != read.load(ordering: .acquiring) else { return false }
        storage[w] = value
        write.store(next, ordering: .releasing)
        return true
    }
    @inline(__always) func pop() -> Element? {
        let r = read.load(ordering: .relaxed)
        guard r != write.load(ordering: .acquiring) else { return nil }
        let value = storage[r]
        storage[r] = empty
        read.store((r + 1) % (capacity + 1), ordering: .releasing)
        return value
    }
    // Consumer only. Producer must be paused for a discontinuity reset.
    func discard() { for _ in 0..<capacity { if pop() == nil { break } } }
    deinit { storage.deinitialize(count: capacity + 1); storage.deallocate() }
}
typealias TriggerRing = SPSCRing<AudioTrigger>
