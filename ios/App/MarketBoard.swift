import SwiftUI

// 盯盘列表：用 UserDefaults 里一个逗号分隔的字符串保存（chain:address），@AppStorage 直接驱动界面刷新
enum WatchPins {
    static func items(_ raw: String) -> [String] { raw.split(separator: ",").map { String($0) } }

    static func has(_ raw: String, _ chain: Chain, _ addr: String) -> Bool {
        let k = (chain.rawValue + ":" + addr).lowercased()
        return items(raw).contains { $0.lowercased() == k }
    }

    static func toggled(_ raw: String, _ chain: Chain, _ addr: String) -> String {
        let k = chain.rawValue + ":" + addr
        var list = items(raw)
        if has(raw, chain, addr) { list.removeAll { $0.lowercased() == k.lowercased() } } else { list.insert(k, at: 0) }
        return list.joined(separator: ",")
    }
}

struct BoardMajor: Identifiable {
    let id: String
    let name: String
    let price: Double
    let change: Double?
}

struct BoardCoin: Identifiable {
    let id: String
    let sym: String
    let name: String
    let chain: Chain
    let addr: String
    let price: Double?
    let ch24: Double?
    let ch1h: Double?
    let liq: Double
    let vol: Double
    let mc: Double?
    let created: Double?
    let logo: String?
    let stale: Bool
}

@MainActor
final class BoardVM: ObservableObject {
    @Published var majors: [BoardMajor] = []
    @Published var watch: [BoardCoin] = []
    @Published var hot: [BoardCoin] = []
    @Published var fresh: [BoardCoin] = []
    @Published var loading = false
    @Published var note: String?
    private var cache: [String: (Date, [BoardCoin])] = [:]

    func load(seg: Int, chain: Chain, pins: [String], force: Bool) async {
        loading = true
        defer { loading = false }
        note = nil
        if majors.isEmpty || force { await loadMajors() }
        if seg == 0 {
            await loadWatch(pins: pins)
        } else if seg == 1 {
            hot = await loadGecko("trending_pools", chain, force: force)
            if hot.isEmpty { note = "GeckoTerminal 暂无数据或被限速（免费 30 次/分钟），稍后下拉刷新" }
        } else {
            fresh = await loadGecko("new_pools", chain, force: force)
            if fresh.isEmpty { note = "GeckoTerminal 暂无数据或被限速（免费 30 次/分钟），稍后下拉刷新" }
        }
    }

    func loadMajors() async {
        let ids: [(String, String)] = [("bitcoin", "BTC"), ("ethereum", "ETH"), ("solana", "SOL"), ("binancecoin", "BNB")]
        let q = ids.map { $0.0 }.joined(separator: ",")
        guard let raw = try? await MarketAPI.json("https://api.coingecko.com/api/v3/simple/price?ids=" + q + "&vs_currencies=usd&include_24hr_change=true") else { return }
        guard let o = raw as? [String: Any] else { return }
        var out: [BoardMajor] = []
        for (id, sym) in ids {
            guard let d = o[id] as? [String: Any], let p = MarketAPI.num(d["usd"]) else { continue }
            out.append(BoardMajor(id: id, name: sym, price: p, change: MarketAPI.num(d["usd_24h_change"])))
        }
        if !out.isEmpty { majors = out }
    }

    private static func coin(_ p: DexPair, _ chain: Chain, stale: Bool) -> BoardCoin? {
        guard let a = p.baseToken?.address, !a.isEmpty else { return nil }
        let created: Double? = p.pairCreatedAt.map { $0 / 1000 }
        return BoardCoin(id: chain.rawValue + ":" + a, sym: p.baseToken?.symbol ?? "?", name: p.baseToken?.name ?? "", chain: chain, addr: a, price: p.price, ch24: p.priceChange?["h24"], ch1h: p.priceChange?["h1"], liq: p.liq, vol: p.volume?["h24"] ?? 0, mc: p.marketCap ?? p.fdv, created: created, logo: p.info?.imageUrl, stale: stale)
    }

