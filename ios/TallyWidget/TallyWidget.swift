import SwiftUI
import WidgetKit

/// This month's spending at a glance (home screen and lock screen).
@main
struct TallyWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthWidget()
    }
}

struct MonthEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthEntry) -> Void) {
        completion(entry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthEntry>) -> Void) {
        // The app reloads this whenever spending changes; refresh daily too so
        // a new month rolls over.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry(preview: false)], policy: .after(tomorrow)))
    }

    private func entry(preview: Bool) -> MonthEntry {
        if let saved = WidgetSnapshot.load() {
            return MonthEntry(date: .now, snapshot: saved, isPlaceholder: false)
        }
        return MonthEntry(date: .now, snapshot: .placeholder, isPlaceholder: !preview)
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TallyMonth", provider: MonthProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.bg }
        }
        .configurationDisplayName("This month")
        .description("What you've spent this month, and where it went.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

enum WidgetPalette {
    static let bg = Color(red: 0.047, green: 0.078, blue: 0.071)
    static let text = Color(red: 0.945, green: 0.925, blue: 0.882)
    static let secondary = Color(red: 0.62, green: 0.64, blue: 0.60)
    static let accent = Color(red: 0.851, green: 0.682, blue: 0.361)
    static let up = Color(red: 0.94, green: 0.45, blue: 0.40)
    static let down = Color(red: 0.32, green: 0.78, blue: 0.53)

    static func category(_ slug: String) -> Color {
        switch slug {
        case "groceries": Color(red: 0.29, green: 0.75, blue: 0.53)
        case "restaurants": Color(red: 0.95, green: 0.63, blue: 0.35)
        case "utilities": Color(red: 0.89, green: 0.75, blue: 0.29)
        case "transport": Color(red: 0.36, green: 0.60, blue: 0.89)
        case "shopping": Color(red: 0.74, green: 0.52, blue: 0.90)
        case "entertainment": Color(red: 0.92, green: 0.45, blue: 0.62)
        case "health": Color(red: 0.40, green: 0.80, blue: 0.80)
        default: Color(red: 0.6, green: 0.62, blue: 0.6)
        }
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthEntry

    private var s: WidgetSnapshot { entry.snapshot }
    private func money(_ value: Decimal, cents: Bool = true) -> String {
        value.formatted(.currency(code: s.currency).precision(.fractionLength(cents ? 2 : 0)))
    }
    private var delta: Decimal { s.monthTotal - s.previousMonthTotal }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(money(s.monthTotal, cents: false)) this month")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    TallyGlyph().frame(width: 15, height: 15)
                    Text("THIS MONTH").font(.caption2.weight(.semibold))
                }
                Text(money(s.monthTotal)).font(.title3.weight(.bold)).minimumScaleFactor(0.7)
                if s.previousMonthTotal > 0 {
                    Text("\(delta >= 0 ? "+" : "−")\(money(abs(delta), cents: false)) vs last month").font(.caption2)
                }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                total
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(s.top.prefix(3), id: \.self) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.name).font(.caption).foregroundStyle(WidgetPalette.text)
                                Spacer()
                                Text(money(c.amount, cents: false)).font(.caption.monospacedDigit()).foregroundStyle(WidgetPalette.secondary)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(WidgetPalette.category(c.slug))
                                    .frame(width: max(4, proxy.size.width * share(c)))
                            }
                            .frame(height: 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(URL(string: "com.vipreshpatel.tally://dashboard"))
        default:
            total.widgetURL(URL(string: "com.vipreshpatel.tally://dashboard"))
        }
    }

    /// Budget used this month as a ring; without budgets, the month's total.
    @ViewBuilder
    private var circular: some View {
        if let spent = s.budgetSpent, let limit = s.budgetLimit, limit > 0 {
            let used = NSDecimalNumber(decimal: spent / limit).doubleValue
            Gauge(value: min(used, 1)) {
                TallyGlyph()
            } currentValueLabel: {
                if used > 1 {
                    // Over budget: how much over reads better than "887%".
                    VStack(spacing: 0) {
                        Text("OVER").font(.system(size: 8, weight: .bold))
                        Text(compact(spent - limit)).font(.system(size: 12, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                    }
                } else {
                    Text("\(Int((used * 100).rounded()))%")
                }
            }
            .gaugeStyle(.accessoryCircular)
            .widgetLabel("Budget used")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    TallyGlyph().frame(width: 16, height: 16)
                    Text(compact(s.monthTotal))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(4)
            }
            .widgetLabel("This month")
        }
    }

    /// $1,474.49 → "$1.5k"; under 1,000 → "$742".
    private func compact(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value).doubleValue
        let symbol = Locale.current.currencySymbol ?? "$"
        return n >= 1000 ? "\(symbol)\(String(format: "%.1f", n / 1000))k" : money(value, cents: false)
    }

    private func share(_ c: WidgetSnapshot.Category) -> CGFloat {
        guard s.monthTotal > 0 else { return 0 }
        return CGFloat(NSDecimalNumber(decimal: c.amount / s.monthTotal).doubleValue)
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.monthLabel.uppercased())
                .font(.caption2.weight(.semibold)).tracking(1.2)
                .foregroundStyle(WidgetPalette.accent)
            Text(money(s.monthTotal))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetPalette.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if s.previousMonthTotal > 0 {
                Text("\(delta >= 0 ? "↑" : "↓") \(money(abs(delta), cents: false)) vs last month")
                    .font(.caption2)
                    .foregroundStyle(delta >= 0 ? WidgetPalette.up : WidgetPalette.down)
            }
            Spacer(minLength: 0)
            if let next = s.nextReturn {
                Label(next, systemImage: "arrow.uturn.backward")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            } else {
                Link(destination: URL(string: "com.vipreshpatel.tally://scan")!) {
                    Label("Scan", systemImage: "camera.viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.bg)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(WidgetPalette.accent, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}


/// The Tally mark: four strokes and a slash (design/logo/tally-mark.svg),
/// drawn so it tints with the lock screen like any other glyph.
struct TallyGlyph: View {
    var body: some View {
        Canvas { context, size in
            // Cropped to the strokes (round caps included), not the logo's padded 1024 box.
            let box: CGFloat = 526, origin: CGFloat = 254
            let unit = min(size.width, size.height) / box
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: (x - origin - box / 2) * unit + size.width / 2,
                    y: (y - origin - box / 2) * unit + size.height / 2
                )
            }
            var strokes = Path()
            for x in [344.0, 459, 574, 689] {
                strokes.move(to: p(x, 300))
                strokes.addLine(to: p(x, 724))
            }
            var slash = Path()
            slash.move(to: p(300, 708))
            slash.addLine(to: p(733, 316))
            let style = StrokeStyle(lineWidth: 92 * unit, lineCap: .round)
            context.stroke(strokes, with: .foreground, style: style)
            context.stroke(slash, with: .foreground, style: style)
        }
        .accessibilityHidden(true)
    }
}
