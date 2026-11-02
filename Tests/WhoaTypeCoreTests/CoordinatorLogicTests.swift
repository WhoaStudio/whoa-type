import Testing
@testable import WhoaTypeCore

struct BankCacheTests {
    @Test func returnsStoredBankAtTheSameRate() {
        var cache = BankCache<Int>()
        cache.store(1, id: "a", rate: 48000, keeping: "a")
        #expect(cache.bank(for: "a", rate: 48000) == 1)
        #expect(cache.bank(for: "b", rate: 48000) == nil)
    }

    @Test func rateChangeInvalidatesEverything() {
        var cache = BankCache<Int>()
        cache.store(1, id: "a", rate: 48000, keeping: "a")
        #expect(cache.bank(for: "a", rate: 44100) == nil)
        cache.store(2, id: "b", rate: 44100, keeping: "a")
        #expect(cache.ids == ["b"])
    }

    @Test func keepsOnlySelectedAndAuditionedPacks() {
        var cache = BankCache<Int>()
        cache.store(1, id: "selected", rate: 48000, keeping: "selected")
        cache.store(2, id: "preview1", rate: 48000, keeping: "selected")
        #expect(cache.ids == ["selected", "preview1"])
        cache.store(3, id: "preview2", rate: 48000, keeping: "selected")
        #expect(cache.ids == ["selected", "preview2"])
    }

    @Test func restoringSelectionAfterPreviewNeedsNoDecode() {
        var cache = BankCache<Int>()
        cache.store(1, id: "selected", rate: 48000, keeping: "selected")
        cache.store(2, id: "preview", rate: 48000, keeping: "selected")
        #expect(cache.bank(for: "selected", rate: 48000) == 1)
    }
}

struct SettingsChangeTests {
    private let base = SettingsSnapshot(enabled: true, volume: 0.5, geometry: .ansi,
        effectsVolume: 1, mouseSounds: true, returnDing: false)

    @Test func identicalSnapshotsHaveNoChanges() {
        #expect(!base.changes(from: base).any)
    }

    @Test func volumeAloneDoesNotTouchEffectsOrLifecycle() {
        var next = base; next.volume = 0.8
        #expect(next.changes(from: base) == .init(volume: true, effects: false, lifecycle: false))
    }

    @Test func effectsFieldsAreTrackedTogether() {
        for mutate in [{ (s: inout SettingsSnapshot) in s.effectsVolume = 0.2 },
                       { $0.mouseSounds.toggle() }, { $0.returnDing.toggle() }] {
            var next = base; mutate(&next)
            #expect(next.changes(from: base) == .init(volume: false, effects: true, lifecycle: false))
        }
    }

    @Test func enableAndLayoutChangesReconcileTheLifecycle() {
        var toggled = base; toggled.enabled = false
        var relaid = base; relaid.geometry = .jis
        #expect(toggled.changes(from: base).lifecycle)
        #expect(relaid.changes(from: base).lifecycle)
    }

    @Test func eachChangeIsReportedOnceWhenSnapshotAdvances() {
        var next = base; next.volume = 0.9
        #expect(next.changes(from: base).volume)
        #expect(!next.changes(from: next).any)
    }
}