    // 盯盘：手动加星的 + 最近查过的（缓存），分链批量向 Dexscreener 取最新价格；取不到就显示缓存里的旧价格
    func loadWatch(pins: [String]) async {
        var keys: [String] = []
        for p in pins where !keys.contains(where: { $0.lowercased() == p.lowercased() }) { keys.append(p) }
        let snaps = TokenStore.list()
        var snapMap: [String: TokenSnapshot] = [:]
        for s in snaps { snapMap[(s.chain + ":" + s.address).lowercased()] = s }
        for s in snaps.prefix(10) {
            let k = s.chain + ":" + s.address
            if !keys.contains(where: { $0.lowercased() == k.lowercased() }) { keys.append(k) }
        }
        var byChain: [String: [String]] = [:]
        for k in keys {
            let parts = k.split(separator: ":", maxSplits: 1).map { String($0) }
            if parts.count == 2 { byChain[parts[0], default: []].append(parts[1]) }
        }
        var live: [String: DexPair] = [:]
        for (cid, addrs) in byChain {
            guard let ch = Chain(rawValue: cid) else { continue }
            var i = 0
            while i < addrs.count {
                let chunk = Array(addrs[i..<min(i + 25, addrs.count)])
                i += 25
                let urlStr = "https://api.dexscreener.com/tokens/v1/" + ch.dexId + "/" + chunk.joined(separator: ",")
                guard let u = URL(string: urlStr), let r = try? await Net.fetch(URLRequest(url: u, timeoutInterval: 20)) else { continue }
                let arr = (try? JSONDecoder().decode([DexPair].self, from: r.0)) ?? []
                for p in arr {
                    let k = cid + ":" + (p.baseToken?.address ?? "").lowercased()
                    if let old = live[k], old.liq >= p.liq { continue }
                    live[k] = p
                }
            }
        }
        var out: [BoardCoin] = []
        for k in keys {
            let parts = k.split(separator: ":", maxSplits: 1).map { String($0) }
            if parts.count != 2 { continue }
            guard let ch = Chain(rawValue: parts[0]) else { continue }
            let lk = (parts[0] + ":" + parts[1]).lowercased()
            if let p = live[lk], let c = BoardVM.coin(p, ch, stale: false) {
                out.append(c)
            } else if let s = snapMap[lk], let p = s.pairs.first, let c = BoardVM.coin(p, ch, stale: true) {
                out.append(c)
            }
        }
        watch = out
    }

    // GeckoTerminal 趋势池 / 新池（免费，带代币头像）
    func loadGecko(_ kind: String, _ chain: Chain, force: Bool) async -> [BoardCoin] {
        let ck = kind + ":" + chain.rawValue
        if !force, let c = cache[ck], Date().timeIntervalSince(c.0) < 60 { return c.1 }
        var url = "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/" + kind + "?include=base_token"
        if kind == "trending_pools" { url += "&duration=1h" }
        guard let raw = try? await MarketAPI.json(url), let root = raw as? [String: Any], let data = root["data"] as? [[String: Any]] else {
            return cache[ck]?.1 ?? []
        }
        var imgs: [String: String] = [:]
        let included = (root["included"] as? [[String: Any]]) ?? []
        for inc in included {
            guard let id = inc["id"] as? String, let a = inc["attributes"] as? [String: Any] else { continue }
            if let u = a["image_url"] as? String, u.hasPrefix("http") { imgs[id.lowercased()] = u }
        }
        let iso = ISO8601DateFormatter()
        let prefix = chain.geckoId + "_"
        var out: [BoardCoin] = []
        for d in data {
            guard let a = d["attributes"] as? [String: Any] else { continue }
            let rels = d["relationships"] as? [String: Any]
            let bt = rels?["base_token"] as? [String: Any]
            let btd = bt?["data"] as? [String: Any]
            let rel = (btd?["id"] as? String) ?? ""
            if !rel.hasPrefix(prefix) { continue }
            let addr = String(rel.dropFirst(prefix.count))
            let name = (a["name"] as? String) ?? ""
            let sym = name.components(separatedBy: " / ").first ?? name
            let chg = a["price_change_percentage"] as? [String: Any]
            let vol = a["volume_usd"] as? [String: Any]
            var created: Double? = nil
            if let s = a["pool_created_at"] as? String, let dt = iso.date(from: s) { created = dt.timeIntervalSince1970 }
            let mc: Double? = MarketAPI.num(a["market_cap_usd"]) ?? MarketAPI.num(a["fdv_usd"])
            out.append(BoardCoin(id: rel, sym: sym, name: name, chain: chain, addr: addr, price: MarketAPI.num(a["base_token_price_usd"]), ch24: MarketAPI.num(chg?["h24"]), ch1h: MarketAPI.num(chg?["h1"]), liq: MarketAPI.num(a["reserve_in_usd"]) ?? 0, vol: MarketAPI.num(vol?["h24"]) ?? 0, mc: mc, created: created, logo: imgs[rel.lowercased()], stale: false))
        }
        cache[ck] = (Date(), out)
        return out
    }
}

