import ActivityKit
import SwiftUI
import WidgetKit

struct RetreatWidgetEntry: TimelineEntry {
    let date: Date
    let phase: String
    let endsAt: Date?
}

struct RetreatWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RetreatWidgetEntry {
        RetreatWidgetEntry(date: Date(), phase: "静坐无言", endsAt: Date().addingTimeInterval(3600))
    }

    func getSnapshot(in context: Context, completion: @escaping (RetreatWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RetreatWidgetEntry>) -> Void) {
        // Spike only: precomputed entries, no server refresh dependency.
        let now = Date()
        let entries = [
            RetreatWidgetEntry(date: now, phase: "气息渐稳", endsAt: now.addingTimeInterval(3600)),
            RetreatWidgetEntry(date: now.addingTimeInterval(1200), phase: "物我两忘", endsAt: now.addingTimeInterval(3600)),
            RetreatWidgetEntry(date: now.addingTimeInterval(2400), phase: "神思渐远", endsAt: now.addingTimeInterval(3600)),
            RetreatWidgetEntry(date: now.addingTimeInterval(3600), phase: "入定已毕", endsAt: nil)
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct RetreatWidgetView: View {
    let entry: RetreatWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("凡人")
                .font(.headline)
            Text(entry.phase)
                .font(.caption)
            if let endsAt = entry.endsAt {
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .padding()
    }
}

struct RetreatHomeWidget: Widget {
    let kind = "RetreatHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RetreatWidgetProvider()) { entry in
            RetreatWidgetView(entry: entry)
        }
        .configurationDisplayName("入定")
        .description("显示当前入定状态。")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

@available(iOSApplicationExtension 16.2, *)
struct RetreatLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RetreatActivityAttributes.self) { context in
            HStack {
                Text("凡人")
                Spacer()
                Text(context.state.phase)
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .monospacedDigit()
            }
            .padding(.horizontal)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("凡人") }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.phase) }
            } compactLeading: {
                Text("凡")
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .monospacedDigit()
            } minimal: {
                Text("凡")
            }
        }
    }
}

@main
struct RetreatWidgetBundle: WidgetBundle {
    var body: some Widget {
        RetreatHomeWidget()
        if #available(iOSApplicationExtension 16.2, *) {
            RetreatLiveActivityWidget()
        }
    }
}
