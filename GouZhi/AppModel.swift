import SwiftUI
import UIKit
import StoreKit
import WidgetKit
import ActivityKit
import Security

enum SheetRoute: Identifiable {
    case projects, detail, importPattern, symbols, share, history, paywall, milestone(String), counter(UUID)
    var id: String {
        switch self {
        case .projects: return "projects"; case .detail: return "detail"; case .importPattern: return "import"
        case .symbols: return "symbols"; case .share: return "share"; case .history: return "history"
        case .paywall: return "paywall"; case .milestone(let key): return key; case .counter(let id): return id.uuidString
        }
    }
}
enum ImportSource { case all, photos, files, text, video }

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var sheet: SheetRoute?
    @Published var banner: String?
    @Published var toast: String?
    @Published var hasPaste = false
    @Published var locked = false
    @Published var active = true
    @Published var knitting = true
    @Published var products: [Product] = []
    @Published var purchasing = false
    @Published var productLoadFailed = false
    @Published var activityEnabled = false
    @Published var importNew = true
    @Published var importSource: ImportSource = .all
    @Published var pendingMilestones: [String] = []
    var cardClosed = false
    let isolated: Bool
    let arguments: [String]
    private(set) var store: Store?
    private var canWrite = true
    private var transactions: Task<Void, Never>?
    private var undoAction: (() -> Void)?
    private var undoContext: (project: UUID?, part: UUID)?
    private var toastToken = UUID()
    private var bannerToken = UUID()
    private var lastCount: Date?
    private var lastTick = Date()
    private var timerProjectID: UUID?
    private var pendingSeconds: TimeInterval = 0
    var project: Project? { data.currentProject }
    var part: Part { data.currentPart }
    var counter: Counter? { part.selectedCounter }
    var hasPro: Bool { data.entitlement.hasPro(at: Date()) }
    var proID: String { Bundle.main.object(forInfoDictionaryKey: "GouZhiProProductID") as? String ?? "com.hgsldswk.knitcount.pro" }
    var trialID: String { Bundle.main.object(forInfoDictionaryKey: "GouZhiTrialProductID") as? String ?? "com.hgsldswk.knitcount.trial" }
    var injectedText: String? {
        guard isolated else { return nil }
        if let text = ProcessInfo.processInfo.environment["GOUZHI_UI_PATTERN_TEXT"] { return text }
        guard let i = arguments.firstIndex(of: "-pattern-text"), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }
    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        #if DEBUG
        isolated = arguments.contains(where: { ["-demo", "-empty", "-ui-testing", "-ring", "-share", "-symbols", "-paid-mode", "-paywall", "-expired"].contains($0) })
        #else
        isolated = false
        #endif
        do {
            if isolated {
                let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Fixtures", isDirectory: true)
                store = try Store(root: root)
                if arguments.contains("-reset") || arguments.contains("-demo") || arguments.contains("-empty") || arguments.contains("-ring") {
                    try store?.update { $0 = AppData() }
                }
            } else { store = try Store() }
            data = try store!.load()
            if isolated, arguments.contains("-demo") || arguments.contains("-ring") || arguments.contains("-share") {
                data = DemoData.make(store: store!, ring: arguments.contains("-ring"))
                if arguments.contains("-grid") { data.projects[0].parts[0].tracker.mode = .grid }
                let initial = data; try store!.update { $0 = initial }
            }
            mutate { state in
                state.launchCount += 1
                if !Launch.isFree, state.entitlement.proStartedAt == nil {
                    state.entitlement.proStartedAt = self.isolated ? Date() : TrialAnchor.loadOrCreate()
                }
                if self.isolated && arguments.contains("-expired") {
                    state.entitlement.firstOpen = Date().addingTimeInterval(-31 * 86400)
                    state.entitlement.proStartedAt = state.entitlement.firstOpen
                }
                if self.isolated && arguments.contains("-share"), let i = state.projects.firstIndex(where: { $0.id == state.recentID }) {
                    state.projects[i].status = .completed; state.projects[i].completedAt = Date()
                }
            }
        } catch {
            canWrite = false
            banner = L.t("数据暂时无法读取，原始文件已保留。请重新打开 App。")
        }
        if isolated {
            if arguments.contains("-share") { sheet = .share }
            else if arguments.contains("-symbols") { sheet = .symbols }
            else if arguments.contains("-paywall") || arguments.contains("-expired") { sheet = .paywall }
        }
    }
    deinit { transactions?.cancel() }
    func mutate(_ change: (inout AppData) -> Void) {
        guard canWrite, let store else { return }
        do {
            data = try store.update(change)
            if !isolated { WidgetCenter.shared.reloadAllTimelines() }
        } catch { notify(L.t("保存失败，请稍后重试。")) }
    }
    func reload() {
        guard let store, canWrite else { return }
        do { data = try store.load() } catch { notify(L.t("读取失败，原始数据已保留。")) }
    }
    func editProject(_ change: (inout Project) -> Void) {
        let context = undoContext ?? (project: project?.id, part: part.id)
        guard let id = context.project else { return }
        mutate { state in if let i = state.projects.firstIndex(where: { $0.id == id }) { change(&state.projects[i]) } }
    }
    func editPart(_ change: (inout Part) -> Void) {
        let context = undoContext ?? (project: project?.id, part: part.id)
        mutate { $0.editPart(projectID: context.project, partID: context.part, change) }
    }
    @discardableResult func requirePro() -> Bool {
        guard hasPro else { notify(L.t("这项功能可在买断后继续使用，已有作品仍可查看。")); sheet = .paywall; return false }
        return true
    }
    func count(_ delta: Int) {
        guard !locked, let counter else { return }
        let pid = project?.id, id = part.id
        var events: [CountEvent] = []
        mutate { events = $0.count(projectID: pid, partID: id, counterID: counter.id, delta: delta) }
        if lastCount == nil { lastTick = Date() }
        lastCount = Date(); timerProjectID = pid
        if data.preferences.haptics {
            UIImpactFeedbackGenerator(style: events.contains(where: { if case .rowCompleted = $0 { return true }; return false }) ? .medium : .light).impactOccurred()
        }
        for event in events {
            if case .reminderHit(let reminder) = event, hasPro {
                notify(reminder.text)
                if data.preferences.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
        updateActivity(); checkMilestones()
    }
    func undoCount() {
        guard !locked else { return }
        let pid = project?.id, id = part.id
        mutate { state in
            var stack = state.undo[id.uuidString] ?? []
            state.editPart(projectID: pid, partID: id) { $0 = Counting.undo($0, stack: &stack) }
            state.undo[id.uuidString] = stack
        }
        updateActivity()
    }
    func restoreHistory(_ index: Int) {
        let pid = project?.id, id = part.id
        var previousPart = part
        var previousStack: [UndoStep] = []
        mutate { state in
            var stack = state.undo[id.uuidString] ?? []
            guard stack.indices.contains(index) else { return }
            previousStack = stack
            state.editPart(projectID: pid, partID: id) { previousPart = $0 }
            let step = stack[index]
            state.editPart(projectID: pid, partID: id) { $0.counters = step.counters; $0.tracker = step.tracker; $0.rowsWorked = step.rowsWorked }
            stack.removeSubrange(index...); state.undo[id.uuidString] = stack
        }
        offerUndo(L.t("计数器已更新")) { [weak self] in
            self?.mutate { state in state.editPart(projectID: pid, partID: id) { $0 = previousPart }; state.undo[id.uuidString] = previousStack }
        }
        updateActivity()
    }
    func changeCounter(_ edited: Counter) {
        var old = part; let pid = project?.id
        editPart { part in
            old = part
            if let i = part.counters.firstIndex(where: { $0.id == edited.id }) { part.counters[i] = edited }
            else { part.counters.append(edited) }
            Counting.moveTracker(&part, from: old.row)
        }
        offerUndo(L.t("计数器已更新")) { [weak self] in
            self?.mutate { $0.editPart(projectID: pid, partID: old.id) { $0 = old } }
        }
        updateActivity()
    }
    func select(_ id: UUID?) {
        flushTime(); pendingSeconds = 0; lastCount = nil; locked = false
        mutate { state in
            state.recentID = id
            if let i = state.projects.firstIndex(where: { $0.id == id }) { state.projects[i].lastOpened = Date() }
        }
        sheet = nil
    }
    func add(_ project: Project, bypassLimit: Bool = false) {
        guard bypassLimit || hasPro || data.projects.filter({ $0.status == .active }).count < 2 else { _ = requirePro(); return }
        flushTime(); pendingSeconds = 0; lastCount = nil
        mutate { $0.projects.append(project); $0.recentID = project.id }
        sheet = nil
    }
    func saveQuick() {
        var p = Project(name: PatternParse.name(from: "")); p.parts = [part]
        add(p)
        if project?.id == p.id { mutate { $0.quick = AppData().quick } }
    }
    func deleteProject(_ id: UUID) {
        guard let p = data.projects.first(where: { $0.id == id }) else { return }
        flushTime()
        mutate { $0.projects.removeAll { $0.id == id }; if $0.recentID == id { $0.recentID = nil } }
        sheet = nil
        offerUndo(L.t("作品已删除")) { [weak self] in self?.mutate { $0.projects.append(p); $0.recentID = p.id } }
    }
    func complete() {
        flushTime(); lastCount = nil
        let completedID = project?.id
        editProject { $0.status = .completed; $0.completedAt = Date() }
        if !isolated {
            Task { for activity in Activity<KnitActivity>.activities where activity.attributes.projectID == completedID { await activity.end(nil, dismissalPolicy: .immediate) }; activityEnabled = false }
        }
        checkMilestones(present: false)
        sheet = nil
        Task { @MainActor in try? await Task.sleep(nanoseconds: 350_000_000); self.sheet = .share }
    }
    func checkMilestones(present: Bool = true) {
        guard !isolated else { return }
        var fresh: [String] = []
        mutate { fresh = Milestones.fresh(projects: $0.projects, announced: &$0.milestones) }
        pendingMilestones.append(contentsOf: fresh)
        if present { presentNextMilestone() }
    }
    func presentNextMilestone() {
        guard sheet == nil, let key = pendingMilestones.first else { return }
        pendingMilestones.removeFirst(); sheet = .milestone(key)
    }
    func importCode(_ text: String) {
        guard let p = ShareCode.decode(text) else { notify(L.t("没有识别出口令，请粘贴完整内容。")); return }
        add(p, bypassLimit: true); hasPaste = false
    }
    func showImport(new: Bool, source: ImportSource = .all) {
        if new && !hasPro && data.projects.filter({ $0.status == .active }).count >= 2 { _ = requirePro(); return }
        importNew = new; importSource = new && source == .all ? .photos : source; sheet = .importPattern
    }
    func setPreference(_ change: (inout Preferences) -> Void) { mutate { change(&$0.preferences) } }
    func notify(_ text: String) {
        banner = text; let token = UUID(); bannerToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.bannerToken == token { self.banner = nil }
        }
    }
    func offerUndo(_ text: String, action: @escaping () -> Void) {
        let context = (project: project?.id, part: part.id)
        undoAction = { [weak self] in
            self?.undoContext = context
            defer { self?.undoContext = nil }
            action()
        }
        toast = text; let token = UUID(); toastToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.toastToken == token { self.toast = nil; self.undoAction = nil }
        }
    }
    func undoToast() { let action = undoAction; toast = nil; undoAction = nil; action?() }
    func updatePasteHint() { hasPaste = !isolated && UIPasteboard.general.hasStrings }
    func foreground(_ isActive: Bool) {
        if !isActive { flushTime() }
        active = isActive; lastTick = Date()
        if isActive {
            reload(); updatePasteHint()
            activityEnabled = Activity<KnitActivity>.activities.contains { $0.attributes.projectID == project?.id }
        }
    }
    func tick() {
        let now = Date()
        defer { lastTick = now }
        guard active, UIApplication.shared.applicationState == .active, knitting, hasPro, let lastCount, now.timeIntervalSince(lastCount) <= 300,
              timerProjectID == project?.id, project != nil else { return }
        pendingSeconds += max(0, min(5, now.timeIntervalSince(lastTick)))
        if pendingSeconds >= 10 { flushTime() }
    }
    func flushTime() {
        guard pendingSeconds >= 1, let id = timerProjectID else { return }
        let seconds = Int(pendingSeconds); pendingSeconds -= Double(seconds)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let day = f.string(from: Date())
        mutate { state in
            if let i = state.projects.firstIndex(where: { $0.id == id }) {
                state.projects[i].totalSeconds += seconds; state.projects[i].weeklySeconds[day, default: 0] += seconds
            }
        }
    }
    func toggleActivity() {
        guard requirePro(), let p = project, let c = counter else { return }
        if activityEnabled {
            Task {
                for activity in Activity<KnitActivity>.activities where activity.attributes.projectID == p.id { await activity.end(nil, dismissalPolicy: .immediate) }
                activityEnabled = false
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { notify(L.t("请在系统设置允许实时活动。")); return }
            do {
                _ = try Activity.request(attributes: KnitActivity(projectID: p.id, partID: part.id, counterID: c.id, name: p.name), content: ActivityContent(state: activityState(part), staleDate: nil), pushType: nil)
                activityEnabled = true
            } catch { notify(L.t("暂时无法显示实时活动。")) }
        }
    }
    private func activityState(_ part: Part) -> KnitActivity.ContentState {
        .init(row: part.row, stitch: part.counters.first(where: { $0.kind == .stitch })?.value ?? 0, target: part.roundTargets[part.row] ?? 0)
    }
    func syncActivitySelection() {
        guard !isolated else { return }
        let activities = Activity<KnitActivity>.activities
        guard !activities.isEmpty else { activityEnabled = false; return }
        guard let p = project, let c = counter, hasPro else {
            Task { for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }; activityEnabled = false }
            return
        }
        let selected = part
        if activities.count == 1, activities[0].attributes.projectID == p.id, activities[0].attributes.partID == selected.id { activityEnabled = true; return }
        Task {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            guard active, project?.id == p.id, part.id == selected.id else { activityEnabled = false; return }
            do {
                _ = try Activity.request(attributes: KnitActivity(projectID: p.id, partID: selected.id, counterID: c.id, name: p.name), content: ActivityContent(state: activityState(selected), staleDate: nil), pushType: nil)
                activityEnabled = true
            } catch { activityEnabled = false; notify(L.t("暂时无法显示实时活动。")) }
        }
    }
    func updateActivity() {
        guard !isolated else { return }
        let projects = data.projects
        Task {
            for activity in Activity<KnitActivity>.activities {
                guard let p = projects.first(where: { $0.id == activity.attributes.projectID }), let part = p.parts.first(where: { $0.id == activity.attributes.partID }) else {
                    await activity.end(nil, dismissalPolicy: .immediate); continue
                }
                await activity.update(ActivityContent(state: activityState(part), staleDate: nil))
            }
        }
    }
    func startStore() async {
        guard !isolated, !Launch.isFree else { return }
        transactions = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, !Task.isCancelled else { return }
                if case .verified(let t) = result, [self.proID, self.trialID].contains(t.productID) {
                    await self.refreshEntitlements(); await t.finish()
                }
            }
        }
        await refreshEntitlements()
        if !hasPro && !data.expiryShown { mutate { $0.expiryShown = true }; notify(L.t("体验已结束，已有作品仍可查看、计数和导出。")) }
    }
    func refreshEntitlements() async {
        var pro = false; var trial: Date?
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let t) = verification, t.revocationDate == nil else { continue }
            if t.productID == proID { pro = true }
            if t.productID == trialID { trial = min(trial ?? t.originalPurchaseDate, t.originalPurchaseDate) }
        }
        mutate {
            $0.entitlement.purchasedPro = pro
            if let trial { $0.entitlement.trialClaimedAt = min($0.entitlement.trialClaimedAt ?? trial, trial) }
        }
    }
    func loadProducts() async {
        guard !isolated, !Launch.isFree else { return }
        do { products = try await Product.products(for: [proID, trialID]); productLoadFailed = products.isEmpty }
        catch { productLoadFailed = true }
    }
    func purchase(_ id: String) async {
        guard !isolated, !Launch.isFree, !purchasing else { return }
        guard let p = products.first(where: { $0.id == id }) else { notify(L.t("商品暂不可用，请稍后重试。")); return }
        purchasing = true; defer { purchasing = false }
        do {
            switch try await p.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else { notify(L.t("无法验证购买，请尝试恢复购买。")); return }
                if t.productID == trialID { mutate { $0.entitlement.trialClaimedAt = min($0.entitlement.trialClaimedAt ?? t.originalPurchaseDate, t.originalPurchaseDate) } }
                await refreshEntitlements(); await t.finish(); if data.entitlement.purchasedPro { sheet = nil }
            case .pending: notify(L.t("购买正在等待批准。"))
            case .userCancelled: break
            @unknown default: break
            }
        } catch { notify(L.t("购买未完成，请稍后重试。")) }
    }
    func restore() async {
        guard !isolated, !Launch.isFree else { return }
        do { try await AppStore.sync(); await refreshEntitlements(); notify(L.t("已检查购买记录。")) }
        catch { notify(L.t("恢复购买失败，请稍后重试。")) }
    }
}

private enum TrialAnchor {
    static func loadOrCreate() -> Date {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.hgsldswk.knitcount", kSecAttrAccount as String: "trialStart"]
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &value) == errSecSuccess, let data = value as? Data, let time = Double(String(decoding: data, as: UTF8.self)) { return Date(timeIntervalSince1970: time) }
        let date = Date(); var add = query
        add[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil); return date
    }
}
