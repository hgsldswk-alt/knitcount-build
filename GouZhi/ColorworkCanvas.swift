import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension ChartSwatch {
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

struct ChartViewport {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    func grid(in size: CGSize, chart: ColorworkChart) -> CGRect {
        let ratio = CGFloat(chart.cellAspect) * CGFloat(chart.width) / CGFloat(chart.height)
        let height = max(0, min(size.height - 24, (size.width - 48) / ratio)) * scale
        let width = height * ratio
        return CGRect(x: (size.width - width) / 2 + offset.width, y: (size.height - height) / 2 + offset.height,
                      width: width, height: height)
    }

    func cell(at point: CGPoint, size: CGSize, chart: ColorworkChart, clamped: Bool) -> ChartCell? {
        let rect = grid(in: size, chart: chart)
        guard rect.width > 0, rect.height > 0, clamped || rect.contains(point) else { return nil }
        let x = Int(floor((point.x - rect.minX) * CGFloat(chart.width) / rect.width))
        let y = Int(floor((point.y - rect.minY) * CGFloat(chart.height) / rect.height))
        return ChartCell(x: max(0, min(chart.width - 1, x)), y: max(0, min(chart.height - 1, y)))
    }

    mutating func zoom(by factor: CGFloat, at point: CGPoint, size: CGSize, chart: ColorworkChart) {
        let next = min(20, max(1, scale * factor))
        let change = next / scale - 1
        offset.width += (size.width / 2 + offset.width - point.x) * change
        offset.height += (size.height / 2 + offset.height - point.y) * change
        scale = next
        constrain(in: size, chart: chart)
    }

    mutating func pan(_ translation: CGPoint, size: CGSize, chart: ColorworkChart) {
        offset.width += translation.x
        offset.height += translation.y
        constrain(in: size, chart: chart)
    }

    private mutating func constrain(in size: CGSize, chart: ColorworkChart) {
        let fitted = grid(in: size, chart: chart)
        let x = max(0, (fitted.width - size.width + 48) / 2)
        let y = max(0, (fitted.height - size.height + 24) / 2)
        offset.width = max(-x, min(x, offset.width))
        offset.height = max(-y, min(y, offset.height))
    }
}

struct ChartGrid: View {
    var chart: ColorworkChart
    var viewport = ChartViewport()
    var row: Int?
    var selection: ChartArea?
    var destination: ChartArea?
    var axes = true

    var body: some View {
        Canvas { context, size in
            let rect = axes ? viewport.grid(in: size, chart: chart) : fittedGrid(in: size)
            guard rect.width > 0, rect.height > 0 else { return }
            let w = rect.width / CGFloat(chart.width), h = rect.height / CGFloat(chart.height)
            let active = row.flatMap(chart.gridRow(for:))
            let palette = chart.palette.map(\.color)
            var cells = [Path](repeating: Path(), count: palette.count + 1)
            for y in 0..<chart.height {
                for x in 0..<chart.width {
                    cells[Int(chart.slot(x: x, y: y))].addRect(CGRect(x: rect.minX + CGFloat(x) * w,
                                                                      y: rect.minY + CGFloat(y) * h, width: w, height: h))
                }
            }
            context.fill(cells[0], with: .color(.white))
            for i in palette.indices { context.fill(cells[i + 1], with: .color(palette[i])) }
            if let active {
                let top = rect.minY + CGFloat(active) * h
                context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: CGFloat(active) * h)),
                             with: .color(Design.card.opacity(0.68)))
                context.fill(Path(CGRect(x: rect.minX, y: top + h, width: rect.width, height: rect.maxY - top - h)),
                             with: .color(Design.card.opacity(0.68)))
            }
            drawLines(context, rect: rect, w: w, h: h)
            if let active {
                let outline = CGRect(x: rect.minX - 1, y: rect.minY + CGFloat(active) * h, width: rect.width + 2, height: h)
                context.stroke(Path(outline), with: .color(Design.accent), lineWidth: 2)
            }
            if axes { drawAxes(context, rect: rect, w: w, h: h, active: active) }
            if let selection { drawArea(selection, context, rect: rect, w: w, h: h, color: Design.accent) }
            if let destination {
                if chart.fits(destination), let selection, let content = chart.sample(selection) {
                    for (index, slot) in content.enumerated() {
                        let x = destination.origin.x + index % destination.width
                        let y = destination.origin.y + index / destination.width
                        let cell = CGRect(x: rect.minX + CGFloat(x) * w, y: rect.minY + CGFloat(y) * h, width: w, height: h)
                        context.fill(Path(cell), with: .color((slot == 0 ? .white : palette[Int(slot) - 1]).opacity(0.8)))
                    }
                }
                drawArea(destination, context, rect: rect, w: w, h: h, color: chart.fits(destination) ? .teal : .red)
            }
        }.clipped()
    }

    private func fittedGrid(in size: CGSize) -> CGRect {
        let ratio = CGFloat(chart.cellAspect) * CGFloat(chart.width) / CGFloat(chart.height)
        let height = min(size.height, size.width / ratio), width = height * ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func drawLines(_ context: GraphicsContext, rect: CGRect, w: CGFloat, h: CGFloat) {
        let lines = Path { path in
            for x in 0...chart.width {
                let offset = rect.minX + CGFloat(x) * w
                path.move(to: CGPoint(x: offset, y: rect.minY))
                path.addLine(to: CGPoint(x: offset, y: rect.maxY))
            }
            for y in 0...chart.height {
                let offset = rect.minY + CGFloat(y) * h
                path.move(to: CGPoint(x: rect.minX, y: offset))
                path.addLine(to: CGPoint(x: rect.maxX, y: offset))
            }
        }
        context.stroke(lines, with: .color(Design.ink.opacity(0.2)), lineWidth: 0.5)
    }

    private func drawAxes(_ context: GraphicsContext, rect: CGRect, w: CGFloat, h: CGFloat, active: Int?) {
        let rowStep = max(1, Int(ceil(22 / max(1, h))))
        let columnStep = max(1, Int(ceil(26 / max(1, w))))
        for y in 0..<chart.height {
            let number = chart.height - y
            guard y == active || number == 1 || number == chart.height || number.isMultiple(of: rowStep) else { continue }
            let right = row == nil || chart.reading.startsAtRight(row: number, firstAtRight: chart.firstAtRight)
            context.draw(Text(String(number)).font(.system(size: 9, weight: y == active ? .bold : .regular, design: .monospaced))
                .foregroundColor(y == active ? Design.accent : Design.secondary),
                         at: CGPoint(x: right ? rect.maxX + 12 : rect.minX - 12, y: rect.minY + (CGFloat(y) + 0.5) * h))
        }
        for x in 0..<chart.width {
            let number = chart.firstAtRight ? chart.width - x : x + 1
            guard number == 1 || number == chart.width || number.isMultiple(of: columnStep) else { continue }
            context.draw(Text(String(number)).font(.system(size: 9, design: .monospaced)).foregroundColor(Design.secondary),
                         at: CGPoint(x: rect.minX + (CGFloat(x) + 0.5) * w, y: rect.maxY + 9))
        }
    }

    private func drawArea(_ area: ChartArea, _ context: GraphicsContext, rect: CGRect, w: CGFloat, h: CGFloat, color: Color) {
        let bounds = CGRect(x: rect.minX + CGFloat(area.origin.x) * w, y: rect.minY + CGFloat(area.origin.y) * h,
                            width: CGFloat(area.width) * w, height: CGFloat(area.height) * h)
        context.fill(Path(bounds), with: .color(color.opacity(0.12)))
        context.stroke(Path(bounds), with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
    }
}

enum ChartTouchPhase: Equatable { case began, moved, ended, cancelled }

struct ChartTouchInput: UIViewRepresentable {
    var touch: (ChartTouchPhase, CGPoint) -> Void
    var zoom: (CGFloat, CGPoint) -> Void
    var pan: (CGPoint) -> Void

    func makeUIView(context: Context) -> ChartTouchSurface { ChartTouchSurface(frame: .zero) }
    func updateUIView(_ view: ChartTouchSurface, context: Context) {
        view.stroke.touch = touch
        view.zoom = zoom
        view.pan = pan
    }
}

final class ChartTouchSurface: UIView, UIGestureRecognizerDelegate {
    let stroke = ChartStrokeRecognizer(target: nil, action: nil)
    var zoom: ((CGFloat, CGPoint) -> Void)?
    var pan: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        for gesture in [stroke, pinch, pan] as [UIGestureRecognizer] {
            gesture.delegate = self
            addGestureRecognizer(gesture)
        }
    }

    required init?(coder: NSCoder) { return nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other.view === self
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        zoom?(gesture.scale, gesture.location(in: self))
        gesture.scale = 1
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        pan?(gesture.translation(in: self))
        gesture.setTranslation(.zero, in: self)
    }
}

final class ChartStrokeRecognizer: UIGestureRecognizer {
    var touch: ((ChartTouchPhase, CGPoint) -> Void)?
    private var finger: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard finger == nil, touches.count == 1, let first = touches.first else {
            let wasDrawing = finger != nil
            if wasDrawing { touch?(.cancelled, .zero); finger = nil }
            state = wasDrawing ? .cancelled : .failed
            return
        }
        finger = first
        state = .began
        touch?(.began, first.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        state = .changed
        touch?(.moved, finger.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let finger, touches.contains(finger) else { return }
        touch?(.ended, finger.location(in: view))
        self.finger = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touch?(.cancelled, .zero)
        finger = nil
        state = .cancelled
    }

    override func reset() {
        if finger != nil { touch?(.cancelled, .zero) }
        finger = nil
        super.reset()
    }
}
