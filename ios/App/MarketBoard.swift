import SwiftUI

// MARK: - 盯盘看板：大盘 / 我的盯盘 / 各链热门 / 新池。数据全部由手机直连免费公共接口。
struct BoardMajor: Identifiable {
    let id: String
    let name: String
    let price: Double
    let ch: Double?
}

struct BoardPool: Identifiable {
    let id: String
    let symbol: String
    let address: String
    let chain: Chain
    var price: Double?
    var ch1: Double?
    var ch24: Double?
    var liq: Double
    var vol24: Double
    var mc: Double?
    var ageMin: Double?
    var logo: String?
}

@MainActor
final class MarketBoardVM: ObservableObject {
    @Published var majors: [BoardMajor] = []
    @Published var watch: [BoardPool] = []
    @Published var pools: [BoardPool] = []
    @Published var poolNote: String?
    @Published var loadingPools = false
    @Published var loadingWatch = false
    @Published var chain: Chain = .solana
    @Published var seg = 0   // 0 我的盯盘 1 热门 2 新池

    var poolKey: String { cat(String(seg), ":", chain.rawValue) }

    func reload() async {
        await loadMajors()
        await loadWatch()
        if seg > 0 { await loadPools() }
    }

    func loadMajors() async {
        let url = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,binancecoin&vs_currencies=usd&include_24hr_change=true"
        guard let o = (try? await MarketAPI.json(url)) as? [String: Any] else { return }
        let defs: [(String, String)] = [("bitcoin", "BTC"), ("ethereum", "ETH"), ("solana", "SOL"), ("binancecoin", "BNB")]
        var out: [BoardMajor] = []
        for d in defs {
            guard let e = o[d.0] as? [String: Any], let p = MarketAPI.num(e["usd"]) else { continue }
            out.append(BoardMajor(id: d.1, name: d.1, price: p, ch: MarketAPI.num(e["usd_24h_change"])))
        }
        if !out.isEmpty { majors = out }
    }

    // 我的盯盘 = 最近查过的代币，按链分组一次取回最新行情
    func loadWatch() async {
        let items = Array(QueryHistory.items.filter { $0.kind == "token" }.prefix(24))
        if items.isEmpty {
            watch = []
            return
        }
        loadingWatch = true
        defer { loadingWatch = false }
        var groups: [String: [HistoryItem]] = [:]
        for h in items {
            guard let c = Chain(rawValue: h.chain) else { continue }
            groups[c.dexId, default: []].append(h)
        }
        var best: [String: BoardPool] = [:]
        for (cid, hs) in groups {
            let addrs = hs.map { $0.address }.joined(separator: ",")
            guard let url = URL(string: "https://api.dexscreener.com/tokens/v1/" + cid + "/" + addrs) else { continue }
            guard let r = try? await Net.fetch(URLRequest(url: url, timeoutInterval: 20)) else { continue }
            let pairs: [DexPair] = (try? JSONDecoder().decode([DexPair].self, from: r.0)) ?? []
            for p in pairs {
                guard let b = p.baseToken?.address, let c = Chain.fromDex(p.chainId ?? "") else { continue }
                let k = b.lowercased()
                if let old = best[k], old.liq >= p.liq { continue }
                var age: Double? = nil
                if let cr = p.pairCreatedAt { age = (Date().timeIntervalSince1970 * 1000 - cr) / 60000 }
                let pool = BoardPool(id: k, symbol: p.baseToken?.symbol ?? "?", address: b, chain: c, price: p.price, ch1: p.priceChange?["h1"], ch24: p.priceChange?["h24"], liq: p.liq, vol24: p.volume?["h24"] ?? 0, mc: p.marketCap ?? p.fdv, ageMin: age, logo: p.info?.imageUrl)
                best[k] = pool
            }
        }
        var out: [BoardPool] = []
        for h in items {
            if let p = best[h.address.lowercased()] { out.append(p) }
        }
        watch = out
    }

