import SwiftUI
import PencilKit

struct PatternView: View {
    @EnvironmentObject var model: AppModel
    @State private var drawing = false
    @State private var calibrating = false
    @State private var showPages = false
    var body: some View {
        VStack(spacing: 0) {
            if let chart = model.activeColorwork {
                ColorworkFollowView(chart: chart, row: model.part.row).id(chart.id)
            } else {
                usualPattern
            }
        }.background(.white)
    }
    private var usualPattern: some View {
        VStack(spacing: 0) {
            if !model.part.patternPages.isEmpty || model.part.textPattern != nil { tools }
            if let lines = model.part.textPattern, !lines.isEmpty, model.part.patternPages.isEmpty || (!showPages && model.part.tracker.mode != .ring && model.part.tracker.mode != .grid) {
                TextPatternView(lines: lines)
            } else if !model.part.patternPages.isEmpty {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = model.part.patternPages.reduce(CGFloat(0)) { $0 + width / max(0.05, $1.aspectRatio) + 12 }
                    let above = model.part.patternPages.prefix(max(0, model.part.tracker.page)).reduce(CGFloat(0)) { $0 + width / max(0.05, $1.aspectRatio) + 12 }
                    let pageHeight = model.part.patternPages.indices.contains(model.part.tracker.page) ? width / max(0.05, model.part.patternPages[model.part.tracker.page].aspectRatio) : width
                    ZoomScroll(scale: model.part.tracker.zoomScale, offset: CGPoint(x: model.part.tracker.offsetX, y: model.part.tracker.offsetY), contentSize: CGSize(width: width, height: height), focus: above + pageHeight * model.part.tracker.y, focusToken: String(model.part.row) + ":" + String(model.part.tracker.page)) { scale, offset in
                        model.editPart { $0.tracker.zoomScale = scale; $0.tracker.offsetX = offset.x; $0.tracker.offsetY = offset.y }
                    } content: {
                        VStack(spacing: 12) {
                            ForEach(Array(model.part.patternPages.enumerated()), id: \.element.id) { index, page in
                                pageView(page, index: index, width: width)
                            }
                        }.frame(width: width)
                    }.id(model.part.id)
                }
            } else { empty }
        }
    }
    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if model.part.textPattern != nil && !model.part.patternPages.isEmpty {
                    Button { showPages.toggle() } label: { Image(systemName: showPages ? "doc.text" : "photo") }.accessibilityLabel(L.t("文字图解")).accessibilityIdentifier("togglePatternFormat")
                }
                Menu {
                    ForEach(TrackerMode.allCases, id: \.self) { mode in
                        Button(mode.title) {
                            guard mode == .bar || mode == .none || model.requirePro() else { return }
                            model.editPart { $0.tracker.mode = mode }
                        }.accessibilityIdentifier("tracker-" + mode.rawValue)
                    }
                } label: { Label(model.part.tracker.mode.title, systemImage: "line.3.horizontal.decrease") }.accessibilityIdentifier("trackerMode")
                Button { model.editPart { $0.tracker.dim.toggle() } } label: { Image(systemName: model.part.tracker.dim ? "circle.lefthalf.filled" : "circle") }.accessibilityLabel(L.t("暗化其余区域")).accessibilityIdentifier("toggleDim")
                Button { if model.requirePro() { drawing.toggle(); if drawing { showPages = true } } } label: { Image(systemName: drawing ? "highlighter" : "pencil.tip") }.accessibilityLabel(L.t("荧光笔")).disabled(model.part.patternPages.isEmpty).accessibilityIdentifier("toggleHighlighter")
                Button { calibrating.toggle() } label: { Image(systemName: "scope") }.accessibilityLabel(L.t("手动标定")).accessibilityIdentifier("calibrateTracker")
                Button { model.sheet = .symbols } label: { Image(systemName: "text.book.closed") }.accessibilityLabel(L.t("符号速查")).accessibilityIdentifier("patternSymbols")
                if let video = model.project?.videoLink, let url = PatternParse.videoURL(video, seconds: model.part.videoMarks[model.part.row] ?? 0) {
                    Link(destination: url) { Image(systemName: "play.rectangle") }.accessibilityLabel(L.t("视频")).accessibilityIdentifier("openVideo")
                }
            }.font(.system(size: 13)).foregroundStyle(Design.secondary).padding(.horizontal, 14).frame(height: 36)
        }.background(Design.background.opacity(0.92))
    }
    private var empty: some View {
        VStack(spacing: 14) {
            Text(L.t("添加图解")).font(.subheadline).foregroundStyle(Design.secondary)
            HStack(spacing: 20) {
                Button(L.t("相册")) { model.showImport(new: false, source: .photos) }.accessibilityIdentifier("addFromPhotos")
                Button(L.t("文件 / PDF")) { model.showImport(new: false, source: .files) }.accessibilityIdentifier("addFromFiles")
                Button(L.t("粘贴文字")) { model.showImport(new: false, source: .text) }.accessibilityIdentifier("addFromText")
            }.font(.subheadline)
            Button(L.t("也可以从视频跟织：粘贴视频链接")) { model.showImport(new: false, source: .video) }.font(.caption).foregroundStyle(Design.muted).accessibilityIdentifier("addFromVideo")
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.card)
    }
    @ViewBuilder private func pageView(_ page: PatternPage, index: Int, width: CGFloat) -> some View {
        let height = width / max(0.05, page.aspectRatio)
        ZStack(alignment: .topLeading) {
            if let url = try? model.store?.file(page.filename), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().frame(width: width, height: height).accessibilityLabel(L.t("我的图解")).accessibilityIdentifier("patternChart")
            }
            if model.part.tracker.page == index {
                PatternOverlay(tracker: Binding(get: { model.part.tracker }, set: { value in model.editPart { $0.tracker = value } }), row: model.part.row, calibrating: calibrating, onCenter: { point in
                    guard let path = try? model.store?.file(page.filename), let image = UIImage(contentsOfFile: path.path) else { return }
                    Task {
                        let spacing = await Task.detached { PatternAnalyzer.ringSpacing(image, center: point) }.value
                        if let spacing { model.editPart { $0.tracker.ringSpacing = spacing } }
                    }
                }).frame(width: width, height: height).allowsHitTesting(!drawing)
            } else {
                Button(L.t("在此页跟织")) { model.editPart { $0.tracker.page = index; $0.tracker.y = $0.tracker.pageY[index] ?? 0.15 } }
                    .font(.caption).padding(8).background(Design.background, in: Capsule()).padding(8).accessibilityIdentifier("trackPage-" + page.id.uuidString)
            }
            if drawing && model.hasPro, let store = model.store {
                DrawingCanvas(url: store.files.appendingPathComponent(page.id.uuidString + ".drawing"), enabled: true).frame(width: width, height: height)
            } else if let store = model.store {
                DrawingCanvas(url: store.files.appendingPathComponent(page.id.uuidString + ".drawing"), enabled: false).frame(width: width, height: height).allowsHitTesting(false)
            }
        }.frame(width: width, height: height).clipped()
            .overlay(alignment: .bottomTrailing) { Text(L.f("图解 %@ / %@ · 双指放大", String(index + 1), String(model.part.patternPages.count))).font(.caption2).padding(6).background(Design.background, in: Capsule()).padding(8).allowsHitTesting(false) }
    }
}

