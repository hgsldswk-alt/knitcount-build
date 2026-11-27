import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(summary).font(.caption).foregroundStyle(Design.muted).padding(.top, 8)
                        if let recent = model.project ?? model.data.projects.sorted(by: { $0.lastOpened > $1.lastOpened }).first {
                            Button { model.select(recent.id) } label: { hero(recent) }.buttonStyle(.plain).accessibilityIdentifier("project-" + recent.id.uuidString)
                        }
                        HStack { Text(L.t("其他作品")).font(.subheadline.bold()); Spacer(); Text(L.f("共 %@ 件", String(model.data.projects.count))).font(.caption).foregroundStyle(Design.muted) }
                        VStack(spacing: 0) {
                            ForEach(model.data.projects.filter { $0.id != (model.project ?? model.data.projects.sorted(by: { $0.lastOpened > $1.lastOpened }).first)?.id }) { p in
                                Button { model.select(p.id) } label: { row(p) }.buttonStyle(.plain).accessibilityIdentifier("projectName-" + p.name)
                                Divider().padding(.leading, 78)
                            }
                        }.background(Design.card, in: RoundedRectangle(cornerRadius: 22))
                        Button { model.select(nil) } label: {
                            HStack(spacing: 12) { Image(systemName: "plus.circle"); Text(L.t("快速计数")).bold(); Text(L.t("不建作品，直接数")).font(.caption); Spacer() }
                                .foregroundStyle(Design.secondary).padding(16).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Design.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5])))
                        }.accessibilityIdentifier("openQuick")
                    }.padding(20)
                }.background(Design.background).navigationTitle(L.t("我的作品"))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button { model.showImport(new: true) } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Design.ink) }.accessibilityIdentifier("newProject") }
                        ToolbarItem(placement: .topBarLeading) { Button(L.t("返回跟织")) { dismiss() }.accessibilityIdentifier("closeSheet") }
                    }
            }.tabItem { Label(L.t("作品"), systemImage: "square.stack") }
            NavigationStack { WallView() }.tabItem { Label(L.t("作品墙"), systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView() }.tabItem { Label(L.t("设置"), systemImage: "slider.horizontal.3") }
        }
    }
    private var summary: String {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let seconds = model.data.projects.reduce(0) { sum, p in sum + p.weeklySeconds.reduce(0) { total, entry in
            guard let date = f.date(from: entry.key), interval?.contains(date) == true else { return total }; return total + entry.value
        } }
        return L.f("%@ 件进行中 · 本周织了 %@", String(model.data.projects.filter { $0.status == .active }.count), L.duration(seconds))
    }
    private func hero(_ p: Project) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ProjectThumb(project: p, store: model.store).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) { Text(p.name).font(.system(size: 18, weight: .semibold)); Text(L.t("上次织到") + " · " + p.lastOpened.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Design.secondary) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(p.part.row)).font(.system(size: 76, weight: .bold, design: .rounded)); Text(L.t("行 / 圈")).foregroundStyle(Design.secondary)
                Spacer(); if p.targetRows > 0 { Text(L.f("共 %@ 行", String(p.targetRows))).font(.caption).foregroundStyle(Design.muted) }
            }
            ProgressView(value: p.progress).tint(Design.accent)
            HStack { Text(p.part.name); if let c = p.part.counters.first(where: { $0.kind == .stitch }) { Text(String(c.value) + " / " + String(p.part.roundTargets[p.part.row] ?? 0) + " " + L.t("针")) }; Spacer(); Text(p.hookSize) }.font(.caption).foregroundStyle(Design.secondary)
        }.knitCard().foregroundStyle(Design.ink)
    }
    private func row(_ p: Project) -> some View {
        HStack(spacing: 14) {
            ProjectThumb(project: p, store: model.store).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Design.ink)
                Text(p.status == .planned ? L.t("想织") : L.f("%@ · 第 %@ 行", p.part.name, String(p.part.row))).font(.caption).foregroundStyle(Design.muted)
                if p.targetRows > 0 { ProgressView(value: p.progress).tint(Design.accent).frame(width: 140) }
            }
            Spacer(); Text(p.targetRows > 0 ? String(Int(p.progress * 100)) + "%" : "›").foregroundStyle(Design.secondary)
        }.padding(16)
    }
}

