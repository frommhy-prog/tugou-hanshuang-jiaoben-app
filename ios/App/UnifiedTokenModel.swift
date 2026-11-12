import SwiftUI
import Charts

// MARK: - 行情与成交数据源（手机直连公共接口，避免引擎云出口 IP 被限速）
struct DexTok: Codable {
    var address: String?
    var name: String?
    var symbol: String?
}
struct DexTx: Codable {
    var buys: Int?
    var sells: Int?
}
struct DexLiq: Codable {
    var usd: Double?
}
struct DexSocial: Codable {
    var type: String?
    var url: String?
}
struct DexWeb: Codable {
    var url: String?
    var label: String?
}
struct DexInfo: Codable {
    var imageUrl: String?
    var websites: [DexWeb]?
    var socials: [DexSocial]?
}
struct DexPair: Codable, Identifiable {
    var chainId: String?
    var dexId: String?
    var pairAddress: String?
    var baseToken: DexTok?
    var quoteToken: DexTok?
    var priceUsd: String?
    var txns: [String: DexTx]?
    var volume: [String: Double]?
    var priceChange: [String: Double]?
    var liquidity: DexLiq?
    var fdv: Double?
    var marketCap: Double?
    var pairCreatedAt: Double?
    var info: DexInfo?
    var id: String { pairAddress ?? "" }
    var price: Double? { priceUsd.flatMap { Double($0) } }
    var liq: Double { liquidity?.usd ?? 0 }
}

struct Candle: Identifiable {
    let t: Double
    let o: Double
    let h: Double
    let l: Double
    let c: Double
    let v: Double
    var id: Double { t }
    var date: Date { Date(timeIntervalSince1970: t) }
    var up: Bool { c >= o }
    var color: Color { c >= o ? Color.green : Color.red }
}

struct UTrade: Identifiable, Codable {
    let id: String
    let t: Double
    let buy: Bool
    let usd: Double
    let who: String
    let tx: String
}

enum TF: String, CaseIterable, Identifiable {
    case m1, m5, m15, h1, h4, d1, w1, mo1
    var id: String { rawValue }
    var title: String {
        switch self {
        case .m1: return "1分"
        case .m5: return "5分"
        case .m15: return "15分"
        case .h1: return "1时"
        case .h4: return "4时"
        case .d1: return "日"
        case .w1: return "周"
        case .mo1: return "月"
        }
    }
    var unit: String {
        switch self {
        case .m1, .m5, .m15: return "minute"
        case .h1, .h4: return "hour"
        case .d1, .w1, .mo1: return "day"
        }
    }
    var aggregate: Int {
        switch self {
        case .m1, .h1, .d1, .w1, .mo1: return 1
        case .m5: return 5
        case .m15: return 15
        case .h4: return 4
        }
    }
}

