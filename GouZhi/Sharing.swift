import SwiftUI
import CoreImage.CIFilterBuiltins
import PhotosUI
import AVFoundation

struct SystemShare: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareCard: View {
    var project: Project
    var photo: UIImage?
    var milestone: String?
    private var qr: UIImage? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String, !id.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(("https://apps.apple.com/app/id" + id).utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("HANDMADE JOURNAL").font(.system(size: 9, weight: .semibold, design: .serif)).tracking(2); Spacer(); Text(project.createdAt.formatted(.dateTime.year().month())).font(.system(size: 9)) }.foregroundStyle(Design.secondary).padding(.bottom, 8)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: 324, height: milestone == nil ? 176 : 158).clipped()
            } else {
                VStack(spacing: 10) { Image(systemName: "square.stack.3d.up").font(.system(size: 60, weight: .ultraLight)); Text(L.t("一针一线，慢慢成形")).font(.system(size: 17, design: .serif)) }.foregroundStyle(Design.accent).frame(width: 324, height: milestone == nil ? 176 : 158).background(Design.line.opacity(0.5))
            }
            Rectangle().fill(Design.accent).frame(width: 32, height: 3).padding(.top, 10).padding(.bottom, 6)
            Text(milestone.map(Milestones.title) ?? project.name).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Design.ink).lineLimit(1).minimumScaleFactor(0.7)
            if milestone != nil { Text(project.name).font(.caption).foregroundStyle(Design.secondary).padding(.top, 4) }
            HStack(alignment: .top, spacing: 18) {
                metric(L.t("用时"), L.duration(project.totalSeconds))
                metric(L.t("总行数"), String(project.totalRows))
                metric(L.t("针号"), project.hookSize.isEmpty ? "—" : project.hookSize)
            }.padding(.top, 8)
            if let yarn = project.yarns.first { Text([yarn.brand, yarn.color, yarn.amount].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(Design.secondary).padding(.top, 5).lineLimit(1) }
            Spacer(minLength: 5)
            HStack(alignment: .bottom) {
                Text(L.t("钩织计数")).font(.system(size: 11, weight: .medium)).foregroundStyle(Design.accent)
                Spacer()
                if let qr { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 32, height: 32) }
            }.frame(height: 32, alignment: .bottom)
        }.padding(18).frame(width: 360, height: 480).background(Design.card)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 9)).foregroundStyle(Design.muted); Text(value).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(Design.ink) }
    }
}

struct ShareCardSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var milestone: String? = nil
    @State private var image: UIImage?
    @State private var sharing = false
    @State private var camera = false
    @State private var photo: PhotosPickerItem?
    @State private var items: [Any] = []
    private let caption = "#钩针 #钩织 #毛线编织 #钩织计数"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: Design.ink.opacity(0.08), radius: 14).accessibilityLabel(milestone.map(Milestones.title) ?? L.t("作品完成了")).accessibilityIdentifier("sharePreview") }
                    if model.project?.photos.isEmpty != false {
                        HStack {
                            Button(L.t("拍成品照")) { requestCamera() }.accessibilityIdentifier("takeFinishedPhoto")
                            PhotosPicker(L.t("从相册添加"), selection: $photo, matching: .images).accessibilityIdentifier("finishedPhotoPicker")
                        }.font(.subheadline)
                    }
                    Button {
                        guard let image else { return }; items = [image, caption]; sharing = true
                    } label: { Label(L.t("分享"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(16).background(Design.accent, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white) }.accessibilityIdentifier("shareImage")
                    Button(L.t("复制文案")) { UIPasteboard.general.string = caption; model.notify(L.t("文案已复制")) }.accessibilityIdentifier("copyCaption")
                }.padding(24)
            }.background(Design.background).navigationTitle(milestone.map(Milestones.title) ?? L.t("作品完成了")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
                .onAppear { render() }
                .onDisappear {
                    model.cardClosed = true
                    if model.project?.status == .completed, milestone == nil { ReviewGate.completedShareClosed = true }
                }
                .onChange(of: model.project?.photos) { _, _ in render() }
                .onChange(of: photo) { _, selected in Task { if let data = try? await selected?.loadTransferable(type: Data.self), let image = UIImage(data: data) { savePhoto(image) } } }
                .sheet(isPresented: $sharing) { SystemShare(items: items) }
                .sheet(isPresented: $camera) { CameraPicker { image in if let image { savePhoto(image) } } }
        }
    }
    private func render() {
        guard let project = model.project else { return }
        let name = project.coverFilename ?? project.photos.last ?? project.part.patternPages.first?.filename
        let photo = name.flatMap { try? model.store?.file($0) }.flatMap { UIImage(contentsOfFile: $0.path) }
        let renderer = ImageRenderer(content: ShareCard(project: project, photo: photo, milestone: milestone))
        renderer.scale = 3; image = renderer.uiImage
        if image == nil { model.notify(L.t("分享图生成失败，请重试。")) }
    }
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.notify(L.t("相机不可用，可以从相册添加照片。")); return }
        Task { if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { model.notify(L.t("相机未开启，可以从相册添加照片。")) } }
    }
    private func savePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9), let name = try? model.store?.writeFile(data, extension: "jpg") else { model.notify(L.t("保存失败，请稍后重试。")); return }
        model.editProject { $0.photos.append(name); $0.coverFilename = name }; render()
    }
}