struct TextPatternView: View {
    @EnvironmentObject var model: AppModel
    var lines: [PatternLine]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.hasPro {
                        Picker(L.t("尺码"), selection: Binding(get: { model.part.sizeIndex ?? 0 }, set: { value in model.editPart { $0.sizeIndex = value } })) {
                            Text("S").tag(0); Text("M").tag(1); Text("L").tag(2); Text("XL").tag(3)
                        }.pickerStyle(.segmented).padding(12).accessibilityIdentifier("sizePicker")
                    }
                    ForEach(lines) { line in
                        let current = line.row == model.part.row
                        Text(styled(line.text)).font(.system(size: 14, weight: current ? .semibold : .regular)).lineSpacing(5)
                            .foregroundStyle(Design.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 9)
                            .opacity((line.row ?? Int.max) < model.part.row ? 0.35 : 1)
                            .background(current ? Design.accent.opacity(0.16) : .clear)
                            .overlay(alignment: .top) { if current { Rectangle().fill(Design.accent).frame(height: 2) } }
                            .overlay(alignment: .bottom) { if current { Rectangle().fill(Design.accent).frame(height: 2) } }
                            .id(line.id).accessibilityIdentifier(current ? "currentPatternLine" : "patternLine-" + line.id.uuidString)
                    }
                }
            }.onAppear { scroll(proxy) }.onChange(of: model.part.row) { _, _ in withAnimation { scroll(proxy) } }.onChange(of: model.part.id) { _, _ in scroll(proxy) }
        }
    }
    private func scroll(_ proxy: ScrollViewProxy) { if let line = lines.first(where: { $0.row == model.part.row }) { proxy.scrollTo(line.id, anchor: .center) } }
    private func styled(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard model.hasPro, let size = model.part.sizeIndex else { return result }
        for range in PatternParse.sizeRanges(in: text, sizeIndex: size) {
            if let lower = AttributedString.Index(range.lowerBound, within: result), let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].foregroundColor = Design.accent
                result[lower..<upper].backgroundColor = Design.accent.opacity(0.15)
                result[lower..<upper].font = .system(size: 14, weight: .bold)
            }
        }
        return result
    }
}

