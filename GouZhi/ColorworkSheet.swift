import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ColorworkFile {
    static let type = UTType(exportedAs: "com.hgsldswk.knitcount.colorwork", conformingTo: .data)

    static func read(_ url: URL) throws -> ColorworkChart? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let bytes = try file.read(upToCount: ColorworkExchange.maxFileBytes + 1) else { return nil }
        return ColorworkExchange.read(bytes)
    }
}

struct ColorworkSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editID: UUID?
    @State private var stitches = "16"
    @State private var rows = "16"
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var converting = false
    @State private var photoSetup = false
    @State private var filePicker = false
    @State private var pasteSheet = false
    @State private var message: String?

    init(initialChart: UUID?) { _editID = State(initialValue: initialChart) }

    var body: some View {
        NavigationStack {
            Group {
                if let project = model.project, let chart = project.colorworkCharts.first(where: { $0.id == editID }) {
                    ColorworkEditor(chart: chart, projectID: project.id) { editID = nil }
                        .id(chart.id)
                } else {
                    library
                        .navigationTitle(L.t("配色图解"))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeColorwork")
                            }
                        }
                }
            }.navigationBarTitleDisplayMode(.inline)
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in if item != nil { photoSetup = true } }
        .sheet(isPresented: $photoSetup, onDismiss: { photo = nil }) {
            if let photo {
                ColorworkPhotoSetup(photo: photo, stitches: stitches, rows: rows) { chart in
                    add(chart, fromPhoto: true)
                }
            }
        }
        .sheet(isPresented: $pasteSheet) {
            ColorworkPasteSheet { chart in add(chart) }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [ColorworkFile.type]) { result in
            switch result {
            case .success(let url):
                do {
                    if let chart = try ColorworkFile.read(url) { _ = add(chart) }
                    else { message = L.t("无法读取配色图解。") }
                } catch { message = L.t("无法读取配色图解。") }
            case .failure:
                message = L.t("无法读取配色图解。")
            }
        }
    }

    private var library: some View {
        Form {
            if let project = model.project, !project.colorworkCharts.isEmpty {
                Section {
                    ForEach(project.colorworkCharts) { chart in
                        Button {
                            editID = chart.id
                        } label: {
                            HStack(spacing: 12) {
                                ChartGrid(chart: chart, axes: false).frame(width: 42, height: 42).accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(chart.name).foregroundStyle(Design.ink)
                                    Text(L.f("%@ 针 × %@ 行", String(chart.width), String(chart.height)))
                                        .font(.caption).foregroundStyle(Design.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }.swipeActions {
                            Button(L.t("删除"), role: .destructive) { model.removeColorwork(chart) }
                        }.accessibilityIdentifier("openChart-" + chart.id.uuidString)
                    }
                }
            }
            Section {
                ChartDimensions(stitches: $stitches, rows: $rows)
                Button(L.t("新建配色图解"), systemImage: "plus") {
                    if let chart = ColorworkChart(name: nextName, width: Int(stitches) ?? 0, height: Int(rows) ?? 0) {
                        _ = add(chart)
                    } else {
                        message = L.t("针数和行数须为 1–60 的整数。")
                    }
                }.accessibilityIdentifier("createColorwork")
                Button(L.t("图片转色格"), systemImage: "photo") {
                    if model.requirePro() { pickingPhoto = true }
                }.accessibilityIdentifier("importColorworkPhoto")
                Menu {
                    Button(L.t("导入口令"), systemImage: "doc.on.clipboard") { pasteSheet = true }
                    Button(L.t("导入图解文件"), systemImage: "folder") { filePicker = true }
                } label: {
                    Label(L.t("导入配色图解"), systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("importColorwork")
                if let message { Text(message).font(.footnote).foregroundStyle(Design.accent) }
            } header: {
                EmptyView()
            } footer: {
                if !model.hasPro { Text(L.t("第一张图解免费，多张图解和图片转色格可用 Pro 解锁。")) }
            }
        }.scrollContentBackground(.hidden).background(Design.background).scrollDismissesKeyboard(.interactively)
    }

    private var nextName: String {
        let charts = model.project?.colorworkCharts ?? []
        let names = Set(charts.map(\.name))
        let number = (1...(charts.count + 1)).first { !names.contains(L.f("配色图解 %@", String($0))) }
        return L.f("配色图解 %@", String(number ?? 1))
    }

    private func add(_ chart: ColorworkChart, fromPhoto: Bool = false) -> Bool {
        guard model.addColorwork(chart, fromPhoto: fromPhoto) else { return false }
        editID = chart.id
        message = nil
        return true
    }
}

struct ChartDimensions: View {
    @Binding var stitches: String
    @Binding var rows: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("针数")).font(.caption).foregroundStyle(Design.secondary)
                TextField(L.t("针数"), text: $stitches).keyboardType(.numberPad).accessibilityIdentifier("colorworkStitches")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("行数")).font(.caption).foregroundStyle(Design.secondary)
                TextField(L.t("行数"), text: $rows).keyboardType(.numberPad).accessibilityIdentifier("colorworkRows")
            }
        }.monospacedDigit()
    }
}

