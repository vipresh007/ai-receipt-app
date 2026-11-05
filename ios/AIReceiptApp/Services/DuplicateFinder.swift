import Foundation

/// The same receipt added twice: same store (loosely: "FRESHCO" = "FreshCo",
/// "Eggholic" = "Eggholic- Indian Street Food (Brampton)", "FreshCo" =
/// "CHALO! FRESH CO"), same day, same total. Mirrors `backend/app/services/duplicates.py`; keep the rules in step.
enum DuplicateFinder {
    static func storeKey(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map(Character.init))
    }

    static func sameStore(_ a: String, _ b: String) -> Bool {
        let ka = storeKey(a), kb = storeKey(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        if ka == kb { return true }
        let (short, long) = ka.count <= kb.count ? (ka, kb) : (kb, ka)
        return short.count >= 4 && long.contains(short)
    }

    static func same(_ a: Receipt, _ b: Receipt, calendar: Calendar = .current) -> Bool {
        a.total > 0 && a.total == b.total && calendar.isDate(a.date, inSameDayAs: b.date) && sameStore(a.merchant, b.merchant)
    }

    /// A saved receipt that looks like this draft, if any (the earliest).
    static func find(
        _ draft: ReceiptDraft, in receipts: [Receipt], except: Receipt? = nil, calendar: Calendar = .current
    ) -> Receipt? {
        guard draft.total > 0 else { return nil }
        return receipts
            .filter {
                $0 !== except && $0.total == draft.total && calendar.isDate($0.date, inSameDayAs: draft.date)
                    && sameStore($0.merchant, draft.merchant)
            }
            .min { $0.createdAt < $1.createdAt }
    }

    /// Receipts that look like the same one, oldest first in each group;
    /// newest groups first.
    static func groups(in receipts: [Receipt], calendar: Calendar = .current) -> [[Receipt]] {
        var buckets: [String: [Receipt]] = [:]
        for r in receipts where r.total > 0 {
            let day = calendar.startOfDay(for: r.date).timeIntervalSince1970
            buckets["\(day)|\(r.total)", default: []].append(r)
        }
        var out: [[Receipt]] = []
        for bucket in buckets.values where bucket.count > 1 {
            var left = bucket.sorted { $0.createdAt < $1.createdAt }
            while let first = left.first {
                let group = left.filter { $0 === first || sameStore(first.merchant, $0.merchant) }
                left.removeAll { r in group.contains { $0 === r } }
                if group.count > 1 { out.append(group) }
            }
        }
        return out.sorted { $0[0].date > $1[0].date }
    }
}