struct PatternOverlay: View {
    @Binding var tracker: Tracker
    var row: Int
    var calibrating: Bool
    var onCenter: (CGPoint) -> Void
    @State private var dragStart: Double?
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                if tracker.mode == .bar {
                    if tracker.dim {
                        Rectangle().fill(.black.opacity(0.3)).frame(height: h * tracker.y).allowsHitTesting(false)
                        Rectangle().fill(.black.opacity(0.3)).frame(height: max(0, h * (1 - tracker.y - tracker.height))).offset(y: h * (tracker.y + tracker.height)).allowsHitTesting(false)
                    }
                    Rectangle().fill(Design.accent.opacity(0.16)).frame(height: h * tracker.height)
                        .overlay(alignment: .top) { Rectangle().fill(Design.accent).frame(height: 2) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Design.accent).frame(height: 2) }
                        .overlay(alignment: .trailing) { Text(L.t("当前")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Design.accent).padding(8) }
                        .offset(y: h * tracker.y)
                        .gesture(DragGesture().onChanged { value in
                            if dragStart == nil { dragStart = tracker.y }
                            tracker.y = min(1 - tracker.height, max(0, (dragStart ?? tracker.y) + value.translation.height / h)); tracker.pageY[tracker.page] = tracker.y
                        }.onEnded { _ in dragStart = nil }).accessibilityIdentifier("highlightBar").accessibilityValue(String(tracker.y))
                    Circle().fill(Design.accent).frame(width: 18, height: 18).position(x: w - 14, y: h * (tracker.y + tracker.height))
                        .gesture(DragGesture(coordinateSpace: .named("patternOverlay")).onChanged { value in tracker.height = min(0.3, max(0.015, value.location.y / h - tracker.y)) })
                    if calibrating {
                        VStack { Text(L.t("每行步长")).font(.caption); Slider(value: $tracker.step, in: 0.005...0.2) }.padding(10).background(Design.card).frame(width: 180).offset(x: 10, y: 10)
                    }
                } else if tracker.mode == .ring {
                    let radius = min(w, h) * tracker.radius
                    if tracker.dim {
                        Path { path in
                            path.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                            path.addEllipse(in: CGRect(x: tracker.centerX * w - radius, y: tracker.centerY * h - radius, width: radius * 2, height: radius * 2))
                        }.fill(.black.opacity(0.25), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                    }
                    Circle().stroke(Design.accent.opacity(0.35), lineWidth: max(6, min(w, h) * tracker.ringSpacing))
                        .overlay(Circle().stroke(Design.accent, lineWidth: 2)).frame(width: radius * 2, height: radius * 2)
                        .position(x: tracker.centerX * w, y: tracker.centerY * h).allowsHitTesting(false)
                    if calibrating {
                        Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                            tracker.centerX = value.location.x / w; tracker.centerY = value.location.y / h
                            onCenter(CGPoint(x: tracker.centerX, y: tracker.centerY))
                        })
                        Circle().fill(Design.accent).frame(width: 22, height: 22).position(x: tracker.centerX * w + radius, y: tracker.centerY * h)
                            .gesture(DragGesture(coordinateSpace: .named("patternOverlay")).onChanged { value in
                                let dx = value.location.x - tracker.centerX * w, dy = value.location.y - tracker.centerY * h
                                tracker.radius = min(0.7, max(0.01, hypot(dx, dy) / min(w, h)))
                                tracker.firstRadius = max(0.005, tracker.radius - Double(max(0, row - 1)) * tracker.ringSpacing)
                            })
                    }
                } else if tracker.mode == .grid {
                    Rectangle().fill(Design.accent.opacity(0.22)).frame(height: tracker.cellHeight * h).offset(y: tracker.y * h).allowsHitTesting(false)
                    Rectangle().fill(Design.accent).frame(height: 2).offset(y: tracker.y * h).allowsHitTesting(false)
                    Rectangle().fill(Design.accent).frame(width: 2).offset(x: (tracker.originX + Double(tracker.gridColumn) * tracker.cellWidth) * w).allowsHitTesting(false)
                    if calibrating {
                        gridHandle(x: tracker.originX * w, y: tracker.originY * h) { point in tracker.originX = min(0.95, max(0, point.x / w)); tracker.originY = min(0.95, max(0, point.y / h)); tracker.y = tracker.originY }
                        gridHandle(x: (tracker.originX + tracker.cellWidth * 2) * w, y: (tracker.originY + tracker.cellHeight * 2) * h) { point in
                            tracker.cellWidth = min(0.3, max(0.005, (point.x / w - tracker.originX) / 2))
                            tracker.cellHeight = min(0.3, max(0.005, (point.y / h - tracker.originY) / 2))
                        }
                    }
                }
            }.coordinateSpace(name: "patternOverlay")
        }
    }
    private func gridHandle(x: CGFloat, y: CGFloat, move: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(Design.accent).frame(width: 24, height: 24).position(x: x, y: y)
            .gesture(DragGesture(coordinateSpace: .named("patternOverlay")).onChanged { move($0.location) })
    }
}

