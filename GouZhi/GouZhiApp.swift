import SwiftUI
import UIKit
import StoreKit

@main struct GouZhiApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(Design.accent).preferredColorScheme(.light)
                .onOpenURL { model.openExternal($0) }
                .task { model.updatePasteHint(); await model.startStore() }
                .onChange(of: phase) { _, value in model.foreground(value == .active) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.requestReview) private var requestReview
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var reviewHome: Bool {
        model.active && model.knitting && !model.isolated && model.sheet == nil && model.toast == nil
            && model.banner == nil && !model.purchasing
    }

    var body: some View {
        KnitView()
            .overlay(alignment: .top) {
                if let banner = model.banner { Text(banner).font(.subheadline).padding().frame(maxWidth: .infinity).background(Design.card, in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.08), radius: 10).padding(.horizontal).allowsHitTesting(false).accessibilityIdentifier("reminderBanner") }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { UndoToast() }
            .onReceive(clock) { _ in model.tick() }
            .reviewAfterCoreAction(when: reviewHome, alreadyRequested: model.data.reviewedVersion == ReviewGate.version) {
                requestReview()
                model.mutate { $0.reviewedVersion = ReviewGate.version }
            }
            .task(id: reviewHome && ReviewGate.completedShareClosed) {
                guard reviewHome, ReviewGate.completedShareClosed else { return }
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
                guard !Task.isCancelled, reviewHome else { return }
                if CoreReview.shared.attempt(ifEligible: { ReviewGate.shouldAsk(model) }, { requestReview() }) {
                    model.mutate { $0.reviewedVersion = ReviewGate.version }
                }
            }
            .sheet(item: $model.sheet, onDismiss: {
                model.knitting = true
                if model.cardClosed {
                    model.cardClosed = false
                    Task { @MainActor in try? await Task.sleep(nanoseconds: 500_000_000); model.presentNextMilestone() }
                }
            }) { route in
                Group {
                    switch route {
                    case .projects: ProjectsView()
                    case .detail: ProjectDetailView()
                    case .importPattern: ImportFlow()
                    case .symbols: SymbolsView()
                    case .share: ShareCardSheet()
                    case .history: HistoryView()
                    case .paywall: PaywallView()
                    case .yarnEstimate: YarnEstimateSheet()
                    case .gauge: GaugeSheet()
                    case .colorwork(let id): ColorworkSheet(initialChart: id)
                    case .milestone(let key): ShareCardSheet(milestone: key)
                    case .counter(let id): CounterEditor(counterID: id)
                    }
                }
                .environmentObject(model).tint(Design.accent)
                .safeAreaInset(edge: .bottom) { UndoToast() }
                .overlay(alignment: .top) { if let text = model.banner { Text(text).font(.subheadline).padding().background(Design.card, in: RoundedRectangle(cornerRadius: 16)).padding().allowsHitTesting(false) } }
                .onAppear { model.knitting = false; model.flushTime() }
            }
    }
}
