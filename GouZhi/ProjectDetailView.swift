import SwiftUI
import PhotosUI
import AVFoundation

struct ProjectDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newReminderRow = 1
    @State private var reminderText = ""
    @State private var reminderColor = -1
    @State private var targetRow = 1
    @State private var targetCount = 24
    @State private var videoTime = "00:00"
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var sharing = false
    @State private var shared: [Any] = []
    @State private var cropPage: PatternPage?
    var body: some View {
        NavigationStack {
            Form {
                if let project = model.project {
                    Section {
                        TextField(L.t("作品名称"), text: projectText(\.name)).accessibilityIdentifier("projectName")
                        Picker(L.t("状态"), selection: Binding(get: { project.status }, set: { value in
                            if value == .completed { model.complete() } else { model.editProject { $0.status = value; $0.completedAt = nil } }
                        })) { ForEach(ProjectStatus.allCases, id: \.self) { Text($0.title).tag($0) } }
                        LabeledContent(L.t("开始日期"), value: project.createdAt.formatted(date: .abbreviated, time: .omitted))
                        if let date = project.completedAt { LabeledContent(L.t("完成日期"), value: date.formatted(date: .abbreviated, time: .omitted)) }
                    }
                    Section {
                        Button(L.t("配色图解"), systemImage: "square.grid.3x3") {
                            model.sheet = .colorwork(nil)
                        }.accessibilityIdentifier("detailColorwork")
                    }
                    partsSection(project)
                    countersSection
                    remindersSection
                    targetsSection
                    materialsSection(project)
                    Section(L.t("本行备注")) {
                        TextField(L.f("第 %@ 行", String(model.part.row)), text: Binding(get: { model.part.rowNotes[model.part.row] ?? "" }, set: { value in model.editPart { $0.rowNotes[$0.row] = value } }), axis: .vertical)
                    }
                    photosSection(project)
                    videoSection
                    pagesSection
                    Section {
                        Button(L.t("分享作品口令")) { shareCode() }.accessibilityIdentifier("shareCode")
                        Button(L.t("分享图解")) { sharePattern() }.accessibilityIdentifier("sharePattern")
                        Text(L.t("请只分享你有权分享的图解")).font(.caption).foregroundStyle(Design.muted)
                        Button(L.t("导出全部作品")) { export() }.accessibilityIdentifier("detailExportAll")
                        Button(L.t("完成")) { model.complete() }.accessibilityIdentifier("detailComplete")
                        Button(L.t("删除作品"), role: .destructive) { model.deleteProject(project.id) }.accessibilityIdentifier("deleteProject")
                    }
                }
            }.scrollContentBackground(.hidden).background(Design.background).navigationTitle(L.t("作品详情")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("完成编辑")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
                .sheet(isPresented: $sharing) { SystemShare(items: shared) }
                .sheet(isPresented: $camera) { CameraPicker { image in if let image { savePhoto(image) } } }
                .sheet(item: $cropPage) { page in
                    if let path = try? model.store?.file(page.filename), let image = UIImage(contentsOfFile: path.path) {
                        CropSheet(image: image) { cropped in replaceCrop(page, image: cropped) }
                    }
                }
                .onChange(of: photoItems) { _, items in Task {
                    for item in items { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { savePhoto(image) } }
                    photoItems = []
                } }
        }
    }
    private func projectText(_ key: WritableKeyPath<Project, String>) -> Binding<String> {
        Binding(get: { model.project?[keyPath: key] ?? "" }, set: { value in model.editProject { $0[keyPath: key] = value } })
    }
    private func partsSection(_ project: Project) -> some View {
        Section(L.t("部件")) {
            Picker(L.t("当前部件"), selection: Binding(get: { model.part.id }, set: { value in model.editProject { $0.selectedPartID = value } })) { ForEach(project.parts) { Text($0.name).tag($0.id) } }
            TextField(L.t("部件名称"), text: Binding(get: { model.part.name }, set: { value in model.editPart { $0.name = value } }))
            Stepper(L.f("共 %@ 份", String(model.part.copies)), value: Binding(get: { model.part.copies }, set: { value in model.editPart { $0.copies = value; $0.currentCopy = min(value, $0.currentCopy) } }), in: 1...100)
            Stepper(L.f("当前第 %@ 份", String(model.part.currentCopy)), value: Binding(get: { model.part.currentCopy }, set: { value in model.editPart { $0.currentCopy = value } }), in: 1...max(1, model.part.copies))
            Button(L.t("添加部件")) {
                guard model.hasPro || project.parts.reduce(0, { $0 + $1.counters.count }) < 2 else { _ = model.requirePro(); return }
                model.editProject { let part = Part(name: L.t("新部件")); $0.parts.append(part); $0.selectedPartID = part.id }
            }.accessibilityIdentifier("addPart")
            Button(L.t("复制部件设置")) { copyPart() }.accessibilityIdentifier("copyPart")
            if project.parts.count > 1 {
                Button(L.t("删除此部件"), role: .destructive) {
                    let old = project
                    model.editProject { $0.parts.removeAll { $0.id == model.part.id }; $0.selectedPartID = $0.parts.first?.id }
                    model.offerUndo(L.t("部件已删除")) { model.editProject { $0.parts = old.parts; $0.selectedPartID = old.selectedPartID } }
                }.accessibilityIdentifier("deletePart")
            }
        }
    }
    private var countersSection: some View {
        Section(L.t("计数器")) {
            ForEach(model.part.counters) { c in
                Button { model.sheet = .counter(c.id) } label: { HStack { Text(c.name); Spacer(); Text(String(c.value)).foregroundStyle(Design.secondary); Image(systemName: "chevron.right").font(.caption) } }.accessibilityIdentifier("editCounter-" + c.id.uuidString)
            }
            Button(L.t("添加计数器")) {
                guard model.hasPro || (model.project?.parts.reduce(0, { $0 + $1.counters.count }) ?? model.part.counters.count) < 2 else { _ = model.requirePro(); return }
                model.sheet = .counter(UUID())
            }.accessibilityIdentifier("addCounter")
        }
    }
    private var remindersSection: some View {
        Section(L.t("行提醒")) {
            ForEach(model.part.reminders) { reminder in
                HStack {
                    if let tag = reminder.colorTag { Circle().fill(tagColor(tag)).frame(width: 16, height: 16) }
                    Text(L.f("第 %@ 行", String(reminder.atRow)))
                    TextField(L.t("提醒内容"), text: Binding(get: { model.part.reminders.first(where: { $0.id == reminder.id })?.text ?? "" }, set: { value in
                        guard model.requirePro() else { return }; model.editPart { if let i = $0.reminders.firstIndex(where: { $0.id == reminder.id }) { $0.reminders[i].text = value } }
                    }))
                }.swipeActions { Button(L.t("删除"), role: .destructive) {
                    model.editPart { $0.reminders.removeAll { $0.id == reminder.id } }; model.offerUndo(L.t("提醒已删除")) { model.editPart { $0.reminders.append(reminder) } }
                }.accessibilityIdentifier("deleteReminder-" + reminder.id.uuidString) }
            }
            Stepper(L.f("第 %@ 行", String(newReminderRow)), value: $newReminderRow, in: 1...100_000)
            TextField(L.t("提醒内容"), text: $reminderText)
            Picker(L.t("换色色块"), selection: $reminderColor) {
                Text(L.t("无")).tag(-1); Text(L.t("陶土红")).tag(0); Text(L.t("燕麦色")).tag(1); Text(L.t("苔藓绿")).tag(2); Text(L.t("浅灰")).tag(3)
            }
            Button(L.t("添加提醒")) {
                guard model.requirePro(), !reminderText.isEmpty else { return }
                model.editPart { $0.reminders.append(RowReminder(atRow: newReminderRow, text: reminderText, colorTag: reminderColor < 0 ? nil : reminderColor)) }; reminderText = ""
            }.accessibilityIdentifier("addReminder")
        }
    }
    private var targetsSection: some View {
        Section(L.t("每圈针数表")) {
            ForEach(model.part.roundTargets.keys.sorted(), id: \.self) { row in
                HStack {
                    Text(L.f("第 %@ 行", String(row)))
                    TextField(L.t("针数"), value: Binding(get: { model.part.roundTargets[row] ?? 1 }, set: { value in if model.requirePro() { model.editPart { $0.roundTargets[row] = min(Counting.limit, max(1, value)) } } }), format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }.swipeActions { Button(L.t("删除"), role: .destructive) {
                    let old = model.part.roundTargets[row]
                    model.editPart { $0.roundTargets[row] = nil }; model.offerUndo(L.t("针数已删除")) { model.editPart { $0.roundTargets[row] = old } }
                }.accessibilityIdentifier("deleteTarget-" + String(row)) }
            }
            HStack {
                TextField(L.t("行号"), value: $targetRow, format: .number).keyboardType(.numberPad)
                TextField(L.t("针数"), value: $targetCount, format: .number).keyboardType(.numberPad)
                Button(L.t("添加")) {
                    guard model.requirePro(), targetRow > 0, targetCount > 0, targetCount <= Counting.limit else { return }
                    model.editPart { $0.roundTargets[targetRow] = targetCount }
                }.accessibilityIdentifier("addRoundTarget")
            }
        }
    }
    private func materialsSection(_ p: Project) -> some View {
        Section(L.t("线材与记录")) {
            ForEach(p.yarns) { yarn in
                VStack {
                    TextField(L.t("品牌"), text: yarnText(yarn.id, \.brand))
                    HStack { TextField(L.t("色号"), text: yarnText(yarn.id, \.color)); TextField(L.t("批号"), text: yarnText(yarn.id, \.batch)) }
                    TextField(L.t("用量"), text: yarnText(yarn.id, \.amount))
                }.swipeActions { Button(L.t("删除"), role: .destructive) {
                    model.editProject { $0.yarns.removeAll { $0.id == yarn.id } }; model.offerUndo(L.t("线材已删除")) { model.editProject { $0.yarns.append(yarn) } }
                }.accessibilityIdentifier("deleteYarn-" + yarn.id.uuidString) }
            }
            Button(L.t("添加线材")) { model.editProject { $0.yarns.append(Yarn()) } }.accessibilityIdentifier("addYarn")
            TextField(L.t("针号，如 2.5 mm"), text: projectText(\.hookSize))
            TextField(L.t("尺码"), text: projectText(\.size))
            TextField(L.t("备注"), text: projectText(\.notes), axis: .vertical)
        }
    }
    private func yarnText(_ id: UUID, _ key: WritableKeyPath<Yarn, String>) -> Binding<String> {
        Binding(get: { model.project?.yarns.first(where: { $0.id == id })?[keyPath: key] ?? "" }, set: { value in model.editProject { if let i = $0.yarns.firstIndex(where: { $0.id == id }) { $0.yarns[i][keyPath: key] = value } } })
    }
    private func photosSection(_ p: Project) -> some View {
        Section(L.t("进度照片")) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(p.photos, id: \.self) { name in
                        if let path = try? model.store?.file(name), let image = UIImage(contentsOfFile: path.path) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 90, height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(RoundedRectangle(cornerRadius: 12))
                                .contextMenu {
                                    Button(L.t("设为封面")) { model.editProject { $0.coverFilename = name } }.accessibilityIdentifier("setCover-" + name)
                                    Button(L.t("删除"), role: .destructive) {
                                        model.editProject { $0.photos.removeAll { $0 == name }; if $0.coverFilename == name { $0.coverFilename = nil } }
                                        model.offerUndo(L.t("照片已删除")) { model.editProject { $0.photos.append(name) } }
                                    }.accessibilityIdentifier("deletePhoto-" + name)
                                }
                        }
                    }
                }
            }
            PhotosPicker(L.t("从相册添加"), selection: $photoItems, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images).accessibilityIdentifier("progressPhotoPicker")
            Button(L.t("拍进度照片")) { requestCamera() }.accessibilityIdentifier("takeProgressPhoto")
        }
    }
    private var videoSection: some View {
        Section(L.t("视频与书签")) {
            TextField(L.t("视频链接"), text: Binding(get: { model.project?.videoLink ?? "" }, set: { value in model.editProject { $0.videoLink = value.isEmpty ? nil : value } })).keyboardType(.URL).textInputAutocapitalization(.never)
            HStack {
                TextField("mm:ss", text: $videoTime).keyboardType(.numbersAndPunctuation)
                Button(L.t("记下视频时间")) {
                    guard let seconds = PatternParse.seconds(videoTime) else { model.notify(L.t("请输入 mm:ss 格式的时间。")); return }
                    model.editPart { $0.videoMarks[$0.row] = seconds }
                }.accessibilityIdentifier("addVideoBookmark")
            }
            ForEach(model.part.videoMarks.keys.sorted(), id: \.self) { row in
                if let raw = model.project?.videoLink, let url = PatternParse.videoURL(raw, seconds: model.part.videoMarks[row] ?? 0) {
                    Link(L.f("第 %@ 行 · %@", String(row), String(format: "%d:%02d", (model.part.videoMarks[row] ?? 0) / 60, (model.part.videoMarks[row] ?? 0) % 60)), destination: url).accessibilityIdentifier("videoBookmark-" + String(row))
                }
            }
        }
    }
    private var pagesSection: some View {
        Section(L.t("图解页管理")) {
            ForEach(model.part.patternPages) { page in
                HStack {
                    if let path = try? model.store?.file(page.filename), let image = UIImage(contentsOfFile: path.path) { Image(uiImage: image).resizable().scaledToFit().frame(width: 46, height: 60) }
                    Text(L.f("第 %@ 页", String((model.part.patternPages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1)))
                    Spacer(); Button(L.t("裁剪")) { cropPage = page }.buttonStyle(.borderless).accessibilityIdentifier("cropPage-" + page.id.uuidString)
                }
            }.onMove { source, target in model.editPart { $0.patternPages.move(fromOffsets: source, toOffset: target) } }
                .onDelete { offsets in
                    let old = model.part.patternPages
                    model.editPart { $0.patternPages.remove(atOffsets: offsets); $0.tracker.page = min($0.tracker.page, max(0, $0.patternPages.count - 1)) }
                    model.offerUndo(L.t("图解页已删除")) { model.editPart { $0.patternPages = old } }
                }
            Button(L.t("添加图解")) { model.showImport(new: false) }.accessibilityIdentifier("detailAddPattern")
            EditButton().accessibilityIdentifier("reorderPages")
        }
    }
    private func copyPart() {
        let total = model.project?.parts.reduce(0, { $0 + $1.counters.count }) ?? 0
        guard model.hasPro || total + model.part.counters.count <= 2 else { _ = model.requirePro(); return }
        var copy = model.part; copy.id = UUID(); copy.name += " · " + L.t("副本")
        let map = Dictionary(uniqueKeysWithValues: copy.counters.map { ($0.id, UUID()) })
        copy.mainCounterID = copy.mainCounterID.flatMap { map[$0] }
        for i in copy.counters.indices { let old = copy.counters[i]; copy.counters[i].id = map[old.id]!; copy.counters[i].linkTo = old.linkTo.flatMap { map[$0] }; copy.counters[i].value = old.min }
        copy.currentCopy = 1; copy.tracker = Tracker(); copy.rowsWorked = 0
        model.editProject { $0.parts.append(copy); $0.selectedPartID = copy.id }
    }
    private func shareCode() {
        guard let p = model.project, let encoded = ShareCode.encode(p) else { model.notify(L.t("口令内容过长，请减少部件或备注。")); return }
        if encoded.omittedText { model.notify(L.t("口令较长，已省略文字图解，其他设置保留。")) }
        shared = [encoded.text]; sharing = true
    }
    private func sharePattern() {
        guard let p = model.project, let encoded = ShareCode.encode(p) else { return }
        shared = p.parts.flatMap(\.patternPages).compactMap { page -> UIImage? in guard let url = try? model.store?.file(page.filename) else { return nil }; return UIImage(contentsOfFile: url.path) }
        shared.append(encoded.text); if encoded.omittedText { model.notify(L.t("口令较长，已省略文字图解，其他设置保留。")) }; sharing = true
    }
    private func export() { guard let store = model.store else { return }; Task { do { let url = try await Task.detached { try store.exportAll() }.value; shared = [url]; sharing = true } catch { model.notify(L.t("导出失败，请稍后重试。")) } } }
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.notify(L.t("相机不可用，可以从相册添加照片。")); return }
        Task { if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { model.notify(L.t("相机未开启，可以从相册添加照片。")) } }
    }
    private func savePhoto(_ image: UIImage) {
        guard let store = model.store, let data = image.jpegData(compressionQuality: 0.9), let name = try? store.writeFile(data, extension: "jpg") else { model.notify(L.t("保存失败，请稍后重试。")); return }
        model.editProject { $0.photos.append(name); $0.coverFilename = name }
    }
    private func replaceCrop(_ page: PatternPage, image: UIImage) {
        guard let store = model.store else { return }
        Task {
            do {
                let imported = try await Task.detached { try PatternImporter.image(image, store: store) }.value
                guard let next = imported.pages.first else { return }
                model.editPart { if let i = $0.patternPages.firstIndex(where: { $0.id == page.id }) { $0.patternPages[i] = next } }
                model.offerUndo(L.t("图解已裁剪")) { model.editPart { if let i = $0.patternPages.firstIndex(where: { $0.id == next.id }) { $0.patternPages[i] = page } } }
            } catch { model.notify(L.t("保存失败，请稍后重试。")) }
        }
    }
    private func tagColor(_ tag: Int) -> Color { [Design.accent, Color.brown, Color.green, Color.gray][max(0, min(3, tag))] }
}