struct WallView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(L.f("完成 %@ 件", String(model.data.projects.filter { $0.status == .completed }.count))).font(.title2.bold()); Spacer(); if model.hasPro { Text(L.duration(model.data.projects.reduce(0) { $0 + $1.totalSeconds })).font(.title2.monospacedDigit()) } }.padding(.vertical)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(model.data.projects.filter { $0.status == .completed }) { p in
                        Button { model.select(p.id) } label: { VStack(alignment: .leading, spacing: 8) { ProjectThumb(project: p, store: model.store).frame(height: 190); Text(p.name).font(.subheadline).foregroundStyle(Design.ink) } }.buttonStyle(.plain).accessibilityIdentifier("wallProject-" + p.id.uuidString)
                    }
                }
                if !model.data.projects.contains(where: { $0.status == .completed }) { Text(L.t("完成的作品会留在这里。")).foregroundStyle(Design.muted) }
            }.padding(20)
        }.background(Design.background).navigationTitle(L.t("作品墙"))
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var shared: [Any] = []
    @State private var sharing = false
    var body: some View {
        Form {
            Section {
                Toggle(L.t("触觉反馈"), isOn: preference(\.haptics))
                Toggle(L.t("保持屏幕常亮"), isOn: preference(\.keepAwake))
                Toggle(L.t("默认暗化图解其余区域"), isOn: preference(\.dimDefault))
                Toggle(L.t("音量键计数"), isOn: Binding(get: { model.data.preferences.volumeKeys }, set: { value in if !value || model.requirePro() { model.setPreference { $0.volumeKeys = value } } }))
            } footer: { Text(L.t("音量键只在跟织页前台生效，可能影响其他音频的音量。默认关闭。")) }
            Section {
                Button(L.t("导出全部作品")) { export() }.accessibilityIdentifier("exportAll")
                if !Launch.isFree {
                    Button(L.t("买断解锁")) { model.sheet = .paywall }.accessibilityIdentifier("openPaywall")
                    Button(L.t("恢复购买")) { Task { await model.restore() } }.accessibilityIdentifier("restorePurchases")
                }
                Button(L.t("评分")) { if let url = ReviewGate.storeURL { UIApplication.shared.open(url) } }.accessibilityIdentifier("rateApp")
                Link(L.t("联系邮箱"), destination: URL(string: "mailto:2522855586@qq.com")!)
                Text("2522855586@qq.com").font(.caption).foregroundStyle(Design.muted)
                Text(L.t("隐私政策链接待上线")).foregroundStyle(Design.muted)
            }
        }.scrollContentBackground(.hidden).background(Design.background).navigationTitle(L.t("设置"))
            .sheet(isPresented: $sharing) { SystemShare(items: shared) }
    }
    private func preference(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { model.data.preferences[keyPath: key] }, set: { value in model.setPreference { $0[keyPath: key] = value } })
    }
    private func export() {
        guard let store = model.store else { return }
        Task {
            do { let url = try await Task.detached { try store.exportAll() }.value; shared = [url]; sharing = true }
            catch { model.notify(L.t("导出失败，请稍后重试。")) }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                let history = model.data.undo[model.part.historyKey] ?? []
                ForEach(Array(history.enumerated().reversed()), id: \.offset) { i, step in
                    Button {
                        model.restoreHistory(i); dismiss()
                    } label: { HStack { Text(step.at.formatted(date: .omitted, time: .standard)); Spacer(); Text(step.counters.map { $0.name + " " + String($0.value) }.joined(separator: " · ")).foregroundStyle(Design.secondary) } }.accessibilityIdentifier("restoreHistory-" + String(i))
                }
            }.navigationTitle(L.t("最近 50 步")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
        }
    }
}
