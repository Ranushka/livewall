import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry {
    let date: Date
    let note: Shared.LatestNote?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, note: .init(id: "p", text: "Thinking of you", date: .now, mine: false))
    }
    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        completion(NoteEntry(date: .now, note: Shared.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        let entry = NoteEntry(date: .now, note: Shared.load())
        // Pushes reload the widget right away; this is the 15-minute backup refresh.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct NoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NoteEntry

    private var text: String { entry.note?.text ?? "No notes yet" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(text)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note?.mine == true ? "You" : "Partner").font(.caption2).opacity(0.7)
                Text(text).font(.footnote).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.note?.mine == true ? "You" : "Partner").font(.caption).foregroundStyle(.secondary)
                Text(text).font(family == .systemSmall ? .callout : .title3).bold()
                Spacer(minLength: 0)
                if let d = entry.note?.date { Text(d, style: .relative).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct LiveWallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveWallNote", provider: Provider()) { entry in
            NoteWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Partner note")
        .description("The latest note from your partner.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

@main
struct LiveWallWidgetBundle: WidgetBundle {
    var body: some Widget { LiveWallWidget() }
}