struct CounterEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var counterID: UUID
    @State private var draft = Counter()
    @State private var reset = 0
    @State private var link = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField(L.t("名称"), text: $draft.name)
                Picker(L.t("类型"), selection: $draft.kind) { ForEach(CounterKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .onChange(of: draft.kind) { _, kind in draft.min = kind == .row || kind == .repeatCount ? 1 : 0; draft.value = max(draft.min, draft.value) }
                TextField(L.t("当前数值"), value: $draft.value, format: .number).keyboardType(.numberPad)
                HStack { Text(L.t("满")); TextField("0", value: $reset, format: .number).keyboardType(.numberPad); Text(L.t("进")); Picker(L.t("计数器"), selection: $link) { Text(L.t("无")).tag(""); ForEach(model.part.counters.filter { $0.id != counterID }) { Text($0.name).tag($0.id.uuidString) } }.labelsHidden() }
                Text(L.t("填 0 表示不循环；每圈针数表会自动替代针计数的循环值。")).font(.caption).foregroundStyle(Design.muted)
                Button(L.t("清零")) { var zero = draft; zero.value = zero.min; model.changeCounter(zero); dismiss() }.accessibilityIdentifier("resetCounter")
                if model.part.counters.count > 1, model.part.counters.contains(where: { $0.id == counterID }) {
                    Button(L.t("删除计数器"), role: .destructive) {
                        let old = model.part
                        model.editPart { $0.counters.removeAll { $0.id == counterID }; for i in $0.counters.indices where $0.counters[i].linkTo == counterID { $0.counters[i].linkTo = nil }; if $0.mainCounterID == counterID { $0.mainCounterID = $0.counters.first?.id } }
                        model.offerUndo(L.t("计数器已删除")) { model.editPart { $0 = old } }; dismiss()
                    }.accessibilityIdentifier("deleteCounter")
                }
            }.navigationTitle(L.t("计数器")).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") }
                ToolbarItem(placement: .confirmationAction) { Button(L.t("完成")) { save() }.accessibilityIdentifier("saveCounter") }
            }.onAppear { draft = model.part.counters.first(where: { $0.id == counterID }) ?? Counter(id: counterID, name: L.t("针"), kind: .stitch, value: 0, min: 0); reset = draft.resetAt ?? 0; link = draft.linkTo?.uuidString ?? "" }
        }
    }
    private func save() {
        let old = model.part.counters.first(where: { $0.id == counterID })
        if (reset > 0 || !link.isEmpty), (old?.resetAt != (reset > 0 ? reset : nil) || (old?.linkTo?.uuidString ?? "") != link), !model.requirePro() { return }
        draft.value = min(Counting.limit, max(draft.min, draft.value)); draft.resetAt = reset > 0 ? min(Counting.limit, reset) : nil; draft.linkTo = UUID(uuidString: link)
        var test = model.part; test.counters.removeAll { $0.id == draft.id }; test.counters.append(draft)
        var p = Project(); p.parts = [test]
        guard ShareCode.valid(p) else { model.notify(L.t("联动不能形成循环，请选择其他计数器。")); return }
        model.changeCounter(draft); dismiss()
    }
}

