import SwiftUI
import UIKit

extension Notification.Name {
    static let tstzmOpenPage = Notification.Name("tstzm.openPage")
}

// MARK: - 屏幕方向：平时锁竖屏，全屏 K 线打开时放开横竖
enum GMOrient {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ m: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientationMask? = nil) {
        mask = m
        let target: UIInterfaceOrientationMask = rotateTo ?? m
        for sc in UIApplication.shared.connectedScenes {
            guard let ws = sc as? UIWindowScene else { continue }
            ws.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            ws.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
        }
    }
}

final class TSTZAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        GMOrient.mask
    }
}

// MARK: - 价格 / 市值 切换键（和 K 线共用 kMcap）
struct GMModeSwitch: View {
    @AppStorage("kMcap", store: Cfg.defaults) private var mcap = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { b in
                Button { mcap = b } label: {
                    Text(b ? "市值" : "价格")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(mcap == b ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                        .foregroundStyle(mcap == b ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

// MARK: - 分析功能入口（分析数据都在各自的新页面里）
struct GMFuncGrid: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var store = FavStore.shared
    let onOpen: (Int) -> Void

    private struct Cell: Identifiable {
        let id: Int
        let title: String
        let icon: String
        let color: Color
        let sub: String
    }

    private var cells: [Cell] {
        let tx = vm.main?.txns?["h24"]
        let trade: String = "买 " + String(tx?.buys ?? 0) + " · 卖 " + String(tx?.sells ?? 0)
        var hold: String = "持有人榜"
        if let w = vm.conc?.wallets10 { hold = "Top10 " + String(format: "%.1f%%", Double(w)) }
        return [
            Cell(id: 0, title: "综合研判", icon: "checkmark.shield.fill", color: Color.blue, sub: "规则 + AI"),
            Cell(id: 1, title: "成交池子", icon: "arrow.left.arrow.right", color: Color.green, sub: trade),
            Cell(id: 2, title: "持有筹码", icon: "person.3.fill", color: Color.orange, sub: hold),
            Cell(id: 3, title: "合约安全", icon: "lock.shield.fill", color: Color.red, sub: "蜜罐 · 税 · 权限"),
            Cell(id: 4, title: "叙事社交", icon: "text.bubble.fill", color: Color.purple, sub: "叙事 · 热度"),
            Cell(id: 5, title: "庄家情报", icon: "eye.fill", color: Color.teal, sub: "庄家 · 聪明钱"),
            Cell(id: 6, title: "更多工具", icon: "square.grid.2x2.fill", color: Color.gray, sub: "工具箱"),
            Cell(id: 99, title: "监控", icon: "bell.badge.fill", color: Color.yellow, sub: "收藏 " + String(store.items.count)),
        ]
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("分析功能").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    ForEach(cells) { c in
                        Button { onOpen(c.id) } label: {
                            VStack(spacing: 5) {
                                Image(systemName: c.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(c.color)
                                    .frame(width: 46, height: 46)
                                    .background(c.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(c.title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8)
                                Text(c.sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 最新成交（代币页只放精简版，完整成交分析在「成交池子」页）
struct GMTradesMini: View {
    @ObservedObject var vm: UTokenVM
    let onMore: () -> Void

    var body: some View {
        let rows = Array(vm.trades.prefix(10))
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最新成交").font(.headline)
                    Spacer()
                    Button("全部 ›", action: onMore).font(.caption.weight(.semibold))
                }
                if rows.isEmpty {
                    Text(vm.tradesNote ?? "成交读取中…").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { t in
                    HStack(spacing: 8) {
                        Text(TZ.short(Date(timeIntervalSince1970: t.t))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                        Pill(text: t.buy ? "买" : "卖", color: t.buy ? Color.green : Color.red)
                        Text(GMPx.fiat(t.usd)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(t.buy ? Color.green : Color.red)
                        Spacer()
                        Text(Addr.short(t.who)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - K 线下方的「选中这根 K 线」条：点进去看这根 K 线的成交、钱包、AI（不再塞在代币页里）
struct GMKSelBar: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject var cvm: KLineVM

    private var title: String {
        if let t = cvm.selT, let c = cvm.candles.first(where: { $0.t == t }) {
            return "已选中 " + TZ.short(c.date) + " 这根 K 线"
        }
        return "K 线分析 · 全量概览"
    }

    private var sub: String {
        cvm.selT == nil ? "长按或点 K 线选中一根，再点这里看成交 / 钱包 / AI 解读" : "点这里看这根的价格、池子变化、成交、钱包拆解与 AI"
    }

    var body: some View {
        NavigationLink {
            ScrollView {
                KLineDetailCard(vm: vm, cvm: cvm).padding(16)
            }
            .background(Color.page)
            .navigationTitle("K 线分析")
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 全屏 K 线：竖屏 / 横屏都能看（右上角 ⟳ 一键横竖切换，也跟随手机方向）
struct GMFullChart: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject var cvm: KLineVM
    var onFail: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("kMain", store: Cfg.defaults) private var mainSet = "MA,SUPER"
    @AppStorage("kSub", store: Cfg.defaults) private var subInd = "MACD"

    private var mainList: [String] { mainSet.split(separator: ",").map { String($0) } }

    private func toggleMain(_ n: String) {
        var s = Set(mainList)
        if s.contains(n) { s.remove(n) } else { s.insert(n) }
        mainSet = ["MA", "EMA", "BOLL", "SAR", "SUPER"].filter { s.contains($0) }.joined(separator: ",")
    }

    private func topBar(_ wide: Bool) -> some View {
        let h24: Double? = vm.main?.priceChange?["h24"]
        let big: String = vm.main.map { GMPx.headline($0) } ?? "—"
        let c: Color = (h24 ?? 0) >= 0 ? Color.green : Color.red
        let flipTo: UIInterfaceOrientationMask = wide ? UIInterfaceOrientationMask.portrait : UIInterfaceOrientationMask.landscapeRight
        return HStack(spacing: 10) {
            if let m = vm.main {
                AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 30, dex: m.dexId)
            }
            Text(vm.symbol).font(.headline)
            Text(big).font(.headline.monospacedDigit()).foregroundStyle(c)
            if let v = h24 { Text(String(format: "%+.1f%%", v)).font(.caption.weight(.semibold)).foregroundStyle(c) }
            Spacer()
            GMModeSwitch()
            Button {
                GMOrient.set(UIInterfaceOrientationMask.allButUpsideDown, rotateTo: flipTo)
            } label: {
                Image(systemName: "rotate.right").font(.title3)
            }
            Button {
                GMOrient.set(UIInterfaceOrientationMask.portrait, rotateTo: UIInterfaceOrientationMask.portrait)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, wide ? 6 : 10)
    }

    private var periodBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(TF.allCases) { t in
                    Button { cvm.setTF(t) } label: {
                        Text(t.title)
                            .font(.footnote.weight(cvm.tf == t ? .bold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(cvm.tf == t ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                            .foregroundStyle(cvm.tf == t ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var indicatorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(["MA", "EMA", "BOLL", "SAR", "SUPER"], id: \.self) { n in
                    Button { toggleMain(n) } label: {
                        Text(n).font(.footnote.weight(mainList.contains(n) ? .bold : .regular)).foregroundStyle(mainList.contains(n) ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 14)
                ForEach(["VOL", "MACD", "KDJ", "RSI", "ROC"], id: \.self) { n in
                    Button { subInd = (subInd == n ? "" : n) } label: {
                        Text(n).font(.footnote.weight(subInd == n ? .bold : .regular)).foregroundStyle(subInd == n ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var body: some View {
        GeometryReader { g in
            let wide: Bool = g.size.width > g.size.height
            VStack(spacing: 0) {
                topBar(wide)
                periodBar.padding(.horizontal, 14).padding(.bottom, 4)
                if cvm.payload.isEmpty {
                    Spacer()
                    ProgressView("加载 K 线…")
                    Spacer()
                } else {
                    KLineWeb(payload: cvm.payload, seq: cvm.seq, clearToken: cvm.clearToken, onWeb: { t in cvm.onWeb(t) }, onFail: onFail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                indicatorBar.padding(.horizontal, 14).padding(.vertical, wide ? 4 : 8)
            }
        }
        .background(Color.page.ignoresSafeArea())
        .onAppear { GMOrient.set(UIInterfaceOrientationMask.allButUpsideDown) }
        .onDisappear { GMOrient.set(UIInterfaceOrientationMask.portrait, rotateTo: UIInterfaceOrientationMask.portrait) }
    }
}
