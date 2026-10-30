import Foundation

/// Live preview of a split's shares while it's being set up — the same rules
/// as the server's `services/splits.py` (docs/SPLITS.md), which stays the
/// source of truth: the shares that come back from saving are the real ones.
///
/// Whole cents, rounded so the shares add up to the total exactly (largest
/// remainder; earliest person first on ties).
enum SplitMath {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case even, items, shares, custom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .even: "Evenly"
            case .items: "By item"
            case .shares: "Shares"
            case .custom: "Amounts"
            }
        }
    }

    struct Input {
        var itemIndexes: Set<Int> = []
        var amount: Decimal?
        /// Shares mode: parts of the total (2 and 3 → 2/5 and 3/5); nil = 1.
        var weight: Decimal?
    }

    enum Failure: Error, Equatable {
        case noPeople
        case missingAmount
        case noShares
        case amountsDontAddUp(total: Decimal, entered: Decimal)
    }

    static func shares(
        total: Decimal,
        mode: Mode,
        inputs: [Input],
        itemPrices: [Decimal]
    ) -> Result<[Decimal], Failure> {
        let n = inputs.count
        guard n > 0 else { return .failure(.noPeople) }
        let totalCents = cents(total)

        switch mode {
        case .custom:
            var amounts: [Int] = []
            for input in inputs {
                guard let amount = input.amount, amount >= 0 else { return .failure(.missingAmount) }
                amounts.append(cents(amount))
            }
            let entered = amounts.reduce(0, +)
            guard entered == totalCents else {
                return .failure(.amountsDontAddUp(total: decimal(totalCents), entered: decimal(entered)))
            }
            return .success(amounts.map(decimal))

        case .shares:
            let weights = inputs.map { max(0, $0.weight ?? 1) }
            let whole = weights.reduce(0, +)
            guard whole > 0 else { return .failure(.noShares) }
            return .success(allocate(totalCents, weights.map { Decimal(totalCents) * $0 / whole }).map(decimal))

        case .even:
            let each = Decimal(totalCents) / Decimal(n)
            return .success(allocate(totalCents, Array(repeating: each, count: n)).map(decimal))

        case .items:
            // Each item is shared by whoever had it (everyone, if nobody); the
            // rest of the total (tax, tip, discounts) follows each subtotal.
            let itemCents = itemPrices.map(cents)
            var base = Array(repeating: Decimal(0), count: n)
            for (index, price) in itemCents.enumerated() {
                var holders = inputs.indices.filter { inputs[$0].itemIndexes.contains(index) }
                if holders.isEmpty { holders = Array(inputs.indices) }
                for i in holders { base[i] += Decimal(price) / Decimal(holders.count) }
            }
            let rest = Decimal(totalCents - itemCents.reduce(0, +))
            let subtotal = base.reduce(0, +)
            let exact = base.map { b in
                subtotal != 0 ? b + rest * b / subtotal : b + rest / Decimal(n)
            }
            return .success(allocate(totalCents, exact).map(decimal))
        }
    }

    // MARK: - Cents

    static func cents(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value * 100)
            .rounding(accordingToBehavior: roundPlain)
            .intValue
    }

    static func decimal(_ cents: Int) -> Decimal { Decimal(cents) / 100 }

    private static func allocate(_ totalCents: Int, _ exact: [Decimal]) -> [Int] {
        var floors = exact.map { NSDecimalNumber(decimal: $0).rounding(accordingToBehavior: roundDown).intValue }
        let leftover = totalCents - floors.reduce(0, +)
        let order = exact.indices.sorted { a, b in
            let ra = exact[a] - Decimal(floors[a])
            let rb = exact[b] - Decimal(floors[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in order.prefix(max(leftover, 0)) { floors[i] += 1 }
        return floors
    }

    private static let roundPlain = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 0, raiseOnExactness: false,
        raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
    )
    private static let roundDown = NSDecimalNumberHandler(
        roundingMode: .down, scale: 0, raiseOnExactness: false,
        raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
    )
}