// 仪表盘：大盘 / 我的盯盘 / 热门 / 新池。点任意一行直接切到代币页分析；原来的数据源健康与控制台收进「系统诊断」
struct DashboardView: View {
    @StateObject private var vm = BoardVM()
    @Environment(\.dismiss) private var dismiss
    @State private var seg = 0
    @State private var chain: Chain = .solana
    @AppStorage("watchlist", store: Cfg.defaults) private var watchRaw = ""

    private var loadKey: String { String(seg) + chain.rawValue + String(watchRaw.count) }

    private var list: [BoardCoin] {
        if seg == 0 { return vm.watch }
        return seg == 1 ? vm.hot : vm.fresh
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    majorsCard
                    Picker("", selection: $seg) {
                        Text("盯盘").tag(0)
                        Text("热门").tag(1)
                        Text("新池").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if seg != 0 { chainChips }
                    listCard
                    NavigationLink { DiagnosticsView() } label: {
                        Card {
                            HStack {
                                Label("系统诊断：数据源健康 / AI 自检 / 控制台", systemImage: "stethoscope").font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("仪表盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { if vm.loading { ProgressView() } }
            }
            .refreshable { await vm.load(seg: seg, chain: chain, pins: WatchPins.items(watchRaw), force: true) }
            .task(id: loadKey) { await vm.load(seg: seg, chain: chain, pins: WatchPins.items(watchRaw), force: false) }
        }
    }

    private var majorsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("大盘").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if vm.majors.isEmpty { Text("读取中…").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(vm.majors) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(.caption).foregroundStyle(.secondary)
                            Text(Money.format(m.price)).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(m.change.map { String(format: "%+.1f%%", $0) } ?? "—").font(.caption2.weight(.semibold)).foregroundStyle((m.change ?? 0) >= 0 ? Color.green : Color.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var chainChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Chain.allCases.filter { $0.tokenSupported }) { c in
                    Button { chain = c } label: {
                        HStack(spacing: 5) {
                            AvChainBadge(chain: c, size: 16)
                            Text(c.title).font(.footnote.weight(chain == c ? .bold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chain == c ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var listCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                let items = list
                if items.isEmpty && !vm.loading {
                    Text(seg == 0 ? "还没有盯盘：在代币页点右上角 ☆ 加入；查过的币也会出现在这里" : (vm.note ?? "暂无数据")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { c in
                    Button {
                        UTokenVM.shared.start(c.addr)
                        AppRouter.shared.tab = 0
                        dismiss()
                    } label: { row(c) }
                    .buttonStyle(.plain)
                    if c.id != items.last?.id { Divider() }
                }
                if seg == 0 && !items.isEmpty {
                    Text("价格来自 Dexscreener 实时批量查询；标「缓存」的是取不到最新数据时显示的上次结果").font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
        }
    }

    private func meta(_ c: BoardCoin) -> String {
        let age = c.created.map { Fmt2.dur(Date().timeIntervalSince1970 - $0) } ?? ""
        return cat("市值 ", Fmt2.usd(c.mc), " · 池 ", Fmt2.usd(c.liq), " · 量 ", Fmt2.usd(c.vol), age.isEmpty ? "" : " · " + age)
    }

    private func row(_ c: BoardCoin) -> some View {
        HStack(spacing: 12) {
            AvTokenLogo(chain: c.chain, address: c.addr, symbol: c.sym, hint: c.logo, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.sym).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if c.stale { Pill(text: "缓存", color: Color.gray) }
                }
                Text(meta(c)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(c.price.map { Money.price($0) } ?? "—").font(.subheadline.monospacedDigit())
                Text(c.ch24.map { String(format: "%+.1f%%", $0) } ?? "—").font(.caption.weight(.semibold)).foregroundStyle((c.ch24 ?? 0) >= 0 ? Color.green : Color.red)
            }
        }
        .padding(.vertical, 6)
    }
}
