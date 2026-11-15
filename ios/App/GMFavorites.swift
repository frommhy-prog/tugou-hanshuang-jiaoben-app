import SwiftUI
import UIKit

extension FavStore {
    // 把一份最新行情写进收藏条目（价格、市值、流动性、成交、池龄、涨跌、交易所）
    func fill(_ m: DexPair, id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].price = m.price
        items[i].change24h = m.priceChange?["h24"]
        items[i].change1h = m.priceChange?["h1"]
        items[i].change5m = m.priceChange?["m5"]
        items[i].liq = m.liq
        items[i].mcap = m.marketCap ?? m.fdv
        items[i].vol24h = m.volume?["h24"]
        items[i].dex = m.dexId
        items[i].created = m.pairCreatedAt
        if items[i].logo == nil { items[i].logo = m.info?.imageUrl }
        if let d = try? JSONEncoder().encode(items) { Cfg.defaults.set(d, forKey: "favItems") }
    }
}

// MARK: - 收藏页（GMGN 关注页风格：头像带链/发射台徽标，右侧价格或市值 + 涨跌色块）
struct GMFavoritesRoot: View {
    @ObservedObject private var store = FavStore.shared
    @AppStorage("kMcap", store: Cfg.defaults) private var mcapMode = false
    @AppStorage("favSort", store: Cfg.defaults) private var sort = 0
    @State private var showLog = false
    @State private var editing = false
    @State private var busy = false

    private let sorts: [String] = ["最新", "涨幅", "市值", "流动性"]

    private var rows: [FavItem] {
        switch sort {
        case 1: return store.items.sorted { ($0.change24h ?? -99999) > ($1.change24h ?? -99999) }
        case 2: return store.items.sorted { ($0.mcap ?? 0) > ($1.mcap ?? 0) }
        case 3: return store.items.sorted { ($0.liq ?? 0) > ($1.liq ?? 0) }
        default: return store.items
        }
    }

    private func open(_ it: FavItem) {
        UTokenVM.shared.start(it.address)
        AppRouter.shared.tab = 0
    }

    private func refresh() async {
        if busy { return }
        busy = true
        defer { busy = false }
        for it in store.items {
            guard let ch = Chain(rawValue: it.chain) else { continue }
            if let ps = try? await MarketAPI.pairs(ch, it.address), let m = ps.first {
                store.fill(m, id: it.id)
            }
        }
    }

    private func valueText(_ it: FavItem) -> String {
        if mcapMode { return Fmt2.usd(it.mcap) }
        return it.price.map { Money.price($0) } ?? "—"
    }

    private func row(_ it: FavItem) -> some View {
        let ch: Chain = Chain(rawValue: it.chain) ?? .solana
        let chg: Double? = it.change24h
        let c: Color = (chg ?? 0) >= 0 ? Color.green : Color.red
        let pct: String = chg.map { String(format: "%+.1f%%", $0) } ?? "—"
        let age: String = it.created.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—"
        return HStack(spacing: 10) {
            if editing {
                Button { store.remove(it) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
            Button { open(it) } label: {
                HStack(spacing: 12) {
                    AvTokenLogo(chain: ch, address: it.address, symbol: it.symbol, hint: it.logo, size: 46, dex: it.dex)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it.symbol).font(.headline).foregroundStyle(Color.primary).lineLimit(1)
                        Text(ch.title + " · 池龄 " + age).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text("流动性 " + Fmt2.usd(it.liq) + " · 24h量 " + Fmt2.usd(it.vol24h)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(valueText(it)).font(.system(.headline, design: .rounded).monospacedDigit()).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.6)
                        Text(pct)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(c.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(c)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("移除收藏", role: .destructive) { store.remove(it) }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("共 " + String(store.items.count) + " 个 · App 在前台时每 45 秒自动监控").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                GMModeSwitch()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sorts.indices, id: \.self) { i in
                        Button { sort = i } label: {
                            Text(sorts[i])
                                .font(.footnote.weight(sort == i ? .bold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(sort == i ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(sort == i ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if busy { ProgressView() }
                }
            }
        }
    }

    private var empty: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有收藏").font(.headline)
                Text("在「代币」页查到币后，点头部右上角的 ☆ 就会收到这里；收藏的币会自动监控，价格急动、流动性骤降、放量、卖压时发本地通知。").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    controls
                    if store.items.isEmpty {
                        empty
                    } else {
                        ForEach(rows) { it in row(it) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(LogoRefreshHook { await refresh() })
            }
            .background(Color.page)
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editing ? "完成" : "编辑") { editing.toggle() }.disabled(store.items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLog = true } label: { Image(systemName: "bell.badge") }
                }
            }
            .sheet(isPresented: $showLog) { MonitorSheet() }
            .task { await refresh() }
        }
    }
}