private struct ColorworkPasteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var invalid = false
    var apply: (ColorworkChart) -> Bool

    var body: some View {
        NavigationStack {
            Form {
                PasteButton(payloadType: String.self) { input in importCode(input.joined(separator: "\n")) }
                TextField(L.t("图解口令"), text: $code, axis: .vertical).lineLimit(3...5)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(L.t("导入口令")) { importCode(code) }.disabled(code.isEmpty)
                if invalid { Text(L.t("没有识别出口令，请粘贴完整内容。")).foregroundStyle(Design.accent) }
            }.navigationTitle(L.t("导入口令")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() } } }
        }
    }

    private func importCode(_ input: String) {
        guard let chart = ColorworkExchange.readCode(input) else { invalid = true; return }
        invalid = false
        if apply(chart) { dismiss() }
    }
}

private struct ColorworkPhotoSetup: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stitches: String
    @State private var rows: String
    @State private var colorCount = 4
    @State private var imageData: Data?
    @State private var chart: ColorworkChart?
    @State private var previewed: Parameters?
    @State private var failed = false
    let photo: PhotosPickerItem
    let apply: (ColorworkChart) -> Bool

    init(photo: PhotosPickerItem, stitches: String, rows: String, apply: @escaping (ColorworkChart) -> Bool) {
        self.photo = photo
        self.apply = apply
        _stitches = State(initialValue: stitches)
        _rows = State(initialValue: rows)
    }

    private struct Parameters: Hashable { var stitches: String; var rows: String; var colors: Int }
    private var parameters: Parameters { Parameters(stitches: stitches, rows: rows, colors: colorCount) }
    private var valid: Bool { ColorworkChart.validSize(Int(stitches) ?? 0, Int(rows) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                ChartDimensions(stitches: $stitches, rows: $rows)
                Stepper(L.f("%@ 种颜色", String(colorCount)), value: $colorCount, in: 2...8)
                if let chart, previewed == parameters {
                    ChartGrid(chart: chart).frame(height: 225)
                    Button(L.t("使用色格")) { if apply(chart) { dismiss() } }.accessibilityIdentifier("applyPhotoColorwork")
                } else if !valid {
                    Text(L.t("针数和行数须为 1–60 的整数。")).foregroundStyle(Design.accent)
                } else if failed {
                    Text(L.t("无法把这张图片转成色格。")).foregroundStyle(Design.accent)
                } else {
                    ProgressView()
                }
            }.navigationTitle(L.t("图片转色格")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() } } }
        }
        .task(id: parameters) { await preview(parameters) }
    }

    private func preview(_ settings: Parameters) async {
        chart = nil
        previewed = nil
        failed = false
        guard let width = Int(settings.stitches), let height = Int(settings.rows), ColorworkChart.validSize(width, height) else { return }
        do {
            let data: Data?
            if let imageData { data = imageData }
            else { data = try await photo.loadTransferable(type: Data.self) }
            guard !Task.isCancelled else { return }
            guard let data else { failed = true; return }
            imageData = data
            let name = L.t("参考图片图解")
            let result = await Task.detached(priority: .userInitiated) {
                ColorworkImage.chart(from: data, name: name, width: width, height: height, colorCount: settings.colors)
            }.value
            guard !Task.isCancelled, settings == parameters else { return }
            chart = result
            previewed = settings
            failed = result == nil
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