    // 热门 / 新池：GeckoTerminal 各链榜单
    func loadPools() async {
        loadingPools = true
        poolNote = nil
        defer { loadingPools = false }
        let isTrend = seg == 1
        let path = isTrend ? "trending_pools?duration=1h" : "new_pools"
        let u = "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/" + path
        do {
            let o = try await MarketAPI.json(u)
            guard let arr = (o as? [String: Any])?["data"] as? [[String: Any]] else {
                pools = []
                poolNote = "这条链现在没有榜单数据"
                return
            }
            let prefix = chain.geckoId + "_"
            let iso = ISO8601DateFormatter()
            var out: [BoardPool] = []
            for item in arr {
                guard let a = item["attributes"] as? [String: Any] else { continue }
                let rel1 = item["relationships"] as? [String: Any]
                let rel2 = rel1?["base_token"] as? [String: Any]
                let rel3 = rel2?["data"] as? [String: Any]
                let rid = (rel3?["id"] as? String) ?? ""
                if !rid.hasPrefix(prefix) { continue }
                let addr = String(rid.dropFirst(prefix.count))
                if addr.isEmpty { continue }
                let name = (a["name"] as? String) ?? ""
                let sym = name.components(separatedBy: " / ").first ?? name
                let pc = a["price_change_percentage"] as? [String: Any]
                let vol = a["volume_usd"] as? [String: Any]
                var age: Double? = nil
                if let s = a["pool_created_at"] as? String, let d = iso.date(from: s) { age = Date().timeIntervalSince(d) / 60 }
                let pool = BoardPool(id: addr.lowercased(), symbol: sym, address: addr, chain: chain, price: MarketAPI.num(a["base_token_price_usd"]), ch1: MarketAPI.num(pc?["h1"]), ch24: MarketAPI.num(pc?["h24"]), liq: MarketAPI.num(a["reserve_in_usd"]) ?? 0, vol24: MarketAPI.num(vol?["h24"]) ?? 0, mc: MarketAPI.num(a["market_cap_usd"]) ?? MarketAPI.num(a["fdv_usd"]), ageMin: age, logo: nil)
                out.append(pool)
            }
            pools = out
            if out.isEmpty { poolNote = "这条链现在没有榜单数据" }
        } catch {
            pools = []
            poolNote = Net.message(error)
        }
    }
}

struct DashboardView: View {
    @StateObject private var vm = MarketBoardVM()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    majorsCard
                    Picker("", selection: $vm.seg) {
                        Text("我的盯盘").tag(0)
                        Text("热门").tag(1)
                        Text("新池").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if vm.seg > 0 { chainBar }
                    listCard
                    diagLink
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("盯盘看板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.loadingWatch || vm.loadingPools {
                        ProgressView()
                    } else {
                        Button { Task { await vm.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await vm.reload() }
            .task {
                await vm.loadMajors()
                await vm.loadWatch()
            }
            .task(id: vm.poolKey) { if vm.seg > 0 { await vm.loadPools() } }
        }
    }

    private var majorsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("大盘").font(.footnote).foregroundStyle(.secondary)
                if vm.majors.isEmpty {
                    Text("行情读取中，或 CoinGecko 免费接口暂时限速").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(vm.majors) { m in
                            VStack(spacing: 3) {
                                Text(m.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(Money.price(m.price)).font(.footnote.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                                Text(m.ch.map { String(format: "%+.1f%%", $0) } ?? "—")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle((m.ch ?? 0) >= 0 ? Color.green : Color.red)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var chainBar: some View {
        let list: [Chain] = [.solana, .bsc, .base, .eth, .arbitrum, .optimism, .polygon]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(list) { c in
                    Button { vm.chain = c } label: {
                        HStack(spacing: 5) {
                            AvChainBadge(chain: c, size: 16)
                            Text(c.title).font(.footnote.weight(vm.chain == c ? .bold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(vm.chain == c ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(vm.chain == c ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var listCard: some View {
        let rows: [BoardPool] = vm.seg == 0 ? vm.watch : vm.pools
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                if rows.isEmpty {
                    Text(emptyText).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(rows) { p in
                    row(p)
                    Divider()
                }
                Text(footText).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        if vm.seg == 0 { return "我的盯盘（最近查过的代币，实时行情）" }
        return vm.seg == 1 ? "热门池子（1 小时热度）" : "新池子（刚建池）"
    }

    private var emptyText: String {
        if vm.seg == 0 { return "还没有查过代币：去代币页查几个，这里就会出现并实时刷新" }
        if vm.loadingPools { return "读取中…" }
        return vm.poolNote ?? "暂无数据"
    }

    private var footText: String {
        if vm.seg == 0 { return "点一行直接跳到该代币的完整分析" }
        return "来源 GeckoTerminal 免费接口；榜单只是热度，不代表安全，新池尤其要先看风险页"
    }

    private func sub(_ p: BoardPool) -> String {
        var s = cat(p.chain.title, " · 流动性 ", Fmt2.usd(p.liq), " · 成交 ", Fmt2.usd(p.vol24))
        if let a = p.ageMin { s += " · " + Fmt2.dur(a * 60) }
        return s
    }

    private func chg(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(v.map { String(format: "%+.1f%%", $0) } ?? "—")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle((v ?? 0) >= 0 ? Color.green : Color.red)
        }
    }

    private func row(_ p: BoardPool) -> some View {
        Button {
            UTokenVM.shared.start(p.address)
            AppRouter.shared.tab = 0
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AvTokenLogo(chain: p.chain, address: p.address, symbol: p.symbol, hint: p.logo, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                    Text(sub(p)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(p.price.map { Money.price($0) } ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(Color.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        chg("1h", p.ch1)
                        chg("24h", p.ch24)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var diagLink: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            Card {
                HStack {
                    Label("系统诊断：数据源健康 / AI 自检 / 控制台", systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