struct CropSheet: View {
    @Environment(\.dismiss) private var dismiss
    var image: UIImage
    var saved: (UIImage) -> Void
    @State private var rect = CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let width = proxy.size.width, height = min(proxy.size.height, width * image.size.height / max(1, image.size.width))
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: width, height: height)
                    Rectangle().fill(.black.opacity(0.3)).allowsHitTesting(false)
                    Rectangle().fill(.clear).border(.white, width: 2).frame(width: rect.width * width, height: rect.height * height).offset(x: rect.minX * width, y: rect.minY * height)
                    handle(x: rect.minX * width, y: rect.minY * height) { p in let x = max(0, min(rect.maxX - 0.05, p.x / width)), y = max(0, min(rect.maxY - 0.05, p.y / height)); rect = CGRect(x: x, y: y, width: rect.maxX - x, height: rect.maxY - y) }
                    handle(x: rect.maxX * width, y: rect.maxY * height) { p in rect.size = CGSize(width: max(0.05, min(1, p.x / width) - rect.minX), height: max(0.05, min(1, p.y / height) - rect.minY)) }
                }.coordinateSpace(name: "crop")
            }.navigationTitle(L.t("拖动两角裁剪")).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeCrop") }
                ToolbarItem(placement: .confirmationAction) { Button(L.t("裁剪")) {
                    guard let cg = image.cgImage, let cropped = cg.cropping(to: CGRect(x: rect.minX * CGFloat(cg.width), y: rect.minY * CGFloat(cg.height), width: rect.width * CGFloat(cg.width), height: rect.height * CGFloat(cg.height)).integral) else { return }
                    saved(UIImage(cgImage: cropped)); dismiss()
                }.accessibilityIdentifier("saveCrop") }
            }
        }
    }
    private func handle(x: CGFloat, y: CGFloat, move: @escaping (CGPoint) -> Void) -> some View { Circle().fill(.white).frame(width: 28, height: 28).position(x: x, y: y).gesture(DragGesture(coordinateSpace: .named("crop")).onChanged { move($0.location) }) }
}
