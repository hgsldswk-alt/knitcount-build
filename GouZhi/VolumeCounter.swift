import UIKit
import MediaPlayer
import AVFoundation
import SwiftUI

struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

@MainActor final class VolumeCounter {
    private var observation: NSKeyValueObservation?
    private var resetting = false
    private var last = Date.distantPast
    private var baseline: Float = 0.5
    func start(_ action: @escaping () -> Void) {
        guard observation == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do { try session.setCategory(.ambient, options: [.mixWithOthers]); try session.setActive(true) } catch { return }
        baseline = min(0.9, max(0.1, session.outputVolume))
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                guard let self, !self.resetting, let value = change.newValue,
                      abs(value - self.baseline) > 0.001, Date().timeIntervalSince(self.last) > 0.15 else { return }
                self.last = Date(); action(); self.resetting = true
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
                func slider(_ view: UIView) -> UISlider? {
                    if let volume = view as? MPVolumeView { return volume.subviews.compactMap { $0 as? UISlider }.first }
                    for child in view.subviews { if let found = slider(child) { return found } }; return nil
                }
                for window in windows { if let control = slider(window) { control.setValue(self.baseline, animated: false); control.sendActions(for: .touchUpInside); break } }
                try? await Task.sleep(nanoseconds: 150_000_000); self.resetting = false
            }
        }
    }
    func stop() {
        observation?.invalidate(); observation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
