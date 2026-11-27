import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

struct ImportedPattern {
    var pages: [PatternPage] = []
    var targets: [Int: Int] = [:]
    var name: String = ""
    var grid: CGSize?
}
enum PatternImporter {
    static func image(_ image: UIImage, store: Store) throws -> ImportedPattern {
        let factor = min(1, 4096 / max(1, max(image.size.width, image.size.height)))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.jpegData(compressionQuality: 0.9) else { throw StoreError.unavailable }
        let file = try store.writeFile(data, extension: "jpg")
        let analysis = PatternAnalyzer.analyze(normalized)
        let page = PatternPage(filename: file, aspectRatio: Double(image.size.width / max(1, image.size.height)), ocrLines: analysis.boxes, rowMap: analysis.rowMap)
        return ImportedPattern(pages: [page], targets: analysis.targets, name: analysis.text, grid: analysis.grid)
    }
    static func file(_ url: URL, store: Store, renderWidth: CGFloat) throws -> ImportedPattern {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw StoreError.unavailable }
            let source = try store.writeFile(data, extension: "pdf")
            var result = ImportedPattern()
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let ratio = bounds.width / max(1, bounds.height)
                let image = page.thumbnail(of: CGSize(width: renderWidth, height: renderWidth / max(0.01, ratio)), for: .mediaBox)
                guard let jpeg = image.jpegData(compressionQuality: 0.9) else { continue }
                let rendered = try store.writeFile(jpeg, extension: "jpg")
                let analysis = PatternAnalyzer.analyze(image, pdfPage: page)
                result.pages.append(PatternPage(filename: rendered, kind: .pdfPage, pdfFilename: source, pdfPage: index, aspectRatio: Double(ratio), ocrLines: analysis.boxes, rowMap: analysis.rowMap))
                result.targets.merge(analysis.targets) { _, new in new }
                if result.name.isEmpty { result.name = analysis.text }; if result.grid == nil { result.grid = analysis.grid }
            }
            return result
        }
        guard let image = UIImage(data: data) else { throw StoreError.unavailable }
        return try self.image(image, store: store)
    }
}

@MainActor extension AppModel {
    func applyImport(_ imported: ImportedPattern, new: Bool) {
        guard !imported.pages.isEmpty else { notify(L.t("无法读取图解，请换一个文件重试。")); return }
        func fill(_ part: inout Part) {
            part.patternPages.append(contentsOf: imported.pages)
            part.tracker.dim = data.preferences.dimDefault
            if hasPro {
                part.roundTargets.merge(imported.targets) { _, new in new }
                if !part.roundTargets.isEmpty, !part.counters.contains(where: { $0.kind == .stitch }) {
                    let c = Counter(name: L.t("本圈针数"), kind: .stitch, value: 0, min: 0, linkTo: part.counters.first(where: { $0.kind == .row })?.id)
                    part.counters.append(c); part.mainCounterID = c.id
                }
                if let grid = imported.grid { part.tracker.cellWidth = grid.width; part.tracker.cellHeight = grid.height }
            }
            Counting.moveTracker(&part, from: part.row)
        }
        if new || project == nil {
            var p = Project(name: PatternParse.name(from: imported.name)); fill(&p.parts[0]); add(p)
        } else { editPart(fill); sheet = nil }
    }
    func importText(_ text: String, new: Bool) {
        let lines = PatternParse.lines(text)
        guard !lines.isEmpty else { return }
        func fill(_ part: inout Part) {
            part.textPattern = lines
            if hasPro { part.roundTargets.merge(PatternParse.targets(lines)) { _, new in new } }
            if !part.roundTargets.isEmpty, !part.counters.contains(where: { $0.kind == .stitch }) {
                let c = Counter(name: L.t("本圈针数"), kind: .stitch, value: 0, min: 0, linkTo: part.counters.first(where: { $0.kind == .row })?.id)
                part.counters.append(c); part.mainCounterID = c.id
            }
        }
        if new || project == nil { var p = Project(name: PatternParse.name(from: text)); fill(&p.parts[0]); add(p) }
        else { editPart(fill); sheet = nil }
    }
    func openExternal(_ url: URL) {
        if url.pathExtension.lowercased() == ColorworkExchange.fileExtension {
            do {
                if let chart = try ColorworkFile.read(url) {
                    if addColorwork(chart) { sheet = .colorwork(chart.id) }
                } else { notify(L.t("无法读取配色图解。")) }
            } catch { notify(L.t("无法读取配色图解。")) }
            return
        }
        guard let store else { return }
        let width = UIScreen.main.bounds.width * 2
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) { try PatternImporter.file(url, store: store, renderWidth: width) }.value
                applyImport(imported, new: true)
            } catch { notify(L.t("无法读取图解，请换一个文件重试。")) }
        }
    }
}

