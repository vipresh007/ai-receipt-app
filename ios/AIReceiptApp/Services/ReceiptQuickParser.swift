import Foundation

/// A fast, on-device first read of a receipt from its OCR rows: store name,
/// date, total and tax. It's what the confirm screen opens with while the
/// server does the full extraction, so it's deliberately conservative: a field
/// it isn't sure of stays empty rather than guessed (the server fills it in).
enum ReceiptQuickParser {
    static func draft(from rows: [String], today: Date = .now, calendar: Calendar = .current) -> ReceiptDraft {
        var draft = ReceiptDraft()
        draft.merchant = merchant(in: rows) ?? ""
        draft.date = date(in: rows, today: today, calendar: calendar) ?? today
        draft.total = total(in: rows) ?? 0
        let tax = tax(in: rows) ?? 0
        draft.tax = tax < draft.total ? tax : 0
        return draft
    }

    /// Worth showing before the server answers: the total is the one figure
    /// the confirm screen can't do without.
    static func isUseful(_ draft: ReceiptDraft) -> Bool {
        draft.total > 0
    }

    // MARK: - Merchant

    /// The first of the top few rows that reads like a name: some letters, no
    /// digits (which rules out addresses, phone numbers and dates).
    static func merchant(in rows: [String]) -> String? {
        let boilerplate = ["WELCOME", "RECEIPT", "INVOICE", "THANK", "WWW", "HTTP", "TEL", "PHONE"]
        for row in rows.prefix(6) {
            let text = row.trimmingCharacters(in: .whitespaces)
            guard text.filter(\.isLetter).count >= 3, !text.contains(where: \.isNumber) else { continue }
            let upper = text.uppercased()
            if boilerplate.contains(where: upper.contains) { continue }
            return text
        }
        return nil
    }

    // MARK: - Amounts

