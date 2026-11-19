import AppIntents
import WidgetKit
import ActivityKit
import Foundation

struct CountIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "加一针"
    static var openAppWhenRun = false
    @Parameter(title: "作品标识") var project: String
    @Parameter(title: "部件标识") var part: String
    @Parameter(title: "计数器标识") var counter: String
    init() {}
    init(project: UUID?, part: UUID, counter: UUID) {
        self.project = project?.uuidString ?? ""; self.part = part.uuidString; self.counter = counter.uuidString
    }
    func perform() async throws -> some IntentResult {
        let store = try Store()
        let data = try store.update { state in
            guard state.entitlement.hasPro(at: Date()), let partID = UUID(uuidString: part), let counterID = UUID(uuidString: counter) else { return }
            let projectID = UUID(uuidString: project)
            let currentPart = projectID.flatMap { id in state.projects.first(where: { $0.id == id })?.parts.first(where: { $0.id == partID }) } ?? (projectID == nil ? state.quick : nil)
            _ = state.count(projectID: projectID, partID: partID, counterID: currentPart?.selectedCounter?.id ?? counterID, delta: 1)
        }
        WidgetCenter.shared.reloadAllTimelines()
        for activity in Activity<KnitActivity>.activities {
            guard let p = data.projects.first(where: { $0.id == activity.attributes.projectID }),
                  let part = p.parts.first(where: { $0.id == activity.attributes.partID }) else { continue }
            let stitch = part.counters.first(where: { $0.kind == .stitch })?.value ?? 0
            await activity.update(ActivityContent(state: .init(row: part.row, stitch: stitch, target: part.roundTargets[part.row] ?? 0), staleDate: nil))
        }
        return .result()
    }
}