enum MarketAPI {
    static func json(_ urlStr: String) async throws -> Any {
        guard let url = URL(string: urlStr) else { throw APIError.network("地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let r: (Data, URLResponse)
        do { r = try await Net.fetch(req) } catch { throw APIError.network(Net.message(error)) }
        let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 { throw APIError.network("行情接口限速（429），稍后自动重试") }
        if !(200..<300).contains(code) { throw APIError.http(code, String((String(data: r.0, encoding: .utf8) ?? "").prefix(80))) }
        guard let o = try? JSONSerialization.jsonObject(with: r.0) else { throw APIError.decode("行情数据不是 JSON") }
        return o
    }

    static func num(_ x: Any?) -> Double? {
        if let n = x as? NSNumber { return n.doubleValue }
        if let s = x as? String { return Double(s) }
        return nil
    }

    // 某代币在该链上的所有池子
    static func pairs(_ chain: Chain, _ addr: String) async throws -> [DexPair] {
        guard let url = URL(string: "https://api.dexscreener.com/tokens/v1/\(chain.dexId)/\(addr)") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let r: (Data, URLResponse)
        do { r = try await Net.fetch(req) } catch { throw APIError.network(Net.message(error)) }
        let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) { throw APIError.http(code, "Dexscreener") }
        let all = (try? JSONDecoder().decode([DexPair].self, from: r.0)) ?? []
        let key = addr.lowercased()
        return all.filter { ($0.baseToken?.address ?? "").lowercased() == key }.sorted { $0.liq > $1.liq }
    }

    static func candles(_ chain: Chain, _ pair: String, _ tf: TF) async throws -> [Candle] {
        let u = "https://api.geckoterminal.com/api/v2/networks/\(chain.geckoId)/pools/\(pair)/ohlcv/\(tf.unit)?aggregate=\(tf.aggregate)&limit=150&currency=usd&token=base"
        let o = try await json(u)
        guard let d = (o as? [String: Any])?["data"] as? [String: Any],
              let a = d["attributes"] as? [String: Any],
              let list = a["ohlcv_list"] as? [[Any]] else { return [] }
        var out: [Candle] = []
        for row in list where row.count >= 6 {
            guard let t = num(row[0]), let op = num(row[1]), let hi = num(row[2]), let lo = num(row[3]), let cl = num(row[4]) else { continue }
            out.append(Candle(t: t, o: op, h: hi, l: lo, c: cl, v: num(row[5]) ?? 0))
        }
        return out.sorted { $0.t < $1.t }
    }

    static func trades(_ chain: Chain, _ pair: String, _ baseToken: String) async throws -> [UTrade] {
        let u = "https://api.geckoterminal.com/api/v2/networks/\(chain.geckoId)/pools/\(pair)/trades"
        let o = try await json(u)
        guard let arr = (o as? [String: Any])?["data"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        var out: [UTrade] = []
        for item in arr {
            guard let a = item["attributes"] as? [String: Any] else { continue }
            guard let kind = a["kind"] as? String, let usd = num(a["volume_in_usd"]) else { continue }
            guard let ts = a["block_timestamp"] as? String, let d = iso.date(from: ts) else { continue }
            let who = (a["tx_from_address"] as? String) ?? ""
            let tx = (a["tx_hash"] as? String) ?? ""
            out.append(UTrade(id: (item["id"] as? String) ?? tx + String(d.timeIntervalSince1970), t: d.timeIntervalSince1970, buy: kind == "buy", usd: usd, who: who, tx: tx))
        }
        return out.sorted { $0.t > $1.t }
    }

    // 合约在哪条链：向 Dexscreener 搜地址，按流动性取最大的一条链
    static func detect(_ addr: String) async -> Chain? {
        if Addr.isSolana(addr) && !Addr.isEVM(addr) { return .solana }
        guard let url = URL(string: "https://api.dexscreener.com/latest/dex/search?q=" + addr) else { return nil }
        guard let r = try? await Net.fetch(URLRequest(url: url, timeoutInterval: 20)),
              let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
              let pairs = o["pairs"] as? [[String: Any]] else { return nil }
        var score: [Chain: Double] = [:]
        for p in pairs {
            guard let b = p["baseToken"] as? [String: Any], (b["address"] as? String)?.lowercased() == addr.lowercased(),
                  let cid = p["chainId"] as? String, let ch = Chain.fromDex(cid) else { continue }
            let liq = ((p["liquidity"] as? [String: Any])?["usd"] as? NSNumber)?.doubleValue ?? 0
            score[ch, default: 0] += liq + 1
        }
        return score.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - 成交流向分析
struct FlowWindow: Identifiable {
    let id: String
    let label: String
    var buy = 0.0
    var sell = 0.0
    var nb = 0
    var ns = 0
    var net: Double { buy - sell }
    var total: Double { buy + sell }
}

struct FlowBucket: Identifiable {
    let id: Double
    let t: Double
    let width: Double
    var buy = 0.0
    var sell = 0.0
}

struct AddrFlow: Identifiable {
    let who: String
    var buy = 0.0
    var sell = 0.0
    var nb = 0
    var ns = 0
    var id: String { who }
    var total: Double { buy + sell }
}

enum FlowCalc {
    static func windows(_ trades: [UTrade], now: Double) -> [FlowWindow] {
        let defs: [(String, String, Double)] = [("5m", "5 分钟", 300), ("15m", "15 分钟", 900), ("1h", "1 小时", 3600), ("6h", "6 小时", 21600), ("24h", "24 小时", 86400)]
        var out: [FlowWindow] = []
        for d in defs {
            var w = FlowWindow(id: d.0, label: d.1)
            for t in trades where now - t.t <= d.2 {
                if t.buy { w.buy += t.usd; w.nb += 1 } else { w.sell += t.usd; w.ns += 1 }
            }
            out.append(w)
        }
        return out
    }

    static func buckets(_ trades: [UTrade]) -> [FlowBucket] {
        guard let lo = trades.map({ $0.t }).min(), let hi = trades.map({ $0.t }).max(), hi > lo else { return [] }
        let span = hi - lo
        let sizes: [Double] = [60, 120, 300, 600, 900, 1800, 3600, 7200]
        let size = sizes.first(where: { span / $0 <= 36 }) ?? 7200
        var map: [Double: FlowBucket] = [:]
        for t in trades {
            let k = (t.t / size).rounded(.down) * size
            var b = map[k] ?? FlowBucket(id: k, t: k, width: size)
            if t.buy { b.buy += t.usd } else { b.sell += t.usd }
            map[k] = b
        }
        return map.values.sorted { $0.t < $1.t }
    }

    static func addrs(_ trades: [UTrade]) -> [AddrFlow] {
        var m: [String: AddrFlow] = [:]
        for t in trades where !t.who.isEmpty {
            var a = m[t.who] ?? AddrFlow(who: t.who)
            if t.buy { a.buy += t.usd; a.nb += 1 } else { a.sell += t.usd; a.ns += 1 }
            m[t.who] = a
        }
        return m.values.sorted { $0.total > $1.total }
    }
}

// MARK: - 持有人分析模型（引擎 /e/v2/holder）
struct UHPos: Codable {
    var boughtUsd: Double?
    var soldUsd: Double?
    var realizedUsd: Double?
    var qtyHeld: Double?
    var costHeldUsd: Double?
    var valueNowUsd: Double?
    var unrealizedUsd: Double?
    var roi: Double?
    var avgBuyUsd: Double?
    var avgSellUsd: Double?
    var priceNowUsd: Double?
    var soldPct: Double?
    var firstBuy: Double?
    var lastSell: Double?
    var buys: Int?
    var sells: Int?
    var delayMin: Double?
    var entry: String?
    var state: String?
    var uncovQty: Double?
}

struct UHTrade: Codable, Identifiable {
    var tx: String
    var t: Double
    var side: String
    var qty: Double?
    var amt: Double?
    var q: String?
    var usd: Double?
    var approx: Bool?
    var id: String { tx + String(t) }
}

struct UHStats: Codable {
    var tradeN: Int?
    var tokensTraded: Int?
    var realizedN: Int?
    var winN: Int?
    var winRate: Double?
    var medHoldSec: Double?
    var spanDays: Double?
    var perDay: Double?
    var partialTokens: Int?
    var unresolvedSells: Int?
}

struct UHolderAnalysis: Codable {
    var chain: String?
    var owner: String?
    var native: String?
    var usdBasis: String?
    var position: UHPos?
    var insights: [Finding]?
    var trades: [UHTrade]?
    var stats: UHStats?
    var tags: [SolTag]?
    var notes: [String]?
    var sample: String?
    var error: String?
    var detail: String?
}

struct UHolder: Identifiable, Codable {
    let rank: Int
    let owner: String
    let kind: String
    let pct: Double?
    var id: String { owner }
    var kindText: String {
        switch kind {
        case "wallet": return "钱包"
        case "pool": return "池子"
        case "contract", "program": return "合约"
        case "pda": return "金库"
        default: return "未知"
        }
    }
}

struct HolderAgg {
    var analyzed = 0
    var withPos = 0
    var profit = 0
    var snipers = 0
    var early = 0
    var holding = 0
    var spent = 0.0
    var pnl = 0.0
    var valueNow = 0.0
    var unreal = 0.0
}

// MARK: - 状态
@MainActor
final class UTokenVM: ObservableObject {
    @Published var input = ""
    @Published var chain: Chain = .solana
    @Published var address = ""
    @Published var loading = false
    @Published var error: String?
    @Published var pairs: [DexPair] = []
    @Published var candles: [Candle] = []
    @Published var tf: TF = .m15
    @Published var chartNote: String?
    @Published var trades: [UTrade] = []
    @Published var tradesNote: String?
    @Published var holders: [UHolder] = []
    @Published var conc: Conc?
    @Published var holderNote: String?
    @Published var holderFindings: [Finding] = []
    @Published var holderLoading = false
    @Published var holderComplete = true
    @Published var authorities: TokAuth?
    @Published var holderPages = 3
    @Published var analyses: [String: UHolderAnalysis] = [:]
    @Published var analysisErr: [String: String] = [:]
    @Published var analyzing = false
    @Published var security: TokenResponse?
    @Published var ai: AIResult?
    @Published var aiLoading = false
    @Published var aiMsg: String?
    @Published var insights: [Finding] = []
    @Published var shareItems: [Any] = []
    @Published var stamps = Stamps()
    @Published var refreshing = false
    @Published var refreshNote: String?
    @Published var analyzedDone = 0
    @Published var analyzeTotal = 0
    @Published var refreshToken = 0
    private var runID = 0
    private var tradesDone = false
    private var holdersDone = false
    private var aiUsed = 0
    private var persistTask: Task<Void, Never>?

    static let shared = UTokenVM()

    init() {
        if let a = Cfg.defaults.string(forKey: "lastTokenAddr"), !a.isEmpty, let s = TokenStore.load(a) {
            apply(s)
            input = s.address
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.refreshIfStale()
            }
        }
    }

    // 打开 App 时，如果恢复出来的是旧数据，立刻在后台刷新（旧数据先显示，带时间）
    func refreshIfStale() {
        guard !address.isEmpty, !pairs.isEmpty else { return }
        let age = stamps.pairs.map { Date().timeIntervalSince($0) } ?? 9999
        if age > 45 { start(address) }
    }

    // 一个「全部刷新」：行情、成交、持有人、安全、AI 一起重读；叙事 / 社交 / 生命周期卡片也重新取
    func refreshAll() {
        guard !address.isEmpty else { return }
        SocialCard.store = [:]
        NarrativeRulesCard.store = [:]
        LifecycleCard.store = [:]
        refreshToken += 1
        start(address)
    }

    var main: DexPair? { pairs.first }
    var symbol: String { main?.baseToken?.symbol ?? "未知代币" }

    func inputChanged() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if (Addr.isEVM(t) || Addr.isSolana(t)) && t.lowercased() != address.lowercased() { start(t) }
    }

    func start(_ raw: String) {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isEVM(addr) || Addr.isSolana(addr) else {
            error = "地址格式不对：EVM 是 0x 开头 42 位，Solana 是 32–44 位 Base58"
            return
        }
        runID += 1
        let id = runID
        let same = addr.lowercased() == address.lowercased() && !pairs.isEmpty
        if !same {
            resetState()
            if let s = TokenStore.load(addr) { apply(s) } // 先显示上次的旧数据（带时间），后台再刷新
        }
        address = addr
        input = addr
        error = nil
        loading = pairs.isEmpty
        refreshing = true
        Cfg.defaults.set(addr, forKey: "lastTokenAddr")
        Task { await run(addr, id) }
    }

    private func resetState() {
        pairs = []; candles = []; trades = []; holders = []; conc = nil; holderNote = nil; holderFindings = []
        analyses = [:]; analysisErr = [:]; security = nil; ai = nil; aiMsg = nil; insights = []; error = nil
        chartNote = nil; tradesNote = nil; authorities = nil; holderComplete = true; holderPages = 3
        stamps = Stamps(); refreshNote = nil; analyzedDone = 0; analyzeTotal = 0; aiUsed = 0
    }

    private func apply(_ s: TokenSnapshot) {
        address = s.address
        chain = Chain(rawValue: s.chain) ?? chain
        pairs = s.pairs
        trades = s.trades
        holders = s.holders
        conc = s.conc
        holderNote = s.holderNote
        holderFindings = s.holderFindings
        holderComplete = s.holderComplete
        authorities = s.authorities
        analyses = s.analyses
        security = s.security
        ai = s.ai
        stamps = s.stamps
        rebuild()
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            self?.persist()
        }
    }

    func persist() {
        guard !address.isEmpty, !pairs.isEmpty else { return }
        TokenStore.save(TokenSnapshot(address: address, chain: chain.rawValue, pairs: pairs, trades: Array(trades.prefix(300)), holders: holders, conc: conc, holderNote: holderNote, holderFindings: holderFindings, holderComplete: holderComplete, authorities: authorities, analyses: analyses, security: security, ai: ai, stamps: stamps, savedAt: Date()))
    }

    // 一次请求同时拿到链和池子；成交、持有人、安全、AI 全部并行，AI 不等大户拆解
    private func run(_ addr: String, _ id: Int) async {
        do {
            let (c, ps) = try await MarketAPI.resolve(addr)
            guard id == runID else { return }
            if ps.isEmpty {
                if pairs.isEmpty { error = "这条链上没有找到该代币的交易池（Dexscreener 无数据）。可能是新币尚未被收录，或地址/链不对。" } else { refreshNote = "池子数据刷新为空，显示的是旧数据" }
                loading = false; refreshing = false
                return
            }
            chain = c
            pairs = ps
            stamps.pairs = Date()
            refreshNote = nil
            QueryHistory.add(kind: "token", chain: c.rawValue, address: addr, title: ps[0].baseToken?.symbol ?? Addr.short(addr), logo: ps[0].info?.imageUrl)
        } catch {
            guard id == runID else { return }
            if pairs.isEmpty { self.error = error.localizedDescription } else { refreshNote = "刷新失败，显示的是旧数据：" + Net.message(error) }
            loading = false; refreshing = false
            return
        }
        loading = false
        rebuild()
        tradesDone = false
        holdersDone = false
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadTrades(id) }
            g.addTask { await self.loadSecurity(id) }
            g.addTask { await self.loadHolders(id); await self.analyzeHolders(id) }
            g.addTask { await self.autoAI(id) }
        }
        guard id == runID else { return }
        refreshing = false
        persist()
        if AIMode.auto, analyses.count >= 2, analyses.count > aiUsed { await runAI(id, fresh: false) } // 拆解完成后补一版 AI
    }

    private func autoAI(_ id: Int) async {
        guard AIMode.auto else { return }
        var waited = 0.0
        while waited < 25, id == runID, !(tradesDone && holdersDone) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            waited += 0.3
        }
        guard id == runID else { return }
        await runAI(id, fresh: false)
    }

    func loadCandles(_ id: Int) async {
        guard let p = main?.pairAddress else { return }
        do {
            let cs = try await MarketAPI.candles(chain, p, tf)
            guard id == runID else { return }
            candles = cs
            chartNote = cs.isEmpty ? "该池子暂无 K 线数据" : nil
        } catch {
            guard id == runID else { return }
            chartNote = candles.isEmpty ? error.localizedDescription : nil
        }
    }

    func loadTrades(_ id: Int) async {
        defer { tradesDone = true }
        guard let p = main?.pairAddress else { return }
        do {
            let ts = try await MarketAPI.trades(chain, p, address)
            guard id == runID else { return }
            trades = ts
            tradesNote = ts.isEmpty ? "最近没有成交记录" : nil
            stamps.trades = Date()
            rebuild()
            schedulePersist()
        } catch {
            guard id == runID else { return }
            tradesNote = trades.isEmpty ? error.localizedDescription : nil
        }
    }

    func setTF(_ t: TF) {
        tf = t
        let id = runID
        Task { await loadCandles(id) }
    }

    // 动态刷新：价格、K 线、成交
    func tick() async {
        let id = runID
        guard !address.isEmpty, id == runID else { return }
        if let ps = try? await MarketAPI.pairs(chain, address), !ps.isEmpty, id == runID { pairs = ps; stamps.pairs = Date() }
        await loadTrades(id)
    }

    func loadHolders(_ id: Int) async {
        holderLoading = true
        defer { holderLoading = false; holdersDone = true }
        do {
            if chain == .solana {
                let r: SolToken = try await Engine.get("/e/sol/token", ["mint": address])
                guard id == runID else { return }
                if let e = r.error { holderNote = e + (r.detail.map { "：" + $0 } ?? ""); return }
                holders = (r.holders ?? []).map { UHolder(rank: $0.rank, owner: $0.owner, kind: $0.kind, pct: $0.pct) }
                conc = r.concentration
                holderFindings = r.findings ?? []
                authorities = r.authorities
                holderComplete = true
                holderNote = (r.notes ?? []).first
            } else if EvmDetailVM.supported.contains(chain.rawValue) {
                let r: EvmTokenResp = try await Engine.get("/e/evm/token", ["chain": chain.rawValue, "token": address, "pages": String(holderPages)])
                guard id == runID else { return }
                if let e = r.error { holderNote = EvmFmt.errorText(e, r.detail); return }
                holders = (r.holders ?? []).enumerated().map { UHolder(rank: $0.element.rank ?? ($0.offset + 1), owner: $0.element.owner, kind: $0.element.kind ?? "unknown", pct: $0.element.pct) }
                conc = r.concentration.map { Conc(top1: $0.top1, top5: $0.top5, top10: $0.top10, top20: $0.top20, wallets10: $0.wallets10, nonWallet: $0.nonWallet, listed: $0.listed) }
                holderFindings = (r.findings ?? []).compactMap { f in
                    guard let t = f.text else { return nil }
                    return Finding(level: f.level ?? "info", text: t, basis: f.basis)
                }
                holderComplete = r.complete == true
                holderNote = (r.notes ?? []).first
            } else {
                holderNote = "该链暂不支持持有人榜单"
            }
            if !holders.isEmpty { stamps.holders = Date() }
            rebuild()
            schedulePersist()
        } catch {
            guard id == runID else { return }
            holderNote = error.localizedDescription
        }
    }

    func moreHolderPages() {
        holderPages = min(6, holderPages + 3)
        let id = runID
        Task { await loadHolders(id); await analyzeHolders(id) }
    }

    func loadSecurity(_ id: Int) async {
        guard chain != .solana, chain.tokenSupported else { return }
        if let r: TokenResponse = try? await API.get("/api/token", ["chain": chain.rawValue, "address": address]), id == runID, r.error == nil {
            security = r
            stamps.security = Date()
            rebuild()
        }
    }

    // 最多 10 个普通钱包，三路并行，边出结果边显示；10 分钟内拆解过的不重复请求
    func analyzeHolders(_ id: Int) async {
        let recent = stamps.analyses.map { Date().timeIntervalSince($0) < 600 } ?? false
        let targets = holders.filter { $0.kind == "wallet" }.prefix(10).map { $0.owner }.filter { analyses[$0] == nil || !recent }
        if targets.isEmpty { return }
        analyzing = true
        analyzedDone = 0
        analyzeTotal = targets.count
        defer { analyzing = false }
        let lanes = 3
        await withTaskGroup(of: Void.self) { group in
            for lane in 0..<lanes {
                group.addTask { [weak self] in
                    var i = lane
                    while i < targets.count {
                        await self?.analyzeOne(targets[i], id)
                        i += lanes
                    }
                }
            }
        }
        guard id == runID else { return }
        stamps.analyses = Date()
        rebuild()
        schedulePersist()
    }

    func analyzeOne(_ owner: String, _ id: Int) async {
        do {
            let r: UHolderAnalysis = try await Engine.get("/e/v2/holder", ["chain": chain.rawValue, "token": address, "owner": owner, "pages": "2"])
            guard id == runID else { return }
            if let e = r.error { analysisErr[owner] = e + (r.detail.map { "：" + $0 } ?? "") } else { analyses[owner] = r }
        } catch {
            guard id == runID else { return }
            analysisErr[owner] = error.localizedDescription
        }
        analyzedDone += 1
        rebuild()
    }

    var agg: HolderAgg {
        var a = HolderAgg()
        for (_, r) in analyses {
            a.analyzed += 1
            guard let p = r.position else { continue }
            a.withPos += 1
            let spent = p.boughtUsd ?? 0
            a.spent += spent
            a.pnl += (p.realizedUsd ?? 0) + (p.unrealizedUsd ?? 0)
            a.valueNow += p.valueNowUsd ?? 0
            a.unreal += p.unrealizedUsd ?? 0
            if (p.roi ?? -1) > 0 { a.profit += 1 }
            if let d = p.delayMin, d >= 0, d <= 1 { a.snipers += 1 }
            if let d = p.delayMin, d >= 0, d <= 10 { a.early += 1 }
            if (p.qtyHeld ?? 0) > 0 { a.holding += 1 }
        }
        return a
    }

    // MARK: 规则分析：每条结论附依据
    func rebuild() {
        var out: [Finding] = []
        guard let m = main else { insights = []; return }
        let liq = m.liq
        if let created = m.pairCreatedAt {
            let hrs = (Date().timeIntervalSince1970 * 1000 - created) / 3_600_000
            if hrs < 1 { out.append(Finding(level: "risk", text: "池子上线不到 1 小时，处于极早期，价格和流动性都可能剧烈变化", basis: "最深池子创建于 " + TZ.format(Date(timeIntervalSince1970: created / 1000)))) }
            else if hrs < 24 { out.append(Finding(level: "warn", text: String(format: "池子上线仅 %.1f 小时，仍在早期阶段", hrs), basis: "最深池子创建于 " + TZ.format(Date(timeIntervalSince1970: created / 1000)))) }
        }
        if liq > 0 && liq < 5_000 { out.append(Finding(level: "risk", text: "流动性只有 " + Fmt2.usd(liq) + "，几百美元的卖单就能明显砸价", basis: "最深池子流动性（Dexscreener）")) }
        else if liq > 0 && liq < 20_000 { out.append(Finding(level: "warn", text: "流动性偏薄（" + Fmt2.usd(liq) + "），大额进出滑点大", basis: "最深池子流动性（Dexscreener）")) }
        if let mc = m.marketCap ?? m.fdv, mc > 0, liq > 0 {
            let r = liq / mc
            if r < 0.02 { out.append(Finding(level: "risk", text: String(format: "流动性仅为市值的 %.1f%%，市值主要靠少量成交撑起，实际能卖出的远小于账面市值", r * 100), basis: "流动性 " + Fmt2.usd(liq) + " ÷ 市值 " + Fmt2.usd(mc))) }
            else if r < 0.05 { out.append(Finding(level: "warn", text: String(format: "流动性占市值 %.1f%%，偏低", r * 100), basis: "流动性 " + Fmt2.usd(liq) + " ÷ 市值 " + Fmt2.usd(mc))) }
        }
        if let v = m.volume?["h24"], liq > 0, v / liq > 15 {
            out.append(Finding(level: "warn", text: String(format: "24 小时成交额是流动性的 %.0f 倍，高频炒作或刷量的可能性大", v / liq), basis: "成交额 " + Fmt2.usd(v) + " ÷ 流动性 " + Fmt2.usd(liq)))
        }
        if pairs.count >= 2 {
            let top = pairs[0].liq
            let total = pairs.reduce(0) { $0 + $1.liq }
            if total > 0 && top / total >= 0.9 { out.append(Finding(level: "info", text: String(format: "流动性集中在最深的池子（%.0f%%），其余池子很浅", top / total * 100), basis: "共 \(pairs.count) 个池子")) }
            let ps = pairs.filter { $0.liq >= 1000 }.compactMap { $0.price }
            if let lo = ps.min(), let hi = ps.max(), lo > 0, hi / lo > 1.05, ps.count >= 2 {
                out.append(Finding(level: "warn", text: String(format: "不同池子之间价差达 %.1f%%，存在搬砖空间，也可能有池子被操纵", (hi / lo - 1) * 100), basis: "流动性 ≥ $1,000 的池子价格对比"))
            }
        }
        if trades.count >= 30 {
            let now = Date().timeIntervalSince1970
            let ws = FlowCalc.windows(trades, now: now)
            if let w = ws.first(where: { $0.id == "1h" }), w.total >= 500 {
                if w.sell > w.buy * 1.5 { out.append(Finding(level: "warn", text: "最近 1 小时资金净流出 " + Fmt2.usd(-w.net) + "，卖出明显多于买入", basis: "买入 " + Fmt2.usd(w.buy) + "（\(w.nb) 笔）/ 卖出 " + Fmt2.usd(w.sell) + "（\(w.ns) 笔）")) }
                else if w.buy > w.sell * 1.5 { out.append(Finding(level: "ok", text: "最近 1 小时资金净流入 " + Fmt2.usd(w.net) + "，买盘占优", basis: "买入 " + Fmt2.usd(w.buy) + "（\(w.nb) 笔）/ 卖出 " + Fmt2.usd(w.sell) + "（\(w.ns) 笔）")) }
            }
            let ad = FlowCalc.addrs(trades)
            let gross = trades.reduce(0) { $0 + $1.usd }
            if gross > 0, ad.count >= 3 {
                let top5 = ad.prefix(5).reduce(0) { $0 + $1.total } / gross
                if top5 > 0.5 { out.append(Finding(level: "warn", text: String(format: "前 5 个交易地址贡献了最近成交额的 %.0f%%，成交高度集中", top5 * 100), basis: "最近 \(trades.count) 笔成交、\(ad.count) 个交易地址（地址为交易发起方，可能是机器人或聚合器）")) }
            }
            let wash = ad.filter { $0.nb >= 3 && $0.ns >= 3 && abs($0.buy - $0.sell) / max(1, $0.buy + $0.sell) < 0.15 }
            if !wash.isEmpty { out.append(Finding(level: "warn", text: "\(wash.count) 个地址买卖各 ≥3 笔且买卖额接近，可能是套利机器人，也可能是对敲刷量，链上数据无法区分", basis: "买卖额差额 < 15%")) }
            if let big = trades.max(by: { $0.usd < $1.usd }), gross > 0, big.usd / gross > 0.2 {
                out.append(Finding(level: "info", text: String(format: "最大一笔成交 %@ 占最近成交额的 %.0f%%（%@）", Fmt2.usd(big.usd), big.usd / gross * 100, big.buy ? "买入" : "卖出"), basis: "最近 \(trades.count) 笔成交"))
            }
        }
        if let c = conc {
            if let t1 = c.top1, t1 >= 20, holders.first?.kind == "wallet" { out.append(Finding(level: "risk", text: String(format: "第 1 大持有人是普通钱包，持有 %.1f%%，他一个人就能砸盘", t1), basis: "链上持有人榜单")) }
            if let w = c.wallets10 {
                out.append(Finding(level: w >= 30 ? "risk" : (w >= 15 ? "warn" : "ok"), text: String(format: "前 10 大普通钱包合计持有 %.1f%%", w), basis: "占总供应量；已剔除池子、合约、金库"))
            }
        }
        let a = agg
        if a.withPos >= 2 {
            let up = Double(a.profit) / Double(a.withPos)
            out.append(Finding(level: up >= 0.7 ? "warn" : "info", text: "已拆解 \(a.withPos) 个大户：\(a.profit) 个账面盈利（\(Int(up * 100))%），合计盈亏 " + Fmt2.usd(a.pnl, signed: true) + "，" + (up >= 0.7 ? "多数大户有利润可兑现" : (up <= 0.3 ? "多数大户被套" : "盈亏分化")), basis: "按美元成本的平均成本法，已兑现 + 浮动"))
            if a.snipers + a.early >= 3 { out.append(Finding(level: "warn", text: "\(a.early) 个大户在池子创建 10 分钟内买入（其中 \(a.snipers) 个在 1 分钟内），疑似内部或狙击筹码", basis: "首次买入时间 − 池子创建时间")) }
            if liq > 0, a.valueNow > 0 {
                let imp = a.valueNow / liq
                out.append(Finding(level: imp >= 0.5 ? "risk" : (imp >= 0.15 ? "warn" : "info"), text: String(format: "已拆解大户的持仓价值合计 %@，相当于池子流动性的 %.0f%%，集中抛售的价格冲击会很大", Fmt2.usd(a.valueNow), imp * 100), basis: "持仓数量 × 现价 ÷ 最深池子流动性"))
            }
        }
        if chain == .solana {
            if let ma = authorities?.mint, !ma.isEmpty { out.append(Finding(level: "risk", text: "仍有增发权限，发行方可以继续增发", basis: "链上 mint 账户")) }
            if let fa = authorities?.freeze, !fa.isEmpty { out.append(Finding(level: "risk", text: "仍有冻结权限，发行方可以冻结持有人账户", basis: "链上 mint 账户")) }
        } else if let s = security {
            if s.honeypot == true { out.append(Finding(level: "risk", text: "检测为蜜罐：可能买得进卖不出", basis: s.riskSource ?? "合约扫描")) }
            if let st = s.sellTax, st >= 10 { out.append(Finding(level: st >= 50 ? "risk" : "warn", text: String(format: "卖出税 %.1f%%", st), basis: s.riskSource ?? "合约扫描")) }
            if s.mintable == true { out.append(Finding(level: "warn", text: "合约可增发", basis: s.riskSource ?? "合约扫描")) }
        }
        insights = out
    }

    // MARK: AI
    struct Facts: Encodable {
        var token: [String: String]
        var change: [String: Double]
        var pools: [String]
        var flow: [String]
        var concentration: [String: Double]
        var holders: [String]
        var insights: [String]
        var security: [String]
    }

    func buildFacts() -> Facts {
        let m = main
        var tok: [String: String] = ["链": chain.title, "代币": symbol]
        if let p = m?.price { tok["现价美元"] = String(format: "%.6g", p) }
        if let l = m?.liquidity?.usd { tok["流动性美元"] = String(format: "%.0f", l) }
        if let mc = m?.marketCap ?? m?.fdv { tok["市值美元"] = String(format: "%.0f", mc) }
        if let v = m?.volume?["h24"] { tok["24h成交美元"] = String(format: "%.0f", v) }
        if let c = m?.pairCreatedAt { tok["池龄小时"] = String(format: "%.1f", (Date().timeIntervalSince1970 * 1000 - c) / 3_600_000) }
        var ch: [String: Double] = [:]
        for (k, v) in m?.priceChange ?? [:] { ch["涨跌%_" + k] = v }
        let ps = pairs.prefix(4).map { ($0.dexId ?? "?") + " 流动性" + Fmt2.usd($0.liq) + " 24h成交" + Fmt2.usd($0.volume?["h24"]) }
        var fl: [String] = []
        if trades.count >= 10 {
            for w in FlowCalc.windows(trades, now: Date().timeIntervalSince1970) where w.total > 0 {
                fl.append(w.label + "：买" + Fmt2.usd(w.buy) + "(\(w.nb)笔) 卖" + Fmt2.usd(w.sell) + "(\(w.ns)笔)")
            }
        }
        var cc: [String: Double] = [:]
        if let c = conc {
            if let v = c.top1 { cc["第1大占比%"] = v }
            if let v = c.top10 { cc["前10占比%"] = v }
            if let v = c.wallets10 { cc["前10普通钱包占比%"] = v }
        }
        var hs: [String] = []
        for h in holders.filter({ $0.kind == "wallet" }).prefix(10) {
            guard let r = analyses[h.owner], let p = r.position else { continue }
            var s = "#\(h.rank) 占比" + (h.pct.map { String(format: "%.2f%%", $0) } ?? "?") + " " + (p.entry ?? "入场未知") + " " + (p.state ?? "")
            s += " 投入" + Fmt2.usd(p.boughtUsd) + " 兑现" + Fmt2.usd(p.realizedUsd) + " 浮动" + Fmt2.usd(p.unrealizedUsd)
            if let roi = p.roi { s += String(format: " 回报%.0f%%", roi * 100) }
            hs.append(s)
        }
        let ins = insights.prefix(14).map { $0.text }
        var sec: [String] = []
        if chain == .solana {
            sec.append("增发权限" + ((authorities?.mint ?? "").isEmpty ? "已放弃" : "仍在"))
            sec.append("冻结权限" + ((authorities?.freeze ?? "").isEmpty ? "已放弃" : "仍在"))
        } else if let s = security {
            if let v = s.honeypot { sec.append("蜜罐:" + (v ? "是" : "否")) }
            if let v = s.buyTax { sec.append(String(format: "买入税%.1f%%", v)) }
            if let v = s.sellTax { sec.append(String(format: "卖出税%.1f%%", v)) }
        }
        return Facts(token: tok, change: ch, pools: ps, flow: fl, concentration: cc, holders: hs, insights: Array(ins), security: sec)
    }

    func runAI(_ id: Int, fresh: Bool) async {
        guard id == runID, main != nil else { return }
        aiLoading = true
        aiMsg = nil
        aiUsed = analyses.count
        defer { aiLoading = false }
        let r = await AIChain.run(kind: "代币综合分析（行情、成交流向、池子、持有人成本与盈亏、安全）", facts: buildFacts(), fresh: fresh)
        guard id == runID else { return }
        if let m = aiMessage(r) {
            aiMsg = m + (ai != nil ? "（下方仍是上次的 AI 结果）" : "")
        } else {
            ai = r
            stamps.ai = r.generatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        }
        schedulePersist()
    }

    func reAI() {
        let id = runID
        Task { await runAI(id, fresh: true) }
    }
}
