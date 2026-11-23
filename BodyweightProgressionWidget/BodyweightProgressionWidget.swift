import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    var date: Date
    var data: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    private func fallback(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(state: TrainingState(), entitlement: Entitlement(firstOpen: .distantPast),
                       now: date, zone: .current)
    }

    func placeholder(in context: Context) -> TodayEntry {
        let date = Date()
        return TodayEntry(date: date, data: fallback(at: date))
    }

    private func read(at date: Date) -> WidgetSnapshot {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent(WidgetSnapshot.filename),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return fallback(at: date) }
        return snapshot
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let date = Date()
            completion(TodayEntry(date: date, data: read(at: date)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let date = Date()
            let data = read(at: date)
            let times = Set([data.weekEnd, data.expires, data.nextMidnight].compactMap { $0 }.filter { $0 > date }).sorted()
            let entries = ([date] + times).map { TodayEntry(date: $0, data: data) }
            let next = (times.first ?? date).addingTimeInterval(3_600)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

struct TodayWidgetView: View {
    var entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L.t("week.title"), systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
            Text(L.f("widget.count", entry.data.count(at: entry.date), entry.data.goal))
                .font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.white)
            if let movement = entry.data.movement(at: entry.date) {
                Spacer(minLength: 0)
                Text(movement.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(L.f("table.last.value", entry.data.value(at: entry.date).map(movement.unit.format) ?? L.t("value.empty")))
                    .font(.caption2.monospacedDigit()).lineLimit(1)
            } else {
                Spacer(minLength: 0)
                Text(L.t("widget.open")).font(.caption.weight(.semibold)).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color(red: 13/255, green: 106/255, blue: 130/255) }
        .widgetURL(WidgetSnapshot.destination)
    }
}

@main
struct BodyweightProgressionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("widget.name"))
        .description(L.t("widget.description"))
        .supportedFamilies([.systemSmall])
    }
}