struct ImportFlow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotosPickerItem] = []
    @State private var files = false
    @State private var showingPhotos = false
    @State private var camera = false
    @State private var text = ""
    @State private var video = ""
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photos, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images) {
                        Label(L.t("相册"), systemImage: "photo.on.rectangle")
                    }.accessibilityIdentifier("importPhotos")
                    Button { files = true } label: { Label(L.t("文件 / PDF"), systemImage: "doc") }.accessibilityIdentifier("importFile")
                    Button { requestCamera() } label: { Label(L.t("拍照"), systemImage: "camera") }.accessibilityIdentifier("importCamera")
                } footer: { Text(L.t("拿入自己的图片、PDF 或文字图解，直接开始跟织。")) }
                Section(L.t("文字图解")) {
                    PasteButton(payloadType: String.self) { values in text = values.joined(separator: "\n") }.accessibilityIdentifier("pastePattern")
                    TextEditor(text: $text).frame(minHeight: 140).accessibilityIdentifier("patternText")
                    Button(L.t("用这段图解开始")) { model.importText(text, new: model.importNew) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("createTextProject")
                }
                Section(L.t("也可以从视频跟织")) {
                    TextField(L.t("粘贴视频链接"), text: $video).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button(L.t("开始跟织")) {
                        guard PatternParse.videoURL(video, seconds: 0) != nil else { model.notify(L.t("请输入有效的视频链接。")); return }
                        if model.importNew || model.project == nil { model.add(Project(name: PatternParse.name(from: ""), videoLink: video)) }
                        else { model.editProject { $0.videoLink = video }; dismiss() }
                    }.disabled(video.isEmpty).accessibilityIdentifier("createVideoProject")
                }
                if busy { ProgressView(L.t("正在整理图解…")) }
            }
            .navigationTitle(L.t("添加图解")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
            .disabled(busy)
            .onAppear {
                if let injected = model.injectedText { text = injected }
                if model.importSource == .photos { showingPhotos = true }
                if model.importSource == .files { files = true }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $photos, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images, photoLibrary: .shared())
            .onChange(of: photos) { _, selection in importPhotos(selection) }
            .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importURLs(urls) }
            }
            .sheet(isPresented: $camera) { CameraPicker { image in if let image { importImage(image) } } }
        }
    }
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.notify(L.t("相机不可用，可以从相册添加照片。")); return }
        Task { if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { model.notify(L.t("相机未开启，可以从相册添加照片。")) } }
    }
    private func importPhotos(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty, let store = model.store else { return }; busy = true
        let new = model.importNew
        Task {
            var result = ImportedPattern()
            do {
                for item in selection {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
                    let next = try await Task.detached { try PatternImporter.image(image, store: store) }.value
                    merge(next, into: &result)
                }
                model.applyImport(result, new: new)
            } catch { model.notify(L.t("导入未完成，请重试。")) }
            busy = false
        }
    }
    private func importURLs(_ urls: [URL]) {
        guard let store = model.store else { return }; busy = true
        let width = UIScreen.main.bounds.width * 2, new = model.importNew
        Task {
            do {
                let result = try await Task.detached { () -> ImportedPattern in
                    var imported = ImportedPattern()
                    for url in urls {
                        let next = try PatternImporter.file(url, store: store, renderWidth: width)
                        imported.pages += next.pages; imported.targets.merge(next.targets) { _, new in new }
                        if imported.name.isEmpty { imported.name = next.name }; if imported.grid == nil { imported.grid = next.grid }
                    }
                    return imported
                }.value
                model.applyImport(result, new: new)
            } catch { model.notify(L.t("导入未完成，请重试。")) }; busy = false
        }
    }
    private func importImage(_ image: UIImage) {
        guard let store = model.store else { return }; busy = true
        Task {
            do { let result = try await Task.detached { try PatternImporter.image(image, store: store) }.value; model.applyImport(result, new: model.importNew) }
            catch { model.notify(L.t("导入未完成，请重试。")) }; busy = false
        }
    }
    private func merge(_ next: ImportedPattern, into result: inout ImportedPattern) {
        result.pages += next.pages; result.targets.merge(next.targets) { _, new in new }
        if result.name.isEmpty { result.name = next.name }; if result.grid == nil { result.grid = next.grid }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var finished: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var finished: (UIImage?) -> Void
        init(_ finished: @escaping (UIImage?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true); finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true); finished(info[.originalImage] as? UIImage)
        }
    }
}
