import SwiftUI

struct KnitView: View {
    @EnvironmentObject var model: AppModel
    @State private var split = 0.48
    @State private var splitStart: Double?
    @State private var volume = VolumeCounter()
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if model.hasPaste {
                    HStack {
                        Text(L.t("粘贴朋友的作品口令")).font(.caption)
                        Spacer()
                        PasteButton(payloadType: String.self) { values in model.importCode(values.joined(separator: "\n")) }.labelStyle(.iconOnly).accessibilityIdentifier("pasteCode")
                        Button { model.hasPaste = false } label: { Image(systemName: "xmark") }.accessibilityLabel(L.t("关闭")).accessibilityIdentifier("dismissPasteHint")
                    }.padding(.horizontal, 18).padding(.vertical, 6)
                }
                PatternView().frame(height: min(max(105, geometry.size.height * split - 45), max(105, geometry.size.height - 300))).clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 12)
                if let note = model.part.rowNotes[model.part.row], !note.isEmpty { Text(note).font(.caption).foregroundStyle(Design.secondary).lineLimit(2).padding(.horizontal, 18).padding(.top, 4) }
                Capsule().fill(Design.line).frame(width: 42, height: 5).frame(maxWidth: .infinity).frame(height: 16).contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        if splitStart == nil { splitStart = split }
                        split = min(0.75, max(0.22, (splitStart ?? split) + value.translation.height / max(1, geometry.size.height)))
                    }.onEnded { _ in splitStart = nil })
                    .accessibilityLabel(L.t("调整图解高度"))
                counters.padding(.horizontal, 12)
                tapZone.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            }.background(Design.background)
        }
        .onAppear { model.knitting = true; configureHardware() }
        .onDisappear { model.knitting = false; model.flushTime(); UIApplication.shared.isIdleTimerDisabled = false; volume.stop() }
        .onChange(of: model.active) { _, _ in configureHardware() }
        .onChange(of: model.knitting) { _, _ in configureHardware() }
        .onChange(of: model.data.preferences) { _, _ in configureHardware() }
        .onChange(of: model.hasPro) { _, _ in configureHardware() }
        .onChange(of: model.part.id) { _, _ in model.syncActivitySelection() }
        .background(VolumeView().frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false))
    }
    private var header: some View {
        HStack {
            Button { model.sheet = .projects } label: { Label(L.t("作品"), systemImage: "chevron.left") }.accessibilityIdentifier("openProjects")
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(model.project?.name ?? L.t("快速计数")).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if let p = model.project, p.parts.count > 1 || model.part.copies > 1 {
                    Menu {
                        ForEach(p.parts) { part in
                            Button(part.name) { model.editProject { $0.selectedPartID = part.id } }.accessibilityIdentifier("selectPart-" + part.id.uuidString)
                        }
                    } label: { Text(L.f("%@ · 第 %@/%@ 份", model.part.name, String(model.part.currentCopy), String(model.part.copies))).font(.caption2) }
                }
            }.foregroundStyle(Design.ink)
            Spacer(minLength: 8)
            if model.project != nil {
                Button { model.complete() } label: { Image(systemName: "checkmark.circle").frame(width: 32, height: 40) }.accessibilityLabel(L.t("完成")).accessibilityIdentifier("finishDirect")
            }
            Menu {
                if model.project != nil {
                    Button(L.t("完成"), systemImage: "checkmark") { model.complete() }.accessibilityIdentifier("completeProject")
                    Button(L.t("作品详情"), systemImage: "slider.horizontal.3") { model.sheet = .detail }.accessibilityIdentifier("openDetails")
                    Button(L.t("在锁屏显示"), systemImage: model.activityEnabled ? "lock.open" : "lock") { model.toggleActivity() }.accessibilityIdentifier("toggleActivity")
                }
                Button(L.t("计数历史"), systemImage: "clock.arrow.circlepath") { model.sheet = .history }.accessibilityIdentifier("openHistory")
                Button(L.t("符号速查"), systemImage: "text.book.closed") { model.sheet = .symbols }.accessibilityIdentifier("openSymbols")
                Button(model.locked ? L.t("已锁定，长按解锁") : L.t("锁定计数"), systemImage: "lock") { model.locked = true }.accessibilityIdentifier("lockCounter")
            } label: { Image(systemName: "ellipsis").frame(width: 40, height: 40).contentShape(Rectangle()) }.accessibilityIdentifier("knitMenu")
        }.font(.system(size: 15)).foregroundStyle(Design.secondary).padding(.horizontal, 18).frame(height: 48)
    }
    private var counters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.part.counters) { counter in
                    Button { model.editPart { $0.mainCounterID = counter.id } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(counter.name).font(.caption).foregroundStyle(Design.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(counter.value)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Design.ink).accessibilityIdentifier(counter.kind == .row ? "rowValue" : "counter-" + counter.id.uuidString)
                                if let target = Counting.target(for: counter, in: model.part) { Text("/ " + String(target)).font(.caption).foregroundStyle(Design.muted) }
                            }
                        }.frame(minWidth: 80, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Design.card, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(model.counter?.id == counter.id ? Design.accent : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityIdentifier("selectCounter-" + counter.kind.rawValue).accessibilityValue(String(counter.value))
                        .simultaneousGesture(LongPressGesture().onEnded { _ in model.sheet = .counter(counter.id) })
                }
                if let p = model.project, model.hasPro {
                    VStack(alignment: .leading, spacing: 6) { Text(L.t("计时")).font(.caption).foregroundStyle(Design.muted); Text(L.duration(p.totalSeconds)).font(.system(size: 22, weight: .semibold, design: .rounded)) }
                        .frame(minWidth: 65, alignment: .leading).padding(12).background(Design.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }.frame(height: 80)
    }
    private var tapZone: some View {
        let prompt = model.locked ? L.t("已锁定，长按解锁") : L.f("点任意处 +1 %@", model.counter?.kind.title ?? L.t("针"))
        return ZStack(alignment: .bottom) {
            Button { withAnimation(.snappy(duration: 0.2)) { model.count(1) } } label: {
                VStack(spacing: 4) {
                    Text(prompt).font(.subheadline).opacity(0.8)
                    Text(String(model.counter?.value ?? 0)).font(.system(size: 106, weight: .bold, design: .rounded)).minimumScaleFactor(0.3).lineLimit(1).monospacedDigit().contentTransition(.numericText())
                    if let c = model.counter, let target = Counting.target(for: c, in: model.part), model.hasPro {
                        Text(L.f("满 %@ 自动进位", String(target))).font(.caption).opacity(0.75)
                    }
                    Spacer().frame(height: 40)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("countButton").accessibilityLabel(prompt).accessibilityValue(String(model.counter?.value ?? 0)).disabled(model.locked)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in if !model.locked, let counter = model.counter { model.sheet = .counter(counter.id) } })
            if !model.locked {
                HStack {
                    Button { model.count(-1) } label: { Image(systemName: "minus").frame(width: 46, height: 46) }.accessibilityLabel(L.t("减一")).accessibilityIdentifier("minusButton")
                    Spacer()
                    if model.project == nil { Button(L.t("存为作品")) { model.saveQuick() }.font(.caption).accessibilityIdentifier("saveQuick") }
                    Spacer()
                    Button(L.t("撤销")) { model.undoCount() }.font(.subheadline).padding(.horizontal, 14).frame(height: 46).accessibilityIdentifier("undoButton")
                }.buttonStyle(.plain).padding(16)
            }
            if model.locked {
                Color.clear.contentShape(Rectangle()).onLongPressGesture(minimumDuration: 0.5) { model.locked = false }.accessibilityElement().accessibilityLabel(L.t("已锁定，长按解锁")).accessibilityIdentifier("unlockZone").accessibilityAddTraits(.isButton).accessibilityAction { model.locked = false }
            }
        }.foregroundStyle(.white).background(Design.accent, in: RoundedRectangle(cornerRadius: 30))
            .frame(maxHeight: .infinity).frame(minHeight: 150)
    }
    private func configureHardware() {
        let enabled = model.active && UIApplication.shared.applicationState == .active && model.knitting
        UIApplication.shared.isIdleTimerDisabled = enabled && model.data.preferences.keepAwake
        if enabled && model.data.preferences.volumeKeys && model.hasPro { volume.start { if model.active && model.knitting { model.count(1) } } } else { volume.stop() }
    }
}