struct ZoomScroll<Content: View>: UIViewRepresentable {
    var scale: Double
    var offset: CGPoint
    var contentSize: CGSize
    var focus: CGFloat
    var focusToken: String
    var changed: (Double, CGPoint) -> Void
    @ViewBuilder var content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(content: content(), changed: changed) }
    func makeUIView(context: Context) -> UIScrollView {
        let view = UIScrollView(); view.minimumZoomScale = 1; view.maximumZoomScale = 5
        view.delegate = context.coordinator; view.backgroundColor = .white; view.bouncesZoom = false
        let host = context.coordinator.host.view!; host.backgroundColor = .clear
        host.frame = CGRect(origin: .zero, size: contentSize); view.addSubview(host); view.contentSize = contentSize
        context.coordinator.size = contentSize; context.coordinator.focusToken = focusToken
        DispatchQueue.main.async {
            view.setZoomScale(CGFloat(min(5, max(1, scale))), animated: false)
            view.setContentOffset(CGPoint(x: offset.x * view.contentSize.width, y: offset.y * view.contentSize.height), animated: false)
            context.coordinator.restored = true
        }
        return view
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.host.rootView = content(); context.coordinator.changed = changed
        if context.coordinator.size != contentSize {
            context.coordinator.size = contentSize
            let zoom = uiView.zoomScale
            uiView.setZoomScale(1, animated: false)
            context.coordinator.host.view.frame = CGRect(origin: .zero, size: contentSize)
            uiView.contentSize = contentSize; uiView.setZoomScale(zoom, animated: false)
        }
        if context.coordinator.restored && context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            let y = min(max(0, uiView.contentSize.height - uiView.bounds.height), max(0, focus * uiView.zoomScale - uiView.bounds.height * 0.35))
            uiView.setContentOffset(CGPoint(x: uiView.contentOffset.x, y: y), animated: true)
        }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        var changed: (Double, CGPoint) -> Void
        var restored = false
        var size = CGSize.zero
        var focusToken = ""
        init(content: Content, changed: @escaping (Double, CGPoint) -> Void) { host = UIHostingController(rootView: content); self.changed = changed }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
        func save(_ view: UIScrollView) {
            guard restored else { return }
            changed(Double(view.zoomScale), CGPoint(x: max(0, view.contentOffset.x) / max(1, view.contentSize.width), y: max(0, view.contentOffset.y) / max(1, view.contentSize.height)))
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { save(scrollView) } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { save(scrollView) }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { save(scrollView) }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { save(scrollView) }
    }
}

struct DrawingCanvas: UIViewRepresentable {
    var url: URL
    var enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView(); canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput; canvas.isScrollEnabled = false; canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.marker, color: UIColor(red: 0.85, green: 0.68, blue: 0.2, alpha: 0.4), width: 18)
        if let data = try? Data(contentsOf: url), let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
        canvas.isUserInteractionEnabled = enabled; return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) { uiView.isUserInteractionEnabled = enabled }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let url: URL
        init(url: URL) { self.url = url }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { try? canvasView.drawing.dataRepresentation().write(to: url, options: .atomic) }
    }
}
