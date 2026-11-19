import SwiftUI
import WidgetKit
import ActivityKit

struct KnitEntry: TimelineEntry {
    var date: Date
    var data: AppData
}
struct KnitProvider: TimelineProvider {
    func placeholder(in context: Context) -> KnitEntry { KnitEntry(date: Date(), data: AppData()) }
    func getSnapshot(in context: Context, completion: @escaping (KnitEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KnitEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(900)))) }
    private func entry() -> KnitEntry { KnitEntry(date: Date(), data: (try? Store().load()) ?? AppData()) }
}

private let accent = Color(red: 181/255, green: 82/255, blue: 59/255)

struct KnitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: KnitEntry
    private var part: Part { entry.data.currentPart }
    private var name: String { entry.data.currentProject?.name ?? L.t("快速计数") }
    private var row: Int { part.counters.first(where: { $0.kind == .row })?.value ?? part.selectedCounter?.value ?? 0 }
    var body: some View {
        Group {
            if !entry.data.entitlement.hasPro(at: entry.date) { Text(L.t("打开 App 查看作品")).font(.caption) }
            else {
                switch family {
                case .accessoryInline: Text(name + " · " + L.f("第 %@ 行", String(row)))
                case .accessoryCircular:
                    if let c = part.selectedCounter { Button(intent: CountIntent(project: entry.data.recentID, part: part.id, counter: c.id)) { VStack { Text(String(c.value)).font(.title2.monospacedDigit()); Image(systemName: "plus").font(.caption2) } }.buttonStyle(.plain).accessibilityIdentifier("widgetCircularCount") }
                case .accessoryRectangular: compact
                default: full
                }
            }
        }.containerBackground(for: .widget) { Color(red: 245/255, green: 241/255, blue: 234/255) }
    }
    private var compact: some View {
        HStack {
            VStack(alignment: .leading) { Text(name).font(.caption).lineLimit(1); Text(L.f("第 %@ 行", String(row))).font(.headline) }
            Spacer(); increment
        }
    }
    private var full: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(alignment: .firstTextBaseline) { Text(String(row)).font(.system(size: 44, weight: .bold, design: .rounded)); Text(L.t("行 / 圈")).font(.caption); Spacer() }
            HStack {
                if let c = part.counters.first(where: { $0.kind == .stitch }) { Text(String(c.value) + " / " + String(part.roundTargets[part.row] ?? 0) + " " + L.t("针")).font(.caption) }
                Spacer(); increment
            }
        }.foregroundStyle(accent)
    }
    @ViewBuilder private var increment: some View {
        if let c = part.selectedCounter {
            Button(intent: CountIntent(project: entry.data.recentID, part: part.id, counter: c.id)) { Image(systemName: "plus").font(.headline).padding(9) }.tint(accent).accessibilityLabel(L.t("加一针")).accessibilityIdentifier("widgetCount")
        }
    }
}

struct GouZhiWidget: Widget {
    let kind = "GouZhiWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KnitProvider()) { KnitWidgetView(entry: $0) }
            .configurationDisplayName(L.t("钩织计数")).description(L.t("随时记下这一针，这一行。"))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct GouZhiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KnitActivity.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text(context.attributes.name).font(.headline); Text(L.f("第 %@ 行 · %@ / %@ 针", String(context.state.row), String(context.state.stitch), String(context.state.target))).font(.subheadline.monospacedDigit()) }
                Spacer(); activityButton(context)
            }.padding(18).activityBackgroundTint(Color(red: 245/255, green: 241/255, blue: 234/255)).activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.name).font(.caption).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { activityButton(context) }
                DynamicIslandExpandedRegion(.bottom) { Text(L.f("第 %@ 行 · %@ / %@ 针", String(context.state.row), String(context.state.stitch), String(context.state.target))).font(.title3.monospacedDigit()) }
            } compactLeading: { Text(String(context.state.row)).foregroundStyle(accent) }
              compactTrailing: { Text(String(context.state.stitch)).monospacedDigit() }
              minimal: { Text(String(context.state.row)).monospacedDigit() }
        }
    }
    private func activityButton(_ context: ActivityViewContext<KnitActivity>) -> some View {
        Button(intent: CountIntent(project: context.attributes.projectID, part: context.attributes.partID, counter: context.attributes.counterID)) { Image(systemName: "plus").font(.title3).padding(8) }.tint(accent).accessibilityIdentifier("activityCount")
    }
}

@main struct GouZhiWidgets: WidgetBundle {
    var body: some Widget { GouZhiWidget(); GouZhiLiveActivity() }
}
