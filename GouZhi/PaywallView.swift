import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if Launch.isFree { Color.clear.onAppear { dismiss() } }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(L.t("你的图解，你的进度")).font(.largeTitle.bold())
                            Text(L.t("一次买断，不订阅")).font(.title3).foregroundStyle(Design.accent)
                            Text(L.t("无限作品与计数器、联动、行提醒、圆环和网格跟踪、荧光笔、锁屏计数与计时统计。"))
                            Text(L.f("完整体验还剩 %@ 天", String(model.data.entitlement.remainingDays(at: Date())))).foregroundStyle(Design.secondary).accessibilityIdentifier("trialDaysRemaining")
                            Text(L.t("已有作品和图解始终可查看、计数与导出。")).font(.subheadline).foregroundStyle(Design.secondary)
                            ForEach(model.products, id: \.id) { product in
                                Button { Task { await model.purchase(product.id) } } label: {
                                    HStack { Text(product.id == model.proID ? L.t("买断解锁") : L.t("领取 30 天体验凭证")); Spacer(); Text(product.displayPrice) }.padding().background(Design.accent, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
                                }.disabled(model.purchasing).accessibilityIdentifier("purchase-" + product.id)
                            }
                            if model.products.isEmpty { Button(L.t("重新加载商品")) { Task { await model.loadProducts() } }.accessibilityIdentifier("reloadProducts") }
                            Button(L.t("恢复购买")) { Task { await model.restore() } }.accessibilityIdentifier("restorePurchases")
                            if model.purchasing { ProgressView() }
                        }.padding(24)
                    }.background(Design.background)
                }
            }.navigationTitle(L.t("买断解锁")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("关闭")) { dismiss() }.accessibilityIdentifier("closeSheet") } }
                .task { await model.loadProducts() }
        }
    }
}
