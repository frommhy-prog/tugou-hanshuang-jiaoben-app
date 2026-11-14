import SwiftUI
import UserNotifications

// MARK: - 收藏（一键查询）+ 自动监控
struct FavItem: Codable, Identifiable, Equatable {
    var chain: String
    var address: String
    var symbol: String
    var logo: String?
    var price: Double?
    var change24h: Double?
    var liq: Double?
    var addedAt: Double
    var id: String { chain + ":" + address.lowercased() }
}

@MainActor
final class FavStore: ObservableObject {
    static let shared = FavStore()
    @Published var items: [FavItem] = []
    private let key = "favItems"

    init() {
        if let d = Cfg.defaults.data(forKey: key), let a = try? JSONDecoder().decode([FavItem].self, from: d) { items = a }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { Cfg.defaults.set(d, forKey: key) }
    }

    func has(_ chain: Chain, _ addr: String) -> Bool {
        items.contains { $0.chain == chain.rawValue && $0.address.lowercased() == addr.lowercased() }
    }

    func toggle(chain: Chain, address: String, symbol: String, logo: String?, price: Double?) {
        if let i = items.firstIndex(where: { $0.chain == chain.rawValue && $0.address.lowercased() == address.lowercased() }) {
            items.remove(at: i)
        } else {
            items.insert(FavItem(chain: chain.rawValue, address: address, symbol: symbol, logo: logo, price: price, change24h: nil, liq: nil, addedAt: Date().timeIntervalSince1970), at: 0)
        }
        save()
    }

    func remove(_ it: FavItem) {
        items.removeAll { $0.id == it.id }
        save()
    }

    func update(id: String, price: Double?, change: Double?, liq: Double?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].price = price
        items[i].change24h = change
        items[i].liq = liq
        save()
    }
}

struct MonitorLog: Identifiable {
    let id = UUID()
    let at: Date
    let symbol: String
    let text: String
}

// 前台每 45 秒扫一遍收藏：价格急动、流动性骤降、放量、卖压；命中后发本地通知（免费账号没有服务器推送，App 不在前台时不扫）
@MainActor
final class WatchMonitor: ObservableObject {
    static let shared = WatchMonitor()
    @Published var log: [MonitorLog] = []
    private var loop: Task<Void, Never>?
    private var last: [String: DexPair] = [:]
    private var cool: [String: Date] = [:]

    func start() {
        if loop != nil { return }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
    }

    func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func scan() async {
        let items = FavStore.shared.items
        for it in items {
            if Task.isCancelled { return }
            guard let ch = Chain(rawValue: it.chain) else { continue }
            guard let ps = try? await MarketAPI.pairs(ch, it.address), let m = ps.first else { continue }
            FavStore.shared.update(id: it.id, price: m.price, change: m.priceChange?["h24"], liq: m.liq)
            if let old = last[it.id] { evaluate(it, old, m) }
            last[it.id] = m
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func evaluate(_ it: FavItem, _ old: DexPair, _ m: DexPair) {
        var hits: [(String, String)] = []
        if let c = m.priceChange?["m5"], abs(c) >= 8 { hits.append(("m5", String(format: "5 分钟涨跌 %+.1f%%", c))) }
        if let c = m.priceChange?["h1"], c >= 25 || c <= -15 { hits.append(("h1", String(format: "1 小时涨跌 %+.1f%%", c))) }
        if old.liq > 0, m.liq > 0, m.liq / old.liq <= 0.75 { hits.append(("liq", "流动性骤降：" + Fmt2.usd(old.liq) + " → " + Fmt2.usd(m.liq))) }
        let v5 = m.volume?["m5"] ?? 0
        let h1 = m.volume?["h1"] ?? 0
        if h1 > 0, v5 > 2000, v5 > h1 / 12 * 5 { hits.append(("vol", "5 分钟放量：成交 " + Fmt2.usd(v5) + "，是 1 小时均值的 5 倍以上")) }
        let b5 = Double(m.txns?["m5"]?.buys ?? 0)
        let s5 = Double(m.txns?["m5"]?.sells ?? 0)
        if b5 + s5 >= 20, s5 > b5 * 3 { hits.append(("sell", "5 分钟卖出笔数是买入的 3 倍以上（卖压）")) }
        for h in hits { notify(it, key: h.0, text: h.1) }
    }

    private func notify(_ it: FavItem, key: String, text: String) {
        let k = it.id + "#" + key
        if let t = cool[k], Date().timeIntervalSince(t) < 600 { return }
        cool[k] = Date()
        log.insert(MonitorLog(at: Date(), symbol: it.symbol, text: text), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
        let c = UNMutableNotificationContent()
        c.title = it.symbol + " 监控提醒"
        c.body = text
        c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

struct FavButton: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var store = FavStore.shared

    var body: some View {
        let on = store.has(vm.chain, vm.address)
        return Button {
            store.toggle(chain: vm.chain, address: vm.address, symbol: vm.symbol, logo: vm.main?.info?.imageUrl, price: vm.main?.price)
            if !on { WatchMonitor.shared.askPermission() }
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.body)
                .foregroundStyle(on ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct FavBar: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var store = FavStore.shared
    @State private var showLog = false

    var body: some View {
        if !store.items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("收藏 · 自动监控中", systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showLog = true } label: { Text("监控记录").font(.caption) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.items) { it in chip(it) }
                    }
                }
            }
            .sheet(isPresented: $showLog) { MonitorSheet() }
        }
    }

    private func chip(_ it: FavItem) -> some View {
        let ch = Chain(rawValue: it.chain) ?? .solana
        let up = (it.change24h ?? 0) >= 0
        return Button { vm.start(it.address) } label: {
            HStack(spacing: 6) {
                AvTokenLogo(chain: ch, address: it.address, symbol: it.symbol, hint: it.logo, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(it.symbol).font(.caption.weight(.bold)).lineLimit(1)
                    Text(it.change24h.map { String(format: "%+.1f%%", $0) } ?? "—").font(.caption2).foregroundStyle(up ? Color.green : Color.red)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("移除收藏", role: .destructive) { store.remove(it) } }
    }
}

struct MonitorSheet: View {
    @ObservedObject private var mon = WatchMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("监控规则（收藏的币，App 在前台时每 45 秒扫一次）") {
                    Text("5 分钟涨跌 ≥ 8%；1 小时涨 ≥ 25% 或跌 ≥ 15%").font(.footnote)
                    Text("流动性比上次下降 ≥ 25%").font(.footnote)
                    Text("5 分钟成交额 > 1 小时均值的 5 倍（且 ≥ $2K）").font(.footnote)
                    Text("5 分钟卖出笔数 ≥ 买入的 3 倍（且总笔数 ≥ 20）").font(.footnote)
                    Text("同一币同一信号 10 分钟内只提醒一次；App 退到后台后 iOS 会暂停，免费账号没有服务器推送。").font(.caption2).foregroundStyle(.secondary)
                }
                Section("最近触发") {
                    if mon.log.isEmpty { Text("暂无").foregroundStyle(.secondary) }
                    ForEach(mon.log) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.symbol + " · " + TZ.format(l.at)).font(.caption).foregroundStyle(.secondary)
                            Text(l.text).font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("监控记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