    /// `12.34`, `1,234.56`; not part of a longer number, and not a percentage.
    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d%])"#
    )

    static func amounts(in row: String) -> [Decimal] {
        let range = NSRange(row.startIndex..., in: row)
        return amountPattern.matches(in: row, range: range).compactMap { match in
            guard let r = Range(match.range, in: row) else { return nil }
            return Decimal(string: row[r].replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// Amount printed on a labelled row, or — when OCR split the label and the
    /// figure onto separate rows — alone on the next row.
    private static func amount(labelledAt index: Int, in rows: [String]) -> Decimal? {
        if let amount = amounts(in: rows[index]).last { return amount }
        let next = index + 1
        guard next < rows.count, !rows[next].contains(where: \.isLetter) else { return nil }
        return amounts(in: rows[next]).last
    }

    // MARK: - Total

    static func total(in rows: [String]) -> Decimal? {
        let upper = rows.map { $0.uppercased() }
        let notTheTotal = [
            "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "SAVING", "SAVED", "TOTAL ITEMS", "TOTAL QTY",
            "ITEMS SOLD", "TOTAL TAX", "TAX TOTAL", "TOTAL DISCOUNT",
        ]
        // Most specific labels first; plain TOTAL only if none of them appear.
        for labels in [["GRAND TOTAL", "AMOUNT DUE", "BALANCE DUE", "TOTAL DUE"], ["TOTAL"]] {
            for (index, row) in upper.enumerated() where labels.contains(where: row.contains) {
                if notTheTotal.contains(where: row.contains) { continue }
                if let amount = amount(labelledAt: index, in: rows), amount > 0 { return amount }
            }
        }
        return nil
    }

    // MARK: - Tax

    private static let taxPattern = try! NSRegularExpression(pattern: #"\b(HST|GST|PST|QST|TPS|TVQ|TAX|VAT)\b"#)

    /// The "TOTAL TAX" row if there is one, else the sum of the individual tax
    /// rows (e.g. GST + PST).
    static func tax(in rows: [String]) -> Decimal? {
        var sum: Decimal = 0
        var found = false
        for (index, row) in rows.enumerated() {
            let upper = row.uppercased()
            let range = NSRange(upper.startIndex..., in: upper)
            guard taxPattern.firstMatch(in: upper, range: range) != nil else { continue }
            if ["TAXABLE", "PRE-TAX", "BEFORE TAX", "INCL", "EXEMPT"].contains(where: upper.contains) { continue }
            guard let amount = amount(labelledAt: index, in: rows) else { continue }
            if upper.contains("TOTAL") { return amount }
            sum += amount
            found = true
        }
        return found ? sum : nil
    }

    // MARK: - Date

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let monthName = #"(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?"#

    private static let yearFirst = try! NSRegularExpression(pattern: #"\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"#)
    private static let numeric = try! NSRegularExpression(pattern: #"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b"#)
    private static let dayMonthName = try! NSRegularExpression(pattern: #"\b(\d{1,2})\s*"# + monthName + #",?\s*(\d{4}|\d{2})\b"#)
    private static let monthNameDay = try! NSRegularExpression(pattern: #"\b"# + monthName + #"\s*(\d{1,2}),?\s*(\d{4})\b"#)

    /// The first plausible purchase date: a real calendar day, not in the
    /// future, and within the last three years. `03/04/26` reads month-first
    /// (North American receipts) unless only day-first makes a valid date.
    static func date(in rows: [String], today: Date = .now, calendar: Calendar = .current) -> Date? {
        for row in rows {
            let upper = row.uppercased()
            let range = NSRange(upper.startIndex..., in: upper)
            func groups(_ regex: NSRegularExpression) -> [String]? {
                guard let match = regex.firstMatch(in: upper, range: range) else { return nil }
                return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: upper).map { String(upper[$0]) } }
            }
            var candidates: [(year: Int, month: Int, day: Int)] = []
            if let g = groups(yearFirst), let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) {
                candidates.append((y, m, d))
            } else if let g = groups(numeric), let a = Int(g[0]), let b = Int(g[1]), let y = Int(g[2]) {
                let year = y < 100 ? 2000 + y : y
                candidates.append((year, a, b))
                candidates.append((year, b, a))
            } else if let g = groups(dayMonthName), let d = Int(g[0]), let m = monthNumber(g[1]), let y = Int(g[2]) {
                candidates.append((y < 100 ? 2000 + y : y, m, d))
            } else if let g = groups(monthNameDay), let m = monthNumber(g[0]), let d = Int(g[1]), let y = Int(g[2]) {
                candidates.append((y, m, d))
            }
            for c in candidates {
                if let date = validDate(year: c.year, month: c.month, day: c.day, today: today, calendar: calendar) {
                    return date
                }
            }
        }
        return nil
    }

    private static func monthNumber(_ name: String) -> Int? {
        months.firstIndex(of: String(name.prefix(3))).map { $0 + 1 }
    }

    private static func validDate(year: Int, month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            // Rejects rollovers like Feb 30 → Mar 2.
            calendar.component(.day, from: date) == day,
            let latest = calendar.date(byAdding: .day, value: 1, to: today),
            let earliest = calendar.date(byAdding: .year, value: -3, to: today),
            date <= latest, date >= earliest
        else { return nil }
        return date
    }
}

extension ReceiptDraft {
    /// The server's full read laid over what's on screen now: a field still
    /// equal to the quick on-device read (`baseline`) takes the server's value,
    /// one the user already changed keeps theirs. The image is never replaced.
    func refined(with server: ReceiptDraft, baseline: ReceiptDraft) -> ReceiptDraft {
        var out = self
        if merchant == baseline.merchant, !server.merchant.isEmpty { out.merchant = server.merchant }
        if date == baseline.date { out.date = server.date }
        if total == baseline.total, server.total > 0 { out.total = server.total }
        if tax == baseline.tax { out.tax = server.tax }
        if category == baseline.category { out.category = server.category }
        if items == baseline.items { out.items = server.items }
        return out
    }
}
