import SwiftUI
import WidgetKit

struct PufflineEntry: TimelineEntry {
    let date: Date
    var used: Int
    var limit: Int
    var ready: Bool
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PufflineEntry { PufflineEntry(date: Date(), used: 0, limit: 150, ready: true) }
    func getSnapshot(in context: Context, completion: @escaping (PufflineEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PufflineEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }
    func entry() -> PufflineEntry {
        guard var state = try? SharedStorage.load(), state.onboarded else { return PufflineEntry(date: Date(), used: 0, limit: 0, ready: false) }
        // Widgets are read-only. The app is the only writer, avoiding lost updates.
        state.advance(to: Date())
        let day = DayKey.key(Date())
        return PufflineEntry(date: Date(), used: state.count(on: day), limit: state.limit(on: day), ready: true)
    }
}
struct WidgetView: View {
    var entry: PufflineEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Puffline").font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: "cloud").font(.caption)
                }
                if entry.ready {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.used)").font(.system(size: 43, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                        Text("/ \(entry.limit)").font(.caption).foregroundColor(.secondary)
                    }.lineLimit(1)
                    Text("затяжок сьогодні").font(.system(size: 10)).foregroundColor(.secondary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.primary).frame(width: proxy.size.width * min(1, CGFloat(entry.used) / CGFloat(max(1, entry.limit))))
                        }
                    }.frame(height: 4)
                } else {
                    Text("Твій перший крок").font(.headline)
                    Text("Відкрий застосунок і створи свій план.").font(.caption).foregroundColor(.secondary)
                }
            }
            if family == .systemMedium {
                Link(destination: URL(string: "puffline://add?count=1")!) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .medium))
                        Text("Відмітити").font(.system(size: 10))
                    }.frame(width: 90, height: 106).background(Color.primary).foregroundColor(Color(UIColor.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 22))
                }
            }
        }.padding(18).background(Color(UIColor.systemBackground))
            .widgetURL(URL(string: "puffline://home"))
    }
}
@main
struct PufflineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PufflineDaily", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Puffline · Сьогодні")
            .description("Затяжки та денний ліміт завжди поруч.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
