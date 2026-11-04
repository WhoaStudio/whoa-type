import Foundation

/// Keeps the decoded bank for the selected pack and the one being auditioned, so restoring the
/// selection after a preview does not decode it again. Entries are only valid for one sample rate.
nonisolated struct BankCache<Bank> {
    private var banks: [String: Bank] = [:]
    private var rate = 0.0

    var ids: Set<String> { Set(banks.keys) }

    func bank(for id: String, rate: Double) -> Bank? {
        self.rate == rate ? banks[id] : nil
    }

    mutating func store(_ bank: Bank, id: String, rate: Double, keeping selected: String) {
        if self.rate != rate { banks.removeAll(); self.rate = rate }
        banks[id] = bank
        banks = banks.filter { $0.key == id || $0.key == selected }
    }

    mutating func removeAll() { banks.removeAll() }
}
